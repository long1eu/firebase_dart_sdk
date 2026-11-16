// The user calls: the requests they send (URL, headers, body), how they read the answers, and how errors map.
// No network: the Google endpoints are fakes.

import 'package:firebase_admin_dart/auth.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
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

const String _base =
    'https://identitytoolkit.googleapis.com/v1/projects/demo-test';

void main() {
  final TestKey key = TestKey();
  late FakeBackend backend;
  late FakeClock clock;
  late FirebaseAdminApp app;
  late FirebaseAuthAdmin auth;
  late Map<String, Object?> stored;

  setUp(() {
    backend = FakeBackend();
    clock = FakeClock(DateTime.utc(2026, 11, 16, 12));
    app = FirebaseAdminApp(
      projectId: 'demo-test',
      credential: AdminCredential.serviceAccount(key.serviceAccount()),
      httpClient: backend.client,
      clock: clock.call,
    );
    auth = app.auth();
    stored = <String, Object?>{
      'localId': 'user-1',
      'email': 'a@example.com',
      'emailVerified': true,
      'displayName': 'Ada',
      'photoUrl': 'https://example.com/a.png',
      'phoneNumber': '+15555550100',
      'disabled': false,
      'customAttributes': '{"role":"tester"}',
      'validSince': '1794830400',
      'createdAt': '1794830400123',
      'lastLoginAt': '1794830500456',
      'passwordHash': 'must-not-surface',
      'providerUserInfo': <Object?>[
        <String, Object?>{'providerId': 'password'},
      ],
    };
    backend.onToolkit(
      'accounts:lookup',
      (http.Request request) async => FakeBackend.json(<String, Object?>{
        'users': <Object?>[stored],
      }),
    );
    backend.onToolkit(
      'accounts',
      (http.Request request) async =>
          FakeBackend.json(<String, Object?>{'localId': 'user-1'}),
    );
    backend.onToolkit(
      'accounts:update',
      (http.Request request) async =>
          FakeBackend.json(<String, Object?>{'localId': 'user-1'}),
    );
    backend.onToolkit(
      'accounts:delete',
      (http.Request request) async => FakeBackend.json(<String, Object?>{}),
    );
  });

  void expectToolkit(
    http.Request request,
    String method,
    Map<String, Object?> body,
  ) {
    expect(request.method, 'POST');
    expect(request.url.toString(), '$_base/$method');
    expect(request.headers['Authorization'], 'Bearer ya29.fake-1');
    expect(request.headers['Content-Type'], startsWith('application/json'));
    expect(bodyOf(request), body);
  }

  test(
    'the access token comes from the service account, with the admin scopes, and is reused',
    () async {
      await auth.getUser('user-1');
      await auth.getUser('user-1');
      final http.Request token = backend.to('oauth2.googleapis.com').single;
      final String assertion = token.bodyFields['assertion']!;
      expect(
        decodeJson(assertion.split('.')[1])['scope'],
        AdminCredential.scopes.join(' '),
      );
    },
  );

  test('getUser reads every field and no hash', () async {
    final AdminUser user = await auth.getUser('user-1');
    expectToolkit(backend.toolkit.single, 'accounts:lookup', <String, Object?>{
      'localId': <Object?>['user-1'],
    });
    expect(user.uid, 'user-1');
    expect(user.email, 'a@example.com');
    expect(user.emailVerified, isTrue);
    expect(user.displayName, 'Ada');
    expect(user.photoUrl, 'https://example.com/a.png');
    expect(user.phoneNumber, '+15555550100');
    expect(user.disabled, isFalse);
    expect(user.customClaims, <String, Object?>{'role': 'tester'});
    expect(
      user.tokensValidAfter,
      DateTime.fromMillisecondsSinceEpoch(1794830400000, isUtc: true),
    );
    expect(
      user.createdAt,
      DateTime.fromMillisecondsSinceEpoch(1794830400123, isUtc: true),
    );
    expect(
      user.lastSignInAt,
      DateTime.fromMillisecondsSinceEpoch(1794830500456, isUtc: true),
    );
    expect(user.providerIds, <String>['password']);
    expect('$user', 'AdminUser(user-1)');
  });

  test(
    'getUser of a missing user is user-not-found; findUserByEmail returns null',
    () async {
      backend.onToolkit(
        'accounts:lookup',
        (http.Request request) async => FakeBackend.json(<String, Object?>{}),
      );
      await expectLater(auth.getUser('nobody'), throwsAdmin('user-not-found'));
      expect(await auth.findUserByEmail('nobody@example.com'), isNull);
      expect(bodyOf(backend.toolkit.last), <String, Object?>{
        'email': <Object?>['nobody@example.com'],
      });
    },
  );

  test('createUser sends the properties, then reads the user back', () async {
    final AdminUser user = await auth.createUser(
      uid: 'user-1',
      email: 'a@example.com',
      password: 'secret12',
      emailVerified: true,
      displayName: 'Ada',
      photoUrl: 'https://example.com/a.png',
      phoneNumber: '+15555550100',
    );
    expect(user.uid, 'user-1');
    expectToolkit(backend.toolkit[0], 'accounts', <String, Object?>{
      'localId': 'user-1',
      'email': 'a@example.com',
      'password': 'secret12',
      'emailVerified': true,
      'displayName': 'Ada',
      'photoUrl': 'https://example.com/a.png',
      'phoneNumber': '+15555550100',
      'disabled': false,
    });
    expect(backend.toolkit[1].url.path, endsWith('accounts:lookup'));
  });

  test(
    'createUser with claims sets them in a second request; a failure deletes the user',
    () async {
      await auth.createUser(customClaims: <String, Object?>{'role': 'tester'});
      expect(bodyOf(backend.toolkit[0]), <String, Object?>{
        'emailVerified': false,
        'disabled': false,
      });
      expectToolkit(backend.toolkit[1], 'accounts:update', <String, Object?>{
        'localId': 'user-1',
        'customAttributes': '{"role":"tester"}',
      });

      backend.requests.clear();
      backend.onToolkit(
        'accounts:update',
        (http.Request request) async => FakeBackend.error('INVALID_CLAIMS'),
      );
      await expectLater(
        auth.createUser(customClaims: <String, Object?>{'a': 1}),
        throwsAdmin('invalid-claims'),
      );
      expect(
        backend.toolkit.map((http.Request r) => r.url.pathSegments.last),
        <String>['accounts', 'accounts:update', 'accounts:delete'],
      );

      backend.requests.clear();
      await expectLater(
        auth.createUser(customClaims: <String, Object?>{'sub': 'x'}),
        throwsAdmin('forbidden-claim'),
      );
      expect(
        backend.toolkit,
        isEmpty,
        reason: 'the claims are checked before the user is created',
      );
    },
  );

  test('arguments are checked before any request', () async {
    await expectLater(auth.createUser(uid: ''), throwsAdmin('invalid-uid'));
    await expectLater(
      auth.createUser(uid: 'x' * 129),
      throwsAdmin('invalid-uid'),
    );
    await expectLater(
      auth.createUser(email: 'not-an-email'),
      throwsAdmin('invalid-email'),
    );
    await expectLater(
      auth.createUser(password: '12345'),
      throwsAdmin('invalid-password'),
    );
    await expectLater(
      auth.createUser(phoneNumber: '5555550100'),
      throwsAdmin('invalid-phone-number'),
    );
    await expectLater(
      auth.createUser(photoUrl: 'not a url'),
      throwsAdmin('invalid-photo-url'),
    );
    await expectLater(
      auth.createUser(displayName: ''),
      throwsAdmin('invalid-display-name'),
    );
    await expectLater(auth.getUser(''), throwsAdmin('invalid-uid'));
    await expectLater(auth.deleteUser(''), throwsAdmin('invalid-uid'));
    await expectLater(
      auth.deleteUsers(<String>['ok', '']),
      throwsAdmin('invalid-uid'),
    );
    expect(backend.toolkit, isEmpty);
  });

  test('updateUser sends only the given properties', () async {
    await auth.updateUser(
      'user-1',
      displayName: 'Grace',
      disabled: true,
      emailVerified: false,
    );
    expectToolkit(backend.toolkit[0], 'accounts:update', <String, Object?>{
      'localId': 'user-1',
      'emailVerified': false,
      'displayName': 'Grace',
      'disableUser': true,
    });
  });

  test('deleteUser', () async {
    await auth.deleteUser('user-1');
    expectToolkit(backend.toolkit.single, 'accounts:delete', <String, Object?>{
      'localId': 'user-1',
    });
  });

  test(
    'deleteUsers sends batches of 1000 with force, and offsets the errors',
    () async {
      final List<List<Object?>> batches = <List<Object?>>[];
      backend.onToolkit('accounts:batchDelete', (http.Request request) async {
        final Map<String, Object?> body = bodyOf(request);
        expect(body['force'], isTrue);
        final List<Object?> ids = body['localIds']! as List<Object?>;
        batches.add(ids);
        return FakeBackend.json(<String, Object?>{
          if (batches.length == 2)
            'errors': <Object?>[
              <String, Object?>{
                'index': 5,
                'localId': ids[5],
                'message': 'NOT_DISABLED',
              },
            ],
        });
      });
      final List<String> uids = <String>[for (int i = 0; i < 2500; i++) 'u$i'];
      final DeleteUsersResult result = await auth.deleteUsers(uids);
      expect(batches.map((List<Object?> b) => b.length), <int>[
        1000,
        1000,
        500,
      ]);
      expect(batches[2].first, 'u2000');
      expect(result.successCount, 2499);
      expect(result.failureCount, 1);
      expect(result.errors.single.index, 1005);
      expect(result.errors.single.uid, 'u1005');
      expect(result.errors.single.message, 'NOT_DISABLED');

      backend.requests.clear();
      expect((await auth.deleteUsers(<String>[])).successCount, 0);
      expect(backend.toolkit, isEmpty);
    },
  );

  test('setCustomUserClaims: the JSON, clearing, and the checks', () async {
    await auth.setCustomUserClaims('user-1', <String, Object?>{
      'role': 'tester',
      'n': 1,
    });
    expectToolkit(backend.toolkit.last, 'accounts:update', <String, Object?>{
      'localId': 'user-1',
      'customAttributes': '{"role":"tester","n":1}',
    });
    await auth.setCustomUserClaims('user-1', null);
    expect(bodyOf(backend.toolkit.last)['customAttributes'], '{}');

    backend.requests.clear();
    for (final String name in FirebaseAuthAdmin.reservedClaims) {
      await expectLater(
        auth.setCustomUserClaims('user-1', <String, Object?>{name: true}),
        throwsAdmin('forbidden-claim'),
      );
    }
    // 1000 bytes pass, 1001 do not: '{"k":"' + value + '"}' is 8 bytes of overhead.
    await auth.setCustomUserClaims('user-1', <String, Object?>{'k': 'x' * 992});
    await expectLater(
      auth.setCustomUserClaims('user-1', <String, Object?>{'k': 'x' * 993}),
      throwsAdmin('claims-too-large'),
    );
    await expectLater(
      auth.setCustomUserClaims('user-1', <String, Object?>{'k': Object()}),
      throwsAdmin('invalid-claims'),
    );
    expect(backend.toolkit, hasLength(1));
  });

  test('revokeRefreshTokens sets validSince to now in seconds', () async {
    await auth.revokeRefreshTokens('user-1');
    expectToolkit(backend.toolkit.single, 'accounts:update', <String, Object?>{
      'localId': 'user-1',
      'validSince': '${clock.now.millisecondsSinceEpoch ~/ 1000}',
    });
  });

  group('errors', () {
    void answer(http.Response response) => backend.onToolkit(
      'accounts:delete',
      (http.Request request) async => response,
    );

    test('server codes map to the Admin SDK codes', () async {
      final Map<String, String> cases = <String, String>{
        'USER_NOT_FOUND': 'user-not-found',
        'DUPLICATE_LOCAL_ID': 'uid-already-exists',
        'EMAIL_EXISTS': 'email-already-exists',
        'DUPLICATE_EMAIL': 'email-already-exists',
        'PHONE_NUMBER_EXISTS': 'phone-number-already-exists',
        'INVALID_EMAIL': 'invalid-email',
        'WEAK_PASSWORD : Password should be at least 6 characters':
            'invalid-password',
        'INSUFFICIENT_PERMISSION': 'insufficient-permission',
        'PROJECT_NOT_FOUND': 'project-not-found',
        'QUOTA_EXCEEDED': 'quota-exceeded',
        'SOMETHING_NEW': 'internal-error',
      };
      for (final MapEntry<String, String> c in cases.entries) {
        answer(FakeBackend.error(c.key));
        await expectLater(
          auth.deleteUser('user-1'),
          throwsAdmin(c.value),
          reason: c.key,
        );
      }
      answer(
        FakeBackend.error(
          'WEAK_PASSWORD : Password should be at least 6 characters',
        ),
      );
      await expectLater(
        auth.deleteUser('user-1'),
        throwsA(
          isA<FirebaseAuthAdminException>()
              .having(
                (FirebaseAuthAdminException e) => e.serverCode,
                'serverCode',
                'WEAK_PASSWORD',
              )
              .having(
                (FirebaseAuthAdminException e) => e.message,
                'message',
                'Password should be at least 6 characters',
              )
              .having(
                (FirebaseAuthAdminException e) => e.httpStatus,
                'httpStatus',
                400,
              )
              .having(
                (FirebaseAuthAdminException e) => '$e',
                'toString',
                startsWith('[auth/invalid-password]'),
              ),
        ),
      );
    });

    test('a refused credential, a non-JSON answer, a network error', () async {
      answer(
        FakeBackend.json(<String, Object?>{
          'error': <String, Object?>{
            'code': 403,
            'message':
                'Caller does not have required permission to use project demo-test.',
            'status': 'PERMISSION_DENIED',
          },
        }, 403),
      );
      await expectLater(
        auth.deleteUser('user-1'),
        throwsAdmin('insufficient-permission'),
      );
      answer(http.Response('<html>bad gateway</html>', 502));
      await expectLater(
        auth.deleteUser('user-1'),
        throwsAdmin('internal-error'),
      );
      backend.onToolkit(
        'accounts:delete',
        (http.Request request) =>
            throw http.ClientException('down', request.url),
      );
      await expectLater(
        auth.deleteUser('user-1'),
        throwsAdmin('network-error'),
      );
    });

    test(
      'a refused service account key is invalid-credential, and the key is not quoted',
      () async {
        backend.on(
          'oauth2.googleapis.com',
          '/token',
          (http.Request request) async => FakeBackend.json(<String, Object?>{
            'error': 'invalid_grant',
            'error_description': 'Invalid JWT Signature.',
          }, 400),
        );
        await expectLater(
          auth.deleteUser('user-1'),
          throwsA(
            isA<FirebaseAuthAdminException>()
                .having(
                  (FirebaseAuthAdminException e) => e.code,
                  'code',
                  'invalid-credential',
                )
                .having(
                  (FirebaseAuthAdminException e) => e.message,
                  'message',
                  isNot(contains('PRIVATE')),
                ),
          ),
        );
      },
    );

    test('the exception is a FirebaseException of the auth plugin', () async {
      answer(FakeBackend.error('USER_NOT_FOUND'));
      await expectLater(
        auth.deleteUser('user-1'),
        throwsA(
          isA<FirebaseException>().having(
            (FirebaseException e) => e.plugin,
            'plugin',
            'auth',
          ),
        ),
      );
    });
  });

  group('app', () {
    test(
      'emulator requests carry Bearer owner and go to the emulator host',
      () async {
        final FirebaseAdminApp emulator = FirebaseAdminApp.emulator(
          projectId: 'demo-test',
          authEmulatorHost: '127.0.0.1:9099',
          httpClient: backend.client,
        );
        backend.on(
          '127.0.0.1',
          '/identitytoolkit.googleapis.com/v1/projects/demo-test/accounts:delete',
          (http.Request request) async => FakeBackend.json(<String, Object?>{}),
        );
        await emulator.auth().deleteUser('user-1');
        final http.Request request = backend.requests.single;
        expect(
          request.url.toString(),
          'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/projects/demo-test/accounts:delete',
        );
        expect(request.headers['Authorization'], 'Bearer owner');
        expect(emulator.isEmulator, isTrue);
        expect(app.isEmulator, isFalse);
      },
    );

    test(
      'a bad emulator host, a bad project id or a bad key throw ArgumentError',
      () {
        expect(
          () => FirebaseAdminApp.emulator(
            projectId: 'demo-test',
            authEmulatorHost: 'identitytoolkit.googleapis.com',
          ),
          throwsArgumentError,
        );
        expect(
          () => FirebaseAdminApp.emulator(
            projectId: 'demo-test',
            authEmulatorHost: '127.0.0.1:9099/path',
          ),
          throwsArgumentError,
        );
        expect(
          () => FirebaseAdminApp.emulator(
            projectId: 'a/b',
            authEmulatorHost: '127.0.0.1:9099',
          ),
          throwsArgumentError,
        );
        expect(
          () => AdminCredential.serviceAccount(<String, Object?>{
            ...key.serviceAccount(),
            'type': 'user',
          }),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => '$e',
              'text',
              isNot(contains('PRIVATE')),
            ),
          ),
        );
      },
    );

    test('one FirebaseAuthAdmin per app; calls after close throw', () async {
      expect(identical(app.auth(), FirebaseAuthAdmin(app)), isTrue);
      await app.close();
      expect(app.isClosed, isTrue);
      expect(() => app.auth().getUser('user-1'), throwsStateError);
      expect(() => app.auth().createCustomToken('user-1'), throwsStateError);
      expect(() => app.auth().verifyIdToken('a.b.c'), throwsStateError);
      await app.close();
    });

    test('nothing prints the key', () {
      expect(
        '${AdminCredential.serviceAccount(key.serviceAccount())}',
        isNot(contains('PRIVATE')),
      );
      expect('$app', 'FirebaseAdminApp(demo-test)');
    });
  });
}
