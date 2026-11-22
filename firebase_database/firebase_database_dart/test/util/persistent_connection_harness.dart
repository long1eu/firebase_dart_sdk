// Owner P. A rig for the tests of PersistentConnection: the real RealtimeConnection over T's
// FakeRtdbServer, a scripted token source, the core's RecordingServerActionsDelegate, and helpers
// to wait for conditions. By default the server answers every request as the emulator does, the
// credentials included (a refused token is refused); `hold` keeps the answers back for the test
// to give. Tests that only wait for events run in real time with shrunk ConnectionTimings
// (milliseconds); every test of a delay, or of something that must not happen, runs on fake time
// (`fakeTimeRig`, addendum 3).

import 'dart:async';

import 'package:fake_async/fake_async.dart';

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
import 'package:firebase_database_dart/src/realtime/transport/ws_channel.dart';
import 'package:firebase_database_dart/src/testing/recording_server_actions_delegate.dart';

import 'fake_rtdb_server.dart';

/// A user-shaped JWT the emulator accepts as `auth`: header {"alg":"none"}, claims
/// {"sub":"u1","iat":0} (probe addendum 2 item 14). A token that is not a decodable JWT with
/// `iat` goes out as `gauth` (auth_session.dart authActionFor).
const String validAuthToken =
    'eyJhbGciOiJub25lIn0.eyJzdWIiOiJ1MSIsImlhdCI6MH0.sig';

/// A JWT with claims {"iat":0} and no `sub`: sent as `auth`, refused `invalid_token` ("Missing
/// claim 'sub' in auth token.", measured).
const String authTokenWithoutSub = 'eyJhbGciOiJub25lIn0.eyJpYXQiOjB9.sig';

/// An App Check token the fake server accepts: header {"alg":"RS256"}, claims {"sub":"app"}.
const String validAppCheckToken = 'eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJhcHAifQ.sig';

/// A token source with fixed tokens, change streams, a gate to hold a fetch in flight, and a
/// record of every `forceRefresh`.
final class ScriptedTokens implements RealtimeTokenSource {
  /// Creates the source handing out [auth] and [appCheck].
  ScriptedTokens({
    this.auth = validAuthToken,
    this.appCheck = validAppCheckToken,
  });

  /// The auth token handed out (null: nobody signed in).
  String? auth;

  /// The App Check token handed out.
  String? appCheck;

  /// While set and not completed, every fetch waits for it.
  Completer<void>? gate;

  /// When set, every auth fetch fails with it.
  Exception? error;

  /// Called at the start of every auth fetch, after it was recorded in [authCalls].
  void Function()? onAuthFetch;

  /// The `forceRefresh` of every auth fetch.
  final List<bool> authCalls = <bool>[];

  /// The `forceRefresh` of every App Check fetch.
  final List<bool> appCheckCalls = <bool>[];

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

  /// Emits a new App Check token on [appCheckChanges].
  void emitAppCheck(String? token) {
    appCheck = token;
    _appCheckChanges.add(token);
  }

  @override
  Future<String?> authToken({required bool forceRefresh}) async {
    authCalls.add(forceRefresh);
    onAuthFetch?.call();
    // The value of the moment the fetch starts, as a provider whose request is in flight: a
    // sign-out after this point does not change what the fetch returns (review H2).
    final String? value = auth;
    await gate?.future;
    final Exception? failure = error;
    if (failure != null) {
      throw failure;
    }
    return value;
  }

  @override
  Future<String?> appCheckToken({required bool forceRefresh}) async {
    appCheckCalls.add(forceRefresh);
    // The value of the moment the fetch starts, as for [authToken].
    final String? value = appCheck;
    await gate?.future;
    return value;
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
);

/// A filtered listen spec at [path] (limit 10 on `age`).
ListenSpec taggedListen(String path) => ListenSpec(
  path: path,
  queryObject: const <String, Object?>{'i': 'age', 'l': 10, 'vf': 'l'},
  queryIdentifier: '{"i":"age","l":10,"vf":"l"}',
  isDefault: false,
  loadsAllData: false,
  indexName: 'age',
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
  ///
  /// By default the server answers every request itself, as the emulator does. With [hold], every
  /// answer except those to the credential requests is kept back: the test gives it ([answer], or
  /// `server.connector.last.serverResponse`). With [holdCredentials], the credential answers are
  /// kept back too (a server that answers nothing) until [answerCredentials]; it implies [hold].
  /// With [logConnection], the RealtimeConnection of every attempt logs to [logs] too, as in
  /// production (`server_actions_factories.dart` gives both the same logger).
  PRig({
    ConnectionTimings? timings,
    double Function()? random,
    bool hold = false,
    bool holdCredentials = false,
    bool logConnection = false,
    bool emulator = false,
    RecordingServerActionsDelegate? delegate,
    DateTime Function()? now,
    Duration Function()? elapsed,
    WsConnector Function(WsConnector connector)? wrapConnector,
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
    if (hold || holdCredentials) {
      server.holdResponses(credentials: holdCredentials);
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
              wrapConnector?.call(server.connect) ?? server.connect,
              this.timings,
              delegate,
              lastSessionId: lastSessionId,
              appId: appId,
              appCheckToken: appCheckToken,
              logger: logConnection ? _log : null,
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
      logger: _log,
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

  /// Every log line, as `<level>: <message>`.
  final List<String> logs = <String>[];

  void _log(DatabaseLogLevel level, String message) =>
      logs.add('${level.name}: $message');

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
    server.connector.last.serverResponse(seen.r!, status: status, data: data);
    await settle();
  }

  /// With `holdCredentials`: sends the server's own answers to the credential requests held so
  /// far (`ok` for the default tokens, the emulator's refusal for an invalid one).
  Future<void> answerCredentials() async {
    await settle();
    answerCredentialsNow();
    await settle();
  }

  /// Like [answerCredentials], without waiting: for tests under fake_async, which flush instead.
  void answerCredentialsNow() => server.releaseCredentialResponses();

  /// Closes the current connection from the server side and waits until it is noticed.
  Future<void> drop() async {
    final int before = delegate.callsOf('disconnect').length;
    server.connector.last.serverClose(1006);
    await until(() => delegate.callsOf('disconnect').length > before);
  }

  /// Lets queued events and microtasks run. Not a wait for a timer: a check that something did
  /// not happen after a delay belongs on fake time.
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

/// Advances fake time in 1 ms steps until [condition] holds (at most [limit] of virtual time).
void elapseUntil(
  FakeAsync async,
  bool Function() condition, {
  Duration limit = const Duration(seconds: 30),
}) {
  final Duration end = async.elapsed + limit;
  while (!condition()) {
    if (async.elapsed > end) {
      throw TimeoutException('condition not met in virtual time', limit);
    }
    async.elapse(const Duration(milliseconds: 1));
  }
}

/// The wall clock of [fakeTimeRig] at virtual time zero.
final DateTime fakeTimeStart = DateTime.utc(2026, 11, 22);

/// A rig on fake time: `now` and `elapsed` follow [async]; the other arguments are [PRig]'s.
PRig fakeTimeRig(
  FakeAsync async, {
  ConnectionTimings? timings,
  bool hold = false,
  bool holdCredentials = false,
  WsConnector Function(WsConnector connector)? wrapConnector,
}) => PRig(
  timings: timings,
  hold: hold,
  holdCredentials: holdCredentials,
  now: () => fakeTimeStart.add(async.elapsed),
  elapsed: () => async.elapsed,
  wrapConnector: wrapConnector,
);

/// Shuts [rig] down on fake time and checks that no timer is left (a reconnect, a request or a
/// liveness timer that outlives the connection).
void shutDownOnFakeTime(FakeAsync async, PRig rig) {
  unawaited(rig.connection.shutdown());
  async.flushMicrotasks();
  if (async.pendingTimers.isNotEmpty) {
    throw StateError(
      'timers left after shutdown: ${async.pendingTimers.toList()}',
    );
  }
}

/// A channel that throws on its [failAt]-th sent frame (a socket that died mid-send).
final class FailingChannel implements WsChannel {
  /// Wraps [_inner]; the [failAt]-th call of [sendText] throws.
  FailingChannel(this._inner, this.failAt);

  final WsChannel _inner;

  /// The number of the frame that throws, from 1.
  final int failAt;
  int _sent = 0;

  @override
  Stream<WsEvent> get events => _inner.events;

  @override
  void sendText(String frame) {
    if (++_sent == failAt) {
      throw StateError('the socket is gone');
    }
    _inner.sendText(frame);
  }

  @override
  Future<void> close([int code = 1000, String? reason]) =>
      _inner.close(code, reason);

  @override
  void abandon() => _inner.abandon();
}

/// A connector wrapper for [PRig]: the first channel throws on its [failAt]-th frame, later
/// channels are untouched.
WsConnector Function(WsConnector) failFrameOfFirstChannel(int failAt) {
  int channels = 0;
  return (WsConnector inner) =>
      (
        Uri url, {
        Map<String, String> headers = const <String, String>{},
        Future<void>? abort,
      }) async {
        final WsChannel channel = await inner(
          url,
          headers: headers,
          abort: abort,
        );
        return ++channels == 1 ? FailingChannel(channel, failAt) : channel;
      };
}
