/// A recording fake of the connection, for tests of Repo and the sync tree. No upstream file
/// (JS tests stub `ServerActions` ad hoc; Android tests use mocks of `PersistentConnection`).
///
/// Real code, not a stub: it is part of the frozen test support.
library;

import 'dart:async';

import 'package:firebase_database_dart/src/core/connection/listen_hash_provider.dart';
import 'package:firebase_database_dart/src/core/connection/listen_spec.dart';
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/core/connection/wire_range_merge.dart';
import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/util/server_values.dart';

/// One call made on a [FakeServerActions], in the order made.
final class ServerCall {
  /// Records a call.
  ServerCall(
    this.action, {
    this.path,
    this.data,
    this.hash,
    this.spec,
    this.tag,
    this.hashProvider,
    this.onComplete,
    this.getCompleter,
  });

  /// The method name: `initialize`, `shutdown`, `listen`, `unlisten`, `get`, `put`, `merge`,
  /// `onDisconnectPut`, `onDisconnectMerge`, `onDisconnectCancel`, `purgeOutstandingWrites`,
  /// `interrupt`, `resume`.
  final String action;

  /// The path of a write (`/a/b`), or the reason of interrupt/resume.
  final String? path;

  /// The data of a write.
  final Object? data;

  /// The hash of a transaction put.
  final String? hash;

  /// The listen or get spec.
  final ListenSpec? spec;

  /// The listen tag.
  final int? tag;

  /// The hash provider of a listen.
  final ListenHashProvider? hashProvider;

  /// The completion of a request.
  final RequestResultCallback? onComplete;

  /// The future of a get.
  final Completer<Object?>? getCompleter;

  /// Whether [FakeServerActions.respond] was called.
  bool get answered => _answered;
  bool _answered = false;

  /// Whether the request has left: made while the fake was connected, or still unanswered at a
  /// later [FakeServerActions.connect], which replays it as the real connection does. Otherwise
  /// it is one the connection queues while offline.
  bool get sent => _sent;
  bool _sent = false;

  /// Whether a listen was answered `ok`: the server may still revoke it once, with an error.
  bool _listenOk = false;

  @override
  String toString() =>
      'ServerCall($action${path == null ? '' : ' $path'}'
      '${spec == null ? '' : ' ${spec!.path} ${spec!.queryIdentifier}'}'
      '${tag == null ? '' : ' t=$tag'}${hash == null ? '' : ' h=$hash'})';
}

/// A [ServerActions] that records every call in [calls] and lets a test play the server: answer
/// requests with [respond], push data with [deliverDataUpdate] and [deliverRangeMerge], and drop
/// or restore the connection with [disconnect] and [connect].
///
/// Writes must be answered in the order they left: answering a put, merge or onDisconnect request
/// while one sent before it is unanswered, or one that was never sent on the current connection,
/// throws a [StateError], unless the call passes `outOfOrder: true` (see [respond]). The order is
/// the one the real connection sends in: a request made while connected leaves at once, and
/// [connect] replays the unanswered puts and merges first, then the onDisconnect requests, as
/// `PersistentConnection._replay` does. That the server answers writes in that order is inferred
/// from the emulator probe (`rtdb_emulator_probe.md`, addendum 2 item 4), which measured a
/// pipelined `auth`, listen, get, `unauth`, get answered in order; it sent no write. Listens and
/// gets were answered in order there too; this fake does not check their order.
///
/// It follows the reconnect contract of [ServerActions]: on [disconnect], sent transaction puts
/// (puts with a hash) are answered with [statusDisconnect] before the delegate hears of it; other
/// unanswered writes stay pending. Nothing is called back synchronously from inside a
/// [ServerActions] method.
///
/// Server pushes take the path as the server sends it (`a/b`, `""` for the root) and reach the
/// delegate normalised to `/a/b` (`/`), as a real connection does. A failed [get] fails with a
/// [ServerActionsException].
final class FakeServerActions implements ServerActions {
  /// Creates a fake; set [delegate] before delivering anything.
  FakeServerActions([this.delegate]);

  /// The receiver of server pushes, normally the Repo.
  ServerActionsDelegate? delegate;

  /// Every call, in order.
  final List<ServerCall> calls = <ServerCall>[];

  /// The active listens by spec.
  final Map<ListenSpec, ServerCall> activeListens = <ListenSpec, ServerCall>{};

  final Set<String> _interruptReasons = <String>{};

  /// Whether [shutdown] was called.
  bool isShutdown = false;

  /// Whether the fake is connected: [connect] sets it, [disconnect] clears it.
  ///
  /// Setting it by hand changes the send order as those do, without telling the delegate or
  /// answering anything: false forgets what was sent on the connection; true (from false) counts
  /// every unanswered request as sent and replays the unanswered writes, puts and merges first.
  bool get isConnected => _isConnected;
  set isConnected(bool value) {
    if (value == _isConnected) {
      return;
    }
    _isConnected = value;
    if (!value) {
      _sendLog.clear();
      return;
    }
    for (final ServerCall call in calls) {
      if (!call._answered) {
        call._sent = true;
      }
    }
    final List<ServerCall> pending = pendingWrites;
    _sendLog
      ..clear()
      ..addAll(pending.where((ServerCall c) => _putOrMerge.contains(c.action)))
      ..addAll(
        pending.where(
          (ServerCall c) => _onDisconnectActions.contains(c.action),
        ),
      );
  }

  bool _isConnected = false;

  /// The calls with action [action].
  List<ServerCall> callsOf(String action) =>
      calls.where((ServerCall call) => call.action == action).toList();

  /// The writes (put, merge, onDisconnect) not answered yet, in order.
  List<ServerCall> get pendingWrites => calls
      .where(
        (ServerCall call) =>
            _writeActions.contains(call.action) && !call.answered,
      )
      .toList();

  static const Set<String> _writeActions = <String>{
    'put',
    'merge',
    'onDisconnectPut',
    'onDisconnectMerge',
    'onDisconnectCancel',
  };

  /// The writes in the order they left on the current connection; answered ones stay in it.
  final List<ServerCall> _sendLog = <ServerCall>[];

  ServerCall _record(ServerCall call) {
    call._sent = isConnected;
    calls.add(call);
    if (isConnected && _writeActions.contains(call.action)) {
      _sendLog.add(call);
    }
    return call;
  }

  /// The wire path form of the seam: `/a/b`, `/` for the root, from the server's `a/b` or `""`.
  static String normalizePath(String path) =>
      path.startsWith('/') ? path : '/$path';

  ServerActionsDelegate get _delegate {
    final ServerActionsDelegate? value = delegate;
    if (value == null) {
      throw StateError('FakeServerActions.delegate is not set.');
    }
    return value;
  }

  @override
  void initialize() => _record(ServerCall('initialize'));

  @override
  Future<void> shutdown() async {
    _record(ServerCall('shutdown'));
    isShutdown = true;
    activeListens.clear();
    for (final ServerCall call in callsOf('get')) {
      if (!call._answered) {
        call._answered = true;
        call.getCompleter!.completeError(
          const ServerActionsException('database_closed'),
        );
      }
    }
  }

  @override
  void listen(
    ListenSpec spec, {
    required ListenHashProvider hashProvider,
    int? tag,
    required RequestResultCallback onComplete,
  }) {
    if (activeListens.containsKey(spec)) {
      throw StateError('listen() called twice for the same query: $spec');
    }
    final ServerCall call = _record(
      ServerCall(
        'listen',
        spec: spec,
        tag: tag,
        hashProvider: hashProvider,
        onComplete: onComplete,
      ),
    );
    activeListens[spec] = call;
  }

  @override
  void unlisten(ListenSpec spec, {int? tag}) {
    _record(ServerCall('unlisten', spec: spec, tag: tag));
    activeListens.remove(spec);
  }

  @override
  Future<Object?> get(ListenSpec spec) {
    final Completer<Object?> completer = Completer<Object?>();
    _record(ServerCall('get', spec: spec, getCompleter: completer));
    return completer.future;
  }

  @override
  void put(
    String path,
    Object? data, {
    String? hash,
    RequestResultCallback? onComplete,
  }) => _record(
    ServerCall(
      'put',
      path: path,
      data: data,
      hash: hash,
      onComplete: onComplete,
    ),
  );

  @override
  void merge(
    String path,
    Map<String, Object?> data, {
    String? hash,
    RequestResultCallback? onComplete,
  }) => _record(
    ServerCall(
      'merge',
      path: path,
      data: data,
      hash: hash,
      onComplete: onComplete,
    ),
  );

  @override
  void onDisconnectPut(
    String path,
    Object? data, {
    RequestResultCallback? onComplete,
  }) => _record(
    ServerCall(
      'onDisconnectPut',
      path: path,
      data: data,
      onComplete: onComplete,
    ),
  );

  @override
  void onDisconnectMerge(
    String path,
    Map<String, Object?> data, {
    RequestResultCallback? onComplete,
  }) => _record(
    ServerCall(
      'onDisconnectMerge',
      path: path,
      data: data,
      onComplete: onComplete,
    ),
  );

  @override
  void onDisconnectCancel(String path, {RequestResultCallback? onComplete}) =>
      _record(
        ServerCall('onDisconnectCancel', path: path, onComplete: onComplete),
      );

  /// As the real connection does: every unanswered put and merge, sent or not, then every
  /// onDisconnect request not yet [ServerCall.sent], each in call order, completes with
  /// `write_canceled` (no reason), one microtask per completion, never inside this call. A sent
  /// onDisconnect request is left for its own answer or a [disconnect].
  ///
  /// The purged calls count as answered at once: a later [respond], [queueResponse] or
  /// [ackWrite] for one throws a [StateError] (the fake's rule for a second answer), and
  /// [pendingWrites], [disconnect] and the `*Last*` helpers skip them. The real connection
  /// instead drops a server answer for a purged write without a word.
  @override
  void purgeOutstandingWrites() {
    _record(ServerCall('purgeOutstandingWrites'));
    final List<ServerCall> pending = pendingWrites;
    final List<ServerCall> purged = <ServerCall>[
      for (final ServerCall call in pending)
        if (call.action == 'put' || call.action == 'merge') call,
      for (final ServerCall call in pending)
        if (call.action.startsWith('onDisconnect') && !call.sent) call,
    ];
    for (final ServerCall call in purged) {
      call._answered = true;
      scheduleMicrotask(
        () => call.onComplete?.call(
          DatabaseErrorCode.writeCanceled.wireStatus,
          null,
        ),
      );
    }
  }

  @override
  void interrupt(String reason) {
    _record(ServerCall('interrupt', path: reason));
    _interruptReasons.add(reason);
  }

  @override
  void resume(String reason) {
    _record(ServerCall('resume', path: reason));
    _interruptReasons.remove(reason);
  }

  @override
  bool isInterrupted(String reason) => _interruptReasons.contains(reason);

  // The server side, driven by the test.

  /// Answers [call] with [status] and [data]; a failed listen leaves the listen table, a get
  /// completes its future (with a [ServerActionsException] unless [status] is `ok`).
  ///
  /// Throws a [StateError] for a second answer to one call, except the one revoke of a listen
  /// answered `ok`.
  ///
  /// A write (put, merge, onDisconnectPut, onDisconnectMerge, onDisconnectCancel) must be the
  /// oldest unanswered one sent on the current connection (see the class doc); otherwise this
  /// throws a [StateError] naming both, or saying the write was never sent. Pass [outOfOrder] true
  /// only for a test that models something a server does not do, and say why next to it. The
  /// order of listens and gets is not checked.
  void respond(
    ServerCall call, {
    String status = statusOk,
    Object? data,
    bool outOfOrder = false,
  }) => _respond(
    call,
    'respond',
    status: status,
    data: data,
    outOfOrder: outOfOrder,
  );

  void _respond(
    ServerCall call,
    String helper, {
    String status = statusOk,
    Object? data,
    bool outOfOrder = false,
  }) {
    if (!outOfOrder) {
      _checkSendOrder(call, helper);
    }
    final bool revoke =
        call._answered &&
        call._listenOk &&
        status != statusOk &&
        call.action == 'listen';
    if (call._answered && !revoke) {
      throw StateError('$call was already answered.');
    }
    call._answered = true;
    if (revoke) {
      call._listenOk = false;
    } else if (call.action == 'listen' && status == statusOk) {
      call._listenOk = true;
    }
    final Completer<Object?>? completer = call.getCompleter;
    if (completer != null) {
      if (status == statusOk) {
        completer.complete(data);
      } else {
        completer.completeError(
          ServerActionsException(status, data?.toString()),
        );
      }
      return;
    }
    if (call.action == 'listen' && status != statusOk) {
      activeListens.remove(call.spec);
    }
    call.onComplete?.call(status, data);
  }

  /// Answers the put or merge [call] as a connection that has received the answer but not yet
  /// delivered it: the call counts as answered now (a later [purgeOutstandingWrites] or
  /// [disconnect] skips it), and the delegate hears [status] in a microtask. Ordered as in
  /// [respond].
  void queueResponse(
    ServerCall call, {
    String status = statusOk,
    bool outOfOrder = false,
  }) {
    if (call.action != 'put' && call.action != 'merge') {
      throw ArgumentError.value(call, 'call', 'Not a put or merge.');
    }
    if (call._answered) {
      throw StateError('$call was already answered.');
    }
    if (!outOfOrder) {
      _checkSendOrder(call, 'queueResponse');
    }
    call._answered = true;
    scheduleMicrotask(() => call.onComplete?.call(status, null));
  }

  /// Answers the listen of [spec] (see [respond]).
  void respondToListen(
    ListenSpec spec, {
    String status = statusOk,
    Object? data,
  }) {
    final ServerCall? call = activeListens[spec];
    if (call == null) {
      throw StateError('No active listen for $spec.');
    }
    respond(call, status: status, data: data);
  }

  /// Revokes the listen of [spec] as a `c` push does: completes it with `permission_denied`.
  void revokeListen(ListenSpec spec) => respondToListen(
    spec,
    status: 'permission_denied',
    data: "Client doesn't have permission to access the desired data.",
  );

  /// Pushes `d` ([isMerge] false) or `m` at [path] (either form), tagged with [tag]; merge keys
  /// are passed on unchanged.
  void deliverDataUpdate(
    String path,
    Object? data, {
    bool isMerge = false,
    int? tag,
  }) {
    if (tag == null) {
      _storeUpdate(normalizePath(path), data, isMerge: isMerge);
    }
    _delegate.onDataUpdate(
      normalizePath(path),
      data,
      isMerge: isMerge,
      tag: tag,
    );
  }

  /// Pushes `rm` at [path] (either form).
  void deliverRangeMerge(
    String path,
    List<WireRangeMerge> merges, {
    int? tag,
  }) => _delegate.onRangeMergeUpdate(normalizePath(path), merges, tag: tag);

  /// The server's clock for `{'.sv': 'timestamp'}` in acknowledged writes (milliseconds since
  /// the epoch); settable.
  int Function() serverTimeMillis = () => DateTime.now().millisecondsSinceEpoch;

  /// The data the fake server holds: untagged pushes ([deliverDataUpdate]) and acknowledged
  /// writes, in export form.
  Object? get data => _store.toJson(exportFormat: true);
  Node _store = ChildrenNode.empty;

  /// The stored data at [path] (either form), in export form.
  Object? dataAt(String path) =>
      _store.getChild(Path(path)).toJson(exportFormat: true);

  /// Acknowledges the most recently sent unanswered put or merge (see [ackWrite]). With another
  /// write or onDisconnect request sent before it unanswered this is out of order and throws,
  /// unless [outOfOrder] is true.
  void ackLastWrite({bool outOfOrder = false}) => _ackWrite(
    _lastPending(_putOrMerge),
    'ackLastWrite',
    outOfOrder: outOfOrder,
  );

  /// Acknowledges the oldest sent unanswered put or merge (see [ackWrite]). Throws a [StateError]
  /// when an onDisconnect request sent before it is unanswered, or when no put or merge is sent
  /// and unanswered.
  void ackNextWrite() => _ackWrite(_nextPending(_putOrMerge), 'ackNextWrite');

  /// Acknowledges the put or merge [call] as the measured server does.
  ///
  /// A put with a hash that does not match the stored data at its path answers `datastale` with
  /// the stored value as data and changes nothing. Otherwise server values are resolved (the
  /// timestamp from [serverTimeMillis], an increment against the stored value), the data is
  /// stored and pushed once to each overlapping listen (a tagged listen gets the path data with
  /// its tag, unfiltered), and then the write is answered `ok`: the push comes before the ack.
  /// Ordered as in [respond].
  void ackWrite(ServerCall call, {bool outOfOrder = false}) =>
      _ackWrite(call, 'ackWrite', outOfOrder: outOfOrder);

  void _ackWrite(ServerCall call, String helper, {bool outOfOrder = false}) {
    if (call.action != 'put' && call.action != 'merge') {
      throw ArgumentError.value(call, 'call', 'Not a put or merge.');
    }
    if (call._answered) {
      throw StateError('$call was already answered.');
    }
    if (!outOfOrder) {
      _checkSendOrder(call, helper);
    }
    final String writePath = normalizePath(call.path!);
    final String? hash = call.hash;
    if (hash != null && _store.getChild(Path(writePath)).hash() != hash) {
      respond(
        call,
        status: 'datastale',
        data: dataAt(writePath),
        outOfOrder: true,
      );
      return;
    }
    final Map<String, Object?> serverValues = generateServerValues(
      timestamp: serverTimeMillis(),
    );
    final Object? resolved;
    if (call.action == 'put') {
      resolved = resolveDeferredValueSnapshot(
        nodeFromJson(call.data),
        _store.getChild(Path(writePath)),
        serverValues,
      ).toJson(exportFormat: true);
    } else {
      resolved = <String, Object?>{
        for (final MapEntry<String, Object?> entry
            in (call.data! as Map<String, Object?>).entries)
          entry.key: resolveDeferredValueSnapshot(
            nodeFromJson(entry.value),
            _store.getChild(Path(writePath).childPath(Path(entry.key))),
            serverValues,
          ).toJson(exportFormat: true),
      };
    }
    _storeUpdate(writePath, resolved, isMerge: call.action == 'merge');
    _pushWrite(writePath, resolved, isMerge: call.action == 'merge');
    respond(call, outOfOrder: true);
  }

  /// Refuses the most recently sent unanswered put or merge with [status] (`permission_denied`,
  /// `datastale`, ...) and the optional [reason]; pushes and stores nothing. Ordered as
  /// [ackLastWrite], with the same [outOfOrder].
  void failLastWrite(
    String status, {
    String? reason,
    bool outOfOrder = false,
  }) => _respond(
    _lastPending(_putOrMerge),
    'failLastWrite',
    status: status,
    data: reason,
    outOfOrder: outOfOrder,
  );

  /// Refuses the oldest sent unanswered put or merge with [status] and the optional [reason].
  /// Throws as [ackNextWrite] does.
  void failNextWrite(String status, {String? reason}) => _respond(
    _nextPending(_putOrMerge),
    'failNextWrite',
    status: status,
    data: reason,
  );

  /// Acknowledges the most recently sent unanswered onDisconnect request. Ordered as
  /// [ackLastWrite], with the same [outOfOrder].
  void ackLastOnDisconnect({bool outOfOrder = false}) => _respond(
    _lastPending(_onDisconnectActions),
    'ackLastOnDisconnect',
    outOfOrder: outOfOrder,
  );

  /// Acknowledges the oldest sent unanswered onDisconnect request. Throws a [StateError] when a
  /// put or merge sent before it is unanswered, or when no onDisconnect request is sent and
  /// unanswered.
  void ackNextOnDisconnect() =>
      _respond(_nextPending(_onDisconnectActions), 'ackNextOnDisconnect');

  static const Set<String> _putOrMerge = <String>{'put', 'merge'};

  static const Set<String> _onDisconnectActions = <String>{
    'onDisconnectPut',
    'onDisconnectMerge',
    'onDisconnectCancel',
  };

  /// The unanswered writes sent on the current connection, in the order they left.
  List<ServerCall> get _sentPending => <ServerCall>[
    for (final ServerCall call in _sendLog)
      if (!call._answered) call,
  ];

  List<ServerCall> _pendingOf(Set<String> actions) {
    final List<ServerCall> pending = <ServerCall>[
      for (final ServerCall call in _sentPending)
        if (actions.contains(call.action)) call,
    ];
    if (pending.isEmpty) {
      throw StateError('No sent, unanswered request of $actions.');
    }
    return pending;
  }

  ServerCall _lastPending(Set<String> actions) => _pendingOf(actions).last;

  ServerCall _nextPending(Set<String> actions) => _pendingOf(actions).first;

  /// Throws when [call] is a write that was not sent on the current connection, or a write sent
  /// before it is still unanswered.
  void _checkSendOrder(ServerCall call, String helper) {
    if (!_writeActions.contains(call.action) || call._answered) {
      return;
    }
    final List<ServerCall> sent = _sentPending;
    if (!sent.contains(call)) {
      throw StateError(
        '$helper answers $call (call ${calls.indexOf(call)}), which was not sent on the '
        'current connection: it was made while offline, or sent before the last disconnect(), '
        'and connect() has not sent it again. Call connect() first, or pass outOfOrder: true '
        'with a reason.',
      );
    }
    final ServerCall oldest = sent.first;
    if (identical(oldest, call)) {
      return;
    }
    throw StateError(
      '$helper answers $call (call ${calls.indexOf(call)}) while $oldest '
      '(call ${calls.indexOf(oldest)}), sent before it, is unanswered. Writes are answered '
      'in the order they left: answer the earlier one first (ackNextWrite, failNextWrite, '
      'ackNextOnDisconnect), or pass outOfOrder: true with a reason.',
    );
  }

  void _storeUpdate(String path, Object? data, {required bool isMerge}) {
    final Path at = Path(path);
    if (!isMerge) {
      _store = _store.updateChild(at, nodeFromJson(data));
      return;
    }
    for (final MapEntry<Object?, Object?> entry
        in (data! as Map<Object?, Object?>).entries) {
      _store = _store.updateChild(
        at.childPath(Path('${entry.key}')),
        nodeFromJson(entry.value),
      );
    }
  }

  /// Whether a tagged listen gets the whole data at its path for every write that overlaps it,
  /// instead of the write itself.
  ///
  /// Measured on the emulator (probe addendum 5): the server pushes a deep write at its deep path
  /// only when the written child is already in the query's window; a child entering the window is
  /// pushed whole at the child's path, and a child leaving while another enters comes as one merge
  /// at the query's path. A client therefore never gets a deep write below a child it does not
  /// hold. This fake does not model windows: false pushes every write as written, true pushes the
  /// whole data, which is the form that is right for any window.
  bool taggedListensGetWholeData = false;

  /// Pushes a write at [writePath] once to each overlapping listen.
  void _pushWrite(String writePath, Object? data, {required bool isMerge}) {
    for (final ServerCall listen in activeListens.values.toList()) {
      final String listenPath = listen.spec!.path;
      final int? tag = listen.tag;
      final bool whole = tag != null && taggedListensGetWholeData;
      if (_covers(listenPath, writePath) && !whole) {
        _delegate.onDataUpdate(writePath, data, isMerge: isMerge, tag: tag);
      } else if (_covers(writePath, listenPath) ||
          _covers(listenPath, writePath)) {
        // The listen lies below the write: it gets its own path's data.
        _delegate.onDataUpdate(
          listenPath,
          dataAt(listenPath),
          tag: tag,
          isMerge: false,
        );
      }
    }
  }

  /// Another client writes [data] at [path] (either form; a map of children when [isMerge]):
  /// the data is stored, and pushed once to each overlapping listen while [isConnected].
  void writeByOtherClient(String path, Object? data, {bool isMerge = false}) {
    final String writePath = normalizePath(path);
    _storeUpdate(writePath, data, isMerge: isMerge);
    if (isConnected) {
      _pushWrite(writePath, data, isMerge: isMerge);
    }
  }

  /// Whether [outer] is [inner] or one of its ancestors (both `/a/b` form).
  static bool _covers(String outer, String inner) =>
      outer == '/' || inner == outer || inner.startsWith('$outer/');

  /// Reports the connection up (after the replay): every unanswered request counts as
  /// [ServerCall.sent] from now on. The unanswered puts and merges leave first, then the
  /// onDisconnect requests, each in call order, as `PersistentConnection._replay` sends them.
  void connect() {
    isConnected = true;
    for (final ServerCall call in calls) {
      if (!call._answered) {
        call._sent = true;
      }
    }
    _delegate.onConnect();
  }

  /// Drops the connection: sent transaction puts are answered with [statusDisconnect], then the
  /// delegate hears [ServerActionsDelegate.onDisconnect]. A call answered while this runs (a
  /// handler that purges) is not answered again.
  void disconnect() {
    isConnected = false;
    for (final ServerCall call in pendingWrites) {
      if (call.answered) {
        continue;
      }
      if (call.action == 'put' && call.hash != null ||
          call.action.startsWith('onDisconnect') && call.sent) {
        // The connection is gone, so the send order no longer applies.
        respond(call, status: statusDisconnect, outOfOrder: true);
      }
    }
    _delegate.onDisconnect();
  }

  /// Reports the server's time offset.
  void deliverServerTimeOffset(int offsetMillis) => _delegate
      .onServerInfoUpdate(<String, Object?>{'serverTimeOffset': offsetMillis});

  /// Reports an auth status (`ok` or a revoke status).
  void deliverAuthStatus(String status, {String? explanation}) =>
      _delegate.onAuthStatus(status, explanation: explanation);

  /// Reports an App Check status.
  void deliverAppCheckStatus(String status, {String? explanation}) =>
      _delegate.onAppCheckStatus(status, explanation: explanation);

  /// Shuts the client down from the server side.
  void deliverServerShutdown(String reason) =>
      _delegate.onServerShutdown(reason);
}
