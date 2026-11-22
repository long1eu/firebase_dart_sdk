// Owner P. A rig for the tests of PersistentConnection: the real RealtimeConnection over T's
// FakeRtdbServer, a scripted token source, the core's RecordingServerActionsDelegate, and helpers
// to wait for conditions. Most tests run in real time with shrunk ConnectionTimings (milliseconds);
// the timing-sensitive ones (test/security/p_limits_test.dart) inject `now` and `elapsed` from
// fake_async (addendum 3).

import 'dart:async';

import 'package:firebase_database_dart/src/core/connection/listen_hash_provider.dart';
import 'package:firebase_database_dart/src/core/connection/listen_spec.dart';
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/core/connection/wire_range_merge.dart';
import 'package:firebase_database_dart/src/core/repo_info.dart';
import 'package:firebase_database_dart/src/core/util/logger.dart';
import 'package:firebase_database_dart/src/realtime/auth_session.dart';
import 'package:firebase_database_dart/src/realtime/connection.dart';
import 'package:firebase_database_dart/src/realtime/connection_timings.dart';
import 'package:firebase_database_dart/src/realtime/persistent_connection.dart';
import 'package:firebase_database_dart/src/realtime/realtime_target.dart';
import 'package:firebase_database_dart/src/realtime/reconnect_backoff.dart';
import 'package:firebase_database_dart/src/testing/recording_server_actions_delegate.dart';

import 'fake_rtdb_server.dart';

/// A token source with fixed tokens, change streams, a gate to hold a fetch in flight, and a
/// record of every `forceRefresh`.
final class ScriptedTokens implements RealtimeTokenSource {
  /// Creates the source handing out [auth] and [appCheck].
  ScriptedTokens({
    this.auth = 'header.eyJpYXQiOjB9.sig',
    this.appCheck = 'app-check-token',
  });

  /// The auth token handed out (null: nobody signed in).
  String? auth;

  /// The App Check token handed out.
  String? appCheck;

  /// While set and not completed, every fetch waits for it.
  Completer<void>? gate;

  /// When set, every auth fetch fails with it.
  Exception? error;

  /// The `forceRefresh` of every auth fetch.
  final List<bool> authCalls = <bool>[];

  /// The kinds reported invalid.
  final List<TokenKind> invalid = <TokenKind>[];

  final StreamController<String?> _authChanges =
      StreamController<String?>.broadcast();
  final StreamController<String?> _appCheckChanges =
      StreamController<String?>.broadcast();

  /// Emits a new auth token on [authChanges].
  void emitAuth(String? token) {
    auth = token;
    _authChanges.add(token);
  }

  @override
  Future<String?> authToken({required bool forceRefresh}) async {
    authCalls.add(forceRefresh);
    await gate?.future;
    final Exception? failure = error;
    if (failure != null) {
      throw failure;
    }
    return auth;
  }

  @override
  Future<String?> appCheckToken({required bool forceRefresh}) async {
    await gate?.future;
    return appCheck;
  }

  @override
  Stream<String?> get authChanges => _authChanges.stream;

  @override
  Stream<String?> get appCheckChanges => _appCheckChanges.stream;

  @override
  void notifyInvalid(TokenKind kind) => invalid.add(kind);
}

/// A hash provider with a fixed simple hash that counts its calls.
final class CountingHash implements ListenHashProvider {
  /// Creates the provider answering [hash].
  CountingHash(this.hash);

  /// The simple hash.
  String hash;

  /// How many times the hash was read.
  int calls = 0;

  @override
  String simpleHash() {
    calls++;
    return hash;
  }

  @override
  bool shouldIncludeCompoundHash() => false;

  @override
  WireCompoundHash compoundHash() => throw StateError('no compound hash');
}

/// A default listen spec at [path].
ListenSpec defaultListen(String path) => ListenSpec(
  path: path,
  queryObject: const <String, Object?>{},
  queryIdentifier: 'default',
  isDefault: true,
  loadsAllData: true,
  indexName: '.priority',
  restParams: const <String, String>{},
);

/// A filtered listen spec at [path] (limit 10 on `age`).
ListenSpec taggedListen(String path) => ListenSpec(
  path: path,
  queryObject: const <String, Object?>{'i': 'age', 'l': 10, 'vf': 'l'},
  queryIdentifier: '{"i":"age","l":10,"vf":"l"}',
  isDefault: false,
  loadsAllData: false,
  indexName: 'age',
  restParams: const <String, String>{'orderBy': '"age"', 'limitToFirst': '10'},
);

/// Timings shrunk so a scenario takes milliseconds; reconnects wait [reconnectMin] unless a test
/// gives other values.
ConnectionTimings shrunkTimings({
  Duration reconnectMin = const Duration(milliseconds: 1),
  Duration reconnectMax = const Duration(milliseconds: 1),
  Duration reconnectResetAfter = const Duration(minutes: 1),
  Duration requestTimeout = const Duration(minutes: 1),
}) => ConnectionTimings(
  keepAlive: const Duration(minutes: 5),
  connectTimeout: const Duration(seconds: 5),
  healthyTimeout: const Duration(minutes: 5),
  idleProbeAfter: const Duration(minutes: 5),
  reconnectMin: reconnectMin,
  reconnectMax: reconnectMax,
  reconnectMultiplier: 2,
  reconnectResetAfter: reconnectResetAfter,
  requestTimeout: requestTimeout,
);

/// One PersistentConnection over a FakeRtdbServer.
final class PRig {
  /// Builds the rig; nothing connects before [start]. [random] is the jitter of the backoff (1:
  /// the full bound, so delays are deterministic upper bounds).
  PRig({
    ConnectionTimings? timings,
    double Function()? random,
    bool hold = true,
    bool emulator = false,
    RecordingServerActionsDelegate? delegate,
    DateTime Function()? now,
    Duration Function()? elapsed,
  }) : _now = now ?? DateTime.now,
       _elapsed = elapsed,
       timings = timings ?? shrunkTimings(),
       delegate = delegate ?? RecordingServerActionsDelegate(),
       tokens = ScriptedTokens(),
       server = FakeRtdbServer(clock: () => serverTimeMs) {
    final RealtimeTarget target = RealtimeTarget(
      RepoInfo(
        host: emulator ? '127.0.0.1:9000' : 'test-ns.firebaseio.com',
        namespace: 'test-ns',
        secure: !emulator,
        isUsingEmulator: emulator,
      ),
      useHeaders: true,
    );
    final double Function() jitter = random ?? () => 1;
    if (hold) {
      server.holdResponses();
    }
    connection = PersistentConnection(
      target: target,
      connectionFactory:
          (
            RealtimeDelegate delegate, {
            String? lastSessionId,
            String? appId,
            String? appCheckToken,
          }) {
            attemptTimes.add(this.elapsed);
            lastSessionIds.add(lastSessionId);
            return RealtimeConnection(
              target,
              server.connect,
              this.timings,
              delegate,
              lastSessionId: lastSessionId,
              appId: appId,
              appCheckToken: appCheckToken,
              now: _now,
              random: jitter,
            );
          },
      backoff: ReconnectBackoff(
        min: this.timings.reconnectMin,
        max: this.timings.reconnectMax,
        multiplier: this.timings.reconnectMultiplier,
        resetAfter: this.timings.reconnectResetAfter,
        now: _now,
        random: jitter,
      ),
      tokens: tokens,
      delegate: _Forwarding(this),
      timings: this.timings,
      appId: '1:123:dart:abc',
      logger: (DatabaseLogLevel level, String message) =>
          logs.add('${level.name}: $message'),
      now: _now,
      random: jitter,
      connectivityHints: hints.stream,
    );
  }

  /// The hello `ts`.
  static const int serverTimeMs = 1700000000000;

  /// The timings in use.
  final ConnectionTimings timings;

  /// The token source.
  final ScriptedTokens tokens;

  /// The server.
  final FakeRtdbServer server;

  /// What the connection told Repo.
  final RecordingServerActionsDelegate delegate;

  /// Called with the method name (as `DelegateCall.method`) after each delegate call, at the
  /// moment it happens: for ordering checks against callbacks and the server log.
  void Function(String method)? onCall;

  /// Every log line.
  final List<String> logs = <String>[];

  /// The connectivity hints.
  final StreamController<void> hints = StreamController<void>.broadcast();

  /// When each connection attempt was created, since the rig was built.
  final List<Duration> attemptTimes = <Duration>[];

  /// The `lastSessionId` of each attempt.
  final List<String?> lastSessionIds = <String?>[];

  final DateTime Function() _now;
  final Duration Function()? _elapsed;
  final Stopwatch _clock = Stopwatch()..start();

  /// The time since the rig was built: the injected clock under fake_async, else a stopwatch.
  Duration get elapsed => _elapsed?.call() ?? _clock.elapsed;

  /// The connection under test.
  late final PersistentConnection connection;

  /// How many times the delegate heard `connect`.
  int get connects => delegate.callsOf('connect').length;

  /// Initializes the connection and waits for its first `connect`.
  Future<void> start() async {
    connection.initialize();
    await until(() => connects == 1);
  }

  /// The requests of [action] the server received (on [connection] when given).
  List<ServerSeen> sent(String action, {int? onConnection}) => server.log
      .where(
        (ServerSeen seen) =>
            seen.action == action &&
            (onConnection == null || seen.connection == onConnection),
      )
      .toList();

  /// The actions the server received on connection [number], in order.
  List<String> actionsOn(int number) => server.log
      .where((ServerSeen seen) => seen.connection == number)
      .map((ServerSeen seen) => seen.action)
      .toList();

  /// Answers the last request of [action] on the current connection.
  Future<void> answer(
    String action, {
    String status = 'ok',
    Object? data,
  }) async {
    await settle();
    final ServerSeen seen = sent(action).last;
    _answered.add('${seen.connection}/${seen.r}');
    server.connector.last.serverResponse(seen.r!, status: status, data: data);
    await settle();
  }

  /// Answers `ok` to every credential request (`auth`, `gauth`, `appcheck`) of the current
  /// connection that is not answered yet.
  Future<void> answerCredentials() async {
    await settle();
    answerCredentialsNow();
    await settle();
  }

  final Set<String> _answered = <String>{};

  /// Like [answerCredentials], without waiting: for tests under fake_async, which flush instead.
  void answerCredentialsNow() {
    for (final ServerSeen seen in server.log) {
      if (seen.connection == server.connections &&
          const <String>{'auth', 'gauth', 'appcheck'}.contains(seen.action) &&
          _answered.add('${seen.connection}/${seen.r}')) {
        server.connector.last.serverResponse(seen.r!);
      }
    }
  }

  /// Closes the current connection from the server side and waits until it is noticed.
  Future<void> drop() async {
    final int before = delegate.callsOf('disconnect').length;
    server.connector.last.serverClose(1006);
    await until(() => delegate.callsOf('disconnect').length > before);
  }

  /// Lets queued events and microtasks run.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 5));
}

/// Waits until [condition] holds, failing after [timeout].
Future<void> until(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final Stopwatch watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > timeout) {
      throw TimeoutException('condition not met', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

/// Forwards to the rig's recording delegate and reports each call to [PRig.onCall].
final class _Forwarding implements ServerActionsDelegate {
  _Forwarding(this._rig);

  final PRig _rig;

  RecordingServerActionsDelegate get _inner => _rig.delegate;

  void _report(String method) => _rig.onCall?.call(method);

  @override
  void onDataUpdate(
    String path,
    Object? data, {
    required bool isMerge,
    int? tag,
  }) {
    _inner.onDataUpdate(path, data, isMerge: isMerge, tag: tag);
    _report('dataUpdate');
  }

  @override
  void onRangeMergeUpdate(
    String path,
    List<WireRangeMerge> merges, {
    int? tag,
  }) {
    _inner.onRangeMergeUpdate(path, merges, tag: tag);
    _report('rangeMergeUpdate');
  }

  @override
  void onConnect() {
    _inner.onConnect();
    _report('connect');
  }

  @override
  void onDisconnect() {
    _inner.onDisconnect();
    _report('disconnect');
  }

  @override
  void onAuthStatus(String status, {String? explanation}) {
    _inner.onAuthStatus(status, explanation: explanation);
    _report('authStatus');
  }

  @override
  void onAppCheckStatus(String status, {String? explanation}) {
    _inner.onAppCheckStatus(status, explanation: explanation);
    _report('appCheckStatus');
  }

  @override
  void onServerShutdown(String reason) {
    _inner.onServerShutdown(reason);
    _report('serverShutdown');
  }

  @override
  void onServerInfoUpdate(Map<String, Object?> updates) {
    _inner.onServerInfoUpdate(updates);
    _report('serverInfoUpdate');
  }
}
