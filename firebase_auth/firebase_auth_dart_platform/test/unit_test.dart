// Tests through the official firebase_auth API, against a fake backend: the
// registration, the mapping of each kind of call, and the members that throw.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show FileSystemException;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_dart_platform/firebase_auth_dart_platform.dart';
import 'package:firebase_auth_dart_platform/src/convert.dart';
import 'package:firebase_auth_dart_platform/src/core.dart';
import 'package:firebase_auth_dart_platform/src/storage.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart'
    show FirebaseAuthPlatform;
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart'
    as dart_auth
    show AuthStorage, OAuthCredential;
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart'
    show InMemoryAuthStorage;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart'
    show FirebasePlatform, FirebaseAppPlatform, MethodChannelFirebase;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'fake_backend.dart';

const FirebaseOptions _options = FirebaseOptions(
  apiKey: 'test-api-key',
  appId: '1:1:web:1',
  messagingSenderId: '1',
  projectId: 'demo-unit',
);

final FakeBackend backend = FakeBackend();
final Map<String, InMemoryAuthStorage> storages =
    <String, InMemoryAuthStorage>{};

/// A storage for the app of a name instead of its InMemoryAuthStorage.
final Map<String, dart_auth.AuthStorage> storageOverrides =
    <String, dart_auth.AuthStorage>{};

/// What registerWith left in place, before setUpAll calls use.
late FirebasePlatform coreAfterRegisterWith;
late AuthStorageFactory? storageAfterRegisterWith;

int _apps = 0;

/// The FirebaseAuth of a new app, so that every test starts signed out.
Future<FirebaseAuth> newAuth() async {
  final FirebaseApp app = await Firebase.initializeApp(
    name: 'app${_apps++}',
    options: _options,
  );
  return FirebaseAuth.instanceFor(app: app);
}

Matcher throwsAuthCode(String code) => throwsA(
  isA<FirebaseAuthException>().having(
    (FirebaseAuthException e) => e.code,
    'code',
    code,
  ),
);

void main() {
  setUpAll(() {
    // Pretend to be on Linux, where registerWith also installs the Dart core.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    FirebaseAuthDart.registerWith();
    coreAfterRegisterWith = FirebasePlatform.instance;
    storageAfterRegisterWith = DartFirebaseAuth.config.storageFor;
    FirebaseAuthDart.use(
      httpClient: backend.client,
      storageFor: (FirebaseApp app) =>
          storageOverrides[app.name] ??
          storages.putIfAbsent(app.name, InMemoryAuthStorage.new),
    );
  });

  tearDownAll(() {
    debugDefaultTargetPlatformOverride = null;
  });

  setUp(() {
    backend.requests.clear();
    backend.override = null;
  });

  group('registration', () {
    test('registerWith under flutter test installs neither the core nor the '
        'session file', () async {
      expect(coreAfterRegisterWith, isA<MethodChannelFirebase>());
      expect(storageAfterRegisterWith, isNotNull);
      final FirebaseApp app = await Firebase.initializeApp(
        name: 'registered',
        options: _options,
      );
      expect(storageAfterRegisterWith!(app), isA<InMemoryAuthStorage>());
    });

    test('use on Linux installs the auth and core implementations', () {
      expect(FirebaseAuthDart.isRegistered, isTrue);
      expect(FirebaseAuthPlatform.instance, isA<DartFirebaseAuth>());
      expect(FirebasePlatform.instance, isA<LinuxFirebaseCore>());
    });

    test('a forced core does not replace the Dart core', () {
      final FirebasePlatform before = FirebasePlatform.instance;
      installCoreIfNeeded(force: true);
      expect(FirebasePlatform.instance, same(before));
    });

    test('the default storage is one object for all the apps', () {
      expect(defaultStorage(), same(defaultStorage()));
    });

    test('a core installed by another package is kept', () {
      final FirebasePlatform before = FirebasePlatform.instance;
      final _OtherCore other = _OtherCore();
      FirebasePlatform.instance = other;
      installCoreIfNeeded();
      expect(FirebasePlatform.instance, same(other));
      FirebasePlatform.instance = before;
    });

    test('use after the first instance throws', () async {
      await newAuth().then((FirebaseAuth auth) => auth.currentUser);
      expect(FirebaseAuthDart.use, throwsStateError);
    });

    test('the default session file is per executable, under XDG', () {
      final String? file = defaultSessionFile();
      expect(file, isNotNull);
      expect(file, endsWith('firebase_auth_dart_platform/sessions.json'));
    });
  });

  group('sign-in', () {
    test('anonymous sign-in, the streams and sign-out', () async {
      final FirebaseAuth auth = await newAuth();
      final List<String?> states = <String?>[];
      final List<String?> users = <String?>[];
      final StreamSubscription<User?> s1 = auth.authStateChanges().listen(
        (User? user) => states.add(user?.uid),
      );
      final StreamSubscription<User?> s2 = auth.userChanges().listen(
        (User? user) => users.add(user?.uid),
      );
      await pumpEventQueue();

      final UserCredential result = await auth.signInAnonymously();
      expect(result.user!.uid, 'anon-user');
      expect(result.user!.isAnonymous, isTrue);
      expect(result.additionalUserInfo?.isNewUser, isTrue);
      expect(auth.currentUser!.uid, 'anon-user');
      expect(auth.currentUser!.displayName, 'Ada');
      expect(
        auth.currentUser!.metadata.creationTime,
        DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true),
      );
      expect(backend.paths, <String>[
        '/v1/accounts:signUp',
        '/v1/accounts:lookup',
      ]);

      await auth.signOut();
      await pumpEventQueue();
      expect(auth.currentUser, isNull);
      expect(states, <String?>[null, 'anon-user', null]);
      // userChanges starts with the current user, then one event per change.
      expect(users, <String?>[null, 'anon-user', null]);
      await s1.cancel();
      await s2.cancel();
    });

    test('userChanges: one event per sign-in, refresh, profile change and '
        'sign-out', () async {
      final FirebaseAuth auth = await newAuth();
      final List<String?> users = <String?>[];
      final StreamSubscription<User?> s = auth.userChanges().listen(
        (User? user) => users.add(user?.uid),
      );
      await pumpEventQueue();
      await auth.signInAnonymously();
      await pumpEventQueue();
      await auth.currentUser!.getIdToken(true);
      await pumpEventQueue();
      // The fake backend answers the update with a new ID token: the client
      // emits on both of its streams, this one once.
      await auth.currentUser!.updateDisplayName('Grace');
      await pumpEventQueue();
      await auth.signOut();
      await pumpEventQueue();
      expect(users, <String?>[
        null,
        'anon-user', // sign-in
        'anon-user', // refresh
        'anon-user', // profile change
        null, // sign-out
      ]);
      await s.cancel();
    });

    test('a failed write of the session keeps the user signed in', () async {
      storageOverrides['app$_apps'] = _FailingStorage();
      final FirebaseAuth auth = await newAuth();
      final List<String?> states = <String?>[];
      final StreamSubscription<User?> s = auth.authStateChanges().listen(
        (User? user) => states.add(user?.uid),
      );
      await pumpEventQueue();
      final UserCredential result = await auth.signInAnonymously();
      await pumpEventQueue();
      expect(result.user!.uid, 'anon-user');
      expect(auth.currentUser?.uid, 'anon-user');
      expect(states, <String?>[null, 'anon-user']);
      await auth.signOut();
      expect(auth.currentUser, isNull);
      await s.cancel();
    });

    test('email and password, with the provider data', () async {
      final FirebaseAuth auth = await newAuth();
      await auth.createUserWithEmailAndPassword(
        email: 'a@example.com',
        password: 'secret',
      );
      final User user = auth.currentUser!;
      expect(user.uid, 'uid-of-a@example.com');
      expect(user.email, 'a@example.com');
      expect(user.providerData.single.providerId, 'password');
      expect(user.providerData.single.email, 'a@example.com');
    });

    test('a Google credential goes to signInWithIdp', () async {
      final FirebaseAuth auth = await newAuth();
      final UserCredential result = await auth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: 'google-id-token'),
      );
      expect(result.user!.uid, 'google-user');
      final Map<String, Object?> body = backend.bodyOf(
        'accounts:signInWithIdp',
      );
      expect(
        body['postBody'],
        'id_token=google-id-token&providerId=google.com',
      );
      expect(result.credential?.providerId, 'google.com');
      expect(result.additionalUserInfo?.providerId, 'google.com');
    });

    test('backend errors keep their code', () async {
      final FirebaseAuth auth = await newAuth();
      backend.override = (http.Request r) => errorResponse('EMAIL_NOT_FOUND');
      await expectLater(
        auth.signInWithEmailAndPassword(email: 'x@example.com', password: 'p'),
        throwsAuthCode('user-not-found'),
      );
      backend.override = (http.Request r) => errorResponse('EMAIL_EXISTS');
      await expectLater(
        auth.createUserWithEmailAndPassword(
          email: 'x@example.com',
          password: 'p',
        ),
        throwsAuthCode('email-already-in-use'),
      );
    });

    test('a second factor gives the hints, and cannot be resolved', () async {
      final FirebaseAuth auth = await newAuth();
      backend.override = (http.Request r) => jsonResponse(<String, Object?>{
        'localId': 'uid',
        'mfaPendingCredential': 'pending',
        'mfaInfo': <Object?>[
          <String, Object?>{
            'mfaEnrollmentId': 'totp-1',
            'totpInfo': <String, Object?>{},
          },
        ],
      });
      try {
        await auth.signInWithEmailAndPassword(email: 'a@b.c', password: 'p');
        fail('expected a FirebaseAuthMultiFactorException');
      } on FirebaseAuthMultiFactorException catch (e) {
        expect(e.code, 'multi-factor-auth-required');
        expect(e.resolver.hints.single, isA<TotpMultiFactorInfo>());
        expect(e.resolver.hints.single.uid, 'totp-1');
        expect(e.resolver.session.id, 'pending');
      }
      // The assertion the resolver would need cannot be made yet.
      await expectLater(
        TotpMultiFactorGenerator.getAssertionForSignIn('totp-1', '123456'),
        throwsAuthCode('unimplemented'),
      );
    });
  });

  group('user', () {
    test('updateProfile: null removes, a missing field stays', () async {
      final FirebaseAuth auth = await newAuth();
      await auth.signInAnonymously();
      await auth.currentUser!.updateProfile(displayName: null);
      expect(
        backend.bodyOf('accounts:update'),
        containsPair('deleteAttribute', <Object?>['DISPLAY_NAME']),
      );
      expect(backend.bodyOf('accounts:update'), isNot(contains('photoUrl')));
      await auth.currentUser!.updatePhotoURL('https://example.com/a.png');
      expect(
        backend.bodyOf('accounts:update'),
        containsPair('photoUrl', 'https://example.com/a.png'),
      );
    });

    test('getIdTokenResult reads the claims', () async {
      final FirebaseAuth auth = await newAuth();
      await auth.signInAnonymously();
      final IdTokenResult result = await auth.currentUser!.getIdTokenResult();
      expect(result.signInProvider, 'anonymous');
      expect(result.claims?['sub'], 'anon-user');
      expect(result.expirationTime!.isAfter(DateTime.now()), isTrue);
      final String? forced = await auth.currentUser!.getIdToken(true);
      expect(forced, isNot(result.token));
      expect(backend.paths.last, '/v1/token');
    });

    test('a user that is no longer signed in throws no-current-user', () async {
      final FirebaseAuth auth = await newAuth();
      await auth.signInAnonymously();
      final User user = auth.currentUser!;
      await auth.signOut();
      await expectLater(user.reload(), throwsAuthCode('no-current-user'));
    });

    test('action codes and email links', () async {
      final FirebaseAuth auth = await newAuth();
      final ActionCodeInfo info = await auth.checkActionCode('code');
      expect(info.operation, ActionCodeInfoOperation.passwordReset);
      expect(info.data['email'], 'a@example.com');
      await auth.sendSignInLinkToEmail(
        email: 'a@example.com',
        actionCodeSettings: ActionCodeSettings(
          url: 'https://example.com/finish',
          handleCodeInApp: true,
        ),
      );
      expect(backend.bodyOf('accounts:sendOobCode'), <String, Object?>{
        'requestType': 'EMAIL_SIGNIN',
        'email': 'a@example.com',
        'continueUrl': 'https://example.com/finish',
        'canHandleCodeInApp': true,
      });
    });
  });

  group('settings', () {
    test('tenantId and languageCode reach the requests', () async {
      final FirebaseAuth auth = await newAuth();
      auth.tenantId = 'tenant-1';
      await auth.setLanguageCode('fr');
      expect(auth.tenantId, 'tenant-1');
      expect(auth.languageCode, 'fr');
      await auth.sendPasswordResetEmail(email: 'a@example.com');
      expect(backend.bodyOf('accounts:sendOobCode')['tenantId'], 'tenant-1');
      expect(backend.requests.last.headers['X-Firebase-Locale'], 'fr');
    });

    test('useAuthEmulator sends the requests to the emulator', () async {
      final FirebaseAuth auth = await newAuth();
      await auth.useAuthEmulator('localhost', 9099);
      await auth.signInAnonymously();
      expect(
        backend.requests.first.url.toString(),
        startsWith('http://localhost:9099/identitytoolkit.googleapis.com/'),
      );
    });

    test('setPersistence(NONE) moves the session out of the storage', () async {
      final FirebaseAuth auth = await newAuth();
      await auth.signInAnonymously();
      final InMemoryAuthStorage storage = storages[auth.app.name]!;
      final String key =
          'firebase_auth_providers_dart:'
          '${_options.apiKey}:${auth.app.name}';
      expect(storage.read(key), isNotNull);
      await auth.setPersistence(Persistence.NONE);
      expect(storage.read(key), isNull);
      expect(auth.currentUser?.uid, 'anon-user');
      await auth.setPersistence(Persistence.LOCAL);
      expect(jsonDecode(storage.read(key)!), isA<Map<String, Object?>>());
    });

    test('a stored session is restored by a new instance', () async {
      final FirebaseAuth first = await newAuth();
      await first.signInAnonymously();
      final String name = first.app.name;
      final InMemoryAuthStorage storage = storages[name]!;
      await first.app.delete();
      // A new app of the same name reads the same storage.
      final FirebaseApp app = await Firebase.initializeApp(
        name: name,
        options: _options,
      );
      expect(storages[name], same(storage));
      final FirebaseAuth second = FirebaseAuth.instanceFor(app: app);
      final User? restored = await second.authStateChanges().first;
      expect(restored?.uid, 'anon-user');
    });
  });

  group('conversions', () {
    test('an Apple credential keeps the name', () {
      final dart_auth.OAuthCredential credential =
          clientCredentialOf(
                AppleAuthProvider.credentialWithIDToken(
                  'apple-id-token',
                  'nonce',
                  AppleFullPersonName(givenName: 'Ada', familyName: 'Lovelace'),
                ),
              )
              as dart_auth.OAuthCredential;
      expect(credential.idToken, 'apple-id-token');
      expect(credential.rawNonce, 'nonce');
      expect(credential.appleFullPersonName?.givenName, 'Ada');
      expect(credential.appleFullPersonName?.familyName, 'Lovelace');
      final OAuthCredential back = credentialOf(credential)! as OAuthCredential;
      expect(back.appleFullPersonName?.familyName, 'Lovelace');
    });

    test('guard turns other errors into FirebaseAuthException', () async {
      await expectLater(
        guard<void>(() => throw StateError('state')),
        throwsAuthCode('internal-error'),
      );
      await expectLater(
        guard<void>(() => throw ArgumentError('argument')),
        throwsAuthCode('argument-error'),
      );
      await expectLater(
        guard<void>(() => throw const FileSystemException('disk full')),
        throwsAuthCode('internal-error'),
      );
    });
  });

  group('passthroughs', () {
    test('revokeAccessToken and revokeTokenWithAuthorizationCode reach the '
        'revoke endpoint', () async {
      final FirebaseAuth auth = await newAuth();
      await auth.signInAnonymously();
      backend.override = (http.Request request) =>
          request.url.path.endsWith('accounts:revokeToken')
          ? jsonResponse(<String, Object?>{})
          : null;
      await auth.revokeAccessToken('apple-access-token');
      expect(backend.bodyOf('accounts:revokeToken'), <String, Object?>{
        'providerId': 'apple.com',
        'tokenType': 'ACCESS_TOKEN',
        'token': 'apple-access-token',
        'idToken': isA<String>(),
      });
      await auth.revokeTokenWithAuthorizationCode('apple-code');
      expect(
        backend.bodyOf('accounts:revokeToken'),
        containsPair('tokenType', '3'),
      );
      expect(
        backend.bodyOf('accounts:revokeToken'),
        containsPair('token', 'apple-code'),
      );
      expect(
        backend.requests.last.url.path,
        endsWith('v2/accounts:revokeToken'),
      );
    });

    test('revoking without a user fails like the other user calls', () async {
      final FirebaseAuth auth = await newAuth();
      await expectLater(
        auth.revokeAccessToken('apple-access-token'),
        throwsA(isA<FirebaseAuthException>()),
      );
      expect(backend.paths, isNot(contains(endsWith('accounts:revokeToken'))));
    });

    test('a server error keeps the server code and the HTTP status', () async {
      final FirebaseAuth auth = await newAuth();
      backend.override = (http.Request request) =>
          jsonResponse(<String, Object?>{
            'error': <String, Object?>{'code': 400, 'message': 'EMAIL_EXISTS'},
          }, 400);
      await expectLater(
        auth.createUserWithEmailAndPassword(
          email: 'a@example.com',
          password: 'secret1',
        ),
        throwsA(
          isA<DartFirebaseAuthException>()
              .having(
                (DartFirebaseAuthException e) => e.code,
                'code',
                'email-already-in-use',
              )
              .having(
                (DartFirebaseAuthException e) => e.serverCode,
                'serverCode',
                'EMAIL_EXISTS',
              )
              .having(
                (DartFirebaseAuthException e) => e.httpStatus,
                'httpStatus',
                400,
              ),
        ),
      );
    });

    test('validatePassword checks against the fetched policy', () async {
      final FirebaseAuth auth = await newAuth();
      backend.override = (http.Request request) =>
          request.url.path.endsWith('passwordPolicy')
          ? jsonResponse(<String, Object?>{
              'customStrengthOptions': <String, Object?>{
                'minPasswordLength': 8,
                'containsNumericCharacter': true,
              },
              'allowedNonAlphanumericCharacters': <String>['!'],
              'enforcementState': 'ENFORCE',
              'schemaVersion': 1,
            })
          : null;
      final PasswordValidationStatus weak =
          await FirebaseAuthDart.validatePassword(auth.app, 'abc');
      expect(weak.isValid, isFalse);
      expect(weak.meetsMinPasswordLength, isFalse);
      expect(weak.meetsDigitsRequirement, isFalse);
      expect(weak.meetsLowercaseRequirement, isTrue);
      expect(weak.passwordPolicy.minPasswordLength, 8);
      expect(weak.passwordPolicy.containsNumericCharacter, isTrue);
      expect(weak.passwordPolicy.allowedNonAlphanumericCharacters, <String>[
        '!',
      ]);
      expect(weak.passwordPolicy.enforcementState, 'ENFORCE');
      final PasswordValidationStatus strong =
          await FirebaseAuthDart.validatePassword(auth.app, 'abcdefg1');
      expect(strong.isValid, isTrue);
      expect(
        backend.paths.where((String path) => path.endsWith('passwordPolicy')),
        hasLength(1),
        reason: 'the policy is cached',
      );
    });

    test(
      'validatePassword rejects an empty password without a request',
      () async {
        final FirebaseAuth auth = await newAuth();
        await expectLater(
          FirebaseAuthDart.validatePassword(auth.app, ''),
          throwsAuthCode('invalid-password'),
        );
        expect(backend.requests, isEmpty);
      },
    );
  });

  group('not available', () {
    test('provider, popup, redirect and phone throw unimplemented', () async {
      final FirebaseAuth auth = await newAuth();
      await expectLater(
        auth.signInWithProvider(GoogleAuthProvider()),
        throwsAuthCode('unimplemented'),
      );
      await expectLater(
        auth.signInWithPopup(GoogleAuthProvider()),
        throwsAuthCode('unimplemented'),
      );
      await expectLater(
        auth.signInWithCredential(
          PhoneAuthProvider.credential(verificationId: 'v', smsCode: '1'),
        ),
        throwsAuthCode('unimplemented'),
      );
      await expectLater(
        auth.verifyPhoneNumber(
          phoneNumber: '+15555550100',
          verificationCompleted: (_) {},
          verificationFailed: (_) {},
          codeSent: (_, _) {},
          codeAutoRetrievalTimeout: (_) {},
        ),
        throwsAuthCode('unimplemented'),
      );
      await auth.signInAnonymously();
      await expectLater(
        auth.currentUser!.linkWithProvider(GoogleAuthProvider()),
        throwsAuthCode('unimplemented'),
      );
      await expectLater(
        auth.currentUser!.multiFactor.getEnrolledFactors(),
        throwsAuthCode('unimplemented'),
      );
    });
  });
}

class _FailingStorage implements dart_auth.AuthStorage {
  @override
  String? read(String key) => null;

  @override
  Future<void> write(String key, String? value) async =>
      throw const FileSystemException('Read-only file system');
}

class _OtherCore extends FirebasePlatform {
  @override
  List<FirebaseAppPlatform> get apps => const <FirebaseAppPlatform>[];
}
