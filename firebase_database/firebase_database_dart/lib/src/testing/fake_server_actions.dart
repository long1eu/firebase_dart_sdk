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
  FakeServerActions([this.delegate]) : readOnly = false;

  /// Creates a read-only fake, as the REST client is: every write and onDisconnect request is
  /// recorded and completed with [statusReadOnly] in a microtask.
  FakeServerActions.readOnly([this.delegate]) : readOnly = true;

  /// Whether writes and onDisconnect requests are refused with [statusReadOnly].
  final bool readOnly;

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
    calls.add(call);
    if (readOnly && _writeActions.contains(call.action)) {
      scheduleMicrotask(() {
        if (!call._answered) {
          respond(
            call,
            status: statusReadOnly,
            data: 'This database is read-only here.',
          );
        }
      });
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

  @override
  void purgeOutstandingWrites() {
    _record(ServerCall('purgeOutstandingWrites'));
    for (final ServerCall call in pendingWrites) {
      if (call.action == 'put' || call.action == 'merge') {
        respond(
          call,
          status: 'write_canceled',
          data: 'The write was canceled by the user.',
        );
      }
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
  void respond(ServerCall call, {String status = statusOk, Object? data}) {
    if (call._answered) {
      throw StateError('$call was already answered.');
    }
    call._answered = true;
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
  }) => _delegate.onDataUpdate(
    normalizePath(path),
    data,
    isMerge: isMerge,
    tag: tag,
  );

  /// Pushes `rm` at [path] (either form).
  void deliverRangeMerge(
    String path,
    List<WireRangeMerge> merges, {
    int? tag,
  }) => _delegate.onRangeMergeUpdate(normalizePath(path), merges, tag: tag);

  /// Reports the connection up (after the replay).
  void connect() {
    isConnected = true;
    _delegate.onConnect();
  }

  /// Drops the connection: sent transaction puts are answered with [statusDisconnect], then the
  /// delegate hears [ServerActionsDelegate.onDisconnect].
  void disconnect() {
    isConnected = false;
    for (final ServerCall call in pendingWrites) {
      if (call.action == 'put' && call.hash != null) {
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
