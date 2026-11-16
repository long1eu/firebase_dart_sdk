// createCustomToken: the JWT it builds, its signature (local key, IAM signBlob, none in emulator mode), and the
// checks of its arguments. No network: the Google endpoints are fakes.

import 'dart:convert';
import 'dart:io';

import 'package:firebase_admin_dart/auth.dart';
import 'package:firebase_admin_dart/src/auth/rsa.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'fake_backend.dart';
import 'support.dart';

Matcher throwsAdmin(String code) => throwsA(
  isA<FirebaseAuthAdminException>().having(
    (FirebaseAuthAdminException e) => e.code,
    'code',
    code,
  ),
);

void main() {
  final TestKey key = TestKey();
  final TestKey other = TestKey();
  late FakeBackend backend;
  late FakeClock clock;

  setUp(() {
    backend = FakeBackend();
    clock = FakeClock(DateTime.utc(2026, 11, 16, 12));
  });

  FirebaseAdminApp serviceAccountApp() => FirebaseAdminApp(
    projectId: 'demo-test',
    credential: AdminCredential.serviceAccount(key.serviceAccount()),
    httpClient: backend.client,
    clock: clock.call,
  );

  bool verifies(TestKey key, String token) {
    final List<String> parts = token.split('.');
    return RsaPublicKey(key.n, key.e).verifyRs256(
      ascii.encode('${parts[0]}.${parts[1]}'),
      base64Url.decode(base64Url.normalize(parts[2])),
    );
  }

  group('with a service account key', () {
    test('header, claims and a signature of the key', () async {
      final FirebaseAdminApp app = serviceAccountApp();
      final String token = await app.auth().createCustomToken(
        'user-1',
        claims: <String, Object?>{'role': 'tester', 'level': 3},
      );
      final List<String> parts = token.split('.');
      expect(parts, hasLength(3));
      expect(decodeJson(parts[0]), <String, Object?>{
        'alg': 'RS256',
        'typ': 'JWT',
      });
      final int now = clock.now.millisecondsSinceEpoch ~/ 1000;
      expect(decodeJson(parts[1]), <String, Object?>{
        'aud':
            'https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit',
        'iat': now,
        'exp': now + 3600,
        'iss': 'admin@demo-test.iam.gserviceaccount.com',
        'sub': 'admin@demo-test.iam.gserviceaccount.com',
        'uid': 'user-1',
        'claims': <String, Object?>{'role': 'tester', 'level': 3},
      });
      expect(verifies(key, token), isTrue);
      expect(verifies(other, token), isFalse);
      expect(
        backend.requests,
        isEmpty,
        reason: 'signing with a key needs no request',
      );
    });

    test(
      'the encoding is base64url without padding, also where standard base64 has + and /',
      () async {
        // '???' is 'Pz8/' and '~~~' is 'fn5+' in standard base64; the payload has both.
        final Map<String, Object?> claims = <String, Object?>{
          'q': '???~~~>>>',
          'u': 'ÿûü',
        };
        final String token = await serviceAccountApp().auth().createCustomToken(
          'u',
          claims: claims,
        );
        final List<String> parts = token.split('.');
        expect(
          base64.encode(
            utf8.encode(jsonEncode(<String, Object?>{'claims': claims})),
          ),
          matches(RegExp('[+/]')),
        );
        expect(
          base64.encode(base64Url.decode(base64Url.normalize(parts[1]))),
          matches(RegExp('[+/]')),
        );
        for (final String part in parts) {
          expect(part, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
        }
        expect(decodeJson(parts[1])['claims'], claims);
        expect(verifies(key, token), isTrue);
      },
    );

    test('tenant id, and no claims entry without claims', () async {
      final String token = await serviceAccountApp().auth().createCustomToken(
        'u',
        tenantId: 'tenant-1',
      );
      final Map<String, Object?> payload = decodeJson(token.split('.')[1]);
      expect(payload['tenant_id'], 'tenant-1');
      expect(payload.containsKey('claims'), isFalse);
    });

    test(
      'reserved claims, bad uids and non-JSON claims are refused before signing',
      () async {
        final FirebaseAuthAdmin auth = serviceAccountApp().auth();
        for (final String name in FirebaseAuthAdmin.reservedClaims) {
          await expectLater(
            auth.createCustomToken('u', claims: <String, Object?>{name: 1}),
            throwsAdmin('argument-error'),
            reason: name,
          );
        }
        await expectLater(
          auth.createCustomToken(''),
          throwsAdmin('argument-error'),
        );
        await expectLater(
          auth.createCustomToken('x' * 129),
          throwsAdmin('argument-error'),
        );
        expect(await auth.createCustomToken('x' * 128), isNotEmpty);
        await expectLater(
          auth.createCustomToken(
            'u',
            claims: <String, Object?>{'when': DateTime(2026)},
          ),
          throwsAdmin('argument-error'),
        );
        await expectLater(
          auth.createCustomToken('u', tenantId: ''),
          throwsAdmin('argument-error'),
        );
      },
    );

    final String? skip = opensslSkip();
    test(
      'openssl verifies the signature of a minted token (2048-bit key from openssl)',
      () async {
        final Directory temp = Directory.systemTemp.createTempSync(
          'admin_token_',
        );
        addTearDown(() => temp.deleteSync(recursive: true));
        final ProcessResult made = Process.runSync('openssl', <String>[
          'genpkey',
          '-algorithm',
          'RSA',
          '-pkeyopt',
          'rsa_keygen_bits:2048',
          '-out',
          '${temp.path}/key.pem', //
        ]);
        expect(made.exitCode, 0, reason: '${made.stderr}');
        Process.runSync('openssl', <String>[
          'pkey',
          '-in',
          '${temp.path}/key.pem',
          '-pubout',
          '-out',
          '${temp.path}/public.pem', //
        ]);
        final FirebaseAdminApp app = FirebaseAdminApp(
          projectId: 'demo-test',
          credential: AdminCredential.serviceAccount(<String, Object?>{
            ...key.serviceAccount(),
            'private_key': File('${temp.path}/key.pem').readAsStringSync(),
          }),
          httpClient: backend.client,
        );
        final String token = await app.auth().createCustomToken(
          'user-1',
          claims: <String, Object?>{'q': '???~~~'},
        );
        final List<String> parts = token.split('.');
        File('${temp.path}/input').writeAsStringSync('${parts[0]}.${parts[1]}');
        File(
          '${temp.path}/sig',
        ).writeAsBytesSync(base64Url.decode(base64Url.normalize(parts[2])));
        final ProcessResult verify = Process.runSync('openssl', <String>[
          'dgst', '-sha256', '-verify', '${temp.path}/public.pem', //
          '-signature', '${temp.path}/sig', '${temp.path}/input',
        ]);
        expect('${verify.stdout}', contains('Verified OK'));
      },
      skip: skip,
    );
  });

  group('with IAM signBlob', () {
    late List<int> signedPayloads;

    setUp(() {
      signedPayloads = <int>[];
      backend.on(
        'iamcredentials.googleapis.com',
        '/v1/projects/-/serviceAccounts/signer@demo-test.iam.gserviceaccount.com:signBlob',
        (http.Request request) async {
          final List<int> payload = base64.decode(
            bodyOf(request)['payload']! as String,
          );
          signedPayloads.addAll(payload);
          return FakeBackend.json(<String, Object?>{
            'keyId': 'k1',
            // Standard base64, as the API answers.
            'signedBlob': base64.encode(key.sign(payload)),
          });
        },
      );
      backend.on(
        'metadata.google.internal',
        '/computeMetadata/v1/instance/service-accounts/default/email',
        (http.Request request) async =>
            request.headers['Metadata-Flavor'] == 'Google'
            ? http.Response('signer@demo-test.iam.gserviceaccount.com', 200)
            : http.Response('missing header', 403),
      );
    });

    FirebaseAdminApp iamApp({String? email, String? quotaProject}) =>
        FirebaseAdminApp(
          projectId: 'demo-test',
          credential: AdminCredential.iam(
            OAuthTokenProvider(
              () async => OAuthAccessToken(
                'ya29.adc',
                clock.now.add(const Duration(hours: 1)),
              ),
              clock: clock.call,
            ),
            serviceAccountEmail: email,
            quotaProjectId: quotaProject,
          ),
          httpClient: backend.client,
          clock: clock.call,
        );

    test(
      'signs through signBlob as the email of the metadata server',
      () async {
        final FirebaseAdminApp app = iamApp();
        final String token = await app.auth().createCustomToken('user-1');
        final List<String> parts = token.split('.');
        expect(
          decodeJson(parts[1])['iss'],
          'signer@demo-test.iam.gserviceaccount.com',
        );
        expect(utf8.decode(signedPayloads), '${parts[0]}.${parts[1]}');
        expect(verifies(key, token), isTrue);
        final http.Request sign = backend
            .to('iamcredentials.googleapis.com')
            .single;
        expect(sign.method, 'POST');
        expect(sign.headers['Authorization'], 'Bearer ya29.adc');
        // The email is asked once.
        await app.auth().createCustomToken('user-2');
        expect(backend.to('metadata.google.internal'), hasLength(1));
      },
    );

    test(
      'a given email skips the metadata server; the quota project is sent',
      () async {
        final FirebaseAdminApp app = iamApp(
          email: 'signer@demo-test.iam.gserviceaccount.com',
          quotaProject: 'billing-project',
        );
        await app.auth().createCustomToken('user-1');
        expect(backend.to('metadata.google.internal'), isEmpty);
        expect(
          backend
              .to('iamcredentials.googleapis.com')
              .single
              .headers['X-Goog-User-Project'],
          'billing-project',
        );
      },
    );

    test('errors: no metadata server, permission denied, other failures', () async {
      backend.on(
        'metadata.google.internal',
        '/computeMetadata/v1/instance/service-accounts/default/email',
        (http.Request request) =>
            throw http.ClientException('no route', request.url),
      );
      await expectLater(
        iamApp().auth().createCustomToken('u'),
        throwsAdmin('invalid-credential'),
      );

      backend.on(
        'iamcredentials.googleapis.com',
        '/v1/projects/-/serviceAccounts/signer@demo-test.iam.gserviceaccount.com:signBlob',
        (http.Request request) async => FakeBackend.json(<String, Object?>{
          'error': <String, Object?>{
            'code': 403,
            'message': "Permission 'iam.serviceAccounts.signBlob' denied",
            'status': 'PERMISSION_DENIED',
          },
        }, 403),
      );
      final FirebaseAdminApp app = iamApp(
        email: 'signer@demo-test.iam.gserviceaccount.com',
      );
      await expectLater(
        app.auth().createCustomToken('u'),
        throwsA(
          isA<FirebaseAuthAdminException>()
              .having(
                (FirebaseAuthAdminException e) => e.code,
                'code',
                'insufficient-permission',
              )
              .having(
                (FirebaseAuthAdminException e) => e.serverCode,
                'serverCode',
                'PERMISSION_DENIED',
              )
              .having(
                (FirebaseAuthAdminException e) => e.message,
                'message',
                contains('Token Creator'),
              ),
        ),
      );
      backend.on(
        'iamcredentials.googleapis.com',
        '/v1/projects/-/serviceAccounts/signer@demo-test.iam.gserviceaccount.com:signBlob',
        (http.Request request) async => http.Response('oops', 500),
      );
      await expectLater(
        app.auth().createCustomToken('u'),
        throwsAdmin('internal-error'),
      );
    });

    test('a failing access token source is invalid-credential', () async {
      final FirebaseAdminApp app = FirebaseAdminApp(
        projectId: 'demo-test',
        credential: AdminCredential.iam(
          OAuthTokenProvider(
            () async => throw StateError('no credentials found'),
          ),
          serviceAccountEmail: 'signer@demo-test.iam.gserviceaccount.com',
        ),
        httpClient: backend.client,
      );
      await expectLater(
        app.auth().createCustomToken('u'),
        throwsAdmin('invalid-credential'),
      );
    });
  });

  test(
    'in emulator mode the token is unsigned, issued by the emulator account',
    () async {
      final FirebaseAdminApp app = FirebaseAdminApp.emulator(
        projectId: 'demo-test',
        authEmulatorHost: '127.0.0.1:9099',
        httpClient: backend.client,
        clock: clock.call,
      );
      final String token = await app.auth().createCustomToken(
        'u',
        claims: <String, Object?>{'a': 1},
      );
      final List<String> parts = token.split('.');
      expect(parts[2], isEmpty);
      expect(decodeJson(parts[0]), <String, Object?>{
        'alg': 'none',
        'typ': 'JWT',
      });
      expect(decodeJson(parts[1])['iss'], 'firebase-auth-emulator@example.com');
      expect(backend.requests, isEmpty);
    },
  );
}
