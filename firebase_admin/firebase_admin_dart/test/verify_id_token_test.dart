// verifyIdToken: tokens signed in the test by a key whose certificate a fake of Google's key endpoint serves.

import 'package:firebase_admin_dart/auth.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'fake_backend.dart';
import 'rsa_test.dart' show vectorCertificate, vectorToken;
import 'support.dart';

Matcher throwsAdmin(String code, [Object? message]) => throwsA(
  isA<FirebaseAuthAdminException>()
      .having((FirebaseAuthAdminException e) => e.code, 'code', code)
      .having(
        (FirebaseAuthAdminException e) => e.message,
        'message',
        message ?? anything,
      ),
);

void main() {
  final TestKey key = TestKey();
  final TestKey other = TestKey();
  late FakeBackend backend;
  late FakeClock clock;
  late Map<String, String> certificates;
  late String cacheControl;
  late FirebaseAdminApp app;

  setUp(() {
    backend = FakeBackend();
    clock = FakeClock(DateTime.utc(2026, 11, 16, 12));
    certificates = <String, String>{'kid-1': key.certificatePem};
    cacheControl = 'public, max-age=3600, must-revalidate, no-transform';
    backend.on(
      'www.googleapis.com',
      '/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com',
      (http.Request request) async => FakeBackend.json(
        certificates,
        200,
        <String, String>{'cache-control': cacheControl},
      ),
    );
    app = FirebaseAdminApp(
      projectId: 'demo-test',
      credential: AdminCredential.serviceAccount(key.serviceAccount()),
      httpClient: backend.client,
      clock: clock.call,
    );
  });

  String token({
    Map<String, Object?> extra = const <String, Object?>{},
    Map<String, Object?>? header,
    TestKey? signer,
    bool unsigned = false,
    DateTime? at,
  }) => jwt(
    header ?? <String, Object?>{'alg': 'RS256', 'kid': 'kid-1', 'typ': 'JWT'},
    <String, Object?>{...idTokenClaims(at ?? clock.now), ...extra},
    unsigned ? null : (signer ?? key),
  );

  test('accepts a correctly signed token and returns its claims', () async {
    final VerifiedIdToken verified = await app.auth().verifyIdToken(
      token(
        extra: <String, Object?>{'role': 'tester', 'email': 'a@example.com'},
      ),
    );
    expect(verified.uid, 'user-1');
    expect(verified.claims['role'], 'tester');
    expect(verified.email, 'a@example.com');
    expect(verified.signInProvider, 'custom');
    expect(verified.issuedAt, clock.now);
    expect(verified.expiresAt, clock.now.add(const Duration(hours: 1)));
    expect(verified.authTime, clock.now);
    expect(verified.tenantId, isNull);
  });

  test(
    'the known vector verifies with its certificate (signed by openssl)',
    () async {
      certificates = <String, String>{'vector-kid': vectorCertificate};
      clock.now = DateTime.fromMillisecondsSinceEpoch(
        1790000100 * 1000,
        isUtc: true,
      );
      expect((await app.auth().verifyIdToken(vectorToken)).uid, 'vector-user');
    },
  );

  test('rejects wrong aud, iss, sub', () async {
    final FirebaseAuthAdmin auth = app.auth();
    await expectLater(
      auth.verifyIdToken(
        token(extra: <String, Object?>{'aud': 'other-project'}),
      ),
      throwsAdmin('argument-error', contains('audience')),
    );
    await expectLater(
      auth.verifyIdToken(
        token(
          extra: <String, Object?>{
            'iss': 'https://securetoken.google.com/other',
          },
        ),
      ),
      throwsAdmin('argument-error', contains('issuer')),
    );
    await expectLater(
      auth.verifyIdToken(token(extra: <String, Object?>{'sub': ''})),
      throwsAdmin('argument-error', contains('subject')),
    );
    await expectLater(
      auth.verifyIdToken(token(extra: <String, Object?>{'sub': 'x' * 129})),
      throwsAdmin('argument-error', contains('subject')),
    );
  });

  test('expiry, future iat and auth_time, with the clock skew', () async {
    final FirebaseAuthAdmin auth = app.auth();
    final String fresh = token();
    clock.advance(const Duration(hours: 1, seconds: 9));
    expect(
      (await auth.verifyIdToken(fresh)).uid,
      'user-1',
      reason: 'within the default skew of 10 s',
    );
    clock.advance(const Duration(seconds: 1));
    await expectLater(
      auth.verifyIdToken(fresh),
      throwsAdmin('id-token-expired'),
    );
    await expectLater(
      auth.verifyIdToken(fresh, clockSkew: const Duration(minutes: 1)),
      completes,
    );

    final String future = token(at: clock.now.add(const Duration(seconds: 30)));
    await expectLater(
      auth.verifyIdToken(future),
      throwsAdmin('argument-error', contains('future')),
    );
    expect(
      (await auth.verifyIdToken(
        future,
        clockSkew: const Duration(minutes: 1),
      )).uid,
      'user-1',
    );

    final int later =
        clock.now.add(const Duration(minutes: 2)).millisecondsSinceEpoch ~/
        1000;
    await expectLater(
      auth.verifyIdToken(token(extra: <String, Object?>{'auth_time': later})),
      throwsAdmin('argument-error', contains('auth_time')),
    );
    await expectLater(
      auth.verifyIdToken(token(extra: <String, Object?>{'auth_time': null})),
      throwsAdmin('argument-error'),
    );
    expect(
      () => auth.verifyIdToken(fresh, clockSkew: const Duration(minutes: 6)),
      throwsArgumentError,
    );
    expect(
      () => auth.verifyIdToken(fresh, clockSkew: const Duration(seconds: -1)),
      throwsArgumentError,
    );
  });

  test(
    'rejects a bad signature, unsigned tokens, other algorithms, unknown or missing kid',
    () async {
      final FirebaseAuthAdmin auth = app.auth();
      await expectLater(
        auth.verifyIdToken(token(signer: other)),
        throwsAdmin('argument-error', contains('signature')),
      );
      final List<String> parts = token().split('.');
      final String tampered =
          '${parts[0]}.${segment(<String, Object?>{...idTokenClaims(clock.now), 'role': 'admin'})}.${parts[2]}';
      await expectLater(
        auth.verifyIdToken(tampered),
        throwsAdmin('argument-error', contains('signature')),
      );
      await expectLater(
        auth.verifyIdToken(
          token(
            header: <String, Object?>{'alg': 'none', 'typ': 'JWT'},
            unsigned: true,
          ),
        ),
        throwsAdmin('argument-error', contains('unsigned')),
      );
      await expectLater(
        auth.verifyIdToken(
          token(header: <String, Object?>{'alg': 'HS256', 'kid': 'kid-1'}),
        ),
        throwsAdmin('argument-error', contains('RS256')),
      );
      await expectLater(
        auth.verifyIdToken(
          token(header: <String, Object?>{'alg': 'RS256', 'kid': 'kid-2'}),
        ),
        throwsAdmin('argument-error', contains('kid')),
      );
      await expectLater(
        auth.verifyIdToken(token(header: <String, Object?>{'alg': 'RS256'})),
        throwsAdmin('argument-error', contains('kid')),
      );
      for (final String bad in <String>[
        '',
        'a.b',
        'a.b.c.d',
        '${parts[0]}.${parts[1]}+.${parts[2]}',
        '${parts[0]}=.${parts[1]}.${parts[2]}',
      ]) {
        await expectLater(
          auth.verifyIdToken(bad),
          throwsAdmin('argument-error'),
          reason: bad,
        );
      }
    },
  );

  test('the keys are cached for max-age, then fetched again', () async {
    final FirebaseAuthAdmin auth = app.auth();
    List<http.Request> fetches() => backend.to('www.googleapis.com');
    await Future.wait(<Future<VerifiedIdToken>>[
      auth.verifyIdToken(token()),
      auth.verifyIdToken(token()),
    ]);
    expect(fetches(), hasLength(1), reason: 'concurrent calls share one fetch');
    clock.advance(const Duration(minutes: 59));
    await auth.verifyIdToken(token());
    expect(fetches(), hasLength(1));

    // Google rotated the keys; the cache expires and the new key is picked up.
    certificates = <String, String>{'kid-2': other.certificatePem};
    clock.advance(const Duration(minutes: 1));
    await auth.verifyIdToken(
      token(
        signer: other,
        header: <String, Object?>{'alg': 'RS256', 'kid': 'kid-2'},
      ),
    );
    expect(fetches(), hasLength(2));
    await expectLater(
      auth.verifyIdToken(token()),
      throwsAdmin('argument-error', contains('kid')),
    );
    expect(
      fetches(),
      hasLength(2),
      reason: 'an unknown kid does not force a fetch while the cache is fresh',
    );
  });

  test('without max-age nothing is cached', () async {
    cacheControl = 'no-cache';
    final FirebaseAuthAdmin auth = app.auth();
    await auth.verifyIdToken(token());
    await auth.verifyIdToken(token());
    expect(backend.to('www.googleapis.com'), hasLength(2));
  });

  test('a key endpoint that fails is internal-error', () async {
    backend.on(
      'www.googleapis.com',
      '/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com',
      (http.Request request) async => http.Response('unavailable', 503),
    );
    await expectLater(
      app.auth().verifyIdToken(token()),
      throwsAdmin('internal-error'),
    );
    backend.on(
      'www.googleapis.com',
      '/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com',
      (http.Request request) async =>
          FakeBackend.json(<String, Object?>{'kid-1': 'not a certificate'}),
    );
    await expectLater(
      app.auth().verifyIdToken(token()),
      throwsAdmin('internal-error'),
    );
  });

  group('checkRevoked', () {
    late Map<String, Object?> user;

    setUp(() {
      user = <String, Object?>{'localId': 'user-1'};
      backend.onToolkit(
        'accounts:lookup',
        (http.Request request) async => FakeBackend.json(<String, Object?>{
          'users': <Object?>[user],
        }),
      );
    });

    test('passes for a token issued after validSince', () async {
      user['validSince'] = '${clock.now.millisecondsSinceEpoch ~/ 1000}';
      expect(
        (await app.auth().verifyIdToken(token(), checkRevoked: true)).uid,
        'user-1',
      );
      expect(bodyOf(backend.toolkit.single), <String, Object?>{
        'localId': <Object?>['user-1'],
      });
    });

    test('revoked when the sign-in is older than validSince', () async {
      user['validSince'] = '${clock.now.millisecondsSinceEpoch ~/ 1000 + 1}';
      await expectLater(
        app.auth().verifyIdToken(token(), checkRevoked: true),
        throwsAdmin('id-token-revoked'),
      );
      // Without the check the token passes.
      expect((await app.auth().verifyIdToken(token())).uid, 'user-1');
    });

    test(
      'a disabled user is user-disabled, a deleted one user-not-found',
      () async {
        user['disabled'] = true;
        await expectLater(
          app.auth().verifyIdToken(token(), checkRevoked: true),
          throwsAdmin('user-disabled'),
        );
        backend.onToolkit(
          'accounts:lookup',
          (http.Request request) async => FakeBackend.json(<String, Object?>{}),
        );
        await expectLater(
          app.auth().verifyIdToken(token(), checkRevoked: true),
          throwsAdmin('user-not-found'),
        );
      },
    );
  });

  group('emulator mode', () {
    late FirebaseAdminApp emulator;

    setUp(() {
      emulator = FirebaseAdminApp.emulator(
        projectId: 'demo-test',
        authEmulatorHost: '127.0.0.1:9099',
        httpClient: backend.client,
        clock: clock.call,
      );
    });

    test(
      'accepts the unsigned tokens of the emulator, with the same claim checks',
      () async {
        final String unsigned = token(
          header: <String, Object?>{'alg': 'none', 'typ': 'JWT'},
          unsigned: true,
        );
        expect((await emulator.auth().verifyIdToken(unsigned)).uid, 'user-1');
        await expectLater(
          emulator.auth().verifyIdToken(
            token(
              header: <String, Object?>{'alg': 'none'},
              unsigned: true,
              extra: <String, Object?>{'aud': 'x'},
            ),
          ),
          throwsAdmin('argument-error', contains('audience')),
        );
        expect(backend.to('www.googleapis.com'), isEmpty);
      },
    );

    test(
      'refuses signed tokens and unsigned ones with a signature part',
      () async {
        await expectLater(
          emulator.auth().verifyIdToken(token()),
          throwsAdmin('argument-error', contains('emulator')),
        );
        final String unsigned = token(
          header: <String, Object?>{'alg': 'none'},
          unsigned: true,
        );
        await expectLater(
          emulator.auth().verifyIdToken('${unsigned}AAAA'),
          throwsAdmin('argument-error'),
        );
      },
    );
  });
}
