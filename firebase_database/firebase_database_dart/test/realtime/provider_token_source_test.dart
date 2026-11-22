// ProviderTokenSource (auth_session.dart): which provider failures mean "no token" and which are
// errors of the fetch (rtdb_protocol.md 8.1; threat model T8). The success paths and the forced
// refresh limit are in auth_session_test.dart; the hiding of the provider's message in
// test/security/k_leakage_test.dart.

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/src/realtime/auth_session.dart';
import 'package:test/test.dart';

import '../util/fakes.dart';

ProviderTokenSource _source({
  AuthTokenProvider? auth,
  AppCheckTokenProvider? appCheck,
}) => ProviderTokenSource(
  auth: auth,
  appCheck: appCheck,
  forcedRefreshMinInterval: const Duration(seconds: 60),
  now: () => DateTime.utc(2026, 11, 23),
);

Matcher _failedWith(String message) => throwsA(
  isA<StateError>().having((StateError e) => e.message, 'message', message),
);

void main() {
  test(
    'an App Check provider that is not available gives null, forced or not',
    () async {
      // An app without App Check must still connect: the fetch may not fail.
      final FakeAppCheck appCheck = FakeAppCheck(
        'ac-1',
        error: const FirebaseApiNotAvailableException('no App Check'),
      );
      final ProviderTokenSource tokens = _source(appCheck: appCheck);

      expect(await tokens.appCheckToken(forceRefresh: false), isNull);
      expect(await tokens.appCheckToken(forceRefresh: true), isNull);
      expect(appCheck.calls, <bool>[false, true]);
    },
  );

  test(
    'an unavailable App Check provider leaves the auth token alone',
    () async {
      final ProviderTokenSource tokens = _source(
        auth: FakeAuth(<String?>['id-1']),
        appCheck: FakeAppCheck(
          'ac-1',
          error: const FirebaseApiNotAvailableException('none'),
        ),
      );

      expect(await tokens.appCheckToken(forceRefresh: false), isNull);
      expect(await tokens.authToken(forceRefresh: false), 'id-1');
    },
  );

  test(
    '"nobody signed in" from the App Check provider is a failure, not null',
    () async {
      // Only the auth provider may report a missing user as "no token".
      final ProviderTokenSource tokens = _source(
        appCheck: FakeAppCheck(
          'ac-1',
          error: const FirebaseNoSignedInUserException('x'),
        ),
      );

      await expectLater(
        tokens.appCheckToken(forceRefresh: false),
        _failedWith('The App Check token provider failed.'),
      );
    },
  );

  test('other failures name the provider that failed', () async {
    final ProviderTokenSource tokens = _source(
      auth: FakeAuth(<String?>['id-1'], error: StateError('auth down')),
      appCheck: FakeAppCheck('ac-1', error: Exception('attestation down')),
    );

    await expectLater(
      tokens.authToken(forceRefresh: false),
      _failedWith('The auth token provider failed.'),
    );
    await expectLater(
      tokens.appCheckToken(forceRefresh: true),
      _failedWith('The App Check token provider failed.'),
    );
  });

  test('a failed fetch does not stop the next one from succeeding', () async {
    final _FlakyAppCheck appCheck = _FlakyAppCheck();
    final ProviderTokenSource tokens = _source(appCheck: appCheck);

    await expectLater(
      tokens.appCheckToken(forceRefresh: false),
      _failedWith('The App Check token provider failed.'),
    );
    expect(await tokens.appCheckToken(forceRefresh: false), 'ac-2');
  });
}

/// An App Check provider whose first call fails and whose later calls give `ac-2`.
final class _FlakyAppCheck extends AppCheckTokenProvider {
  int _calls = 0;

  @override
  Future<AppCheckTokenResult> getToken({required bool forceRefresh}) async {
    _calls++;
    if (_calls == 1) {
      throw StateError('first call fails');
    }
    return const AppCheckTokenResult('ac-2');
  }

  @override
  Stream<AppCheckTokenResult> get onTokenChanged =>
      const Stream<AppCheckTokenResult>.empty();
}
