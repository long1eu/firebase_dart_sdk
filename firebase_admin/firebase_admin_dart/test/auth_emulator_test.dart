// The auth admin calls against the Firebase Auth emulator (the real request and response shapes), with the
// client of firebase_auth_providers_dart signing in as the users it makes.
//
//     firebase emulators:start --only auth --project demo-test    (or tool/start_auth_emulators.sh)
//     FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 dart test test/auth_emulator_test.dart
//
// Skipped unless FIREBASE_AUTH_EMULATOR_HOST is set. Never talks to the real service.

@TestOn('vm')
library;

import 'package:firebase_admin_dart/auth.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:test/test.dart';

int _counter = 0;
String unique(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_counter++}';

Matcher throwsAdmin(String code) => throwsA(
  isA<FirebaseAuthAdminException>().having(
    (FirebaseAuthAdminException e) => e.code,
    'code',
    code,
  ),
);

void main() {
  final String? host = FirebaseUserAuth.emulatorHostFromEnvironment;
  final String? skip = host == null
      ? 'FIREBASE_AUTH_EMULATOR_HOST is not set (start the Auth emulator, see the top of this file)'
      : null;

  late FirebaseAdminApp app;
  late FirebaseAuthAdmin admin;
  final List<FirebaseUserAuth> clients = <FirebaseUserAuth>[];

  FirebaseUserAuth client() {
    final FirebaseUserAuth auth = FirebaseUserAuth(
      apiKey: 'fake-api-key',
      emulatorHost: host,
    );
    clients.add(auth);
    return auth;
  }

  setUp(() {
    app = FirebaseAdminApp.emulator(
      projectId: 'demo-test',
      authEmulatorHost: host!,
    );
    admin = app.auth();
  });

  tearDown(() async {
    for (final FirebaseUserAuth auth in clients) {
      await auth.dispose();
    }
    clients.clear();
    await app.close();
  });

  group('Auth emulator', () {
    test(
      'the loop: create, mint with claims, sign in, read claims, verify, delete',
      () async {
        final AdminUser user = await admin.createUser(
          customClaims: <String, Object?>{'role': 'tester'},
        );
        final String customToken = await admin.createCustomToken(
          user.uid,
          claims: <String, Object?>{'tier': 'pro', 'q': '???~~~'},
        );
        final FirebaseUserAuth auth = client();
        final AuthUser signedIn = await auth.signInWithCustomToken(customToken);
        expect(signedIn.uid, user.uid);

        final GetTokenResult idToken = await auth.getAccessToken(
          forceRefresh: false,
        );
        expect(idToken.claims['role'], 'tester');
        expect(idToken.claims['tier'], 'pro');
        expect(idToken.claims['q'], '???~~~');

        final VerifiedIdToken verified = await admin.verifyIdToken(
          idToken.token,
          checkRevoked: true,
        );
        expect(verified.uid, user.uid);
        expect(verified.signInProvider, 'custom');
        expect(verified.claims['tier'], 'pro');

        await admin.deleteUser(user.uid);
        await expectLater(
          admin.getUser(user.uid),
          throwsAdmin('user-not-found'),
        );
        await expectLater(
          admin.verifyIdToken(idToken.token, checkRevoked: true),
          throwsAdmin('user-not-found'),
        );
      },
    );

    test('user CRUD and the errors of the backend', () async {
      final String uid = unique('crud');
      final String email = '$uid@example.com';
      final AdminUser created = await admin.createUser(
        uid: uid,
        email: email,
        password: 'secret12',
        emailVerified: true,
        displayName: 'Ada',
        photoUrl: 'https://example.com/ada.png',
        phoneNumber: '+1555${DateTime.now().microsecondsSinceEpoch % 10000000}'
            .padRight(12, '0'),
      );
      expect(created.uid, uid);
      expect(created.email, email);
      expect(created.emailVerified, isTrue);
      expect(created.displayName, 'Ada');
      expect(created.photoUrl, 'https://example.com/ada.png');
      expect(created.phoneNumber, startsWith('+1555'));
      expect(created.disabled, isFalse);
      expect(created.createdAt, isNotNull);
      expect(created.providerIds, containsAll(<String>['password', 'phone']));

      expect((await admin.findUserByEmail(email))?.uid, uid);
      expect(
        await admin.findUserByEmail('nobody-${unique('x')}@example.com'),
        isNull,
      );

      final AdminUser updated = await admin.updateUser(
        uid,
        displayName: 'Grace',
        disabled: true,
      );
      expect(updated.displayName, 'Grace');
      expect(updated.disabled, isTrue);
      expect(updated.email, email, reason: 'what was not passed is kept');

      await expectLater(
        admin.createUser(uid: uid),
        throwsAdmin('uid-already-exists'),
      );
      await expectLater(
        admin.createUser(email: email),
        throwsAdmin('email-already-exists'),
      );

      // The password works for the client, and a disabled account cannot sign in.
      await expectLater(
        client().signInWithEmailAndPassword(email: email, password: 'secret12'),
        throwsA(
          isA<FirebaseAuthException>().having(
            (FirebaseAuthException e) => e.code,
            'code',
            'user-disabled',
          ),
        ),
      );
      await admin.updateUser(uid, disabled: false, password: 'changed12');
      expect(
        (await client().signInWithEmailAndPassword(
          email: email,
          password: 'changed12',
        )).uid,
        uid,
      );

      await admin.deleteUser(uid);
      await expectLater(admin.deleteUser(uid), throwsAdmin('user-not-found'));
      await expectLater(
        admin.updateUser(uid, displayName: 'x'),
        throwsAdmin('user-not-found'),
      );
    });

    test('custom claims round trip through a real sign-in', () async {
      final AdminUser user = await admin.createUser();
      final FirebaseUserAuth auth = client();
      await auth.signInWithCustomToken(await admin.createCustomToken(user.uid));
      expect(
        (await auth.getAccessToken(
          forceRefresh: false,
        )).claims.containsKey('plan'),
        isFalse,
      );

      await admin.setCustomUserClaims(user.uid, <String, Object?>{
        'plan': 'pro',
        'groups': <Object?>['a', 'b'],
      });
      expect((await admin.getUser(user.uid)).customClaims, <String, Object?>{
        'plan': 'pro',
        'groups': <Object?>['a', 'b'],
      });
      // The client sees new claims after a refresh of its ID token.
      final GetTokenResult refreshed = await auth.getAccessToken(
        forceRefresh: true,
      );
      expect(refreshed.claims['plan'], 'pro');
      expect(
        (await admin.verifyIdToken(refreshed.token)).claims['groups'],
        <Object?>['a', 'b'],
      );

      await admin.setCustomUserClaims(user.uid, null);
      expect((await admin.getUser(user.uid)).customClaims, isEmpty);
      await admin.deleteUser(user.uid);
    });

    test('revoke, then checkRevoked refuses the old token', () async {
      final AdminUser user = await admin.createUser();
      final FirebaseUserAuth auth = client();
      await auth.signInWithCustomToken(await admin.createCustomToken(user.uid));
      final String before = (await auth.getAccessToken(
        forceRefresh: false,
      )).token;
      expect(
        (await admin.verifyIdToken(before, checkRevoked: true)).uid,
        user.uid,
      );

      // validSince has second precision: make the sign-in strictly older.
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await admin.revokeRefreshTokens(user.uid);
      expect((await admin.getUser(user.uid)).tokensValidAfter, isNotNull);
      await expectLater(
        admin.verifyIdToken(before, checkRevoked: true),
        throwsAdmin('id-token-revoked'),
      );
      expect(
        (await admin.verifyIdToken(before)).uid,
        user.uid,
        reason: 'without the check it still passes',
      );

      // A new sign-in is valid again.
      await auth.signInWithCustomToken(await admin.createCustomToken(user.uid));
      final String after = (await auth.getAccessToken(
        forceRefresh: false,
      )).token;
      expect(
        (await admin.verifyIdToken(after, checkRevoked: true)).uid,
        user.uid,
      );

      await admin.updateUser(user.uid, disabled: true);
      await expectLater(
        admin.verifyIdToken(after, checkRevoked: true),
        throwsAdmin('user-disabled'),
      );
      await admin.deleteUser(user.uid);
    });

    test(
      'deleteUsers over more than one batch',
      () async {
        final String prefix = unique('bulk');
        final List<String> uids = <String>[
          for (int i = 0; i < FirebaseAuthAdmin.deleteUsersBatchSize + 5; i++)
            '$prefix-$i',
        ];
        for (int start = 0; start < uids.length; start += 100) {
          await Future.wait(<Future<AdminUser>>[
            for (final String uid in uids.skip(start).take(100))
              admin.createUser(uid: uid),
          ]);
        }
        final DeleteUsersResult result = await admin.deleteUsers(<String>[
          ...uids,
          unique('missing'),
        ]);
        expect(result.successCount, uids.length + 1);
        expect(result.errors, isEmpty);
        await expectLater(
          admin.getUser(uids.first),
          throwsAdmin('user-not-found'),
        );
        await expectLater(
          admin.getUser(uids.last),
          throwsAdmin('user-not-found'),
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'an unsigned emulator token is refused by a non-emulator app',
      () async {
        final AdminUser user = await admin.createUser();
        final FirebaseUserAuth auth = client();
        await auth.signInWithCustomToken(
          await admin.createCustomToken(user.uid),
        );
        final String token = (await auth.getAccessToken(
          forceRefresh: false,
        )).token;
        final FirebaseAdminApp real = FirebaseAdminApp(
          projectId: 'demo-test',
          credential: AdminCredential.iam(
            OAuthTokenProvider(() async => throw StateError('never used')),
            serviceAccountEmail: 'unused@example.com',
          ),
        );
        await expectLater(
          real.auth().verifyIdToken(token),
          throwsAdmin('argument-error'),
        );
        await real.close();
        await admin.deleteUser(user.uid);
      },
    );
  }, skip: skip);
}
