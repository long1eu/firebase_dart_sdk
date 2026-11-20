// The full user record: what a sign-in and a reload read, AdditionalUserInfo, UserCredential, and the stored
// format (version 2, which still reads the sessions of 0.2).

import 'dart:convert';

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:test/test.dart';

import 'harness.dart';

void main() {
  late FakeBackend backend;
  late FirebaseUserAuth auth;
  const String key = 'firebase_auth_providers_dart:$apiKey';

  setUp(() {
    backend = FakeBackend();
    auth = backend.create();
  });

  tearDown(() => auth.dispose());

  final Map<String, Object?> fullAccount = <String, Object?>{
    'email': 'ada@example.com',
    'emailVerified': true,
    'displayName': 'Ada',
    'photoUrl': 'https://example.com/ada.png',
    'phoneNumber': '+15555550100',
    'tenantId': null,
    'createdAt': '1700000000000',
    'lastLoginAt': '1790000000000',
    'passwordHash': 'hash',
    'providerUserInfo': <Object?>[
      <String, Object?>{
        'providerId': 'password',
        'rawId': 'ada@example.com',
        'email': 'ada@example.com',
        'federatedId': 'ada@example.com',
      },
      <String, Object?>{
        'providerId': 'google.com',
        'rawId': '1234',
        'email': 'ada@gmail.com',
        'displayName': 'Ada L.',
        'photoUrl': 'https://example.com/g.png',
      },
      <String, Object?>{'providerId': 'phone', 'phoneNumber': '+15555550100'},
    ],
  };

  final AuthUser fullUser = AuthUser(
    uid: 'uid-of-ada@example.com',
    email: 'ada@example.com',
    emailVerified: true,
    displayName: 'Ada',
    photoUrl: 'https://example.com/ada.png',
    phoneNumber: '+15555550100',
    metadata: UserMetadata(creationTime: _created, lastSignInTime: _lastLogin),
    providerData: const <UserInfo>[
      UserInfo(
        providerId: 'password',
        uid: 'ada@example.com',
        email: 'ada@example.com',
      ),
      UserInfo(
        providerId: 'google.com',
        uid: '1234',
        email: 'ada@gmail.com',
        displayName: 'Ada L.',
        photoUrl: 'https://example.com/g.png',
      ),
      UserInfo(providerId: 'phone', uid: '', phoneNumber: '+15555550100'),
    ],
  );

  group('a sign-in', () {
    test(
      'reads the whole account (accounts:lookup) before it completes',
      () async {
        backend.accounts['uid-of-ada@example.com'] = fullAccount;
        final List<AuthUser?> announced = <AuthUser?>[];
        auth.userChanges().listen(announced.add);
        final UserCredential result = await auth.signInWithEmailAndPassword(
          email: 'ada@example.com',
          password: 'secret',
        );
        expect(backend.methods, <String>[
          'accounts:signInWithPassword',
          'accounts:lookup',
        ]);
        expect(
          backend.bodiesOf('accounts:lookup').single['idToken'],
          (await auth.getAccessToken(forceRefresh: false)).token,
        );
        expect(result.user, fullUser);
        expect(auth.currentUser, fullUser);
        expect(announced, <AuthUser?>[fullUser]);
        expect(result.photoURL, 'https://example.com/ada.png');
        expect(result.providerData[1].photoURL, 'https://example.com/g.png');
        expect(fullUser.metadata.creationTime!.isUtc, isTrue);
      },
    );

    test(
      'fails, and signs nobody in, when the account cannot be read',
      () async {
        backend.on('accounts:lookup', (_) => errorResponse('USER_NOT_FOUND'));
        await expectLater(
          auth.signInWithEmailAndPassword(
            email: 'ada@example.com',
            password: 'secret',
          ),
          throwsAuth('user-token-expired'),
        );
        expect(auth.currentUser, isNull);
        expect(backend.storage.read(key), isNull);
        backend.on(
          'accounts:lookup',
          (_) => jsonResponse(<String, Object?>{'users': <Object?>[]}),
        );
        await expectLater(
          auth.signInAnonymously(),
          throwsAuth('internal-error'),
        );
        expect(auth.currentUser, isNull);
      },
    );

    test('a sign-in overtaken during the lookup is cancelled', () async {
      backend.on('accounts:lookup', (Map<String, Object?> body) async {
        backend.overrides.remove('accounts:lookup');
        // The second sign-in starts while the first one reads the account.
        final Future<UserCredential> second = auth.signInWithCustomToken('t');
        await second;
        return jsonResponse(<String, Object?>{
          'users': <Object?>[
            <String, Object?>{'localId': 'anon-user'},
          ],
        });
      });
      await expectLater(auth.signInAnonymously(), throwsAuth('cancelled'));
      expect(auth.uid, 'custom-user');
    });
  });

  group('User fields of the JS SDK', () {
    test('providerId is firebase, for a user and a sign-in result', () async {
      expect(const AuthUser(uid: 'u').providerId, 'firebase');
      final UserCredential result = await auth.signInAnonymously();
      expect(result.providerId, 'firebase');
      expect(result.user!.providerId, 'firebase');
    });

    test('toJson has the keys of User.toJSON, without the session', () {
      expect(fullUser.toJson(), <String, Object?>{
        'uid': 'uid-of-ada@example.com',
        'email': 'ada@example.com',
        'emailVerified': true,
        'displayName': 'Ada',
        'isAnonymous': false,
        'photoURL': 'https://example.com/ada.png',
        'phoneNumber': '+15555550100',
        'providerData': <Object?>[
          <String, Object?>{
            'providerId': 'password',
            'uid': 'ada@example.com',
            'displayName': null,
            'email': 'ada@example.com',
            'phoneNumber': null,
            'photoURL': null,
          },
          <String, Object?>{
            'providerId': 'google.com',
            'uid': '1234',
            'displayName': 'Ada L.',
            'email': 'ada@gmail.com',
            'phoneNumber': null,
            'photoURL': 'https://example.com/g.png',
          },
          <String, Object?>{
            'providerId': 'phone',
            'uid': '',
            'displayName': null,
            'email': null,
            'phoneNumber': '+15555550100',
            'photoURL': null,
          },
        ],
        'createdAt': '1700000000000',
        'lastLoginAt': '1790000000000',
      });
      expect(jsonDecode(jsonEncode(fullUser.toJson())), fullUser.toJson());
    });

    test('toJson leaves out what the user does not have', () {
      expect(
        const AuthUser(uid: 'u', isAnonymous: true, tenantId: 't').toJson(),
        <String, Object?>{
          'uid': 'u',
          'emailVerified': false,
          'isAnonymous': true,
          'tenantId': 't',
          'providerData': <Object?>[],
        },
      );
    });
  });

  group('AdditionalUserInfo', () {
    test('of the built-in sign-ins', () async {
      final UserCredential anonymous = await auth.signInAnonymously();
      expect(anonymous.additionalUserInfo?.isNewUser, isTrue);
      expect(anonymous.additionalUserInfo?.providerId, isNull);
      expect(anonymous.isAnonymous, isTrue);

      final UserCredential created = await auth.createUserWithEmailAndPassword(
        email: 'b@example.com',
        password: 'secret',
      );
      expect(created.additionalUserInfo?.isNewUser, isTrue);
      expect(created.additionalUserInfo?.providerId, 'password');
      expect(created.additionalUserInfo?.profile, isNull);

      final UserCredential signedIn = await auth.signInWithEmailAndPassword(
        email: 'b@example.com',
        password: 'secret',
      );
      expect(signedIn.additionalUserInfo?.isNewUser, isFalse);
      expect(signedIn.additionalUserInfo?.providerId, 'password');

      final UserCredential custom = await auth.signInWithCustomToken('t');
      expect(custom.additionalUserInfo?.isNewUser, isFalse);
      expect(custom.additionalUserInfo?.providerId, isNull);
    });

    test('of federated answers: profile and user name', () async {
      Map<String, Object?> answer = <String, Object?>{};
      backend.on(
        'accounts:signInWithCustomToken',
        (_) => jsonResponse(<String, Object?>{
          ...backend.tokensFor('fed', provider: 'github.com'),
          ...answer,
        }),
      );
      answer = <String, Object?>{
        'providerId': 'github.com',
        'isNewUser': true,
        'rawUserInfo': jsonEncode(<String, Object?>{'login': 'ada', 'id': 7}),
      };
      AdditionalUserInfo info = (await auth.signInWithCustomToken(
        't',
      )).additionalUserInfo!;
      expect(info.isNewUser, isTrue);
      expect(info.providerId, 'github.com');
      expect(info.username, 'ada');
      expect(info.profile, <String, Object?>{'login': 'ada', 'id': 7});
      expect('$info', isNot(contains('ada')));

      answer = <String, Object?>{
        'providerId': 'twitter.com',
        'screenName': 'ada_l',
        'rawUserInfo': '{}',
      };
      info = (await auth.signInWithCustomToken('t')).additionalUserInfo!;
      expect(info.username, 'ada_l');
      expect(info.isNewUser, isFalse);

      answer = <String, Object?>{
        'providerId': 'oidc.example',
        'rawUserInfo': 'not json',
      };
      info = (await auth.signInWithCustomToken('t')).additionalUserInfo!;
      expect(info.providerId, 'oidc.example');
      expect(info.profile, isEmpty);
      expect(info.username, isNull);
    });
  });

  test('UserCredential is the user, for the code of 0.2', () async {
    final UserCredential result = await auth.signInAnonymously();
    final AuthUser user = result;
    expect(user, auth.currentUser);
    expect(result.user, auth.currentUser);
    expect(result.user, isNot(isA<UserCredential>()));
    expect('$result', 'UserCredential(uid: anon-user, isAnonymous: true)');
  });

  group('reload', () {
    test('reads phone, tenant, metadata and providers', () async {
      await auth.signInWithEmailAndPassword(
        email: 'ada@example.com',
        password: 'secret',
      );
      backend.accounts['uid-of-ada@example.com'] = <String, Object?>{
        ...fullAccount,
        'tenantId': 'tenant-1',
      };
      await auth.reload();
      expect(auth.currentUser!.tenantId, 'tenant-1');
      expect(auth.currentUser!.providerData, hasLength(3));
      expect(auth.currentUser!.metadata, fullUser.metadata);
    });

    test('keeps the providers the answer does not list (JS SDK)', () async {
      backend.accounts['uid-of-ada@example.com'] = fullAccount;
      await auth.signInWithEmailAndPassword(
        email: 'ada@example.com',
        password: 'secret',
      );
      backend.accounts['uid-of-ada@example.com'] = <String, Object?>{
        ...fullAccount,
        'providerUserInfo': <Object?>[
          <String, Object?>{'providerId': 'password', 'rawId': 'new'},
        ],
      };
      await auth.reload();
      expect(
        auth.currentUser!.providerData.map((UserInfo i) => i.providerId),
        <String>['google.com', 'phone', 'password'],
      );
    });
  });

  group('storage', () {
    test('version 2 keeps the whole record', () async {
      backend.accounts['uid-of-ada@example.com'] = <String, Object?>{
        ...fullAccount,
        'tenantId': 'tenant-1',
      };
      auth.tenantId = 'tenant-1';
      await auth.signInWithEmailAndPassword(
        email: 'ada@example.com',
        password: 'secret',
      );
      final Map<String, Object?> stored =
          jsonDecode(backend.storage.read(key)!) as Map<String, Object?>;
      expect(stored['version'], 2);
      expect(stored['createdAt'], 1700000000000);
      expect(stored['tenantId'], 'tenant-1');
      expect(stored, isNot(contains('idToken')));
      await auth.dispose();

      auth = backend.create();
      await auth.restore();
      expect(auth.currentUser!.tenantId, 'tenant-1');
      expect(auth.currentUser!.metadata, fullUser.metadata);
      expect(auth.currentUser!.providerData, fullUser.providerData);
      expect(auth.currentUser!.phoneNumber, '+15555550100');
    });

    test(
      'a session stored by 0.2 is restored, and reload completes it',
      () async {
        // Exactly what 0.2.1 wrote.
        backend.storage.write(
          key,
          jsonEncode(<String, Object?>{
            'uid': 'uid-of-ada@example.com',
            'email': 'ada@example.com',
            'isAnonymous': false,
            'emailVerified': true,
            'displayName': 'Ada',
            'photoUrl': 'https://example.com/ada.png',
            'refreshToken': 'refresh:uid-of-ada@example.com',
          }),
        );
        await auth.restore();
        expect(
          auth.currentUser,
          const AuthUser(
            uid: 'uid-of-ada@example.com',
            email: 'ada@example.com',
            emailVerified: true,
            displayName: 'Ada',
            photoUrl: 'https://example.com/ada.png',
          ),
        );
        // Nothing is written back until something changes.
        expect(
          jsonDecode(backend.storage.read(key)!),
          isNot(contains('version')),
        );
        backend.accounts['uid-of-ada@example.com'] = fullAccount;
        await auth.reload();
        expect(auth.currentUser, fullUser);
        expect(
          (jsonDecode(backend.storage.read(key)!)
              as Map<String, Object?>)['version'],
          2,
        );
      },
    );

    test('a newer version is read for the fields this one knows', () async {
      backend.storage.write(
        key,
        jsonEncode(<String, Object?>{
          'version': 99,
          'uid': 'u',
          'refreshToken': 'refresh:u',
          'phoneNumber': '+1555',
          'somethingNew': <String, Object?>{},
        }),
      );
      await auth.restore();
      expect(auth.currentUser?.phoneNumber, '+1555');
    });
  });
}

final DateTime _created = DateTime.fromMillisecondsSinceEpoch(
  1700000000000,
  isUtc: true,
);
final DateTime _lastLogin = DateTime.fromMillisecondsSinceEpoch(
  1790000000000,
  isUtc: true,
);
