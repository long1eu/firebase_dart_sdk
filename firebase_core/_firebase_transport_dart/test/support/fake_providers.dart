/// Test doubles for `TokenSource`: fake Auth and App Check providers, an app factory, a probe for
/// futures driven by fake time, and a rig that ties them to one `fakeAsync` zone.
///
/// A typical test:
///
/// ```dart
/// fakeAsync((FakeAsync async) {
///   final FakeAppCheckProvider appCheck = FakeAppCheckProvider()..holdCalls();
///   final TokenRig rig = TokenRig(async, appCheck: appCheck);
///   final Probe<RequestTokens> tokens = rig.ask();
///   async.elapse(TokenSource.providerWait);
///   expect(tokens.value.appCheck, AppCheckOutcome.timedOut);
/// });
/// ```
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:_firebase_transport_dart/_firebase_transport_dart.dart';
import 'package:test/test.dart';

/// The origin every [TokenRig] declares unless told otherwise.
final Uri apiOrigin = Uri.parse('https://api.example.test');

/// A request URL of [apiOrigin].
final Uri apiUrl = Uri.parse('https://api.example.test/v1/call');

/// The Auth token a [FakeAuthProvider] gives by default. Not a real token.
const String fakeAuthToken = 'FAKE-AUTH-TOKEN';

/// The session token a [FakeAppCheckProvider] gives by default. Not a real token.
const String fakeAppCheckToken = 'FAKE-APPCHECK-SESSION-TOKEN';

/// The limited-use token a [FakeLimitedUseProvider] gives by default. Not a real token.
const String fakeLimitedUseToken = 'FAKE-APPCHECK-LIMITED-TOKEN';

int _appCount = 0;

/// A new app with a unique name and no token provider.
FirebaseApp newTransportApp() => FirebaseApp.withOptions(
  const FirebaseOptions(
    apiKey: 'fake-api-key',
    appId: '1:1234567890:web:transporttest',
    projectId: 'demo-transport',
  ),
  name: 'transport-test-${_appCount++}',
);

/// Installs [auth] on [app] and forgets the warm-up call the app's setter makes
/// (`getAccessToken(forceRefresh: true)`), so [FakeAuthProvider.calls] and
/// [FakeAuthProvider.waiting] hold only the calls of the code under test.
void installAuth(FirebaseApp app, FakeAuthProvider auth) {
  final Future<GetTokenResult> Function(bool) answer = auth.answer;
  auth.answer = (bool _) async => GetTokenResult('');
  app.authProvider = auth;
  auth
    ..answer = answer
    ..calls.clear()
    ..waiting.clear();
}

/// An Auth provider whose answer a test sets. [calls] holds the `forceRefresh` of every call.
final class FakeAuthProvider extends AuthTokenProvider {
  /// A provider that gives [token] at once.
  FakeAuthProvider([String token = fakeAuthToken])
    : answer = ((bool _) async => GetTokenResult(token));

  /// A provider that answers every call with [answer].
  FakeAuthProvider.answering(this.answer);

  /// What a call returns; it may throw synchronously.
  Future<GetTokenResult> Function(bool forceRefresh) answer;

  /// The `forceRefresh` argument of every call, in order.
  final List<bool> calls = <bool>[];

  /// The completers of the calls made after [holdCalls], in order.
  final List<Completer<GetTokenResult>> waiting = <Completer<GetTokenResult>>[];

  /// Makes every later call wait until the test completes its entry of [waiting].
  void holdCalls() {
    answer = (bool _) {
      final Completer<GetTokenResult> completer = Completer<GetTokenResult>();
      waiting.add(completer);
      return completer.future;
    };
  }

  @override
  Future<GetTokenResult> getAccessToken({required bool forceRefresh}) {
    calls.add(forceRefresh);
    return answer(forceRefresh);
  }

  @override
  String? get uid => null;

  @override
  Stream<AuthTokenChange> get onTokenChanged =>
      const Stream<AuthTokenChange>.empty();
}

/// An App Check provider that cannot mint limited-use tokens. [calls] holds the `forceRefresh` of
/// every `getToken` call.
base class FakeAppCheckProvider extends AppCheckTokenProvider {
  /// A provider that gives [token] at once.
  FakeAppCheckProvider([String token = fakeAppCheckToken])
    : answer = ((bool _) async => AppCheckTokenResult(token));

  /// A provider that answers every `getToken` call with [answer].
  FakeAppCheckProvider.answering(this.answer);

  /// What `getToken` returns; it may throw synchronously.
  Future<AppCheckTokenResult> Function(bool forceRefresh) answer;

  /// The `forceRefresh` argument of every `getToken` call, in order.
  final List<bool> calls = <bool>[];

  /// The completers of the `getToken` calls made after [holdCalls], in order.
  final List<Completer<AppCheckTokenResult>> waiting =
      <Completer<AppCheckTokenResult>>[];

  /// Makes every later `getToken` call wait until the test completes its entry of [waiting].
  void holdCalls() {
    answer = (bool _) {
      final Completer<AppCheckTokenResult> completer =
          Completer<AppCheckTokenResult>();
      waiting.add(completer);
      return completer.future;
    };
  }

  @override
  Future<AppCheckTokenResult> getToken({required bool forceRefresh}) {
    calls.add(forceRefresh);
    return answer(forceRefresh);
  }

  @override
  Stream<AppCheckTokenResult> get onTokenChanged =>
      const Stream<AppCheckTokenResult>.empty();
}

/// A second provider type, for the warnings that are keyed by the provider's type.
final class OtherAppCheckProvider extends FakeAppCheckProvider {
  /// A provider that gives [token] at once.
  OtherAppCheckProvider([super.token]);
}

/// An App Check provider that can mint limited-use tokens.
base class FakeLimitedUseProvider extends FakeAppCheckProvider
    implements LimitedUseAppCheckTokenProvider {
  /// A provider that gives [token] as its session token and [limitedToken] for each mint.
  FakeLimitedUseProvider({
    String token = fakeAppCheckToken,
    String limitedToken = fakeLimitedUseToken,
  }) : limitedAnswer = (() async => AppCheckTokenResult(limitedToken)),
       super(token);

  /// A provider whose session and limited-use calls both give [answer].
  FakeLimitedUseProvider.bothAnswering(
    Future<AppCheckTokenResult> Function() answer,
  ) : limitedAnswer = answer,
      super.answering((bool _) => answer());

  /// What `getLimitedUseToken` returns; it may throw synchronously.
  Future<AppCheckTokenResult> Function() limitedAnswer;

  /// How many times `getLimitedUseToken` was called.
  int limitedCalls = 0;

  /// The completers of the `getLimitedUseToken` calls made after [holdLimitedCalls], in order.
  final List<Completer<AppCheckTokenResult>> limitedWaiting =
      <Completer<AppCheckTokenResult>>[];

  /// Makes every later `getLimitedUseToken` call wait for its entry of [limitedWaiting].
  void holdLimitedCalls() {
    limitedAnswer = () {
      final Completer<AppCheckTokenResult> completer =
          Completer<AppCheckTokenResult>();
      limitedWaiting.add(completer);
      return completer.future;
    };
  }

  @override
  Future<AppCheckTokenResult> getLimitedUseToken() {
    limitedCalls++;
    return limitedAnswer();
  }
}

/// A second limited-use provider type, for the warnings keyed by the provider's type.
final class OtherLimitedUseProvider extends FakeLimitedUseProvider {
  /// A provider whose session and limited-use calls both give [answer].
  OtherLimitedUseProvider.bothAnswering(super.answer) : super.bothAnswering();
}

/// What became of a future that fake time drives: read it after `flushMicrotasks` or `elapse`.
final class Probe<T> {
  /// Listens to [future] at once, so that its error is never unhandled.
  Probe(Future<T> future) {
    future.then<void>(
      (T value) {
        _value = value;
        _hasValue = true;
      },
      onError: (Object error, StackTrace stackTrace) {
        _error = error;
        _stackTrace = stackTrace;
      },
    );
  }

  T? _value;
  bool _hasValue = false;
  Object? _error;
  StackTrace? _stackTrace;

  /// Whether the future has completed, with a value or an error.
  bool get isDone => _hasValue || _error != null;

  /// The value; fails the test when the future failed or has not completed.
  T get value {
    expect(_error, isNull, reason: 'the future failed');
    expect(_hasValue, isTrue, reason: 'the future has not completed');
    return _value as T;
  }

  /// The error; fails the test when the future gave a value or has not completed.
  Object get error {
    expect(_hasValue, isFalse, reason: 'the future completed with a value');
    expect(_error, isNotNull, reason: 'the future has not completed');
    return _error!;
  }

  /// The stack trace that came with [error].
  StackTrace get stackTrace {
    error;
    return _stackTrace!;
  }
}

/// Matches a [TokenFetchException] with [failure].
Matcher isTokenFailure(TokenFailure failure) => isA<TokenFetchException>()
    .having((TokenFetchException e) => e.failure, 'failure', failure);

/// One app, its providers and a [TokenSource] on the fake clock of [async].
///
/// Create it inside `fakeAsync`. With `sink` false the source gets no `onWarning`.
final class TokenRig {
  /// A rig whose source declares [origins] (default: [apiOrigin]).
  TokenRig(
    this.async, {
    FakeAuthProvider? auth,
    AppCheckTokenProvider? appCheck,
    Iterable<Uri>? origins,
    EmulatorHost? emulator,
    bool sink = true,
  }) : app = newTransportApp() {
    if (auth != null) {
      installAuth(app, auth);
    }
    app.appCheckProvider = appCheck;
    source = TokenSource(
      app,
      origins: origins ?? <Uri>[apiOrigin],
      emulator: emulator,
      onWarning: sink ? warnings.add : null,
      elapsed: () => async.elapsed,
    );
  }

  /// The fake time the source's clock follows.
  final FakeAsync async;

  /// The app of the source.
  final FirebaseApp app;

  /// The source under test.
  late final TokenSource source;

  /// Every warning the source logged, in order.
  final List<String> warnings = <String>[];

  /// Calls `tokensFor` and runs the microtasks, so an answer that needs no time has arrived.
  Probe<RequestTokens> ask({
    Uri? url,
    bool limitedUse = false,
    bool chosenByApplication = false,
    Duration? timeLeft,
  }) {
    final Probe<RequestTokens> probe = Probe<RequestTokens>(
      source.tokensFor(
        url ?? apiUrl,
        limitedUseAppCheck: limitedUse,
        originChosenByApplication: chosenByApplication,
        timeLeft: timeLeft,
      ),
    );
    async.flushMicrotasks();
    return probe;
  }
}

/// The headers of [tokens] for [url] (default: [apiUrl]) in the `bearer` style. Spends the single
/// use of [tokens].
Map<String, String> headersOf(RequestTokens tokens, [Uri? url]) =>
    tokens.headersFor(url ?? apiUrl, auth: AuthHeaderStyle.bearer);
