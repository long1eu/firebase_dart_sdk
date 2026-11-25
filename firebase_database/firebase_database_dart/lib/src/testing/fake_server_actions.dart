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
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/util/server_values.dart';
import 'package:firebase_database_dart/src/testing/json_server_model.dart';

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

  /// Whether [connect] was called more recently than [disconnect].
  bool isConnected = false;

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

  ServerCall _record(ServerCall call) {
    call._sent = isConnected;
    calls.add(call);
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
  void respond(ServerCall call, {String status = statusOk, Object? data}) {
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
  /// [disconnect] skips it), and the delegate hears [status] in a microtask.
  void queueResponse(ServerCall call, {String status = statusOk}) {
    if (call.action != 'put' && call.action != 'merge') {
      throw ArgumentError.value(call, 'call', 'Not a put or merge.');
    }
    if (call._answered) {
      throw StateError('$call was already answered.');
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
  /// writes, in export form, as a reader sees it.
  Object? get data => _model.export('', hidden: false);

  /// The server's data and write rules (shared with the property test's server model).
  final JsonServerModel _model = JsonServerModel();

  /// The stored data at [path] (either form), in export form, as the server sends it: a node
  /// emptied by a write below it, which keeps its priority, reads `{".priority": p}`.
  Object? dataAt(String path) => _model.export(path, hidden: true);

  /// The stored node at [path], read back as a client node (for resolving server values).
  Node _nodeAt(String path) => nodeFromServerJson(dataAt(path));

  /// Acknowledges the most recent unanswered put or merge (see [ackWrite]).
  void ackLastWrite() => ackWrite(_lastPending(const <String>{'put', 'merge'}));

  /// Acknowledges the put or merge [call] as the measured server does.
  ///
  /// A put with a hash that does not match the stored data at its path answers `datastale` with
  /// the stored value as data and changes nothing. Otherwise server values are resolved (the
  /// timestamp from [serverTimeMillis], an increment against the stored value), the data is
  /// stored and pushed once to each overlapping listen (a tagged listen gets the path data with
  /// its tag, unfiltered), and then the write is answered `ok`: the push comes before the ack.
  void ackWrite(ServerCall call) {
    if (call.action != 'put' && call.action != 'merge') {
      throw ArgumentError.value(call, 'call', 'Not a put or merge.');
    }
    if (call._answered) {
      throw StateError('$call was already answered.');
    }
    final String writePath = normalizePath(call.path!);
    final String? hash = call.hash;
    if (hash != null && _model.hash(writePath) != hash) {
      respond(call, status: 'datastale', data: dataAt(writePath));
      return;
    }
    final Map<String, Object?> serverValues = generateServerValues(
      timestamp: serverTimeMillis(),
    );
    final Object? resolved;
    if (call.action == 'put') {
      resolved = resolveDeferredValueSnapshot(
        nodeFromJson(call.data),
        _nodeAt(writePath),
        serverValues,
      ).toJson(exportFormat: true);
    } else {
      resolved = <String, Object?>{
        for (final MapEntry<String, Object?> entry
            in (call.data! as Map<String, Object?>).entries)
          entry.key: resolveDeferredValueSnapshot(
            nodeFromJson(entry.value),
            _nodeAt(Path(writePath).childPath(Path(entry.key)).toString()),
            serverValues,
          ).toJson(exportFormat: true),
      };
    }
    if (!_storeUpdate(writePath, resolved, isMerge: call.action == 'merge')) {
      respond(
        call,
        status: 'invalid_parameters',
        data: 'could not set priority on non-existent node',
      );
      return;
    }
    _pushWrite(writePath, resolved, isMerge: call.action == 'merge');
    respond(call);
  }

  /// Refuses the most recent unanswered put or merge with [status] (`permission_denied`,
  /// `datastale`, ...) and the optional [reason]; pushes and stores nothing.
  void failLastWrite(String status, [String? reason]) => respond(
    _lastPending(const <String>{'put', 'merge'}),
    status: status,
    data: reason,
  );

  /// Acknowledges the most recent unanswered onDisconnect request.
  void ackLastOnDisconnect() => respond(
    _lastPending(const <String>{
      'onDisconnectPut',
      'onDisconnectMerge',
      'onDisconnectCancel',
    }),
  );

  ServerCall _lastPending(Set<String> actions) {
    final List<ServerCall> pending = pendingWrites
        .where((ServerCall call) => actions.contains(call.action))
        .toList();
    if (pending.isEmpty) {
      throw StateError('No unanswered request of $actions.');
    }
    return pending.last;
  }

  /// Applies a write to the stored data as the server does ([JsonServerModel.write]); false when
  /// the server refuses it (a priority on a node that does not exist).
  bool _storeUpdate(String path, Object? data, {required bool isMerge}) =>
      _model.write(path, data, merge: isMerge);

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
  /// the data is stored, and pushed once to each overlapping listen while [isConnected]. A write
  /// the server refuses (a priority on a node that does not exist) changes and pushes nothing.
  void writeByOtherClient(String path, Object? data, {bool isMerge = false}) {
    final String writePath = normalizePath(path);
    if (!_storeUpdate(writePath, data, isMerge: isMerge)) {
      return;
    }
    if (isConnected) {
      _pushWrite(writePath, data, isMerge: isMerge);
    }
  }

  /// Whether [outer] is [inner] or one of its ancestors (both `/a/b` form).
  static bool _covers(String outer, String inner) =>
      outer == '/' || inner == outer || inner.startsWith('$outer/');

  /// Reports the connection up (after the replay): every unanswered request counts as
  /// [ServerCall.sent] from now on.
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
        respond(call, status: statusDisconnect);
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
