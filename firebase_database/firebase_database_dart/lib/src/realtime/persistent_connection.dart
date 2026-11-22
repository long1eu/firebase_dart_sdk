/// The connection that survives disconnects (owner P): requests, the listen table, puts, gets,
/// the onDisconnect queue, replay after reconnect, `.info` callbacks and interrupt/resume
/// (`rtdb_protocol.md` 4, 5 and 8). The implementation of the core's [ServerActions] seam.
library;

import 'dart:async';

import 'package:firebase_database_dart/src/core/connection/listen_hash_provider.dart';
import 'package:firebase_database_dart/src/core/connection/listen_spec.dart';
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/core/util/logger.dart';
import 'package:firebase_database_dart/src/realtime/auth_session.dart';
import 'package:firebase_database_dart/src/realtime/connection.dart';
import 'package:firebase_database_dart/src/realtime/connection_timings.dart';
import 'package:firebase_database_dart/src/realtime/realtime_error.dart';
import 'package:firebase_database_dart/src/realtime/realtime_target.dart';
import 'package:firebase_database_dart/src/realtime/reconnect_backoff.dart';
import 'package:firebase_database_dart/src/realtime/replay.dart';
import 'package:firebase_database_dart/src/realtime/request_table.dart';
import 'package:firebase_database_dart/src/realtime/server_message.dart';

/// Creates the [RealtimeConnection] of the next attempt for [delegate] (test plan section 5).
/// Production passes a closure over `RealtimeConnection` and the platform connector; tests return a
/// connection over the fake connector.
typedef RealtimeConnectionFactory =
    RealtimeConnection Function(
      RealtimeDelegate delegate, {
      String? lastSessionId,
      String? appId,
      String? appCheckToken,
    });

/// The WebSocket implementation of [ServerActions] (test plan section 5, P gives the Repo half).
///
/// Follows the reconnect contract of [ServerActions]: after each hello it replays auth, App Check,
/// listens (hash recomputed through their [ListenHashProvider]), unacknowledged puts and merges,
/// unsent onDisconnects and outstanding gets (8.4), then calls
/// [ServerActionsDelegate.onConnect]. Sent transaction puts complete with [statusDisconnect] on a
/// disconnect (8.5).
///
/// Paths cross the seam as `/a/b` both ways; the server pushes them without the leading slash
/// (emulator probe, measured), and the decoded pushes already carry it (`wirePathFromServer` in
/// `server_message.dart`, `rtdb_seam_changes.md` A.3). [get] fails with a
/// [ServerActionsException] (A.2).
/// Merge maps are handed over with their keys as the server sent them. A `c` push cancels every
/// listen at its path with `permission_denied` (lead's decision). Every delegate call and every
/// [RequestResultCallback] runs on the event loop, never synchronously inside a call of this
/// class. Before each attempt the tokens are fetched through an [AuthSession] built over the
/// given [RealtimeTokenSource] (8.1, A.1: it subscribes to token changes itself); its results
/// reach [ServerActionsDelegate.onAuthStatus] and [ServerActionsDelegate.onAppCheckStatus]. The
/// only external reconnect trigger is the `connectivityHints` stream (test plan B-8.7).
///
/// Request timeouts (lead's decision): a request times out only while sent on a live connection
/// (`RequestTable`); the first timeout closes the connection and the request is replayed; after
/// `ConnectionTimings.maxRequestTimeouts` (2) it completes with `network_error` and is dropped
/// from the replay (a `get` fails with a [ServerActionsException] of that status).
final class PersistentConnection implements ServerActions {
  /// Creates the connection; nothing happens before [initialize].
  ///
  /// [now] and [random] replace the clock and the random source (test plan 2.4); [appId] goes to
  /// every connection (2.3); [logger] gets every log line, never a token (threat model T7, A.10);
  /// null drops them (the core's `ServerActionsFactory` passes a nullable logger).
  PersistentConnection({
    required RealtimeTarget target,
    required RealtimeConnectionFactory connectionFactory,
    required ReconnectBackoff backoff,
    required RealtimeTokenSource tokens,
    required ServerActionsDelegate delegate,
    ConnectionTimings timings = const ConnectionTimings(),
    String? appId,
    DatabaseLogger? logger,
    required DateTime Function() now,
    required double Function() random,
    Stream<void>? connectivityHints,
  }) : _connectionFactory = connectionFactory,
       _backoff = backoff,
       _tokens = tokens,
       _delegate = delegate,
       _timings = timings,
       _appId = appId,
       _logger = logger,
       _now = now,
       _connectivityHints = connectivityHints,
       _requests = RequestTable(timeout: timings.requestTimeout) {
    _session = AuthSession(
      _sendSessionRequest,
      tokens,
      invalidTokenThreshold: timings.invalidTokenThreshold,
      protocol: RealtimeProtocol(
        isUsingEmulator: target.repoInfo.isUsingEmulator,
      ),
      onAuthStatus: (String status, String? explanation) =>
          _emit(() => _delegate.onAuthStatus(status, explanation: explanation)),
      onAppCheckStatus: (String status, String? explanation) => _emit(
        () => _delegate.onAppCheckStatus(status, explanation: explanation),
      ),
    );
  }

  final RealtimeConnectionFactory _connectionFactory;
  final ReconnectBackoff _backoff;
  final RealtimeTokenSource _tokens;
  final ServerActionsDelegate _delegate;
  final ConnectionTimings _timings;
  final String? _appId;
  final DatabaseLogger? _logger;
  final DateTime Function() _now;
  final Stream<void>? _connectivityHints;
  final RequestTable _requests;
  late final AuthSession _session;

  final ReplayQueues _queues = ReplayQueues();
  final Set<String> _interruptReasons = <String>{};
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];

  bool _initialized = false;
  bool _shutdown = false;

  /// Bumped for every attempt and on interrupt/shutdown: a token fetch of an older attempt is
  /// dropped when it completes (8.1 step 3, PersistentConnection.ts:844-875).
  int _attempt = 0;
  Timer? _reconnectTimer;
  bool _fetchingTokens = false;
  DateTime? _attemptStartedAt;

  RealtimeConnection? _connection;
  _Link? _link;
  bool _connected = false;
  bool _reportedConnected = false;
  String? _lastSessionId;
  int _messagesOnConnection = 0;
  bool _okOnConnection = false;
  bool _established = false;

  // ---------------------------------------------------------------------------------------------
  // Lifecycle

  @override
  void initialize() {
    if (_initialized || _shutdown) {
      return;
    }
    _initialized = true;
    // Exactly one subscriber to the token changes: P, which forwards each change to
    // AuthSession.authChanged/appCheckChanged (AuthSession never subscribes; A.1).
    _subscriptions
      ..add(_tokens.authChanges.listen(_onAuthTokenChanged))
      ..add(_tokens.appCheckChanges.listen(_onAppCheckTokenChanged))
      ..add(_session.connectionMustClose.listen((_) => _onCredentialRevoked()));
    final Stream<void>? hints = _connectivityHints;
    if (hints != null) {
      _subscriptions.add(hints.listen((_) => _onConnectivityHint()));
    }
    // The first connection starts at once, not at the first operation (8.1, test plan B-8.1a).
    _scheduleConnect(Duration.zero);
  }

  @override
  Future<void> shutdown() async {
    if (_shutdown) {
      return;
    }
    _shutdown = true;
    _attempt++;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    for (final StreamSubscription<Object?> subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    final RealtimeConnection? connection = _connection;
    _detach();
    connection?.close();
    _requests.clear();
    _queues.clear();
  }

  // ---------------------------------------------------------------------------------------------
  // Listens

  @override
  void listen(
    ListenSpec spec, {
    required ListenHashProvider hashProvider,
    int? tag,
    required RequestResultCallback onComplete,
  }) {
    if (_shutdown) {
      return;
    }
    // A query listen without a tag takes the emulator's whole namespace down for 30 s
    // (rtdb_emulator_probe.md, measured): a non-default spec must carry its tag.
    if (!spec.isDefault && tag == null) {
      throw ArgumentError.value(tag, 'tag', 'A non-default listen needs a tag');
    }
    final ListenRecord record = ListenRecord(
      spec,
      tag,
      hashProvider,
      onComplete,
    );
    if (!_queues.addListen(record)) {
      // PersistentConnection.ts:243-246.
      throw StateError('Listen called twice for the same path and query');
    }
    if (_connected) {
      _sendListen(record);
    }
  }

  @override
  void unlisten(ListenSpec spec, {int? tag}) {
    if (_shutdown) {
      return;
    }
    final ListenRecord? record = _queues.removeListen(
      spec.path,
      spec.queryIdentifier,
    );
    if (record == null || !_connected) {
      return;
    }
    // 4.2: `q` and `t` only for a tagged listen (PersistentConnection.ts:452-469).
    final Map<String, Object?> body = <String, Object?>{'p': spec.path};
    if (tag != null) {
      body['q'] = spec.queryObject;
      body['t'] = tag;
    }
    _send(RealtimeProtocol.unlisten, body);
  }

  void _sendListen(ListenRecord record) {
    record.awaitingAnswer = true;
    final Map<String, Object?> body = record.wireBody();
    _send(
      RealtimeProtocol.listen,
      body,
      onResponse: (Map<String, Object?> response) =>
          _onListenResponse(record, response),
      onTimeout: () => _onTimeout(record),
    );
  }

  void _onListenResponse(ListenRecord record, Map<String, Object?> response) {
    // A response for a listen removed (or replaced) meanwhile is ignored
    // (PersistentConnection.ts:296-300).
    if (!_queues.hasListen(record)) {
      return;
    }
    record.awaitingAnswer = false;
    final String status = _statusOf(response);
    final Object? data = response['d'];
    if (status == statusOk) {
      _warnOnMissingIndex(record.spec, data);
    } else {
      _queues.removeListen(record.spec.path, record.spec.queryIdentifier);
    }
    _emit(() => record.onComplete(status, data));
  }

  void _warnOnMissingIndex(ListenSpec spec, Object? data) {
    // PersistentConnection.ts:316-331.
    if (data is Map<String, Object?>) {
      final Object? warnings = data['w'];
      if (warnings is List<Object?> && warnings.contains(noIndexWarning)) {
        _log(
          DatabaseLogLevel.warning,
          'Using an unspecified index. Consider adding ".indexOn": "${spec.indexName}" at '
          '${spec.path} to your security rules for better performance.',
        );
      }
    }
  }

  // ---------------------------------------------------------------------------------------------
  // Gets

  @override
  Future<Object?> get(ListenSpec spec) {
    if (_shutdown) {
      return Future<Object?>.error(
        ServerActionsException(
          DatabaseErrorCode.disconnected.wireStatus,
          'The connection is shut down.',
        ),
      );
    }
    final OutstandingGet get = OutstandingGet(<String, Object?>{
      'p': spec.path,
      'q': spec.queryObject,
    });
    _queues.gets.add(get);
    if (_connected) {
      _sendGet(get);
    }
    return get.completer.future;
  }

  void _sendGet(OutstandingGet get) {
    get.sent = true;
    get.awaitingAnswer = true;
    _send(
      RealtimeProtocol.get,
      get.body,
      onResponse: (Map<String, Object?> response) {
        if (!_queues.gets.remove(get)) {
          return;
        }
        final String status = _statusOf(response);
        final Object? data = response['d'];
        // Completed here, not through _emit: the completer is asynchronous, so its listeners run in
        // a microtask scheduled now, in arrival order with the delegate calls (addendum 5). Through
        // _emit they would take a second hop and fall behind a push that arrived after.
        if (status == statusOk) {
          get.completer.complete(data);
        } else {
          get.completer.completeError(
            ServerActionsException(status, data is String ? data : null),
          );
        }
      },
      onTimeout: () => _onTimeout(get),
    );
  }

  // ---------------------------------------------------------------------------------------------
  // Writes

  @override
  void put(
    String path,
    Object? data, {
    String? hash,
    RequestResultCallback? onComplete,
  }) => _write(RealtimeProtocol.put, path, data, hash, onComplete);

  @override
  void merge(
    String path,
    Map<String, Object?> data, {
    String? hash,
    RequestResultCallback? onComplete,
  }) => _write(RealtimeProtocol.merge, path, data, hash, onComplete);

  void _write(
    String action,
    String path,
    Object? data,
    String? hash,
    RequestResultCallback? onComplete,
  ) {
    if (_shutdown) {
      return;
    }
    final Map<String, Object?> body = <String, Object?>{'p': path, 'd': data};
    if (hash != null) {
      body['h'] = hash;
    }
    final OutstandingWrite write = OutstandingWrite(
      action,
      body,
      onComplete,
      isTransaction: hash != null,
    );
    _queues.writes.add(write);
    if (_connected) {
      _sendWrite(write);
    }
  }

  void _sendWrite(OutstandingWrite write) {
    write.sent = true;
    write.awaitingAnswer = true;
    _send(
      write.action,
      write.body,
      onResponse: (Map<String, Object?> response) {
        if (!_queues.writes.remove(write)) {
          return; // Purged meanwhile.
        }
        final String status = _statusOf(response);
        final Object? reason = response['d'];
        final RequestResultCallback? onComplete = write.onComplete;
        if (onComplete != null) {
          _emit(() => onComplete(status, reason));
        }
      },
      onTimeout: () => _onTimeout(write),
    );
  }

  @override
  void purgeOutstandingWrites() {
    // Android PersistentConnectionImpl.purgeOutstandingWrites: every put and merge not yet acked
    // completes with write_canceled; a later ack of a sent one is ignored.
    final List<OutstandingWrite> purged = _queues.writes.toList();
    _queues.writes.clear();
    for (final OutstandingWrite write in purged) {
      final RequestResultCallback? onComplete = write.onComplete;
      if (onComplete != null) {
        _emit(
          () => onComplete(DatabaseErrorCode.writeCanceled.wireStatus, null),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------------------------
  // onDisconnect

  @override
  void onDisconnectPut(
    String path,
    Object? data, {
    RequestResultCallback? onComplete,
  }) => _onDisconnect(RealtimeProtocol.onDisconnectPut, path, data, onComplete);

  @override
  void onDisconnectMerge(
    String path,
    Map<String, Object?> data, {
    RequestResultCallback? onComplete,
  }) =>
      _onDisconnect(RealtimeProtocol.onDisconnectMerge, path, data, onComplete);

  @override
  void onDisconnectCancel(String path, {RequestResultCallback? onComplete}) =>
      // 4.5: `oc` carries `d: null` explicitly (PersistentConnection.ts:516).
      _onDisconnect(
        RealtimeProtocol.onDisconnectCancel,
        path,
        null,
        onComplete,
      );

  void _onDisconnect(
    String action,
    String path,
    Object? data,
    RequestResultCallback? onComplete,
  ) {
    if (_shutdown) {
      return;
    }
    final QueuedOnDisconnect request = QueuedOnDisconnect(
      action,
      <String, Object?>{'p': path, 'd': data},
      onComplete,
    );
    if (_connected) {
      _sendOnDisconnect(request);
    } else {
      // Queued while offline, sent at the next connection (PersistentConnection.ts:478-486).
      _queues.onDisconnects.add(request);
    }
  }

  void _sendOnDisconnect(QueuedOnDisconnect request) {
    // Once sent it is the server's: not replayed after a drop, its callback dropped with the
    // connection (PersistentConnection.ts:527-545, 783).
    _send(
      request.action,
      request.body,
      onResponse: (Map<String, Object?> response) {
        final RequestResultCallback? onComplete = request.onComplete;
        if (onComplete != null) {
          final String status = _statusOf(response);
          final Object? reason = response['d'];
          _emit(() => onComplete(status, reason));
        }
      },
      onTimeout: () => _onTimeout(null),
    );
  }

  // ---------------------------------------------------------------------------------------------
  // Interrupt, resume, hints

  @override
  void interrupt(String reason) {
    if (_shutdown) {
      return;
    }
    _interruptReasons.add(reason);
    _cancelPendingAttempt();
    if (_connection != null) {
      _closeConnection(DisconnectReason.other);
    }
  }

  @override
  void resume(String reason) {
    // A server kill is never cleared (PersistentConnection.ts:919-928): only the named reason goes.
    if (_shutdown || reason == RealtimeProtocol.serverKillInterruptReason) {
      return;
    }
    _interruptReasons.remove(reason);
    if (_interruptReasons.isEmpty) {
      // A waiting attempt is replaced by an immediate one (PersistentConnection.ts:919-928 and
      // scheduleConnect_, which clears the pending timer).
      _backoff.reset();
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _scheduleConnect(Duration.zero);
    }
  }

  @override
  bool isInterrupted(String reason) => _interruptReasons.contains(reason);

  void _onConnectivityHint() {
    if (_shutdown) {
      return;
    }
    // A network change: the delay goes back to its minimum and a waiting attempt starts now
    // (lead's decision; JS onOnline_, PersistentConnection.ts:759-765).
    _backoff.reset();
    if (_reconnectTimer != null) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _scheduleConnect(Duration.zero);
    }
  }

  void _cancelPendingAttempt() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    if (_fetchingTokens) {
      // The fetch result is dropped when it arrives (8.6, test plan B-8.6b).
      _attempt++;
      _fetchingTokens = false;
    }
  }

  // ---------------------------------------------------------------------------------------------
  // Tokens

  void _onAuthTokenChanged(String? token) {
    if (!_shutdown) {
      _session.authChanged(token);
    }
  }

  void _onAppCheckTokenChanged(String? token) {
    if (!_shutdown) {
      _session.appCheckChanged(token);
    }
  }

  void _onCredentialRevoked() {
    // 8.3: a revoked auth closes the connection; the next attempt forces a token refresh.
    if (_connection != null) {
      _closeConnection(DisconnectReason.other);
    }
  }

  void _sendSessionRequest(
    String action,
    Map<String, Object?> body,
    void Function(Map<String, Object?> body)? onResponse,
  ) {
    if (!_connected) {
      return;
    }
    _send(
      action,
      body,
      onResponse: onResponse,
      // Credentials are sent again on every connection: a timeout only closes this one.
      onTimeout: () => _onTimeout(null),
    );
  }

  // ---------------------------------------------------------------------------------------------
  // Connecting

  bool get _shouldConnect =>
      _initialized &&
      !_shutdown &&
      _interruptReasons.isEmpty &&
      _connection == null;

  void _scheduleConnect(Duration delay) {
    if (!_shouldConnect || _reconnectTimer != null || _fetchingTokens) {
      return;
    }
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      unawaited(_establish());
    });
  }

  Future<void> _establish() async {
    if (!_shouldConnect) {
      return;
    }
    final int attempt = ++_attempt;
    _attemptStartedAt = _now();
    _fetchingTokens = true;
    final bool forceRefresh = _session.forceRefreshNext;
    final String? authToken;
    final String? appCheckToken;
    try {
      // 8.1 steps 1-2: both tokens before every connection, forced after a revoke.
      final List<String?> fetched = await Future.wait(<Future<String?>>[
        _tokens.authToken(forceRefresh: forceRefresh),
        _tokens.appCheckToken(forceRefresh: forceRefresh),
      ]);
      authToken = fetched[0];
      appCheckToken = fetched[1];
    } on Object catch (error) {
      if (attempt != _attempt) {
        return;
      }
      _fetchingTokens = false;
      // The provider's message may hold a credential: only its type is logged (threat model T8).
      _log(
        DatabaseLogLevel.warning,
        'Failed to get a token: ${error.runtimeType}',
      );
      _scheduleReconnect();
      return;
    }
    if (attempt != _attempt) {
      return; // Interrupted or shut down while the tokens were fetched (8.1 step 3).
    }
    _fetchingTokens = false;
    if (!_shouldConnect) {
      return;
    }
    // Stored while offline; AuthSession sends them at onConnected, which also clears its
    // forceRefreshNext (so a forced fetch is requested until a connection is up).
    _session
      ..authChanged(authToken)
      ..appCheckChanged(appCheckToken);
    _openConnection(appCheckToken);
  }

  void _openConnection(String? appCheckToken) {
    final _Link link = _Link(this);
    _link = link;
    _messagesOnConnection = 0;
    _okOnConnection = false;
    _established = false;
    final RealtimeConnection connection = _connectionFactory(
      link,
      lastSessionId: _lastSessionId,
      appId: _appId,
      appCheckToken: appCheckToken,
    );
    _connection = connection;
    connection.open();
  }

  void _scheduleReconnect() {
    if (!_shouldConnect) {
      return;
    }
    final DateTime started = _attemptStartedAt ?? _now();
    _scheduleConnect(_backoff.nextDelay(attemptStartedAt: started));
  }

  // ---------------------------------------------------------------------------------------------
  // Events of the current connection

  void _onReady(_Link link, int serverTimeMs, String sessionId) {
    if (!identical(link, _link)) {
      return;
    }
    _connected = true;
    _lastSessionId = sessionId;
    final int offset = serverTimeMs - _now().millisecondsSinceEpoch;
    _emit(
      () => _delegate.onServerInfoUpdate(<String, Object?>{
        'serverTimeOffset': offset,
      }),
    );
    _replay();
    _reportedConnected = true;
    _emit(_delegate.onConnect);
  }

  /// Sends the state after a hello, in the order of 8.4 (PersistentConnection.ts:1035-1069): auth
  /// and App Check (pipelined, not awaited), listens, unacked puts and merges, queued onDisconnect
  /// requests, outstanding gets.
  void _replay() {
    _session.onConnected();
    for (final ListenRecord record in _queues.listens) {
      _sendListen(record);
    }
    for (final OutstandingWrite write in _queues.writes.toList()) {
      _sendWrite(write);
    }
    final List<QueuedOnDisconnect> queued = _queues.onDisconnects.toList();
    _queues.onDisconnects.clear();
    for (final QueuedOnDisconnect request in queued) {
      _sendOnDisconnect(request);
    }
    for (final OutstandingGet get in _queues.gets.toList()) {
      _sendGet(get);
    }
  }

  void _onDataMessage(_Link link, Map<String, Object?> message) {
    if (!identical(link, _link)) {
      return;
    }
    _messagesOnConnection++;
    final ServerMessage decoded = decodeServerMessage(message);
    switch (decoded) {
      case Response(:final int r, :final String status, :final Object? data):
        if (status == statusOk) {
          _okOnConnection = true;
        }
        _requests.complete(r, <String, Object?>{'s': status, 'd': data});
      case DataPush():
        _emit(
          () => _delegate.onDataUpdate(
            decoded.path,
            decoded.data,
            isMerge: decoded.isMerge,
            tag: decoded.tag,
          ),
        );
      case RangeMergePush():
        _emit(
          () => _delegate.onRangeMergeUpdate(
            decoded.path,
            decoded.merges,
            tag: decoded.tag,
          ),
        );
      case ListenRevokedPush():
        _onListenRevoked(decoded.path);
      case AuthRevokedPush():
        _session.onAuthRevoked(decoded.status, decoded.explanation);
      case AppCheckRevokedPush():
        _session.onAppCheckRevoked(decoded.status, decoded.explanation);
      case SecurityDebugPush():
        _log(
          DatabaseLogLevel.info,
          'Security debug: ${safeServerText(decoded.message)}',
        );
      case ServerError():
        // Android ignores it, JS throws (5); logged here (lead's decision, iOS U-I01).
        _log(
          DatabaseLogLevel.warning,
          'Server error: ${safeServerText(decoded.message)}',
        );
      case Ignored():
        _log(
          DatabaseLogLevel.debug,
          'Ignored a server message: ${decoded.why}',
        );
    }
    _markEstablishedWhenHealthy();
  }

  /// The backoff resets only after the connection was healthy (enough messages, 3.4) and the server
  /// answered at least one request `ok` (threat model T13).
  void _markEstablishedWhenHealthy() {
    if (_established || !_okOnConnection) {
      return;
    }
    if (_messagesOnConnection >= _timings.responsesRequiredToBeHealthy) {
      _established = true;
      _backoff.markEstablished();
    }
  }

  void _onListenRevoked(String path) {
    // Every listen at the path, whatever its query (Android PersistentConnectionImpl.java:912-930;
    // lead's decision).
    for (final ListenRecord record in _queues.removeListensAt(path)) {
      _emit(
        () => record.onComplete(
          DatabaseErrorCode.permissionDenied.wireStatus,
          null,
        ),
      );
    }
  }

  void _onDisconnected(_Link link) {
    if (!identical(link, _link)) {
      return;
    }
    _detach();
    _scheduleReconnect();
  }

  void _onKill(_Link link, String reason) {
    if (!identical(link, _link)) {
      return;
    }
    // 3.3: a shutdown is never followed by a reconnect (PersistentConnection.ts:879-882).
    _interruptReasons.add(RealtimeProtocol.serverKillInterruptReason);
    final String safeReason = safeServerText(reason);
    _log(
      DatabaseLogLevel.warning,
      'The server shut the connection down: $safeReason',
    );
    final RealtimeConnection? connection = _connection;
    _detach();
    connection?.close();
    _emit(() => _delegate.onServerShutdown(safeReason));
  }

  /// Closes the current connection and runs the disconnect path now; the connection's own
  /// callback, if it comes, is ignored.
  void _closeConnection(DisconnectReason reason) {
    final RealtimeConnection? connection = _connection;
    if (connection == null) {
      return;
    }
    _detach();
    connection.close(reason);
    _scheduleReconnect();
  }

  /// Forgets the current connection (8.2 `onRealtimeDisconnect_`): request callbacks dropped,
  /// sent transaction puts completed with `disconnect`, every request marked unsent for the
  /// replay, the delegate told once if it had been told connected.
  void _detach() {
    _link = null;
    _connection = null;
    _connected = false;
    _requests.clear();
    if (_shutdown) {
      return;
    }
    _session.onDisconnected();
    for (final OutstandingWrite write in _queues.takeSentTransactions()) {
      final RequestResultCallback? onComplete = write.onComplete;
      if (onComplete != null) {
        _emit(() => onComplete(statusDisconnect, null));
      }
    }
    _queues.markAllUnsent();
    if (_session.invalidTokenThresholdReached) {
      _backoff.setToMax();
    }
    if (_reportedConnected) {
      _reportedConnected = false;
      _emit(_delegate.onDisconnect);
    }
  }

  // ---------------------------------------------------------------------------------------------
  // Sending

  void _send(
    String action,
    Map<String, Object?> body, {
    void Function(Map<String, Object?> body)? onResponse,
    void Function()? onTimeout,
  }) {
    final RealtimeConnection? connection = _connection;
    if (connection == null || !_connected) {
      return;
    }
    final int r = _requests.add(onResponse, onTimeout: onTimeout);
    // Requests carrying a credential are never logged with their body (threat model T7); no
    // other body is logged either: it holds user data.
    _log(
      DatabaseLogLevel.debug,
      _carriesCredential(action)
          ? '$action (contents hidden)'
          : 'send $action r=$r',
    );
    connection.send(<String, Object?>{
      RealtimeProtocol.requestNumberKey: r,
      RealtimeProtocol.actionKey: action,
      RealtimeProtocol.bodyKey: body,
    });
  }

  static bool _carriesCredential(String action) =>
      action == RealtimeProtocol.auth ||
      action == RealtimeProtocol.gauth ||
      action == RealtimeProtocol.appCheck;

  /// A request timed out on a live connection (lead's decision, addendum 2).
  ///
  /// Every replayable request still waiting for its answer on this connection counts one timeout,
  /// not only the one whose timer fired: closing the connection cancels the other timers, so with
  /// a per-timer count a silent server would let the first request (often `auth`) close every
  /// connection and the others would never reach their limit (found by the first test run). A
  /// request at `ConnectionTimings.maxRequestTimeouts` completes with [statusNetworkError] and
  /// leaves the replay. The connection is closed (and the rest replayed) unless every waiting
  /// request has just failed. [request] is the replayable request whose timer fired, null for a
  /// credential or onDisconnect request; a request that already failed is ignored.
  void _onTimeout(TimedRequest? request) {
    if (request != null &&
        (!request.awaitingAnswer || !_queues.isQueued(request))) {
      return;
    }
    final List<TimedRequest> waiting = _queues.awaitingAnswer.toList();
    bool anyLeft = waiting.isEmpty;
    for (final TimedRequest pending in waiting) {
      pending.timeouts++;
      if (pending.timeouts >= _timings.maxRequestTimeouts) {
        _failWithNetworkError(pending);
      } else {
        anyLeft = true;
      }
    }
    if (anyLeft) {
      _log(DatabaseLogLevel.info, 'A request got no answer; reconnecting');
      _closeConnection(DisconnectReason.other);
    }
  }

  void _failWithNetworkError(TimedRequest request) {
    _log(
      DatabaseLogLevel.warning,
      'A request got no answer twice; it fails with $statusNetworkError',
    );
    request.awaitingAnswer = false;
    switch (request) {
      case ListenRecord():
        _queues.removeListen(request.spec.path, request.spec.queryIdentifier);
        _emit(() => request.onComplete(statusNetworkError, null));
      case OutstandingWrite():
        _queues.writes.remove(request);
        final RequestResultCallback? onComplete = request.onComplete;
        if (onComplete != null) {
          _emit(() => onComplete(statusNetworkError, null));
        }
      case OutstandingGet():
        _queues.gets.remove(request);
        request.completer.completeError(
          const ServerActionsException(statusNetworkError),
        );
    }
  }

  static String _statusOf(Map<String, Object?> response) {
    final Object? status = response['s'];
    return status is String
        ? status
        : DatabaseErrorCode.operationFailed.wireStatus;
  }

  /// Runs [action] on the event loop, never inside the current call (seam rule).
  ///
  /// Every delegate call and every RequestResultCallback takes this same single microtask hop, in
  /// the order the messages arrived on the socket: a write's data push (sent first by the server,
  /// measured) always reaches the delegate before the write's completion, also when both arrive in
  /// one burst (addendum 5). No kind of message may take a different path.
  void _emit(void Function() action) {
    scheduleMicrotask(() {
      if (!_shutdown) {
        action();
      }
    });
  }

  void _log(DatabaseLogLevel level, String message) =>
      _logger?.call(level, message);

  /// Shows the state only: no session id, no token (threat model T7, T8).
  @override
  String toString() => 'PersistentConnection(connected: $_connected)';
}

/// The [RealtimeDelegate] of one connection attempt. Events of an attempt that is no longer the
/// current one are ignored by identity (re-entrancy, test plan B-3.5b).
final class _Link implements RealtimeDelegate {
  _Link(this._owner);

  final PersistentConnection _owner;

  @override
  void onReady(int serverTimeMs, String sessionId) =>
      _owner._onReady(this, serverTimeMs, sessionId);

  @override
  void onDataMessage(Map<String, Object?> message) =>
      _owner._onDataMessage(this, message);

  @override
  void onDisconnect(DisconnectReason reason) => _owner._onDisconnected(this);

  @override
  void onKill(String reason) => _owner._onKill(this, reason);
}
