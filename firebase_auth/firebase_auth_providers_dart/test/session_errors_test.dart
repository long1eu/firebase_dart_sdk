// When an error of the backend ends the session, and how token lifetimes from the backend are bounded.

import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'fakes.dart';
import 'harness.dart';

String _encode(Object json) =>
    base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

/// An ID token without an `exp` claim, so that its expiry comes from `expiresIn`.
String idTokenWithoutExp(String uid) =>
    '${_encode(<String, Object?>{'alg': 'none', 'typ': 'JWT'})}.'
    '${_encode(<String, Object?>{
      'user_id': uid,
      'sub': uid,
      'firebase': <String, Object?>{'sign_in_provider': 'anonymous'},
    })}.';

void main() {
  late FakeBackend backend;
  late FirebaseUserAuth auth;

  setUp(() {
    backend = FakeBackend();
    auth = backend.create();
  });

  tearDown(() => auth.dispose());

  int countOf(String method) =>
      backend.methods.where((String m) => m == method).length;

  group('invalidatesSession', () {
    test('needs HTTP 400', () {
      for (final String message in <String>[
        'TOKEN_EXPIRED',
        'USER_DISABLED',
        'USER_NOT_FOUND',
        'INVALID_REFRESH_TOKEN',
      ]) {
        expect(
          FirebaseAuthException.fromServer(
            message,
            httpStatus: 400,
          ).invalidatesSession,
          isTrue,
          reason: message,
        );
        for (final int? status in <int?>[null, 200, 401, 500, 503]) {
          expect(
            FirebaseAuthException.fromServer(
              message,
              httpStatus: status,
            ).invalidatesSession,
            isFalse,
            reason: '$message $status',
          );
        }
      }
    });
  });

  group('token refresh', () {
    test('a 5xx with TOKEN_EXPIRED keeps the session', () async {
      await auth.signInAnonymously();
      backend.on('token', (_) => errorResponse('TOKEN_EXPIRED', 503));
      await expectLater(
        auth.getAccessToken(forceRefresh: true),
        throwsAuth('user-token-expired'),
      );
      expect(auth.uid, 'anon-user');
      expect(
        backend.storage.read('firebase_auth_providers_dart:$apiKey'),
        isNotNull,
      );
    });

    test('a 400 with TOKEN_EXPIRED ends the session', () async {
      await auth.signInAnonymously();
      backend.on('token', (_) => errorResponse('TOKEN_EXPIRED'));
      await expectLater(
        auth.getAccessToken(forceRefresh: true),
        throwsAuth('user-token-expired'),
      );
      expect(auth.uid, isNull);
      expect(
        backend.storage.read('firebase_auth_providers_dart:$apiKey'),
        isNull,
      );
    });

    test(
      'a 5xx that is not JSON is an internal error and keeps the session',
      () async {
        await auth.signInAnonymously();
        backend.on(
          'token',
          (_) => http.Response('<html>Unavailable</html>', 503),
        );
        await expectLater(
          auth.getAccessToken(forceRefresh: true),
          throwsA(
            isA<FirebaseAuthException>()
                .having(
                  (FirebaseAuthException e) => e.code,
                  'code',
                  'internal-error',
                )
                .having(
                  (FirebaseAuthException e) => e.httpStatus,
                  'httpStatus',
                  503,
                ),
          ),
        );
        expect(auth.uid, 'anon-user');
      },
    );

    test(
      'the proactive refresh retries after a 5xx with USER_DISABLED',
      () async {
        final StreamSubscription<AuthTokenChange> sub = auth.onTokenChanged
            .listen((_) {});
        addTearDown(sub.cancel);
        await auth.signInAnonymously();
        backend.on('token', (_) => errorResponse('USER_DISABLED', 500));
        backend.clock.advance(const Duration(minutes: 55));
        backend.timers.active.single.fire();
        await pump();
        expect(auth.uid, 'anon-user');
        expect(backend.timers.active.single.delay, const Duration(seconds: 30));
      },
    );
  });

  group('a request with the ID token', () {
    test(
      'a 5xx with TOKEN_EXPIRED keeps the session and does not refresh',
      () async {
        await auth.signInAnonymously();
        backend.on(
          'accounts:lookup',
          (_) => errorResponse('TOKEN_EXPIRED', 503),
        );
        await expectLater(auth.reload(), throwsAuth('user-token-expired'));
        expect(auth.uid, 'anon-user');
        expect(countOf('token'), 0);
      },
    );

    test('a 5xx with USER_DISABLED keeps the session', () async {
      await auth.signInAnonymously();
      backend.on('accounts:lookup', (_) => errorResponse('USER_DISABLED', 500));
      await expectLater(auth.reload(), throwsAuth('user-disabled'));
      expect(auth.uid, 'anon-user');
    });

    test('a 400 with USER_DISABLED signs out without a refresh', () async {
      await auth.signInAnonymously();
      backend.on('accounts:lookup', (_) => errorResponse('USER_DISABLED'));
      await expectLater(auth.reload(), throwsAuth('user-disabled'));
      expect(auth.uid, isNull);
      expect(countOf('token'), 0);
    });

    test(
      'a 5xx that is not JSON is an internal error and keeps the session',
      () async {
        await auth.signInAnonymously();
        backend.on('accounts:lookup', (_) => http.Response('Bad gateway', 502));
        await expectLater(auth.reload(), throwsAuth('internal-error'));
        expect(auth.uid, 'anon-user');
        expect(countOf('token'), 0);
      },
    );

    for (final (String message, String code) in <(String, String)>[
      ('TOKEN_EXPIRED', 'user-token-expired'),
      ('INVALID_ID_TOKEN', 'invalid-user-token'),
    ]) {
      test(
        'a 400 with $message refreshes once and retries the request',
        () async {
          await auth.signInAnonymously();
          backend.requests.clear();
          int lookups = 0;
          backend.on('accounts:lookup', (Map<String, Object?> body) {
            lookups++;
            if (lookups == 1) {
              return errorResponse(message);
            }
            return jsonResponse(<String, Object?>{
              'users': <Object?>[
                <String, Object?>{'localId': 'anon-user', 'displayName': 'Ada'},
              ],
            });
          });
          await auth.reload();
          expect(backend.methods, <String>[
            'accounts:lookup',
            'token',
            'accounts:lookup',
          ]);
          final List<Map<String, Object?>> bodies = backend.bodiesOf(
            'accounts:lookup',
          );
          expect(bodies[1]['idToken'], isNot(bodies[0]['idToken']));
          expect(auth.uid, 'anon-user');
          expect(auth.currentUser?.displayName, 'Ada');
        },
      );

      test(
        'a 400 with $message signs out when the refresh says the session ended',
        () async {
          await auth.signInAnonymously();
          backend.requests.clear();
          backend.on('accounts:lookup', (_) => errorResponse(message));
          backend.on('token', (_) => errorResponse('TOKEN_EXPIRED'));
          await expectLater(auth.reload(), throwsAuth(code));
          expect(backend.methods, <String>['accounts:lookup', 'token']);
          expect(auth.uid, isNull);
        },
      );

      test(
        'a 400 with $message keeps the session when the refresh fails otherwise',
        () async {
          await auth.signInAnonymously();
          backend.requests.clear();
          backend.on('accounts:lookup', (_) => errorResponse(message));
          backend.on('token', (_) => errorResponse('TOKEN_EXPIRED', 503));
          await expectLater(auth.reload(), throwsAuth(code));
          expect(backend.methods, <String>['accounts:lookup', 'token']);
          expect(auth.uid, 'anon-user');
        },
      );
    }

    test(
      'a token refreshed while the request was in flight is not refreshed again',
      () async {
        await auth.signInAnonymously();
        backend.requests.clear();
        backend.on('accounts:lookup', (_) async {
          await auth.getAccessToken(forceRefresh: true);
          return errorResponse('TOKEN_EXPIRED');
        });
        await expectLater(auth.reload(), throwsAuth('user-token-expired'));
        expect(backend.methods, <String>['accounts:lookup', 'token']);
        expect(auth.uid, 'anon-user');
      },
    );

    test('a network error of the refresh keeps the session', () async {
      await auth.signInAnonymously();
      backend.on('accounts:lookup', (_) => errorResponse('TOKEN_EXPIRED'));
      backend.on('token', (_) => throw http.ClientException('offline'));
      await expectLater(auth.reload(), throwsAuth('user-token-expired'));
      expect(auth.uid, 'anon-user');
    });

    test(
      'a request rejected again after the refresh is not retried twice',
      () async {
        await auth.signInAnonymously();
        backend.requests.clear();
        backend.on('accounts:lookup', (_) => errorResponse('TOKEN_EXPIRED'));
        await expectLater(auth.reload(), throwsAuth('user-token-expired'));
        expect(backend.methods, <String>[
          'accounts:lookup',
          'token',
          'accounts:lookup',
        ]);
        // The refresh said that the session is valid.
        expect(auth.uid, 'anon-user');
      },
    );
  });

  group('token lifetime', () {
    /// Signs in anonymously with an ID token without `exp` and [expiresIn], and returns the delay of the
    /// proactive refresh.
    Future<Duration> refreshDelayFor(Object? expiresIn, {String? token}) async {
      final StreamSubscription<AuthTokenChange> sub = auth.onTokenChanged
          .listen((_) {});
      addTearDown(sub.cancel);
      backend.on(
        'accounts:signUp',
        (_) => jsonResponse(<String, Object?>{
          'localId': 'anon-user',
          'idToken': token ?? idTokenWithoutExp('anon-user'),
          'refreshToken': 'refresh:anon-user',
          'expiresIn': ?expiresIn,
        }),
      );
      await auth.signInAnonymously();
      return backend.timers.active.single.delay;
    }

    const Duration standard = Duration(minutes: 55);

    for (final Object? expiresIn in <Object?>[
      '0',
      '-60',
      null,
      'garbage',
      '',
      'NaN',
      'Infinity',
      '86401',
      '1e12',
    ]) {
      test('expiresIn $expiresIn is one hour', () async {
        expect(await refreshDelayFor(expiresIn), standard);
      });
    }

    test('expiresIn within (0, 24 h] is used', () async {
      expect(await refreshDelayFor('1800'), const Duration(minutes: 25));
    });

    test('expiresIn of exactly 24 h is used', () async {
      expect(
        await refreshDelayFor(86400),
        const Duration(hours: 23, minutes: 55),
      );
    });

    test('an exp claim more than 24 h ahead falls back to expiresIn', () async {
      final String farToken = idToken(
        'anon-user',
        expires: backend.clock.now.add(const Duration(hours: 48)),
        provider: 'anonymous',
      );
      expect(await refreshDelayFor('garbage', token: farToken), standard);
    });

    test('a refresh delay beyond 24 h refreshes right away', () async {
      await auth.signInAnonymously();
      // The clock went back two days after the sign-in.
      backend.clock.advance(const Duration(hours: -48));
      final StreamSubscription<AuthTokenChange> sub = auth.onTokenChanged
          .listen((_) {});
      addTearDown(sub.cancel);
      expect(backend.timers.active.single.delay, Duration.zero);
    });

    test('the expires_in of a refresh is bounded too', () async {
      final StreamSubscription<AuthTokenChange> sub = auth.onTokenChanged
          .listen((_) {});
      addTearDown(sub.cancel);
      await auth.signInAnonymously();
      backend.on(
        'token',
        (_) => jsonResponse(<String, Object?>{
          'id_token': idTokenWithoutExp('anon-user'),
          'refresh_token': 'refresh:anon-user',
          'expires_in': '99999999999',
        }),
      );
      await auth.getAccessToken(forceRefresh: true);
      expect(backend.timers.active.single.delay, standard);
    });
  });
}
