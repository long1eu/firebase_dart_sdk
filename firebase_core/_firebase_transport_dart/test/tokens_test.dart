// Shared specification v3, 5.6 and 5.9, with the lead's readings 1 to 28: the one failure rule for
// Auth and App Check tokens, the destination rule, the waits, sharing, the pause of a stuck
// provider, forced refreshes, the warnings, and the single-use RequestTokens.
//
// Every provider is a fake; time is fake_async's, and the source's monotonic clock follows it.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:_firebase_transport_dart/_firebase_transport_dart.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'support/fake_providers.dart';

const Duration _tick = Duration(milliseconds: 1);
const String _appCheckHeader = 'X-Firebase-AppCheck';
const String _sentWithout = 'the request was sent without an App Check token.';

/// A test whose body runs in a `fakeAsync` zone.
void _fakeTest(String name, void Function(FakeAsync async) body) {
  test(
    name,
    () => fakeAsync((FakeAsync async) {
      body(async);
      // An error left in a microtask must fail the test that caused it.
      async.flushMicrotasks();
    }),
  );
}

/// The headers of a request that carries both tokens in the `bearer` style.
Map<String, String> _both({
  String auth = fakeAuthToken,
  String appCheck = fakeAppCheckToken,
}) => <String, String>{
  'Authorization': 'Bearer $auth',
  _appCheckHeader: appCheck,
};

Map<String, String> _authOnly([String auth = fakeAuthToken]) =>
    <String, String>{'Authorization': 'Bearer $auth'};

/// A provider that answers a session and a limited-use request alike with [result].
FakeLimitedUseProvider _giving(AppCheckTokenResult result) =>
    FakeLimitedUseProvider.bothAnswering(() async => result);

int _asked(FakeLimitedUseProvider provider) =>
    provider.calls.length + provider.limitedCalls;

String _typeOf(Object object) => '${object.runtimeType}';

void main() {
  _failureRuleTable();
  _providerTests();
  _deadlineTests();
  _sharingTests();
  _stuckProviderTests();
  _forcedRefreshTests();
  _destinationTests();
  _requestTokensTests();
  _limitedUseTests();
  _warningTests();
  _reviewTests();
}

void _failureRuleTable() {
  group('5.6 table', () {
    for (final bool limited in <bool>[false, true]) {
      final String kind = limited ? 'limited-use' : 'session';
      _tableRowsThatProceed(limited, kind);
      _tableRowsThatFail(limited, kind);
    }

    _fakeTest('limited-use asked for and the provider cannot mint: no header, '
        'the call proceeds', (FakeAsync async) {
      final FakeAppCheckProvider appCheck = FakeAppCheckProvider();
      final TokenRig rig = TokenRig(
        async,
        auth: FakeAuthProvider(),
        appCheck: appCheck,
      );
      final RequestTokens tokens = rig.ask(limitedUse: true).value;
      expect(tokens.appCheck, AppCheckOutcome.unsupported);
      expect(headersOf(tokens), _authOnly());
    });
  });
}

void _tableRowsThatProceed(bool limited, String kind) {
  final String expectedAppCheck = limited
      ? fakeLimitedUseToken
      : fakeAppCheckToken;

  _fakeTest('no provider on the app: no header, the call proceeds ($kind)', (
    FakeAsync async,
  ) {
    final TokenRig rig = TokenRig(async);
    final RequestTokens tokens = rig.ask(limitedUse: limited).value;
    expect(tokens.hasAuthToken, isFalse);
    expect(tokens.appCheck, AppCheckOutcome.none);
    expect(headersOf(tokens), isEmpty);
    expect(rig.warnings, isEmpty);
  });

  _fakeTest('nobody signed in, or an empty token: no header, the call proceeds '
      '($kind)', (FakeAsync async) {
    final TokenRig signedOut = TokenRig(
      async,
      auth: FakeAuthProvider.answering(
        (bool _) async => throw const FirebaseNoSignedInUserException('nobody'),
      ),
      appCheck: _giving(const AppCheckTokenResult('')),
    );
    final RequestTokens tokens = signedOut.ask(limitedUse: limited).value;
    expect(tokens.hasAuthToken, isFalse);
    expect(tokens.appCheck, AppCheckOutcome.empty);
    expect(headersOf(tokens), isEmpty);

    final TokenRig emptyAuth = TokenRig(async, auth: FakeAuthProvider(''));
    final RequestTokens none = emptyAuth.ask(limitedUse: limited).value;
    expect(none.hasAuthToken, isFalse);
    expect(headersOf(none), isEmpty);
  });

  _fakeTest('token text, no error: both are sent ($kind)', (FakeAsync async) {
    final TokenRig rig = TokenRig(
      async,
      auth: FakeAuthProvider(),
      appCheck: FakeLimitedUseProvider(),
    );
    final RequestTokens tokens = rig.ask(limitedUse: limited).value;
    expect(tokens.hasAuthToken, isTrue);
    expect(tokens.appCheck, AppCheckOutcome.sent);
    expect(headersOf(tokens), _both(appCheck: expectedAppCheck));
    expect(rig.warnings, isEmpty);
  });

  _fakeTest('token text with an error: the App Check token is sent ($kind)', (
    FakeAsync async,
  ) {
    final TokenRig rig = TokenRig(
      async,
      auth: FakeAuthProvider(),
      appCheck: _giving(AppCheckTokenResult.failure(StateError('down'))),
    );
    final RequestTokens tokens = rig.ask(limitedUse: limited).value;
    expect(tokens.appCheck, AppCheckOutcome.sentPlaceholder);
    expect(
      headersOf(tokens),
      _both(appCheck: AppCheckTokenResult.placeholderToken),
    );
  });

  _fakeTest('an App Check throw, or a token that is not token text: no header, '
      'the call proceeds ($kind)', (FakeAsync async) {
    final TokenRig threw = TokenRig(
      async,
      auth: FakeAuthProvider(),
      appCheck: FakeLimitedUseProvider.bothAnswering(
        () async => throw StateError('attestation failed'),
      ),
    );
    final RequestTokens afterThrow = threw.ask(limitedUse: limited).value;
    expect(afterThrow.appCheck, AppCheckOutcome.providerFailed);
    expect(headersOf(afterThrow), _authOnly());

    final TokenRig threwAtOnce = TokenRig(
      async,
      auth: FakeAuthProvider(),
      appCheck: FakeLimitedUseProvider.bothAnswering(
        () => throw StateError('attestation failed before any await'),
      ),
    );
    final RequestTokens afterSyncThrow = threwAtOnce
        .ask(limitedUse: limited)
        .value;
    expect(afterSyncThrow.appCheck, AppCheckOutcome.providerFailed);
    expect(headersOf(afterSyncThrow), _authOnly());

    for (final String bad in <String>[
      'has space',
      'line\nbreak',
      'nul\u0000',
    ]) {
      final TokenRig rig = TokenRig(
        async,
        auth: FakeAuthProvider(),
        appCheck: _giving(AppCheckTokenResult(bad)),
      );
      final RequestTokens tokens = rig.ask(limitedUse: limited).value;
      expect(tokens.appCheck, AppCheckOutcome.empty);
      expect(headersOf(tokens), _authOnly());
    }
  });

  _fakeTest('no App Check answer within the wait: no header, the call proceeds '
      '($kind)', (FakeAsync async) {
    final FakeLimitedUseProvider appCheck = FakeLimitedUseProvider()
      ..holdCalls()
      ..holdLimitedCalls();
    final TokenRig rig = TokenRig(
      async,
      auth: FakeAuthProvider(),
      appCheck: appCheck,
    );
    final Probe<RequestTokens> probe = rig.ask(limitedUse: limited);
    async.elapse(TokenSource.providerWait - _tick);
    expect(probe.isDone, isFalse);
    async.elapse(_tick);
    expect(probe.value.appCheck, AppCheckOutcome.timedOut);
    expect(headersOf(probe.value), _authOnly());
  });

  _fakeTest(
    'an App Check token over the cap counts as not token text ($kind)',
    (FakeAsync async) {
      final TokenRig atCap = TokenRig(
        async,
        appCheck: _giving(AppCheckTokenResult('a' * maxTokenLength)),
      );
      final RequestTokens sent = atCap.ask(limitedUse: limited).value;
      expect(sent.appCheck, AppCheckOutcome.sent);
      expect(headersOf(sent)[_appCheckHeader], hasLength(maxTokenLength));

      final TokenRig overCap = TokenRig(
        async,
        appCheck: _giving(AppCheckTokenResult('a' * (maxTokenLength + 1))),
      );
      final RequestTokens dropped = overCap.ask(limitedUse: limited).value;
      expect(dropped.appCheck, AppCheckOutcome.empty);
      expect(headersOf(dropped), isEmpty);
    },
  );
}

void _tableRowsThatFail(bool limited, String kind) {
  _fakeTest('an Auth throw, or a token that is not token text: the call fails '
      '($kind)', (FakeAsync async) {
    final StateError cause = StateError('token server said no');
    final TokenRig threw = TokenRig(
      async,
      auth: FakeAuthProvider.answering((bool _) async => throw cause),
      appCheck: FakeLimitedUseProvider(),
    );
    final Object failure = threw.ask(limitedUse: limited).error;
    expect(failure, isTokenFailure(TokenFailure.authProviderFailed));
    expect((failure as TokenFetchException).causeType, _typeOf(cause));

    final TokenRig threwAtOnce = TokenRig(
      async,
      auth: FakeAuthProvider.answering((bool _) => throw cause),
    );
    final Object syncFailure = threwAtOnce.ask(limitedUse: limited).error;
    expect(syncFailure, isTokenFailure(TokenFailure.authProviderFailed));
    expect((syncFailure as TokenFetchException).causeType, _typeOf(cause));

    for (final String bad in <String>[
      'has space',
      'line\nbreak',
      'nul\u0000',
    ]) {
      final TokenRig rig = TokenRig(async, auth: FakeAuthProvider(bad));
      final Object error = rig.ask(limitedUse: limited).error;
      expect(error, isTokenFailure(TokenFailure.authProviderFailed));
      expect((error as TokenFetchException).causeType, isNull);
    }
  });

  _fakeTest('no Auth answer within the wait: the call fails ($kind)', (
    FakeAsync async,
  ) {
    final FakeAuthProvider auth = FakeAuthProvider()..holdCalls();
    final TokenRig rig = TokenRig(
      async,
      auth: auth,
      appCheck: FakeLimitedUseProvider(),
    );
    final Probe<RequestTokens> probe = rig.ask(limitedUse: limited);
    async.elapse(TokenSource.providerWait - _tick);
    expect(probe.isDone, isFalse);
    async.elapse(_tick);
    expect(probe.error, isTokenFailure(TokenFailure.authTimedOut));
  });

  _fakeTest('the Auth token is longer than 8192 characters: the call fails '
      '($kind)', (FakeAsync async) {
    final TokenRig rig = TokenRig(
      async,
      auth: FakeAuthProvider('a' * (maxTokenLength + 1)),
      appCheck: FakeLimitedUseProvider(),
    );
    expect(
      rig.ask(limitedUse: limited).error,
      isTokenFailure(TokenFailure.authTokenTooLong),
    );
  });

  _fakeTest('the destination may not receive tokens: the call fails, with or '
      'without a provider ($kind)', (FakeAsync async) {
    final Uri clearText = Uri.parse('http://api.example.test/v1/call');
    final FakeAuthProvider auth = FakeAuthProvider();
    final FakeLimitedUseProvider appCheck = FakeLimitedUseProvider();
    final TokenRig withProviders = TokenRig(
      async,
      auth: auth,
      appCheck: appCheck,
    );
    expect(
      withProviders.ask(url: clearText, limitedUse: limited).error,
      isTokenFailure(TokenFailure.destinationRefused),
    );
    expect(auth.calls, isEmpty);
    expect(_asked(appCheck), 0);

    final TokenRig bare = TokenRig(async);
    expect(
      bare.ask(url: clearText, limitedUse: limited).error,
      isTokenFailure(TokenFailure.destinationRefused),
    );
  });

  _fakeTest('the app was deleted: StateError, nothing is asked ($kind)', (
    FakeAsync async,
  ) {
    final FakeAuthProvider auth = FakeAuthProvider();
    final FakeLimitedUseProvider appCheck = FakeLimitedUseProvider();
    final TokenRig rig = TokenRig(async, auth: auth, appCheck: appCheck);
    unawaited(rig.app.delete());
    expect(rig.ask(limitedUse: limited).error, isStateError);
    expect(auth.calls, isEmpty);
    expect(_asked(appCheck), 0);
  });
}

void _providerTests() {
  _fakeTest('the app as its own Auth provider', (FakeAsync async) {
    final TokenRig rig = TokenRig(async, appCheck: FakeAppCheckProvider());
    expect(identical(rig.app.authProvider, rig.app), isTrue);
    // The app's own getAccessToken always throws: a call to it would fail the request.
    final RequestTokens tokens = rig.ask().value;
    expect(tokens.hasAuthToken, isFalse);
    expect(headersOf(tokens), <String, String>{
      _appCheckHeader: fakeAppCheckToken,
    });

    final TokenRig explicit = TokenRig(async);
    explicit.app.authProvider = explicit.app;
    expect(explicit.ask().value.hasAuthToken, isFalse);
  });

  _fakeTest('both no-user exceptions', (FakeAsync async) {
    final List<Exception> noUser = <Exception>[
      const FirebaseNoSignedInUserException('nobody is signed in'),
      const FirebaseApiNotAvailableException('Auth is not available'),
    ];
    for (final Exception exception in noUser) {
      final FakeAuthProvider auth = FakeAuthProvider.answering(
        (bool _) async => throw exception,
      );
      final TokenRig rig = TokenRig(
        async,
        auth: auth,
        appCheck: FakeAppCheckProvider(),
      );
      final RequestTokens tokens = rig.ask().value;
      expect(auth.calls, hasLength(1), reason: '$exception');
      expect(tokens.hasAuthToken, isFalse, reason: '$exception');
      expect(headersOf(tokens), <String, String>{
        _appCheckHeader: fakeAppCheckToken,
      });
      expect(rig.warnings, isEmpty);
    }
  });

  _fakeTest('an App Check provider that is not available gives none, '
      'unlogged', (FakeAsync async) {
    final TokenRig rig = TokenRig(
      async,
      auth: FakeAuthProvider(),
      appCheck: FakeAppCheckProvider.answering(
        (bool _) async =>
            throw const FirebaseApiNotAvailableException('closed'),
      ),
    );
    final RequestTokens tokens = rig.ask().value;
    expect(tokens.appCheck, AppCheckOutcome.none);
    expect(headersOf(tokens), _authOnly());
    expect(rig.warnings, isEmpty);
  });

  _fakeTest('providers asked in parallel', (FakeAsync async) {
    final FakeAuthProvider auth = FakeAuthProvider()..holdCalls();
    final FakeAppCheckProvider appCheck = FakeAppCheckProvider()..holdCalls();
    final TokenRig rig = TokenRig(async, auth: auth, appCheck: appCheck);
    final Probe<RequestTokens> probe = rig.ask();
    // Both were asked before either answered.
    expect(auth.calls, <bool>[false]);
    expect(appCheck.calls, <bool>[false]);

    appCheck.waiting.single.complete(
      const AppCheckTokenResult(fakeAppCheckToken),
    );
    async.flushMicrotasks();
    expect(probe.isDone, isFalse);
    auth.waiting.single.complete(GetTokenResult(fakeAuthToken));
    async.flushMicrotasks();
    expect(headersOf(probe.value), _both());

    // An Auth failure is thrown only once the App Check provider has settled too.
    final Probe<RequestTokens> failing = rig.ask();
    auth.waiting.last.completeError(StateError('token server said no'));
    async.flushMicrotasks();
    expect(failing.isDone, isFalse);
    appCheck.waiting.last.complete(
      const AppCheckTokenResult(fakeAppCheckToken),
    );
    async.flushMicrotasks();
    expect(failing.error, isTokenFailure(TokenFailure.authProviderFailed));
  });

  _fakeTest('a result with an error and a real token: the token is sent '
      '(sentPlaceholder)', (FakeAsync async) {
    const String real = 'REAL-UNEXPIRED-APPCHECK-TOKEN';
    final TokenRig rig = TokenRig(
      async,
      auth: FakeAuthProvider(),
      appCheck: FakeAppCheckProvider.answering(
        (bool _) async =>
            AppCheckTokenResult(real, error: StateError('refresh failed')),
      ),
    );
    final RequestTokens tokens = rig.ask().value;
    expect(tokens.appCheck, AppCheckOutcome.sentPlaceholder);
    expect(headersOf(tokens), _both(appCheck: real));
  });

  _fakeTest('providers read per call (a provider set after construction is '
      'used)', (FakeAsync async) {
    final TokenRig rig = TokenRig(async);
    final RequestTokens before = rig.ask().value;
    expect(before.appCheck, AppCheckOutcome.none);
    expect(headersOf(before), isEmpty);

    rig.app.authProvider = FakeAuthProvider();
    rig.app.appCheckProvider = FakeAppCheckProvider();
    final RequestTokens after = rig.ask().value;
    expect(after.appCheck, AppCheckOutcome.sent);
    expect(headersOf(after), _both());

    rig.app.appCheckProvider = null;
    expect(rig.ask().value.appCheck, AppCheckOutcome.none);
  });

  _fakeTest('sequential calls each ask the provider', (FakeAsync async) {
    final FakeAuthProvider auth = FakeAuthProvider();
    final FakeAppCheckProvider appCheck = FakeAppCheckProvider();
    final TokenRig rig = TokenRig(async, auth: auth, appCheck: appCheck);
    for (int i = 1; i <= 3; i++) {
      expect(headersOf(rig.ask().value), _both());
      expect(auth.calls, hasLength(i));
      expect(appCheck.calls, hasLength(i));
    }
  });

  _fakeTest('Auth token of 8193 characters (authTokenTooLong)', (
    FakeAsync async,
  ) {
    final String longest = 'a' * maxTokenLength;
    final TokenRig atCap = TokenRig(async, auth: FakeAuthProvider(longest));
    expect(headersOf(atCap.ask().value), _authOnly(longest));

    final TokenRig overCap = TokenRig(
      async,
      auth: FakeAuthProvider('${longest}a'),
      appCheck: FakeAppCheckProvider(),
    );
    final Object error = overCap.ask().error;
    expect(error, isTokenFailure(TokenFailure.authTokenTooLong));
    expect((error as TokenFetchException).causeType, isNull);
    expect('$error', 'TokenFetchException: authTokenTooLong');
  });

  _fakeTest('deleted app', (FakeAsync async) {
    final FakeAuthProvider auth = FakeAuthProvider();
    final FakeAppCheckProvider appCheck = FakeAppCheckProvider();
    final TokenRig rig = TokenRig(async, auth: auth, appCheck: appCheck);
    expect(headersOf(rig.ask().value), _both());
    final String name = rig.app.name;
    unawaited(rig.app.delete());
    // Reading 12: the StateError arrives through the future, not from the call itself.
    expect(rig.ask().error, isStateError);
    expect(auth.calls, hasLength(1));
    expect(appCheck.calls, hasLength(1));

    // A new app under the same name never gets tokens through the old source.
    final FirebaseApp reborn = FirebaseApp.withOptions(
      const FirebaseOptions(
        apiKey: 'fake-api-key',
        appId: '1:1234567890:web:transporttest',
        projectId: 'demo-transport',
      ),
      name: name,
    );
    installAuth(reborn, auth);
    expect(reborn.name, name);
    expect(rig.ask().error, isStateError);
    expect(auth.calls, isEmpty);
  });

  _fakeTest('deletion during the wait (the tokens are dropped)', (
    FakeAsync async,
  ) {
    final FakeAuthProvider auth = FakeAuthProvider()..holdCalls();
    final TokenRig rig = TokenRig(
      async,
      auth: auth,
      appCheck: FakeAppCheckProvider(),
    );
    final Probe<RequestTokens> probe = rig.ask();
    expect(probe.isDone, isFalse);
    unawaited(rig.app.delete());
    auth.waiting.single.complete(GetTokenResult(fakeAuthToken));
    async.flushMicrotasks();
    expect(probe.error, isStateError);
  });
}

void _deadlineTests() {
  test('providerWait is greater than responseDeadline', () {
    expect(TokenSource.providerWait, const Duration(seconds: 10));
    expect(
      TokenSource.providerWait,
      greaterThan(AppCheckTokenProvider.responseDeadline),
    );
    expect(
      TokenSource.authForcedRefreshMinInterval,
      const Duration(seconds: 60),
    );
    expect(TokenSource.stuckProviderPause, const Duration(seconds: 60));
  });

  _fakeTest('slow App Check provider', (FakeAsync async) {
    final FakeAppCheckProvider appCheck = FakeAppCheckProvider()..holdCalls();
    final TokenRig rig = TokenRig(
      async,
      auth: FakeAuthProvider(),
      appCheck: appCheck,
    );
    final Probe<RequestTokens> probe = rig.ask();
    async.elapse(TokenSource.providerWait - _tick);
    expect(probe.isDone, isFalse);
    async.elapse(_tick);
    final RequestTokens tokens = probe.value;
    expect(tokens.appCheck, AppCheckOutcome.timedOut);
    expect(tokens.hasAuthToken, isTrue);

    // The late answer is ignored; a late error would fail this zone if it were unhandled.
    appCheck.waiting.single.completeError(StateError('late failure'));
    async.flushMicrotasks();
    expect(headersOf(tokens), _authOnly());
    expect(async.pendingTimers, isEmpty);
  });

  _fakeTest('slow Auth provider', (FakeAsync async) {
    final FakeAuthProvider auth = FakeAuthProvider()..holdCalls();
    final TokenRig rig = TokenRig(
      async,
      auth: auth,
      appCheck: FakeAppCheckProvider(),
    );
    final Probe<RequestTokens> probe = rig.ask();
    async.elapse(TokenSource.providerWait - _tick);
    expect(probe.isDone, isFalse);
    async.elapse(_tick);
    expect(probe.error, isTokenFailure(TokenFailure.authTimedOut));
    expect((probe.error as TokenFetchException).causeType, isNull);

    auth.waiting.single.completeError(StateError('late failure'));
    async.flushMicrotasks();
    expect(async.pendingTimers, isEmpty);
  });

  _fakeTest('timeLeft shorter than the wait and a provider still pending: '
      'TimeoutException, late results ignored, no pause started', (
    FakeAsync async,
  ) {
    final FakeAppCheckProvider appCheck = FakeAppCheckProvider()..holdCalls();
    final TokenRig rig = TokenRig(
      async,
      auth: FakeAuthProvider(),
      appCheck: appCheck,
    );
    final Probe<RequestTokens> probe = rig.ask(
      timeLeft: const Duration(seconds: 3),
    );
    async.elapse(const Duration(seconds: 3) - _tick);
    expect(probe.isDone, isFalse);
    async.elapse(_tick);
    expect(probe.error, isA<TimeoutException>());
    expect(async.pendingTimers, isEmpty);

    // Past the provider's own wait: no pause started, so the next request asks again.
    async.elapse(const Duration(seconds: 8));
    expect(rig.warnings, isEmpty);
    final Probe<RequestTokens> next = rig.ask();
    expect(appCheck.calls, hasLength(2));
    expect(next.isDone, isFalse);

    appCheck.waiting.first.complete(const AppCheckTokenResult('LATE-TOKEN'));
    async.flushMicrotasks();
    expect(next.isDone, isFalse);
    appCheck.waiting.last.complete(
      const AppCheckTokenResult(fakeAppCheckToken),
    );
    async.flushMicrotasks();
    expect(next.value.appCheck, AppCheckOutcome.sent);
    expect(headersOf(next.value), _both());
  });

  _fakeTest('timeLeft shorter than the wait and the Auth provider pending: '
      'TimeoutException, no pause started', (FakeAsync async) {
    final FakeAuthProvider auth = FakeAuthProvider()..holdCalls();
    final TokenRig rig = TokenRig(
      async,
      auth: auth,
      appCheck: FakeAppCheckProvider(),
    );
    final Probe<RequestTokens> probe = rig.ask(
      timeLeft: const Duration(seconds: 3),
    );
    async.elapse(const Duration(seconds: 3));
    expect(probe.error, isA<TimeoutException>());
    expect(async.pendingTimers, isEmpty);

    async.elapse(const Duration(seconds: 8));
    final Probe<RequestTokens> next = rig.ask();
    expect(auth.calls, hasLength(2));
    auth.waiting.first.completeError(StateError('late failure'));
    auth.waiting.last.complete(GetTokenResult(fakeAuthToken));
    async.flushMicrotasks();
    expect(headersOf(next.value), _both());
  });

  _fakeTest('timeLeft longer than the wait behaves as without it', (
    FakeAsync async,
  ) {
    final FakeAppCheckProvider appCheck = FakeAppCheckProvider()..holdCalls();
    final TokenRig rig = TokenRig(
      async,
      auth: FakeAuthProvider(),
      appCheck: appCheck,
    );
    final Probe<RequestTokens> probe = rig.ask(
      timeLeft: const Duration(seconds: 30),
    );
    async.elapse(TokenSource.providerWait - _tick);
    expect(probe.isDone, isFalse);
    async.elapse(_tick);
    expect(probe.value.appCheck, AppCheckOutcome.timedOut);
    expect(headersOf(probe.value), _authOnly());
    expect(async.pendingTimers, isEmpty);
    // The provider had its full wait, so the pause started.
    expect(rig.ask().value.appCheck, AppCheckOutcome.skipped);
    expect(appCheck.calls, hasLength(1));
  });

  _fakeTest('zero timeLeft is an ArgumentError', (FakeAsync async) {
    final FakeAuthProvider auth = FakeAuthProvider();
    final FakeAppCheckProvider appCheck = FakeAppCheckProvider();
    final TokenRig rig = TokenRig(async, auth: auth, appCheck: appCheck);
    // Reading 12: the error arrives through the future; a synchronous throw would fail here.
    expect(rig.ask(timeLeft: Duration.zero).error, isArgumentError);
    expect(rig.ask(timeLeft: -_tick).error, isArgumentError);
    expect(auth.calls, isEmpty);
    expect(appCheck.calls, isEmpty);
    expect(headersOf(rig.ask(timeLeft: _tick).value), _both());
  });

  _fakeTest('reading 5: timeLeft equal to providerWait adds no extra timer', (
    FakeAsync async,
  ) {
    TokenRig stuckRig() => TokenRig(
      async,
      auth: FakeAuthProvider()..holdCalls(),
      appCheck: FakeAppCheckProvider()..holdCalls(),
    );
    final Probe<RequestTokens> without = stuckRig().ask();
    final int perRequest = async.pendingTimers.length;
    expect(perRequest, 2);
    final Probe<RequestTokens> equal = stuckRig().ask(
      timeLeft: TokenSource.providerWait,
    );
    expect(async.pendingTimers, hasLength(2 * perRequest));
    final Probe<RequestTokens> shorter = stuckRig().ask(
      timeLeft: TokenSource.providerWait - _tick,
    );
    expect(async.pendingTimers, hasLength(3 * perRequest + 1));

    async.elapse(TokenSource.providerWait);
    expect(without.error, isTokenFailure(TokenFailure.authTimedOut));
    expect(equal.error, isTokenFailure(TokenFailure.authTimedOut));
    expect(shorter.error, isA<TimeoutException>());
  });

  _fakeTest('timers cancelled', (FakeAsync async) {
    final TokenRig rig = TokenRig(
      async,
      auth: FakeAuthProvider(),
      appCheck: FakeLimitedUseProvider(),
    );
    expect(rig.ask().isDone, isTrue);
    expect(async.pendingTimers, isEmpty);
    expect(rig.ask(limitedUse: true).isDone, isTrue);
    expect(async.pendingTimers, isEmpty);
    expect(rig.ask(timeLeft: const Duration(seconds: 5)).isDone, isTrue);
    expect(async.pendingTimers, isEmpty);
  });
}

void _sharingTests() {
  _fakeTest('concurrent App Check session requests share one provider call', (
    FakeAsync async,
  ) {
    final FakeAppCheckProvider appCheck = FakeAppCheckProvider()..holdCalls();
    final TokenRig rig = TokenRig(
      async,
      auth: FakeAuthProvider(),
      appCheck: appCheck,
    );
    final Probe<RequestTokens> first = rig.ask();
    final Probe<RequestTokens> second = rig.ask();
    expect(appCheck.calls, <bool>[false]);

    appCheck.waiting.single.complete(
      const AppCheckTokenResult(fakeAppCheckToken),
    );
    async.flushMicrotasks();
    expect(first.value.sameTokensAs(second.value), isTrue);
    expect(headersOf(first.value), _both());
    expect(headersOf(second.value), _both());

    // Sharing ends when the call settles: nothing of its result is kept.
    rig.ask();
    expect(appCheck.calls, hasLength(2));
  });

  _fakeTest('an Auth call is never shared', (FakeAsync async) {
    final FakeAuthProvider auth = FakeAuthProvider()..holdCalls();
    final TokenRig rig = TokenRig(async, auth: auth);
    final Probe<RequestTokens> first = rig.ask();
    final Probe<RequestTokens> second = rig.ask();
    expect(auth.calls, <bool>[false, false]);

    auth.waiting.first.complete(GetTokenResult('FAKE-TOKEN-OF-USER-ONE'));
    auth.waiting.last.complete(GetTokenResult('FAKE-TOKEN-OF-USER-TWO'));
    async.flushMicrotasks();
    expect(first.value.sameTokensAs(second.value), isFalse);
    expect(headersOf(first.value), _authOnly('FAKE-TOKEN-OF-USER-ONE'));
    expect(headersOf(second.value), _authOnly('FAKE-TOKEN-OF-USER-TWO'));
  });

  _fakeTest('a limited-use call is never shared', (FakeAsync async) {
    final FakeLimitedUseProvider appCheck = FakeLimitedUseProvider()
      ..holdLimitedCalls();
    final TokenRig rig = TokenRig(async, appCheck: appCheck);
    final Probe<RequestTokens> first = rig.ask(limitedUse: true);
    final Probe<RequestTokens> second = rig.ask(limitedUse: true);
    expect(appCheck.limitedCalls, 2);
    expect(appCheck.calls, isEmpty);

    appCheck.limitedWaiting.first.complete(
      const AppCheckTokenResult('FAKE-LIMITED-ONE'),
    );
    appCheck.limitedWaiting.last.complete(
      const AppCheckTokenResult('FAKE-LIMITED-TWO'),
    );
    async.flushMicrotasks();
    expect(headersOf(first.value)[_appCheckHeader], 'FAKE-LIMITED-ONE');
    expect(headersOf(second.value)[_appCheckHeader], 'FAKE-LIMITED-TWO');
  });

  _fakeTest('a forced request does not join a pending call', (FakeAsync async) {
    final FakeAppCheckProvider appCheck = FakeAppCheckProvider()..holdCalls();
    final TokenRig rig = TokenRig(async, appCheck: appCheck);
    final Probe<RequestTokens> before = rig.ask();
    rig.source.invalidate(TokenKind.appCheck);
    final Probe<RequestTokens> forced = rig.ask();
    expect(appCheck.calls, <bool>[false, true]);

    appCheck.waiting.first.complete(const AppCheckTokenResult('FAKE-REFUSED'));
    appCheck.waiting.last.complete(const AppCheckTokenResult('FAKE-FRESH'));
    async.flushMicrotasks();
    expect(headersOf(before.value)[_appCheckHeader], 'FAKE-REFUSED');
    expect(headersOf(forced.value)[_appCheckHeader], 'FAKE-FRESH');
  });

  _fakeTest('reading 13: a later request joins the most recent getToken call', (
    FakeAsync async,
  ) {
    final FakeAppCheckProvider appCheck = FakeAppCheckProvider()..holdCalls();
    final TokenRig rig = TokenRig(async, appCheck: appCheck);
    rig.ask();
    rig.source.invalidate(TokenKind.appCheck);
    rig.ask();
    final Probe<RequestTokens> later = rig.ask();
    // The debt was paid by the forced call; the later request joins that call.
    expect(appCheck.calls, <bool>[false, true]);

    appCheck.waiting.first.complete(const AppCheckTokenResult('FAKE-REFUSED'));
    async.flushMicrotasks();
    expect(later.isDone, isFalse);
    appCheck.waiting.last.complete(const AppCheckTokenResult('FAKE-FRESH'));
    async.flushMicrotasks();
    expect(headersOf(later.value)[_appCheckHeader], 'FAKE-FRESH');
  });

  _fakeTest('a request on a replaced provider object does not join', (
    FakeAsync async,
  ) {
    final FakeAppCheckProvider old = FakeAppCheckProvider()..holdCalls();
    final FakeAppCheckProvider replacement = FakeAppCheckProvider()
      ..holdCalls();
    final TokenRig rig = TokenRig(async, appCheck: old);
    final Probe<RequestTokens> first = rig.ask();
    rig.app.appCheckProvider = replacement;
    final Probe<RequestTokens> second = rig.ask();
    expect(old.calls, hasLength(1));
    expect(replacement.calls, hasLength(1));

    old.waiting.single.complete(const AppCheckTokenResult('FAKE-OLD'));
    replacement.waiting.single.complete(const AppCheckTokenResult('FAKE-NEW'));
    async.flushMicrotasks();
    expect(headersOf(first.value)[_appCheckHeader], 'FAKE-OLD');
    expect(headersOf(second.value)[_appCheckHeader], 'FAKE-NEW');
  });

  _fakeTest('a short-timeLeft joiner on a shared App Check call times out, and '
      'the other request still gets its token', (FakeAsync async) {
    final FakeAppCheckProvider appCheck = FakeAppCheckProvider()..holdCalls();
    final TokenRig rig = TokenRig(
      async,
      auth: FakeAuthProvider(),
      appCheck: appCheck,
    );
    final Probe<RequestTokens> patient = rig.ask();
    final Probe<RequestTokens> hurried = rig.ask(
      timeLeft: const Duration(seconds: 2),
    );
    expect(appCheck.calls, hasLength(1));

    async.elapse(const Duration(seconds: 2));
    expect(hurried.error, isA<TimeoutException>());
    expect(patient.isDone, isFalse);

    async.elapse(const Duration(seconds: 3));
    appCheck.waiting.single.complete(
      const AppCheckTokenResult(fakeAppCheckToken),
    );
    async.flushMicrotasks();
    expect(patient.value.appCheck, AppCheckOutcome.sent);
    expect(headersOf(patient.value), _both());
    expect(async.pendingTimers, isEmpty);
  });

  _fakeTest('reading 4: a call others still wait on runs its full wait and '
      'can start a pause', (FakeAsync async) {
    final FakeAppCheckProvider appCheck = FakeAppCheckProvider()..holdCalls();
    final TokenRig rig = TokenRig(async, appCheck: appCheck);
    final Probe<RequestTokens> patient = rig.ask();
    final Probe<RequestTokens> hurried = rig.ask(
      timeLeft: const Duration(seconds: 2),
    );
    async.elapse(const Duration(seconds: 2));
    expect(hurried.error, isA<TimeoutException>());
    // The call's timer survives the request that ran out.
    expect(async.pendingTimers, hasLength(1));

    async.elapse(const Duration(seconds: 8) - _tick);
    expect(patient.isDone, isFalse);
    async.elapse(_tick);
    expect(patient.value.appCheck, AppCheckOutcome.timedOut);
    expect(rig.ask().value.appCheck, AppCheckOutcome.skipped);
    expect(appCheck.calls, hasLength(1));
  });

  _fakeTest('reading 4: a call whose first request ran out stays shared by '
      'the others', (FakeAsync async) {
    final FakeAppCheckProvider appCheck = FakeAppCheckProvider()..holdCalls();
    final TokenRig rig = TokenRig(async, appCheck: appCheck);
    final Probe<RequestTokens> hurried = rig.ask(
      timeLeft: const Duration(seconds: 2),
    );
    final Probe<RequestTokens> joiner = rig.ask();
    async.elapse(const Duration(seconds: 2));
    expect(hurried.error, isA<TimeoutException>());
    final Probe<RequestTokens> late = rig.ask();
    expect(appCheck.calls, hasLength(1));

    appCheck.waiting.single.complete(
      const AppCheckTokenResult(fakeAppCheckToken),
    );
    async.flushMicrotasks();
    expect(headersOf(joiner.value)[_appCheckHeader], fakeAppCheckToken);
    expect(headersOf(late.value)[_appCheckHeader], fakeAppCheckToken);
    expect(async.pendingTimers, isEmpty);
  });

  _fakeTest('reading 4: an abandoned call is no longer joinable', (
    FakeAsync async,
  ) {
    final FakeAppCheckProvider appCheck = FakeAppCheckProvider()..holdCalls();
    final TokenRig rig = TokenRig(async, appCheck: appCheck);
    final Probe<RequestTokens> hurried = rig.ask(
      timeLeft: const Duration(seconds: 2),
    );
    async.elapse(const Duration(seconds: 2));
    expect(hurried.error, isA<TimeoutException>());
    // Nobody waits on the call any more: its timer is cancelled.
    expect(async.pendingTimers, isEmpty);

    final Probe<RequestTokens> next = rig.ask();
    expect(appCheck.calls, hasLength(2));
    appCheck.waiting.first.complete(
      const AppCheckTokenResult('FAKE-ABANDONED'),
    );
    async.flushMicrotasks();
    expect(next.isDone, isFalse);
    appCheck.waiting.last.complete(const AppCheckTokenResult('FAKE-OWN'));
    async.flushMicrotasks();
    expect(headersOf(next.value)[_appCheckHeader], 'FAKE-OWN');
  });
}

void _stuckProviderTests() {
  _fakeTest('stuck provider', (FakeAsync async) {
    final FakeLimitedUseProvider appCheck = FakeLimitedUseProvider()
      ..holdCalls();
    final TokenRig rig = TokenRig(
      async,
      auth: FakeAuthProvider(),
      appCheck: appCheck,
    );
    final Probe<RequestTokens> first = rig.ask();
    async.elapse(TokenSource.providerWait);
    expect(first.value.appCheck, AppCheckOutcome.timedOut);

    // No second call for 60 s: session and limited-use requests are skipped at once.
    expect(rig.ask().value.appCheck, AppCheckOutcome.skipped);
    async.elapse(TokenSource.stuckProviderPause - _tick);
    final RequestTokens skipped = rig.ask().value;
    expect(skipped.appCheck, AppCheckOutcome.skipped);
    expect(headersOf(skipped), _authOnly());
    expect(rig.ask(limitedUse: true).value.appCheck, AppCheckOutcome.skipped);
    expect(appCheck.calls, hasLength(1));
    expect(appCheck.limitedCalls, 0);

    // One call after the pause.
    async.elapse(_tick);
    final Probe<RequestTokens> probe = rig.ask();
    expect(appCheck.calls, hasLength(2));
    async.elapse(TokenSource.providerWait);
    expect(probe.value.appCheck, AppCheckOutcome.timedOut);
    expect(rig.ask().value.appCheck, AppCheckOutcome.skipped);
    expect(appCheck.calls, hasLength(2));

    // A late answer ends the pause.
    appCheck.waiting.first.complete(const AppCheckTokenResult('LATE-TOKEN'));
    async.flushMicrotasks();
    final Probe<RequestTokens> afterAnswer = rig.ask();
    expect(appCheck.calls, hasLength(3));
    appCheck.waiting.last.complete(
      const AppCheckTokenResult(fakeAppCheckToken),
    );
    async.flushMicrotasks();
    expect(afterAnswer.value.appCheck, AppCheckOutcome.sent);
    expect(headersOf(afterAnswer.value), _both());
  });

  _fakeTest('reading 2: the App Check call after a pause restarts the pause '
      'clock', (FakeAsync async) {
    final FakeAppCheckProvider appCheck = FakeAppCheckProvider()..holdCalls();
    final TokenRig rig = TokenRig(async, appCheck: appCheck);
    rig.ask();
    async.elapse(TokenSource.providerWait);
    async.elapse(TokenSource.stuckProviderPause);
    final Probe<RequestTokens> probe = rig.ask();
    expect(appCheck.calls, hasLength(2));

    // During the probe, requests are skipped at once and make no further call.
    async.elapse(const Duration(seconds: 5));
    expect(rig.ask().value.appCheck, AppCheckOutcome.skipped);
    expect(appCheck.calls, hasLength(2));

    async.elapse(const Duration(seconds: 5));
    expect(probe.value.appCheck, AppCheckOutcome.timedOut);
    async.elapse(TokenSource.stuckProviderPause - _tick);
    expect(rig.ask().value.appCheck, AppCheckOutcome.skipped);
    expect(appCheck.calls, hasLength(2));
    async.elapse(_tick);
    rig.ask();
    expect(appCheck.calls, hasLength(3));
  });

  _fakeTest('reading 2: the Auth call after a pause restarts the pause clock', (
    FakeAsync async,
  ) {
    final FakeAuthProvider auth = FakeAuthProvider()..holdCalls();
    final TokenRig rig = TokenRig(async, auth: auth);
    rig.ask();
    async.elapse(TokenSource.providerWait);
    async.elapse(TokenSource.stuckProviderPause);
    final Probe<RequestTokens> probe = rig.ask();
    expect(auth.calls, hasLength(2));
    expect(probe.isDone, isFalse);

    async.elapse(const Duration(seconds: 5));
    expect(rig.ask().error, isTokenFailure(TokenFailure.authTimedOut));
    expect(auth.calls, hasLength(2));

    async.elapse(const Duration(seconds: 5));
    expect(probe.error, isTokenFailure(TokenFailure.authTimedOut));
    async.elapse(TokenSource.stuckProviderPause - _tick);
    expect(rig.ask().error, isTokenFailure(TokenFailure.authTimedOut));
    expect(auth.calls, hasLength(2));
    async.elapse(_tick);
    rig.ask();
    expect(auth.calls, hasLength(3));
  });

  _fakeTest('reading 3: a paused Auth provider fails at once and App Check is '
      'not asked', (FakeAsync async) {
    final FakeAuthProvider auth = FakeAuthProvider()..holdCalls();
    final FakeAppCheckProvider appCheck = FakeAppCheckProvider();
    final TokenRig rig = TokenRig(async, auth: auth, appCheck: appCheck);
    final Probe<RequestTokens> first = rig.ask();
    async.elapse(TokenSource.providerWait);
    expect(first.error, isTokenFailure(TokenFailure.authTimedOut));
    expect(appCheck.calls, hasLength(1));

    // No time passes: the failure is there after the microtasks.
    expect(rig.ask().error, isTokenFailure(TokenFailure.authTimedOut));
    expect(auth.calls, hasLength(1));
    expect(appCheck.calls, hasLength(1));
    expect(async.pendingTimers, isEmpty);

    // A late answer ends the Auth pause too.
    auth.waiting.single.complete(GetTokenResult('LATE-TOKEN'));
    async.flushMicrotasks();
    auth.answer = (bool _) async => GetTokenResult(fakeAuthToken);
    expect(headersOf(rig.ask().value), _both());
  });

  _fakeTest('the debt survives a skipped request', (FakeAsync async) {
    final FakeLimitedUseProvider appCheck = FakeLimitedUseProvider()
      ..holdCalls();
    final TokenRig rig = TokenRig(async, appCheck: appCheck);
    rig.ask();
    async.elapse(TokenSource.providerWait);
    rig.source.invalidate(TokenKind.appCheck);
    expect(rig.ask().value.appCheck, AppCheckOutcome.skipped);
    expect(rig.ask(limitedUse: true).value.appCheck, AppCheckOutcome.skipped);
    expect(appCheck.calls, <bool>[false]);

    async.elapse(TokenSource.stuckProviderPause);
    rig.ask();
    expect(appCheck.calls, <bool>[false, true]);
  });

  _fakeTest('reading 17: a paused provider that cannot mint gives unsupported, '
      'not skipped', (FakeAsync async) {
    final FakeAppCheckProvider plain = FakeAppCheckProvider()..holdCalls();
    final TokenRig rig = TokenRig(async, appCheck: plain);
    rig.ask();
    async.elapse(TokenSource.providerWait);
    expect(rig.ask().value.appCheck, AppCheckOutcome.skipped);
    expect(
      rig.ask(limitedUse: true).value.appCheck,
      AppCheckOutcome.unsupported,
    );
    expect(plain.calls, hasLength(1));

    final FakeLimitedUseProvider minter = FakeLimitedUseProvider()..holdCalls();
    final TokenRig minting = TokenRig(async, appCheck: minter);
    minting.ask();
    async.elapse(TokenSource.providerWait);
    expect(
      minting.ask(limitedUse: true).value.appCheck,
      AppCheckOutcome.skipped,
    );
    expect(minter.limitedCalls, 0);
  });
}

void _forcedRefreshTests() {
  _fakeTest('Auth forced refresh limit', (FakeAsync async) {
    final FakeAuthProvider auth = FakeAuthProvider();
    final FakeAppCheckProvider appCheck = FakeAppCheckProvider();
    final TokenRig rig = TokenRig(async, auth: auth, appCheck: appCheck);
    rig.ask();
    expect(auth.calls, <bool>[false]);

    // invalidate(auth) forces only Auth, and only once.
    rig.source.invalidate(TokenKind.auth);
    rig.ask();
    expect(auth.calls, <bool>[false, true]);
    rig.ask();
    expect(auth.calls.last, isFalse);

    // A second one within 60 s does not force; the debt stays.
    rig.source.invalidate(TokenKind.auth);
    async.elapse(TokenSource.authForcedRefreshMinInterval - _tick);
    rig.ask();
    expect(auth.calls.last, isFalse);

    // The debt is paid after 60 s, once.
    async.elapse(_tick);
    rig.ask();
    expect(auth.calls.last, isTrue);
    rig.ask();
    expect(auth.calls.last, isFalse);
    expect(appCheck.calls, everyElement(isFalse));
    expect(appCheck.calls, hasLength(auth.calls.length));
  });

  _fakeTest('App Check force passes through', (FakeAsync async) {
    final FakeAuthProvider auth = FakeAuthProvider();
    final FakeLimitedUseProvider appCheck = FakeLimitedUseProvider();
    final TokenRig rig = TokenRig(async, auth: auth, appCheck: appCheck);
    rig.ask();
    expect(appCheck.calls, <bool>[false]);

    // Never a limited-use fetch: it is not forced and leaves the debt.
    rig.source.invalidate(TokenKind.appCheck);
    final RequestTokens limited = rig.ask(limitedUse: true).value;
    expect(headersOf(limited)[_appCheckHeader], fakeLimitedUseToken);
    expect(appCheck.limitedCalls, 1);
    expect(appCheck.calls, <bool>[false]);

    // The next session fetch is forced, once.
    rig.ask();
    expect(appCheck.calls, <bool>[false, true]);
    rig.ask();
    expect(appCheck.calls, <bool>[false, true, false]);

    // With no interval: each invalidate forces the next session fetch.
    for (int i = 0; i < 3; i++) {
      rig.source.invalidate(TokenKind.appCheck);
      rig.ask();
      expect(appCheck.calls.last, isTrue);
    }
    // Two invalidates before one fetch are one debt.
    rig.source.invalidate(TokenKind.appCheck);
    rig.source.invalidate(TokenKind.appCheck);
    rig.ask();
    rig.ask();
    expect(appCheck.calls.sublist(appCheck.calls.length - 2), <bool>[
      true,
      false,
    ]);
    expect(auth.calls, everyElement(isFalse));
  });
}

void _destinationTests() {
  _fakeTest('undeclared origin asks no provider', (FakeAsync async) {
    final FakeAuthProvider auth = FakeAuthProvider();
    final FakeLimitedUseProvider appCheck = FakeLimitedUseProvider();
    final TokenRig rig = TokenRig(async, auth: auth, appCheck: appCheck);
    final TokenRig bare = TokenRig(async);
    final List<Uri> undeclared = <Uri>[
      Uri.parse('https://other.example.test/v1/call'),
      Uri.parse('https://api.example.test:8443/v1/call'),
      Uri.parse('https://api.example.test.evil.test/v1/call'),
      Uri.parse('wss://api.example.test:8443/socket'),
    ];
    for (final Uri url in undeclared) {
      expect(
        rig.ask(url: url).error,
        isTokenFailure(TokenFailure.destinationRefused),
        reason: '$url',
      );
      expect(
        rig.ask(url: url, limitedUse: true).error,
        isTokenFailure(TokenFailure.destinationRefused),
        reason: '$url',
      );
      expect(
        bare.ask(url: url).error,
        isTokenFailure(TokenFailure.destinationRefused),
        reason: '$url with no provider',
      );
    }
    expect(auth.calls, isEmpty);
    expect(_asked(appCheck), 0);
    expect(async.pendingTimers, isEmpty);
  });

  _fakeTest('refused destination', (FakeAsync async) {
    final FakeAuthProvider auth = FakeAuthProvider();
    final FakeAppCheckProvider appCheck = FakeAppCheckProvider();
    final TokenRig rig = TokenRig(async, auth: auth, appCheck: appCheck);
    final List<Uri> refused = <Uri>[
      Uri.parse('http://api.example.test/v1/call'),
      Uri.parse('ws://api.example.test:80/socket'),
      Uri.parse('https://user:pw@api.example.test/v1/call'),
      Uri.parse('ftp://api.example.test/v1/call'),
      Uri.parse('https:///v1/call'),
      Uri.parse('/v1/call'),
      Uri.parse('wss://api.example.test/socket'),
      Uri.parse('ws://localhost/socket'),
    ];
    for (final Uri url in refused) {
      for (final bool chosen in <bool>[false, true]) {
        expect(
          rig.ask(url: url, chosenByApplication: chosen).error,
          isTokenFailure(TokenFailure.destinationRefused),
          reason: '$url, originChosenByApplication: $chosen',
        );
      }
    }
    expect(auth.calls, isEmpty);
    expect(appCheck.calls, isEmpty);
  });

  _fakeTest('a ws origin and URL with and without an explicit port', (
    FakeAsync async,
  ) {
    final TokenRig rig = TokenRig(
      async,
      auth: FakeAuthProvider(),
      appCheck: FakeAppCheckProvider(),
      origins: <Uri>[Uri.parse('ws://localhost:9000')],
    );
    final Uri socket = Uri.parse('ws://localhost:9000/stream');
    final RequestTokens tokens = rig.ask(url: socket).value;
    expect('${tokens.origin}', 'http://localhost:9000');
    expect(headersOf(tokens, socket), _both());
    // The http URL of the same host and port is the same origin.
    final Uri plain = Uri.parse('http://localhost:9000/v1/call');
    expect(headersOf(rig.ask(url: plain).value, plain), _both());

    expect(
      rig.ask(url: Uri.parse('ws://localhost/stream')).error,
      isTokenFailure(TokenFailure.destinationRefused),
    );
    for (final String entry in <String>['ws://localhost', 'wss://h.test']) {
      expect(
        () => TokenSource(rig.app, origins: <Uri>[Uri.parse(entry)]),
        throwsArgumentError,
        reason: entry,
      );
    }
  });

  _fakeTest('an https and a wss URL on one host and port are one origin', (
    FakeAsync async,
  ) {
    final TokenRig rig = TokenRig(
      async,
      auth: FakeAuthProvider(),
      appCheck: FakeAppCheckProvider(),
    );
    final Uri socket = Uri.parse('wss://api.example.test:443/socket');
    final RequestTokens forSocket = rig.ask(url: socket).value;
    expect('${forSocket.origin}', 'https://api.example.test');
    // Tokens fetched for the socket URL may go to the https URL, and the other way round.
    expect(headersOf(forSocket), _both());
    expect(headersOf(rig.ask().value, socket), _both());

    final TokenRig declaredAsSocket = TokenRig(
      async,
      auth: FakeAuthProvider(),
      appCheck: FakeAppCheckProvider(),
      origins: <Uri>[Uri.parse('wss://api.example.test:443')],
    );
    expect(headersOf(declaredAsSocket.ask().value), _both());
  });

  _fakeTest('originChosenByApplication', (FakeAsync async) {
    final FakeAuthProvider auth = FakeAuthProvider();
    final TokenRig rig = TokenRig(
      async,
      auth: auth,
      appCheck: FakeAppCheckProvider(),
    );
    final Uri chosen = Uri.parse('https://elsewhere.example.test/myFunction');
    expect(
      rig.ask(url: chosen).error,
      isTokenFailure(TokenFailure.destinationRefused),
    );
    expect(auth.calls, isEmpty);

    final RequestTokens tokens = rig
        .ask(url: chosen, chosenByApplication: true)
        .value;
    expect('${tokens.origin}', 'https://elsewhere.example.test');
    expect(() => headersOf(tokens), throwsStateError);
    expect(headersOf(tokens, chosen), _both());
  });

  test('reading 1: rule O applies to each origins entry itself', () {
    final FirebaseApp app = newTransportApp();
    const List<String> refused = <String>[
      'https://api.example.test/v1',
      'https://user@api.example.test',
      'https://user:pw@api.example.test',
      'https://api.example.test?x=1',
      'https://api.example.test#fragment',
      'http://api.example.test',
      'ws://api.example.test:80',
      'wss://api.example.test:443/socket',
      'wss://user:pw@api.example.test:443',
      'ftp://api.example.test',
      'https:///',
    ];
    for (final String entry in refused) {
      expect(
        () => TokenSource(app, origins: <Uri>[apiOrigin, Uri.parse(entry)]),
        throwsArgumentError,
        reason: entry,
      );
    }
    const List<String> accepted = <String>[
      'https://api.example.test/',
      'https://API.example.test:8443',
      'wss://api.example.test:443',
      'ws://localhost:9000',
      'http://127.0.0.1:8080',
      'ws://[::1]:9000',
    ];
    for (final String entry in accepted) {
      TokenSource(app, origins: <Uri>[Uri.parse(entry)]);
    }
    TokenSource(app, origins: const <Uri>[]);
  });

  _fakeTest('reading 16: two spellings of one IPv6 address are one origin', (
    FakeAsync async,
  ) {
    final TokenRig rig = TokenRig(
      async,
      auth: FakeAuthProvider(),
      appCheck: FakeAppCheckProvider(),
      origins: <Uri>[Uri.parse('http://[0:0:0:0:0:0:0:1]:9000')],
    );
    final Uri short = Uri.parse('http://[::1]:9000/v1/call');
    final Uri long = Uri.parse('http://[0:0:0:0:0:0:0:1]:9000/v1/call');
    final RequestTokens tokens = rig.ask(url: short).value;
    expect('${tokens.origin}', 'http://[::1]:9000');
    expect(headersOf(tokens, long), _both());
    expect(headersOf(rig.ask(url: long).value, short), _both());
  });

  _fakeTest('reading 8: an emulator owns every spelling of its IPv6 address', (
    FakeAsync async,
  ) {
    final TokenRig rig = TokenRig(
      async,
      auth: FakeAuthProvider(),
      appCheck: FakeAppCheckProvider(),
      origins: const <Uri>[],
      emulator: EmulatorHost('0:0:0:0:0:0:0:1', 9000),
    );
    final Uri url = Uri.parse('http://[::1]:9000/v1/call');
    expect(headersOf(rig.ask(url: url).value, url), _both());
    expect(
      rig.ask(url: Uri.parse('http://[::1]:9001/v1/call')).error,
      isTokenFailure(TokenFailure.destinationRefused),
    );
    expect(rig.warnings, isEmpty);
  });
}

void _requestTokensTests() {
  _fakeTest('headers for another origin throw', (FakeAsync async) {
    final TokenRig rig = TokenRig(
      async,
      auth: FakeAuthProvider(),
      appCheck: FakeAppCheckProvider(),
    );
    final RequestTokens tokens = rig.ask().value;
    final List<Uri> others = <Uri>[
      Uri.parse('https://other.example.test/v1/call'),
      Uri.parse('https://api.example.test:8443/v1/call'),
      Uri.parse('http://api.example.test/v1/call'),
      Uri.parse('wss://api.example.test:8443/socket'),
      Uri.parse('wss://api.example.test/socket'),
      Uri.parse('/v1/call'),
    ];
    for (final Uri other in others) {
      for (final AuthHeaderStyle style in AuthHeaderStyle.values) {
        expect(
          () => tokens.headersFor(other, auth: style),
          throwsStateError,
          reason: '$other',
        );
      }
    }
  });

  _fakeTest('second use throws', (FakeAsync async) {
    final TokenRig rig = TokenRig(
      async,
      auth: FakeAuthProvider(),
      appCheck: FakeAppCheckProvider(),
    );
    final RequestTokens tokens = rig.ask().value;
    expect(headersOf(tokens), _both());
    expect(() => headersOf(tokens), throwsStateError);
    expect(
      () => tokens.headersFor(apiUrl, auth: AuthHeaderStyle.firebase),
      throwsStateError,
    );

    // Tokens without any value are single-use too.
    final RequestTokens none = TokenRig(async).ask().value;
    expect(headersOf(none), isEmpty);
    expect(() => headersOf(none), throwsStateError);
  });

  _fakeTest('reading 11: a refused origin does not spend the single use', (
    FakeAsync async,
  ) {
    final TokenRig rig = TokenRig(
      async,
      auth: FakeAuthProvider(),
      appCheck: FakeAppCheckProvider(),
    );
    final RequestTokens tokens = rig.ask().value;
    expect(
      () => headersOf(tokens, Uri.parse('https://other.example.test/')),
      throwsStateError,
    );
    expect(headersOf(tokens), _both());
  });

  _fakeTest('sameTokensAs after use', (FakeAsync async) {
    final FakeAuthProvider auth = FakeAuthProvider();
    final FakeAppCheckProvider appCheck = FakeAppCheckProvider();
    final TokenRig rig = TokenRig(async, auth: auth, appCheck: appCheck);
    final RequestTokens first = rig.ask().value;
    final RequestTokens second = rig.ask().value;
    expect(first.sameTokensAs(second), isTrue);
    headersOf(first);
    headersOf(second);
    expect(first.sameTokensAs(second), isTrue);
    expect(second.sameTokensAs(first), isTrue);

    auth.answer = (bool _) async => GetTokenResult('FAKE-TOKEN-OF-USER-TWO');
    final RequestTokens otherUser = rig.ask().value;
    expect(first.sameTokensAs(otherUser), isFalse);
    expect(otherUser.sameTokensAs(first), isFalse);

    appCheck.answer = (bool _) async =>
        const AppCheckTokenResult('FAKE-OTHER-APPCHECK');
    final RequestTokens otherAppCheck = rig.ask().value;
    expect(otherUser.sameTokensAs(otherAppCheck), isFalse);

    final TokenRig bare = TokenRig(async);
    expect(bare.ask().value.sameTokensAs(bare.ask().value), isTrue);
    expect(bare.ask().value.sameTokensAs(first), isFalse);
  });

  _fakeTest('each AuthHeaderStyle', (FakeAsync async) {
    final TokenRig rig = TokenRig(
      async,
      auth: FakeAuthProvider(),
      appCheck: FakeAppCheckProvider(),
    );
    Map<String, String> headers(AuthHeaderStyle style) =>
        rig.ask().value.headersFor(apiUrl, auth: style);
    expect(headers(AuthHeaderStyle.bearer), <String, String>{
      'Authorization': 'Bearer $fakeAuthToken',
      'X-Firebase-AppCheck': fakeAppCheckToken,
    });
    expect(headers(AuthHeaderStyle.firebase), <String, String>{
      'Authorization': 'Firebase $fakeAuthToken',
      'X-Firebase-AppCheck': fakeAppCheckToken,
    });
    expect(headers(AuthHeaderStyle.firebaseAuthToken), <String, String>{
      'X-Firebase-Auth-Token': fakeAuthToken,
      'X-Firebase-AppCheck': fakeAppCheckToken,
    });

    // Without an Auth token no style adds an Auth header.
    final TokenRig signedOut = TokenRig(
      async,
      appCheck: FakeAppCheckProvider(),
    );
    for (final AuthHeaderStyle style in AuthHeaderStyle.values) {
      expect(
        signedOut.ask().value.headersFor(apiUrl, auth: style),
        <String, String>{'X-Firebase-AppCheck': fakeAppCheckToken},
      );
    }
  });

  _fakeTest('applyTokens sets the token headers on the request', (
    FakeAsync async,
  ) {
    final TokenRig rig = TokenRig(
      async,
      auth: FakeAuthProvider(),
      appCheck: FakeAppCheckProvider(),
    );
    final http.Request request = http.Request('POST', apiUrl)
      ..headers['Content-Type'] = 'application/json';
    final RequestTokens tokens = rig.ask().value;
    applyTokens(request, tokens, auth: AuthHeaderStyle.firebase);
    expect(request.headers, <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Firebase $fakeAuthToken',
      'X-Firebase-AppCheck': fakeAppCheckToken,
    });
    // The single use is spent.
    expect(() => headersOf(tokens), throwsStateError);

    final http.Request elsewhere = http.Request(
      'POST',
      Uri.parse('https://other.example.test/v1/call'),
    );
    expect(
      () =>
          applyTokens(elsewhere, rig.ask().value, auth: AuthHeaderStyle.bearer),
      throwsStateError,
    );
    expect(elsewhere.headers, isEmpty);
  });

  _fakeTest('reading 20: user info and a finalised request are refused before '
      'the single use is spent', (FakeAsync async) {
    final TokenRig rig = TokenRig(
      async,
      auth: FakeAuthProvider(),
      appCheck: FakeAppCheckProvider(),
    );
    final RequestTokens tokens = rig.ask().value;
    expect(
      () => headersOf(
        tokens,
        Uri.parse('https://user:pw@api.example.test/v1/call'),
      ),
      throwsStateError,
    );
    final http.Request sent = http.Request('GET', apiUrl)..finalize();
    expect(
      () => applyTokens(sent, tokens, auth: AuthHeaderStyle.bearer),
      throwsStateError,
    );
    expect(sent.headers, isEmpty);
    expect(headersOf(tokens), _both());
  });

  _fakeTest('toString shows the origin, presence and outcome only', (
    FakeAsync async,
  ) {
    final TokenRig rig = TokenRig(
      async,
      auth: FakeAuthProvider(),
      appCheck: FakeAppCheckProvider(),
    );
    expect(
      '${rig.ask().value}',
      'RequestTokens(origin: https://api.example.test, auth: present, '
          'appCheck: sent)',
    );
    expect(
      '${TokenRig(async).ask().value}',
      'RequestTokens(origin: https://api.example.test, auth: absent, '
          'appCheck: none)',
    );
    for (final TokenFailure failure in TokenFailure.values) {
      expect(
        '${TokenFetchException(failure, causeType: 'SomeError')}',
        'TokenFetchException: ${failure.name}',
      );
    }
    expect(
      const TokenFetchException(TokenFailure.authTimedOut).causeType,
      isNull,
    );
  });
}

void _limitedUseTests() {
  _fakeTest('limited-use never calls getToken', (FakeAsync async) {
    final FakeLimitedUseProvider minter = FakeLimitedUseProvider();
    final TokenRig rig = TokenRig(
      async,
      auth: FakeAuthProvider(),
      appCheck: minter,
    );
    final RequestTokens tokens = rig.ask(limitedUse: true).value;
    expect(tokens.appCheck, AppCheckOutcome.sent);
    expect(headersOf(tokens), _both(appCheck: fakeLimitedUseToken));
    // Also when a forced session refresh is owed.
    rig.source.invalidate(TokenKind.appCheck);
    rig.ask(limitedUse: true);
    expect(minter.limitedCalls, 2);
    expect(minter.calls, isEmpty);

    // A provider that cannot mint is not asked for its session token instead.
    final FakeAppCheckProvider plain = FakeAppCheckProvider();
    final TokenRig plainRig = TokenRig(async, appCheck: plain);
    final RequestTokens none = plainRig.ask(limitedUse: true).value;
    expect(plain.calls, isEmpty);
    expect(headersOf(none), isEmpty);
  });

  _fakeTest('limited-use failure sends the placeholder', (FakeAsync async) {
    final FakeLimitedUseProvider minter = FakeLimitedUseProvider()
      ..limitedAnswer = () async =>
          AppCheckTokenResult.failure(StateError('the mint failed'));
    final TokenRig rig = TokenRig(
      async,
      auth: FakeAuthProvider(),
      appCheck: minter,
    );
    final RequestTokens tokens = rig.ask(limitedUse: true).value;
    expect(tokens.appCheck, AppCheckOutcome.sentPlaceholder);
    expect(
      headersOf(tokens),
      _both(appCheck: AppCheckTokenResult.placeholderToken),
    );
    expect(minter.calls, isEmpty);
  });

  _fakeTest('unsupported', (FakeAsync async) {
    final FakeAppCheckProvider plain = FakeAppCheckProvider();
    final TokenRig rig = TokenRig(
      async,
      auth: FakeAuthProvider(),
      appCheck: plain,
    );
    final RequestTokens tokens = rig.ask(limitedUse: true).value;
    expect(tokens.appCheck, AppCheckOutcome.unsupported);
    expect(tokens.hasAuthToken, isTrue);
    expect(headersOf(tokens), _authOnly());
    expect(plain.calls, isEmpty);
    expect(async.pendingTimers, isEmpty);
    // The same provider still serves session requests.
    expect(rig.ask().value.appCheck, AppCheckOutcome.sent);
  });
}

void _warningTests() {
  group('every warning row once per key, with its exact text', () {
    _fakeTest('sentPlaceholder: keyed by provider type and error type', (
      FakeAsync async,
    ) {
      final StateError down = StateError('down');
      const FormatException malformed = FormatException('malformed');
      final FakeAppCheckProvider provider = FakeAppCheckProvider.answering(
        (bool _) async => AppCheckTokenResult.failure(down),
      );
      final TokenRig rig = TokenRig(async, appCheck: provider);
      String text(Object provider, Object error) =>
          'App Check: ${_typeOf(provider)} reported ${_typeOf(error)} together '
          'with a token; that token was sent.';
      rig.ask();
      rig.ask();
      expect(rig.warnings, <String>[text(provider, down)]);

      provider.answer = (bool _) async =>
          const AppCheckTokenResult.failure(malformed);
      rig.ask();
      rig.ask();
      expect(rig.warnings, <String>[
        text(provider, down),
        text(provider, malformed),
      ]);

      final OtherAppCheckProvider other = OtherAppCheckProvider()
        ..answer = (bool _) async => AppCheckTokenResult.failure(down);
      rig.app.appCheckProvider = other;
      rig.ask();
      rig.ask();
      expect(rig.warnings, hasLength(3));
      expect(rig.warnings.last, text(other, down));
    });

    _fakeTest('empty: keyed by provider type', (FakeAsync async) {
      final FakeAppCheckProvider provider = FakeAppCheckProvider('');
      final TokenRig rig = TokenRig(async, appCheck: provider);
      String text(Object provider) =>
          'App Check: ${_typeOf(provider)} gave no usable token; $_sentWithout';
      rig.ask();
      provider.answer = (bool _) async =>
          const AppCheckTokenResult('not token text');
      rig.ask();
      expect(rig.warnings, <String>[text(provider)]);

      final OtherAppCheckProvider other = OtherAppCheckProvider('');
      rig.app.appCheckProvider = other;
      rig.ask();
      rig.ask();
      expect(rig.warnings, <String>[text(provider), text(other)]);

      // Once per TokenSource: another source of the same app logs it again.
      final List<String> second = <String>[];
      final TokenSource another = TokenSource(
        rig.app,
        origins: <Uri>[apiOrigin],
        onWarning: second.add,
        elapsed: () => async.elapsed,
      );
      Probe<RequestTokens>(another.tokensFor(apiUrl));
      async.flushMicrotasks();
      expect(second, <String>[text(other)]);
    });

    _fakeTest('providerFailed: keyed by provider type and error type', (
      FakeAsync async,
    ) {
      final StateError broken = StateError('broken');
      const FormatException malformed = FormatException('malformed');
      final FakeAppCheckProvider provider = FakeAppCheckProvider.answering(
        (bool _) async => throw broken,
      );
      final TokenRig rig = TokenRig(async, appCheck: provider);
      String text(Object provider, Object error) =>
          'App Check: ${_typeOf(provider)} threw ${_typeOf(error)}; '
          '$_sentWithout';
      rig.ask();
      rig.ask();
      expect(rig.warnings, <String>[text(provider, broken)]);

      provider.answer = (bool _) async => throw malformed;
      rig.ask();
      rig.ask();
      expect(rig.warnings, <String>[
        text(provider, broken),
        text(provider, malformed),
      ]);

      final OtherAppCheckProvider other = OtherAppCheckProvider()
        ..answer = (bool _) async => throw broken;
      rig.app.appCheckProvider = other;
      rig.ask();
      expect(rig.warnings, hasLength(3));
      expect(rig.warnings.last, text(other, broken));
    });

    _fakeTest('timedOut: keyed by provider type; skipped is not logged', (
      FakeAsync async,
    ) {
      final FakeAppCheckProvider provider = FakeAppCheckProvider()..holdCalls();
      final TokenRig rig = TokenRig(async, appCheck: provider);
      // Reading 15: the text always says 10 s, also when the request had less or more time left.
      String text(Object provider) =>
          'App Check: ${_typeOf(provider)} did not answer in 10 s; '
          '$_sentWithout';
      rig.ask(timeLeft: const Duration(seconds: 45));
      async.elapse(TokenSource.providerWait);
      expect(rig.warnings, <String>[text(provider)]);
      expect(rig.ask().value.appCheck, AppCheckOutcome.skipped);
      expect(rig.warnings, hasLength(1));

      // The same provider times out again after the pause: the same key, no second line.
      async.elapse(TokenSource.stuckProviderPause);
      final Probe<RequestTokens> again = rig.ask();
      async.elapse(TokenSource.providerWait);
      expect(again.value.appCheck, AppCheckOutcome.timedOut);
      expect(rig.warnings, hasLength(1));

      final OtherAppCheckProvider other = OtherAppCheckProvider()..holdCalls();
      rig.app.appCheckProvider = other;
      async.elapse(TokenSource.stuckProviderPause);
      rig.ask();
      async.elapse(TokenSource.providerWait);
      expect(rig.warnings, <String>[text(provider), text(other)]);
    });

    _fakeTest('unsupported: keyed by provider type', (FakeAsync async) {
      final FakeAppCheckProvider provider = FakeAppCheckProvider();
      final TokenRig rig = TokenRig(async, appCheck: provider);
      String text(Object provider) =>
          'App Check: ${_typeOf(provider)} cannot mint limited-use tokens; '
          '$_sentWithout';
      rig.ask(limitedUse: true);
      rig.ask(limitedUse: true);
      expect(rig.warnings, <String>[text(provider)]);

      final OtherAppCheckProvider other = OtherAppCheckProvider();
      rig.app.appCheckProvider = other;
      rig.ask(limitedUse: true);
      rig.ask(limitedUse: true);
      expect(rig.warnings, <String>[text(provider), text(other)]);
    });

    _fakeTest('sent and none are not logged', (FakeAsync async) {
      final TokenRig rig = TokenRig(
        async,
        auth: FakeAuthProvider(),
        appCheck: FakeLimitedUseProvider(),
      );
      rig.ask();
      rig.ask(limitedUse: true);
      rig.app.appCheckProvider = null;
      rig.ask();
      expect(rig.warnings, isEmpty);
    });
  });

  _fakeTest('no warning without a sink', (FakeAsync async) {
    // Nothing falls back to print when the application gave no logger.
    final List<String> printed = <String>[];
    runZoned(
      () => _everyWarningWithoutSink(async),
      zoneSpecification: ZoneSpecification(
        print: (Zone _, ZoneDelegate _, Zone _, String line) {
          printed.add(line);
        },
      ),
    );
    expect(printed, isEmpty);
  });

  _fakeTest('remote emulator warns once', (FakeAsync async) {
    final TokenRig rig = TokenRig(
      async,
      auth: FakeAuthProvider(),
      appCheck: FakeAppCheckProvider(),
      origins: const <Uri>[],
      emulator: EmulatorHost('10.0.2.2', 9099),
    );
    final Uri url = Uri.parse('http://10.0.2.2:9099/v1/call');
    final RequestTokens tokens = rig.ask(url: url).value;
    rig.ask(url: url);
    rig.ask(url: Uri.parse('ws://10.0.2.2:9099/socket'));
    expect(rig.warnings, <String>[
      'Tokens are sent in clear text to the emulator host, which is not this '
          'machine.',
    ]);
    expect(headersOf(tokens, url), _both());

    // An emulator on this machine is not warned about.
    final TokenRig local = TokenRig(
      async,
      auth: FakeAuthProvider(),
      origins: const <Uri>[],
      emulator: EmulatorHost('localhost', 9099),
    );
    local.ask(url: Uri.parse('http://localhost:9099/v1/call'));
    expect(local.warnings, isEmpty);
  });

  _fakeTest('reading 6: the remote-emulator warning needs a token for that '
      'request', (FakeAsync async) {
    final TokenRig rig = TokenRig(
      async,
      origins: <Uri>[apiOrigin],
      emulator: EmulatorHost('10.0.2.2', 9099),
    );
    final Uri url = Uri.parse('http://10.0.2.2:9099/v1/call');
    expect(headersOf(rig.ask(url: url).value, url), isEmpty);
    expect(rig.warnings, isEmpty);

    // A request to another host with tokens does not warn either.
    rig.app.appCheckProvider = FakeAppCheckProvider();
    rig.ask();
    expect(rig.warnings, isEmpty);

    // An App Check token alone is a token.
    rig.ask(url: url);
    expect(rig.warnings, hasLength(1));
  });

  _fakeTest('reading 18: the App Check warning is logged also when Auth fails '
      'the call', (FakeAsync async) {
    final FakeAppCheckProvider appCheck = FakeAppCheckProvider('');
    final TokenRig rig = TokenRig(
      async,
      auth: FakeAuthProvider.answering(
        (bool _) async => throw StateError('token server said no'),
      ),
      appCheck: appCheck,
    );
    expect(rig.ask().error, isTokenFailure(TokenFailure.authProviderFailed));
    expect(rig.warnings, <String>[
      'App Check: ${_typeOf(appCheck)} gave no usable token; $_sentWithout',
    ]);
  });
}

/// Drives every outcome that warns, and the clear-text emulator, on a source without a sink.
void _everyWarningWithoutSink(FakeAsync async) {
  final EmulatorHost remote = EmulatorHost('10.0.2.2', 9099);
  final FakeAppCheckProvider provider = FakeAppCheckProvider.answering(
    (bool _) async => AppCheckTokenResult.failure(StateError('down')),
  );
  final TokenRig rig = TokenRig(
    async,
    auth: FakeAuthProvider(),
    appCheck: provider,
    emulator: remote,
    sink: false,
  );
  final Uri emulatorUrl = Uri.parse('http://10.0.2.2:9099/v1/call');
  // Behaviour is the same as with a sink, and nothing throws for the lack of one: every
  // outcome that warns, and the clear-text emulator.
  expect(
    rig.ask(url: emulatorUrl).value.appCheck,
    AppCheckOutcome.sentPlaceholder,
  );
  expect(rig.ask(limitedUse: true).value.appCheck, AppCheckOutcome.unsupported);
  provider.answer = (bool _) async => const AppCheckTokenResult('');
  expect(rig.ask().value.appCheck, AppCheckOutcome.empty);
  provider.answer = (bool _) async => throw StateError('broken');
  expect(rig.ask().value.appCheck, AppCheckOutcome.providerFailed);
  provider.holdCalls();
  final Probe<RequestTokens> slow = rig.ask();
  async.elapse(TokenSource.providerWait);
  expect(slow.value.appCheck, AppCheckOutcome.timedOut);
  expect(rig.ask().value.appCheck, AppCheckOutcome.skipped);
}

/// Cases asked for by test review 1, part 2.
void _reviewTests() {
  _fakeTest('reading 22: the sentPlaceholder warning is logged also when Auth '
      'fails the call', (FakeAsync async) {
    final StateError down = StateError('down');
    final FakeAppCheckProvider appCheck = FakeAppCheckProvider.answering(
      (bool _) async => AppCheckTokenResult.failure(down),
    );
    final TokenRig rig = TokenRig(
      async,
      auth: FakeAuthProvider.answering(
        (bool _) async => throw StateError('token server said no'),
      ),
      appCheck: appCheck,
    );
    expect(rig.ask().error, isTokenFailure(TokenFailure.authProviderFailed));
    expect(rig.warnings, <String>[
      'App Check: ${_typeOf(appCheck)} reported ${_typeOf(down)} together with '
          'a token; that token was sent.',
    ]);
  });

  for (final bool limited in <bool>[false, true]) {
    final String kind = limited ? 'limited-use' : 'session';
    _fakeTest('an App Check result with an error and a token that is not token '
        'text gives empty ($kind)', (FakeAsync async) {
      for (final String bad in <String>['has space', 'line\nbreak', '']) {
        final FakeLimitedUseProvider appCheck = _giving(
          AppCheckTokenResult(bad, error: StateError('refresh failed')),
        );
        final TokenRig rig = TokenRig(
          async,
          auth: FakeAuthProvider(),
          appCheck: appCheck,
        );
        final RequestTokens tokens = rig.ask(limitedUse: limited).value;
        expect(tokens.appCheck, AppCheckOutcome.empty, reason: '"$bad"');
        expect(headersOf(tokens), _authOnly(), reason: '"$bad"');
        expect(rig.warnings, <String>[
          'App Check: ${_typeOf(appCheck)} gave no usable token; $_sentWithout',
        ]);
      }
    });
  }

  _fakeTest('a limited-use call that times out starts the pause', (
    FakeAsync async,
  ) {
    final FakeLimitedUseProvider appCheck = FakeLimitedUseProvider()
      ..holdLimitedCalls();
    final TokenRig rig = TokenRig(async, appCheck: appCheck);
    final Probe<RequestTokens> first = rig.ask(limitedUse: true);
    async.elapse(TokenSource.providerWait - _tick);
    expect(first.isDone, isFalse);
    async.elapse(_tick);
    expect(first.value.appCheck, AppCheckOutcome.timedOut);

    // The pause covers session and limited-use requests alike.
    expect(rig.ask(limitedUse: true).value.appCheck, AppCheckOutcome.skipped);
    expect(rig.ask().value.appCheck, AppCheckOutcome.skipped);
    async.elapse(TokenSource.stuckProviderPause - _tick);
    expect(rig.ask(limitedUse: true).value.appCheck, AppCheckOutcome.skipped);
    expect(appCheck.limitedCalls, 1);
    expect(appCheck.calls, isEmpty);

    async.elapse(_tick);
    final Probe<RequestTokens> probe = rig.ask(limitedUse: true);
    expect(appCheck.limitedCalls, 2);
    appCheck.limitedWaiting.last.complete(
      const AppCheckTokenResult(fakeLimitedUseToken),
    );
    async.flushMicrotasks();
    expect(probe.value.appCheck, AppCheckOutcome.sent);
    // The answer ended the pause.
    expect(rig.ask().value.appCheck, AppCheckOutcome.sent);
  });

  _fakeTest('two sources of one app keep their own pause and their own forced '
      'refresh guard', (FakeAsync async) {
    final FakeAuthProvider auth = FakeAuthProvider();
    final FakeAppCheckProvider appCheck = FakeAppCheckProvider()..holdCalls();
    final TokenRig rig = TokenRig(async, auth: auth, appCheck: appCheck);
    final TokenSource other = TokenSource(
      rig.app,
      origins: <Uri>[apiOrigin],
      elapsed: () => async.elapsed,
    );
    Probe<RequestTokens> askOther() {
      final Probe<RequestTokens> probe = Probe<RequestTokens>(
        other.tokensFor(apiUrl),
      );
      async.flushMicrotasks();
      return probe;
    }

    final Probe<RequestTokens> stuck = rig.ask();
    async.elapse(TokenSource.providerWait);
    expect(stuck.value.appCheck, AppCheckOutcome.timedOut);
    expect(rig.ask().value.appCheck, AppCheckOutcome.skipped);
    expect(appCheck.calls, hasLength(1));
    // The other source is not paused: it asks the provider itself.
    final Probe<RequestTokens> fromOther = askOther();
    expect(appCheck.calls, hasLength(2));
    appCheck.waiting.last.complete(
      const AppCheckTokenResult(fakeAppCheckToken),
    );
    async.flushMicrotasks();
    expect(fromOther.value.appCheck, AppCheckOutcome.sent);

    // Each source may force one Auth refresh within the same minute.
    auth.calls.clear();
    rig.source.invalidate(TokenKind.auth);
    other.invalidate(TokenKind.auth);
    rig.ask();
    askOther();
    expect(auth.calls, <bool>[true, true]);
    rig.source.invalidate(TokenKind.auth);
    rig.ask();
    expect(auth.calls.last, isFalse);
  });
}
