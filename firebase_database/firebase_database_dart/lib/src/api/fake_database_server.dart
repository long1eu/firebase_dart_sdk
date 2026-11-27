/// An in-memory server for tests, scripted by the test. JS: none; Android: none (the JS and Android tests
/// use a live backend). Built over `lib/src/testing/fake_server_actions.dart`.
library;

import 'dart:async';

import 'package:firebase_database_dart/src/core/connection/listen_hash_provider.dart';
import 'package:firebase_database_dart/src/core/connection/listen_spec.dart';
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/util/server_values.dart';
import 'package:firebase_database_dart/src/core/view/query_params.dart';
import 'package:firebase_database_dart/src/realtime/auth_session.dart';
import 'package:firebase_database_dart/src/testing/fake_server_actions.dart';
import 'package:meta/meta.dart';

/// A server for tests that sits at the connection seam and answers only what the test tells it to.
///
/// Pass it to `databaseWithFakeServer`. Requests are recorded in [requests]; listens, writes and gets wait
/// until the test answers them. Drive time with `fakeAsync`.
///
/// It behaves as the real connection does around it: the first connection is made in a timer after the
/// database's first operation (or `goOnline`), not when it is created; requests made while offline are queued and sent when the connection comes up,
/// after the listens are sent again; a dropped connection is retried after the database's reconnect delay
/// for as long as [acceptConnections] is false.
///
/// The test must answer writes in the order they left: answering a put, merge or onDisconnect
/// request while one sent before it on the same connection is unanswered throws a [StateError]
/// naming both. A request made while connected leaves at once; after a reconnect the unanswered
/// puts and merges leave first, then the onDisconnect requests made while offline, as the real
/// connection replays them. [ackNextWrite], [failNextWrite] and [ackNextOnDisconnect] answer the
/// oldest request of their kind, and throw when an older request of the other kind is
/// unanswered; the `*Last*` helpers answer the newest of their kind and take `outOfOrder: true`
/// for a test that models something a server does not do.
///
/// That the server answers writes in send order is inferred from the emulator probe
/// (`rtdb_emulator_probe.md`, addendum 2 item 4): a pipelined `auth`, listen, get, `unauth`, get
/// was answered in order; no write was in that burst. Listens and gets were answered in order
/// there too; this fake does not check their order.
///
/// ```dart
/// fakeAsync((FakeAsync async) {
///   final FakeDatabaseServer server = FakeDatabaseServer();
///   final FirebaseDatabase db = databaseWithFakeServer(app, server);
///   db.ref('a').onValue.listen((DatabaseEvent e) => print(e.snapshot.value));
///   async.elapse(Duration.zero);
///   server.answerListen('a', 1); // prints 1
///   async.elapse(Duration.zero);
/// });
/// ```
final class FakeDatabaseServer {
  /// Creates a server that accepts connections.
  FakeDatabaseServer();

  /// Whether a connection attempt succeeds. Default true. Set it to false, then call [dropConnection], to
  /// keep the client offline.
  bool acceptConnections = true;

  /// The server's clock, which resolves `ServerValue.timestamp` in acknowledged writes and onDisconnect
  /// writes; null (the default) reads `DateTime.now()`.
  DateTime? serverTime;

  int _connectionAttempts = 0;
  final FakeServerActions _wire = FakeServerActions();
  final List<String?> _authTokens = <String?>[];
  _FakeConnection? _connection;

  /// The server's data, kept from the answers, pushes and acknowledged writes the test made.
  Node _data = ChildrenNode.empty;

  /// The onDisconnect writes the server acknowledged on the current connection.
  final List<_Write> _onDisconnect = <_Write>[];

  /// The number of connection attempts the client has made.
  int get connectionAttempts => _connectionAttempts;

  /// The auth token the client sent with each connection (and each token change while connected), oldest
  /// first: null for a connection made without a user. A connection after [revokeAuth] sends a token
  /// fetched with `forceRefresh: true`.
  ///
  /// The tokens come through the client's token source, as the real connection gets them: a change
  /// event of the auth provider is a signal, and the token recorded is the one the source then fetches
  /// with `getAccessToken`, never the payload of the event.
  List<String?> get receivedAuthTokens =>
      List<String?>.unmodifiable(_authTokens);

  /// The requests received, oldest first, as `'<action> <path>'`: `q` listen, `n` unlisten, `g` get, `p`
  /// put, `m` merge, `o` onDisconnect put, and so on, for example `'q /a'`. The path always has its
  /// leading slash. A listen, unlisten or get of a filtered query adds its wire query object as compact
  /// JSON with sorted keys: `'q /a {"l":2,"vf":"l"}'`.
  List<String> get requests => List<String>.unmodifiable(<String>[
    for (final ServerCall call in _wire.calls)
      if (_requestCodes[call.action] case final String code)
        _describe(code, call),
  ]);

  static String _describe(String code, ServerCall call) {
    final ListenSpec? spec = call.spec;
    if (spec == null) {
      return '$code ${call.path}';
    }
    return spec.isDefault
        ? '$code ${spec.path}'
        : '$code ${spec.path} ${objectToUniqueKey(spec.queryObject)}';
  }

  static const Map<String, String> _requestCodes = <String, String>{
    'listen': 'q',
    'unlisten': 'n',
    'get': 'g',
    'put': 'p',
    'merge': 'm',
    'onDisconnectPut': 'o',
    'onDisconnectMerge': 'om',
    'onDisconnectCancel': 'oc',
  };

  _FakeConnection get _conn {
    final _FakeConnection? connection = _connection;
    if (connection == null) {
      throw StateError('No database is connected to this FakeDatabaseServer.');
    }
    return connection;
  }

  /// Answers the open listen at [path] (`'a/b'` or `'/a/b'`) with [value] (JSON, `.priority`/`.value`
  /// allowed), completing it.
  ///
  /// [query] is the wire query object of a filtered listen (for example `{'l': 2, 'vf': 'l'}`). Without
  /// it the default listen at [path] is answered, or the only open listen there; several open listens and
  /// no default one throw a [StateError]. A query that loads all data (an `orderBy*` with no range or
  /// limit) is listened to as the default query.
  void answerListen(String path, Object? value, {Map<String, Object?>? query}) {
    final Path p = Path(path);
    final _Listen listen = _pickListen(p, query, answered: false);
    final Node node = nodeFromJson(value);
    if (listen.spec.loadsAllData) {
      _data = _data.updateChild(p, node);
    }
    // A listen whose hash matches the data gets the completion only, as from the server.
    if (listen.sentHash != node.hash()) {
      _wire.deliverDataUpdate(p.toString(), value, tag: listen.tag);
    }
    _wire.respond(listen.wire!);
  }

  /// Refuses the open listen at [path] with the wire [status], for example `'permission_denied'`.
  /// [query] selects the listen as for [answerListen].
  void failListen(String path, String status, {Map<String, Object?>? query}) {
    final _Listen listen = _pickListen(Path(path), query, answered: false);
    _wire.respond(listen.wire!, status: status, data: _reason(status));
  }

  _Listen _pickListen(
    Path path,
    Map<String, Object?>? query, {
    required bool answered,
  }) {
    final List<_Listen> candidates = _conn._listensAt(path, answered: answered);
    final String state = answered ? 'active' : 'open';
    if (query != null) {
      final String id = QueryParams.fromWireObject(query).toQueryIdentifier();
      for (final _Listen listen in candidates) {
        if (listen.spec.queryIdentifier == id) {
          return listen;
        }
      }
      throw StateError('No $state listen at $path with query $query.');
    }
    for (final _Listen listen in candidates) {
      if (listen.spec.isDefault) {
        return listen;
      }
    }
    if (candidates.length == 1) {
      return candidates.single;
    }
    throw StateError(
      candidates.isEmpty
          ? 'No $state listen at $path.'
          : 'Several $state listens at $path; pass the query to choose one.',
    );
  }

  /// Sends [value] as new data at [path], as another client's write would.
  void push(String path, Object? value) {
    final Path p = Path(path);
    _data = _data.updateChild(p, nodeFromJson(value));
    _broadcastOverwrite(p);
  }

  /// Cancels the active listen at [path] with the wire [status], as a rules change would. [query] selects
  /// the listen as for [answerListen].
  void cancelListen(String path, String status, {Map<String, Object?>? query}) {
    final _Listen listen = _pickListen(Path(path), query, answered: true);
    _conn._revoke(listen);
    listen.onComplete(status, _reason(status));
  }

  /// Acknowledges the most recent unanswered write (put or merge): the written data, with server values
  /// resolved (the timestamp from [serverTime], an increment against the server's current value), is
  /// pushed once to every open listen that overlaps it (with its tag for a filtered listen), then the write
  /// is answered `ok`, as the server does.
  ///
  /// A transaction put whose hash does not match the server's current data at its path is answered
  /// `datastale` instead, with nothing pushed.
  ///
  /// Throws a [StateError] when a write or onDisconnect request sent before it is unanswered (use
  /// [ackNextWrite]). [outOfOrder] true skips that check, for a test that models something a
  /// server does not do; give the reason next to it.
  void ackLastWrite({bool outOfOrder = false}) => _ackWrite(
    _lastSentWrite(onDisconnect: false),
    'ackLastWrite',
    outOfOrder: outOfOrder,
  );

  /// Acknowledges the oldest sent unanswered write (put or merge), as [ackLastWrite] does. Throws a
  /// [StateError] when an onDisconnect request sent before it is unanswered, or when no write is
  /// sent and unanswered.
  void ackNextWrite() =>
      _ackWrite(_nextSentWrite(onDisconnect: false), 'ackNextWrite');

  void _ackWrite(_Write write, String helper, {bool outOfOrder = false}) {
    if (!outOfOrder) {
      _checkSendOrder(write, helper);
    }
    final Path path = Path(write.path);
    final String? hash = write.hash;
    if (hash != null && hash != _data.getChild(path).hash()) {
      _wire.respond(
        write.wire!,
        status: 'datastale',
        data: _reason('datastale'),
        outOfOrder: true,
      );
      return;
    }
    final Map<String, Object?> serverValues = _serverValues();
    if (write.action == 'put') {
      _data = _data.updateChild(
        path,
        resolveDeferredValueSnapshot(
          nodeFromJson(write.data),
          _data.getChild(path),
          serverValues,
        ),
      );
      _broadcastOverwrite(path);
    } else {
      final Map<String, Object?> children = <String, Object?>{};
      for (final MapEntry<String, Object?> entry
          in (write.data! as Map<String, Object?>).entries) {
        final Path childPath = path.childPath(Path(entry.key));
        final Node resolved = resolveDeferredValueSnapshot(
          nodeFromJson(entry.value),
          _data.getChild(childPath),
          serverValues,
        );
        _data = _data.updateChild(childPath, resolved);
        children[entry.key] = resolved.toJson(exportFormat: true);
      }
      _broadcastMerge(path, children);
    }
    _wire.respond(write.wire!, outOfOrder: true);
  }

  /// Refuses the most recent unanswered write with the wire [status], for example
  /// `'permission_denied'` or `'datastale'`. Nothing is pushed. Ordered as [ackLastWrite], with
  /// the same [outOfOrder].
  void failLastWrite(String status, {bool outOfOrder = false}) => _failWrite(
    _lastSentWrite(onDisconnect: false),
    status,
    'failLastWrite',
    outOfOrder: outOfOrder,
  );

  /// Refuses the oldest sent unanswered write with the wire [status], as [failLastWrite] does.
  /// Throws as [ackNextWrite] does.
  void failNextWrite(String status) =>
      _failWrite(_nextSentWrite(onDisconnect: false), status, 'failNextWrite');

  void _failWrite(
    _Write write,
    String status,
    String helper, {
    bool outOfOrder = false,
  }) {
    if (!outOfOrder) {
      _checkSendOrder(write, helper);
    }
    _wire.respond(
      write.wire!,
      status: status,
      data: _reason(status),
      outOfOrder: true,
    );
  }

  /// Acknowledges the most recent unanswered onDisconnect request. Ordered as [ackLastWrite], with
  /// the same [outOfOrder].
  void ackLastOnDisconnect({bool outOfOrder = false}) => _ackOnDisconnect(
    _lastSentWrite(onDisconnect: true),
    'ackLastOnDisconnect',
    outOfOrder: outOfOrder,
  );

  /// Acknowledges the oldest sent unanswered onDisconnect request. Throws a [StateError] when a
  /// write sent before it is unanswered, or when no onDisconnect request is sent and unanswered.
  void ackNextOnDisconnect() => _ackOnDisconnect(
    _nextSentWrite(onDisconnect: true),
    'ackNextOnDisconnect',
  );

  void _ackOnDisconnect(
    _Write write,
    String helper, {
    bool outOfOrder = false,
  }) {
    if (!outOfOrder) {
      _checkSendOrder(write, helper);
    }
    if (write.action == 'onDisconnectCancel') {
      final Path path = Path(write.path);
      _onDisconnect.removeWhere((_Write w) => path.contains(Path(w.path)));
    } else {
      _onDisconnect.add(write);
    }
    _wire.respond(write.wire!, outOfOrder: true);
  }

  /// Answers the open get at [path] with [value].
  void answerGet(String path, Object? value) {
    final _Get get = _openGet(path);
    if (get.spec.loadsAllData) {
      _data = _data.updateChild(Path(path), nodeFromJson(value));
    }
    _wire.respond(get.wire!, data: value);
  }

  /// Refuses the open get at [path] with the wire [status].
  void failGet(String path, String status) {
    final _Get get = _openGet(path);
    _wire.respond(get.wire!, status: status, data: _reason(status));
  }

  /// Drops the current connection; the client reconnects when [acceptConnections] allows it.
  void dropConnection() => _conn._drop(reconnect: true);

  /// Revokes the client's auth: the connection drops and the client listens again after reconnecting.
  void revokeAuth() {
    final _FakeConnection connection = _conn;
    connection._forceToken = true;
    connection._delegate.onAuthStatus(
      'expired_token',
      explanation: 'Auth token is expired.',
    );
    connection._drop(reconnect: true);
  }

  /// Kills the connection with [reason], as the server's kill message does: the client stays offline until
  /// the instance is recreated.
  void kill(String reason) {
    final _FakeConnection connection = _conn;
    connection._killed = true;
    connection._timer?.cancel();
    connection._timer = null;
    connection._delegate.onServerShutdown(reason);
    connection._drop(reconnect: false);
  }

  Map<String, Object?> _serverValues() => generateServerValues(
    timestamp: (serverTime ?? DateTime.now()).millisecondsSinceEpoch,
  );

  static String _reason(String status) => 'The fake server answered $status.';

  _Write _lastSentWrite({required bool onDisconnect}) =>
      _sentWrites(onDisconnect: onDisconnect).last;

  _Write _nextSentWrite({required bool onDisconnect}) =>
      _sentWrites(onDisconnect: onDisconnect).first;

  List<_Write> _sentWrites({required bool onDisconnect}) {
    final List<_Write> sent = <_Write>[
      for (final _Write write in _conn._sentPending)
        if (write.isOnDisconnect == onDisconnect) write,
    ];
    if (sent.isEmpty) {
      throw StateError(
        onDisconnect
            ? 'No unanswered onDisconnect request.'
            : 'No unanswered write.',
      );
    }
    return sent;
  }

  /// Throws when a write or onDisconnect request sent before [write] on this connection is
  /// unanswered.
  void _checkSendOrder(_Write write, String helper) {
    final _Write earlier = _conn._sentPending.first;
    if (identical(earlier, write)) {
      return;
    }
    throw StateError(
      '$helper answers ${_describeWrite(write)} while ${_describeWrite(earlier)}, sent '
      'before it, is unanswered. Writes are answered in the order they left: answer the '
      'earlier one first (ackNextWrite, failNextWrite, ackNextOnDisconnect), or pass '
      'outOfOrder: true with a reason.',
    );
  }

  static String _describeWrite(_Write write) =>
      "'${_requestCodes[write.action]} ${write.path}'";

  _Get _openGet(String path) {
    final Path p = Path(path);
    for (final _Get get in _conn._gets) {
      if (get.wire != null && Path(get.spec.path) == p) {
        return get;
      }
    }
    throw StateError('No open get at $p.');
  }

  /// Pushes the server data at [path] to every open listen at, above or below it, once each.
  void _broadcastOverwrite(Path path) {
    final _FakeConnection connection = _conn;
    if (!connection._connected) {
      return;
    }
    for (final _Listen listen in connection._openListens()) {
      final Path listenPath = listen.path;
      if (listenPath.contains(path)) {
        _wire.deliverDataUpdate(
          path.toString(),
          _data.getChild(path).toJson(exportFormat: true),
          tag: listen.tag,
        );
      } else if (path.contains(listenPath)) {
        _wire.deliverDataUpdate(
          listenPath.toString(),
          _data.getChild(listenPath).toJson(exportFormat: true),
          tag: listen.tag,
        );
      }
    }
  }

  /// Pushes a merge of [children] (relative paths to resolved JSON) at [path] to every open listen at or
  /// above it, and the data of each open listen below it, once each.
  void _broadcastMerge(Path path, Map<String, Object?> children) {
    final _FakeConnection connection = _conn;
    if (!connection._connected) {
      return;
    }
    for (final _Listen listen in connection._openListens()) {
      final Path listenPath = listen.path;
      if (listenPath.contains(path)) {
        _wire.deliverDataUpdate(
          path.toString(),
          children,
          isMerge: true,
          tag: listen.tag,
        );
      } else if (path.contains(listenPath)) {
        _wire.deliverDataUpdate(
          listenPath.toString(),
          _data.getChild(listenPath).toJson(exportFormat: true),
          tag: listen.tag,
        );
      }
    }
  }

  /// Applies the acknowledged onDisconnect writes to the server data, as the server does when the
  /// connection ends, and forgets them.
  void _applyOnDisconnect() {
    final Map<String, Object?> serverValues = _serverValues();
    void overwrite(Path path, Object? json) {
      _data = _data.updateChild(
        path,
        resolveDeferredValueSnapshot(
          nodeFromJson(json),
          _data.getChild(path),
          serverValues,
        ),
      );
    }

    for (final _Write write in _onDisconnect) {
      final Path path = Path(write.path);
      if (write.action == 'onDisconnectPut') {
        overwrite(path, write.data);
      } else {
        for (final MapEntry<String, Object?> entry
            in (write.data! as Map<String, Object?>).entries) {
          overwrite(path.childPath(Path(entry.key)), entry.value);
        }
      }
    }
    _onDisconnect.clear();
  }
}

/// How the testing factory connects a database to a [FakeDatabaseServer]. Not exported.
@internal
extension FakeDatabaseServerInternal on FakeDatabaseServer {
  /// The connection of a new database: [delegate] is its Repo; a dropped connection is retried after
  /// [reconnectDelay]. [tokens] is the token source the real connection would get: its auth token is
  /// fetched for each connection (null: no user), and each event of its `authChanges` is a signal to
  /// fetch the token again and send it while connected (the payload of the event is not used).
  ServerActions connect(
    ServerActionsDelegate delegate, {
    required Duration reconnectDelay,
    required RealtimeTokenSource tokens,
  }) {
    _connection?._close();
    _wire
      ..delegate = delegate
      ..activeListens.clear();
    final _FakeConnection connection = _FakeConnection(
      this,
      delegate,
      reconnectDelay,
      tokens,
    );
    connection._tokenSubscription = tokens.authChanges.listen(
      (_) => connection._sendAuth(),
    );
    _connection = connection;
    return connection;
  }
}

/// One listen the client registered.
final class _Listen {
  _Listen(this.spec, this.hashProvider, this.tag, this.onComplete);

  final ListenSpec spec;
  final ListenHashProvider hashProvider;
  final int? tag;
  final RequestResultCallback onComplete;

  /// The request on the current connection, or null while not sent.
  ServerCall? wire;

  /// Whether the server answered it `ok` on the current connection.
  bool answered = false;

  /// The hash the client sent with the request on the current connection.
  String? sentHash;

  Path get path => Path(spec.path);
}

/// One write or onDisconnect request not answered yet.
final class _Write {
  _Write(this.action, this.path, this.data, this.hash, this.onComplete);

  final String action;
  final String path;
  final Object? data;
  final String? hash;
  final RequestResultCallback? onComplete;

  /// The request on the current connection, or null while not sent.
  ServerCall? wire;

  bool get isOnDisconnect => action.startsWith('onDisconnect');
}

/// One get not answered yet.
final class _Get {
  _Get(this.spec);

  final ListenSpec spec;
  final Completer<Object?> completer = Completer<Object?>();

  /// The request on the current connection, or null while not sent.
  ServerCall? wire;
}

/// The client's connection to a [FakeDatabaseServer]: the connection state machine of the seam
/// (queueing, replay, reconnect, interrupt), with [FakeDatabaseServer._wire] recording what is sent.
final class _FakeConnection implements ServerActions {
  _FakeConnection(
    this._server,
    this._delegate,
    this._reconnectDelay,
    this._tokens,
  );

  final FakeDatabaseServer _server;
  final ServerActionsDelegate _delegate;
  final Duration _reconnectDelay;
  final RealtimeTokenSource _tokens;
  StreamSubscription<Object?>? _tokenSubscription;

  final Map<ListenSpec, _Listen> _listens = <ListenSpec, _Listen>{};
  final List<_Write> _writes = <_Write>[];

  /// The writes in the order they left on the current connection; answered, purged and dropped
  /// ones have no `wire` and are skipped by [_sentPending].
  final List<_Write> _sendLog = <_Write>[];

  /// The unanswered writes sent on the current connection, in the order they left.
  List<_Write> get _sentPending => <_Write>[
    for (final _Write write in _sendLog)
      if (write.wire != null) write,
  ];
  final List<_Get> _gets = <_Get>[];
  final Set<String> _interrupts = <String>{};

  bool _connected = false;
  bool _connecting = false;
  bool _killed = false;
  bool _closed = false;
  bool _forceToken = false;
  Timer? _timer;

  FakeServerActions get _wire => _server._wire;

  bool get _mayConnect =>
      !_closed &&
      !_killed &&
      _interrupts.isEmpty &&
      !_connected &&
      !_connecting &&
      identical(_server._connection, this);

  List<_Listen> _listensAt(Path path, {required bool answered}) => <_Listen>[
    for (final _Listen listen in _listens.values)
      if (listen.wire != null &&
          listen.answered == answered &&
          listen.path == path)
        listen,
  ];

  List<_Listen> _openListens() => <_Listen>[
    for (final _Listen listen in _listens.values)
      if (listen.wire != null) listen,
  ];

  void _schedule(Duration delay) {
    if (_timer != null || !_mayConnect) {
      return;
    }
    _timer = Timer(delay, _attempt);
  }

  void _attempt() {
    _timer = null;
    if (!_mayConnect) {
      return;
    }
    _server._connectionAttempts++;
    if (!_server.acceptConnections) {
      _schedule(_reconnectDelay);
      return;
    }
    _connecting = true;
    final bool force = _forceToken;
    _forceToken = false;
    _authToken(forceRefresh: force).then((String? token) {
      _connecting = false;
      if (!_mayConnect) {
        return;
      }
      _server._authTokens.add(token);
      _connected = true;
      _wire.isConnected = true;
      for (final _Listen listen in _listens.values.toList()) {
        _sendListen(listen);
      }
      // As PersistentConnection._replay: puts and merges, then onDisconnect requests.
      _sendLog.clear();
      for (final _Write write in _writes.toList()) {
        if (!write.isOnDisconnect) {
          _sendWrite(write);
        }
      }
      for (final _Write write in _writes.toList()) {
        if (write.isOnDisconnect) {
          _sendWrite(write);
        }
      }
      for (final _Get get in _gets.toList()) {
        _sendGet(get);
      }
      _delegate.onConnect();
    });
  }

  void _sendAuth() {
    if (!_connected) {
      return;
    }
    _authToken(forceRefresh: false).then((String? token) {
      if (_connected) {
        _server._authTokens.add(token);
      }
    });
  }

  /// The auth token from [_tokens]; a failing provider counts as no user here, so a test sees null.
  Future<String?> _authToken({required bool forceRefresh}) async {
    try {
      return await _tokens.authToken(forceRefresh: forceRefresh);
    } on Object {
      return null;
    }
  }

  /// Drops the connection: sent transaction puts and sent onDisconnect requests not answered yet complete
  /// with [statusDisconnect], the server applies its onDisconnect writes, then the delegate hears of it;
  /// with [reconnect] a new attempt is scheduled. Other writes and gets are sent again on reconnect.
  void _drop({required bool reconnect}) {
    if (_connected) {
      _connected = false;
      _wire
        ..isConnected = false
        ..activeListens.clear();
      final List<_Write> sentTransactions = <_Write>[
        for (final _Write write in _writes)
          if (write.wire != null &&
              (write.isOnDisconnect ||
                  (write.action == 'put' && write.hash != null)))
            write,
      ];
      for (final _Write write in _writes) {
        write.wire = null;
      }
      for (final _Listen listen in _listens.values) {
        listen
          ..wire = null
          ..answered = false;
      }
      for (final _Get get in _gets) {
        get.wire = null;
      }
      for (final _Write write in sentTransactions) {
        _writes.remove(write);
        write.onComplete?.call(statusDisconnect, null);
      }
      _server._applyOnDisconnect();
      _delegate.onDisconnect();
    }
    if (reconnect) {
      _schedule(_reconnectDelay);
    }
  }

  /// Forgets [listen] without a request, as after a `c` push.
  void _revoke(_Listen listen) {
    _listens.remove(listen.spec);
    _wire.activeListens.remove(listen.spec);
    listen.wire = null;
  }

  void _close() {
    _closed = true;
    _timer?.cancel();
    _timer = null;
    unawaited(_tokenSubscription?.cancel());
    _tokenSubscription = null;
    if (_connected) {
      _connected = false;
      _wire
        ..isConnected = false
        ..activeListens.clear();
    }
    _listens.clear();
    _writes.clear();
    _gets.clear();
  }

  void _sendListen(_Listen listen) {
    late final ServerCall call;
    _wire.listen(
      listen.spec,
      hashProvider: listen.hashProvider,
      tag: listen.tag,
      onComplete: (String status, Object? data) {
        if (!identical(listen.wire, call)) {
          return;
        }
        if (status == statusOk) {
          listen.answered = true;
        } else {
          _listens.remove(listen.spec);
          listen.wire = null;
        }
        listen.onComplete(status, data);
      },
    );
    call = _wire.calls.last;
    listen
      ..wire = call
      ..answered = false
      ..sentHash = listen.hashProvider.simpleHash();
  }

  void _sendWrite(_Write write) {
    late final ServerCall call;
    void done(String status, Object? data) {
      if (!identical(write.wire, call)) {
        return;
      }
      write.wire = null;
      _writes.remove(write);
      write.onComplete?.call(status, data);
    }

    switch (write.action) {
      case 'put':
        _wire.put(write.path, write.data, hash: write.hash, onComplete: done);
      case 'merge':
        _wire.merge(
          write.path,
          write.data! as Map<String, Object?>,
          hash: write.hash,
          onComplete: done,
        );
      case 'onDisconnectPut':
        _wire.onDisconnectPut(write.path, write.data, onComplete: done);
      case 'onDisconnectMerge':
        _wire.onDisconnectMerge(
          write.path,
          write.data! as Map<String, Object?>,
          onComplete: done,
        );
      default:
        _wire.onDisconnectCancel(write.path, onComplete: done);
    }
    call = _wire.calls.last;
    write.wire = call;
    _sendLog.add(write);
  }

  void _sendGet(_Get get) {
    final Future<Object?> answer = _wire.get(get.spec);
    final ServerCall call = _wire.calls.last;
    get.wire = call;
    answer.then<void>(
      (Object? value) {
        if (identical(get.wire, call)) {
          _gets.remove(get);
          get.completer.complete(value);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (identical(get.wire, call)) {
          _gets.remove(get);
          get.completer.completeError(error, stackTrace);
        }
      },
    );
  }

  void _addWrite(_Write write) {
    if (_closed) {
      return;
    }
    _writes.add(write);
    if (_connected) {
      _sendWrite(write);
    }
  }

  @override
  void initialize() => _schedule(Duration.zero);

  @override
  Future<void> shutdown() {
    _close();
    return Future<void>.value();
  }

  @override
  void listen(
    ListenSpec spec, {
    required ListenHashProvider hashProvider,
    int? tag,
    required RequestResultCallback onComplete,
  }) {
    if (_closed) {
      return;
    }
    final _Listen? previous = _listens[spec];
    if (previous != null) {
      _revoke(previous);
    }
    final _Listen listen = _Listen(spec, hashProvider, tag, onComplete);
    _listens[spec] = listen;
    if (_connected) {
      _sendListen(listen);
    }
  }

  @override
  void unlisten(ListenSpec spec, {int? tag}) {
    final _Listen? listen = _listens.remove(spec);
    if (listen == null) {
      return;
    }
    if (_connected && listen.wire != null) {
      _wire.unlisten(spec, tag: tag);
    }
    listen.wire = null;
  }

  @override
  Future<Object?> get(ListenSpec spec) {
    final _Get get = _Get(spec);
    if (_closed) {
      return get.completer.future;
    }
    _gets.add(get);
    if (_connected) {
      _sendGet(get);
    }
    return get.completer.future;
  }

  @override
  void put(
    String path,
    Object? data, {
    String? hash,
    RequestResultCallback? onComplete,
  }) => _addWrite(_Write('put', path, data, hash, onComplete));

  @override
  void merge(
    String path,
    Map<String, Object?> data, {
    String? hash,
    RequestResultCallback? onComplete,
  }) => _addWrite(_Write('merge', path, data, hash, onComplete));

  @override
  void onDisconnectPut(
    String path,
    Object? data, {
    RequestResultCallback? onComplete,
  }) => _addWrite(_Write('onDisconnectPut', path, data, null, onComplete));

  @override
  void onDisconnectMerge(
    String path,
    Map<String, Object?> data, {
    RequestResultCallback? onComplete,
  }) => _addWrite(_Write('onDisconnectMerge', path, data, null, onComplete));

  @override
  void onDisconnectCancel(String path, {RequestResultCallback? onComplete}) =>
      _addWrite(_Write('onDisconnectCancel', path, null, null, onComplete));

  /// As the real connection does: every put and merge not answered, then every onDisconnect
  /// request queued while offline (not sent), each in the order made, completes with
  /// `write_canceled` in a microtask and is never sent. A sent onDisconnect request is left for its
  /// answer or the drop. An answer the test gives later through [_wire] for a purged write is
  /// ignored, and [FakeDatabaseServer.ackLastWrite] and its siblings no longer see it.
  @override
  void purgeOutstandingWrites() {
    final List<_Write> canceled = <_Write>[
      for (final _Write write in _writes)
        if (!write.isOnDisconnect) write,
      for (final _Write write in _writes)
        if (write.isOnDisconnect && write.wire == null) write,
    ];
    for (final _Write write in canceled) {
      _writes.remove(write);
      write.wire = null;
    }
    scheduleMicrotask(() {
      for (final _Write write in canceled) {
        write.onComplete?.call(
          'write_canceled',
          'The write was canceled by the user.',
        );
      }
    });
  }

  @override
  void interrupt(String reason) {
    _interrupts.add(reason);
    _timer?.cancel();
    _timer = null;
    scheduleMicrotask(() {
      if (_interrupts.isNotEmpty) {
        _drop(reconnect: false);
      }
    });
  }

  @override
  void resume(String reason) {
    _interrupts.remove(reason);
    if (_interrupts.isEmpty) {
      _timer?.cancel();
      _timer = null;
      _schedule(Duration.zero);
    }
  }

  @override
  bool isInterrupted(String reason) => _interrupts.contains(reason);
}
