// Tests through the official firebase_auth API, against a fake backend: the
// registration, the mapping of each kind of call, and the members that throw.

import 'dart:async';
import 'dart:convert';
import 'dart:io'
    show
        FileSystemException,
        HttpClient,
        HttpClientRequest,
        HttpHeaders,
        Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_dart_platform/firebase_auth_dart_platform.dart';
import 'package:firebase_auth_dart_platform/src/convert.dart';
import 'package:firebase_auth_dart_platform/src/core.dart';
import 'package:firebase_auth_dart_platform/src/firebase_auth.dart'
    show DartAuthConfig;
import 'package:firebase_auth_dart_platform/src/storage.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart'
    show FirebaseAuthPlatform;
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart'
    as dart_auth
    show
        AppVerification,
        AuthStorage,
        FirebaseUserAuthDisposedError,
        OAuthCredential,
        OAuthLoopbackProvider,
        RecaptchaAction,
        RecaptchaV2Request;
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart'
    show InMemoryAuthStorage;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart'
    show FirebasePlatform, FirebaseAppPlatform, MethodChannelFirebase;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../firebase_auth_providers_dart/test/phone_platform.dart';
import '../../firebase_auth_providers_dart/test/totp_platform.dart';
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

/// The authorization URLs the provider flows presented, in order.
final List<Uri> presented = <Uri>[];

/// The providers of the provider flows: Google with a login hint, and GitHub.
final List<dart_auth.OAuthLoopbackProvider> oauthProviders =
    <dart_auth.OAuthLoopbackProvider>[
      dart_auth.OAuthLoopbackProvider.google(
        clientId: 'desktop-client',
        clientSecret: 'desktop-secret',
        loginHint: 'ada@example.com',
      ),
      dart_auth.OAuthLoopbackProvider.github(
        clientId: 'github-client',
        clientSecret: 'github-secret',
      ),
    ];

/// Plays the browser of a provider flow: the provider redirects to the
/// loopback server of the flow at once, with a code and the state it was sent.
Future<void> followRedirect(Uri url) async {
  presented.add(url);
  final Map<String, String> query = url.queryParameters;
  final Uri redirect = Uri.parse(query['redirect_uri']!).replace(
    queryParameters: <String, String>{
      'code': 'the-code',
      'state': query['state']!,
    },
  );
  final http.Client browser = http.Client();
  try {
    await browser.get(redirect);
  } finally {
    browser.close();
  }
}

/// Answers the code exchange at the token endpoints of Google and GitHub
/// (the client sends it through the http client of `use`); null for the
/// requests of the default backend.
http.Response? providerTokens(http.Request request) =>
    switch (request.url.host) {
      'oauth2.googleapis.com' => jsonResponse(<String, Object?>{
        'access_token': 'google-access-token',
        'id_token': unsignedJwt(<String, Object?>{
          'sub': 'google-sub',
          'nonce': presented.last.queryParameters['nonce'],
        }),
        'expires_in': 3599,
        'token_type': 'Bearer',
      }),
      'github.com' => jsonResponse(<String, Object?>{
        'access_token': 'github-access-token',
        'token_type': 'bearer',
        'scope': 'read:user',
      }),
      _ => null,
    };

/// Posts the form of a secure_flow page at [url] (the reCAPTCHA page posts a
/// `token`), as the page would.
Future<void> postPageForm(Uri url, Map<String, String> fields) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.postUrl(
      url.replace(query: ''),
    );
    request.headers
      ..set(HttpHeaders.contentTypeHeader, 'application/x-www-form-urlencoded')
      ..set('origin', 'http://${url.host}:${url.port}');
    request.write(
      Uri(
        queryParameters: <String, String>{
          'state': url.queryParameters['state']!,
          ...fields,
        },
      ).query,
    );
    await (await request.close()).drain<void>();
  } finally {
    client.close(force: true);
  }
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
      oauthProviders: oauthProviders,
      presenter: CallbackPresenter(followRedirect),
    );
  });

  tearDownAll(() {
    debugDefaultTargetPlatformOverride = null;
  });

  setUp(() {
    backend.requests.clear();
    backend.unhandled.clear();
    backend.override = null;
    presented.clear();
  });

  tearDown(() {
    expect(
      backend.unhandled,
      isEmpty,
      reason: 'requests the fake backend has no answer for',
    );
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
      expect(
        file,
        endsWith(
          'firebase_auth_dart_platform${Platform.pathSeparator}sessions.json',
        ),
      );
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

    test('User.refreshToken: the session token while that user is signed '
        'in', () async {
      final FirebaseAuth auth = await newAuth();
      final UserCredential result = await auth.signInAnonymously();
      final User kept = result.user!;
      expect(kept.refreshToken, 'refresh:anon-user');
      expect(auth.currentUser!.refreshToken, 'refresh:anon-user');
      await auth.signOut();
      expect(kept.refreshToken, isNull);
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
  });

  group('multi-factor', () {
    setUp(backend.factors.clear);

    /// Signs [email] in and enrols a TOTP factor named [name]; returns it.
    Future<MultiFactorInfo> enrollTotp(
      FirebaseAuth auth,
      String email, {
      String name = 'Phone',
    }) async {
      await auth.signInWithEmailAndPassword(email: email, password: 'p');
      final MultiFactor multiFactor = auth.currentUser!.multiFactor;
      final TotpSecret secret = await TotpMultiFactorGenerator.generateSecret(
        await multiFactor.getSession(),
      );
      await multiFactor.enroll(
        await TotpMultiFactorGenerator.getAssertionForEnrollment(
          secret,
          backend.totpCode,
        ),
        displayName: name,
      );
      return (await multiFactor.getEnrolledFactors()).single;
    }

    test('enrol a TOTP factor, list it, and unenrol it', () async {
      final FirebaseAuth auth = await newAuth();
      await auth.signInWithEmailAndPassword(
        email: 'enrol@example.com',
        password: 'p',
      );
      final MultiFactor multiFactor = auth.currentUser!.multiFactor;
      expect(await multiFactor.getEnrolledFactors(), isEmpty);

      final MultiFactorSession session = await multiFactor.getSession();
      expect(session.id, auth.currentUser!.uid);
      expect(backend.paths.where((p) => p.contains('mfa')), isEmpty);
      final TotpSecret secret = await TotpMultiFactorGenerator.generateSecret(
        session,
      );
      expect(secret.secretKey, totpSecretKey);
      expect(secret.codeLength, 6);
      expect(secret.codeIntervalSeconds, 30);
      expect(secret.hashingAlgorithm, 'SHA1');
      expect(
        secret.enrollmentCompletionDeadline,
        DateTime.utc(2026, 1, 1, 12, 10, 0, 123, 456),
      );

      await multiFactor.enroll(
        await TotpMultiFactorGenerator.getAssertionForEnrollment(
          secret,
          backend.totpCode,
        ),
        displayName: 'Phone',
      );
      expect(backend.bodyOf('mfaEnrollment:finalize'), <String, Object?>{
        'idToken': isA<String>(),
        'displayName': 'Phone',
        'totpVerificationInfo': <String, Object?>{
          'sessionInfo': 'enrollment-session',
          'verificationCode': backend.totpCode,
        },
      });
      final List<MultiFactorInfo> factors = await multiFactor
          .getEnrolledFactors();
      final MultiFactorInfo factor = factors.single;
      expect(factor, isA<TotpMultiFactorInfo>());
      expect(factor.factorId, 'totp');
      expect(factor.displayName, 'Phone');
      expect(factor.enrollmentTimestamp, 1767268800);

      await multiFactor.unenroll(multiFactorInfo: factor);
      expect(
        backend.bodyOf('mfaEnrollment:withdraw'),
        containsPair('mfaEnrollmentId', factor.uid),
      );
      expect(await multiFactor.getEnrolledFactors(), isEmpty);
      await expectLater(
        multiFactor.unenroll(factorUid: factor.uid),
        throwsAuthCode('multi-factor-info-not-found'),
      );
    });

    test('the QR code URL defaults to the email and the app name', () async {
      final FirebaseAuth auth = await newAuth();
      await auth.signInWithEmailAndPassword(
        email: 'qr@example.com',
        password: 'p',
      );
      final TotpSecret secret = await TotpMultiFactorGenerator.generateSecret(
        await auth.currentUser!.multiFactor.getSession(),
      );
      expect(
        await secret.generateQrCodeUrl(),
        'otpauth://totp/${auth.app.name}:qr@example.com'
        '?secret=$totpSecretKey&issuer=${auth.app.name}'
        '&algorithm=SHA1&digits=6',
      );
      expect(
        await secret.generateQrCodeUrl(accountName: 'ada', issuer: 'My App'),
        'otpauth://totp/My%20App:ada?secret=$totpSecretKey'
        '&issuer=My%20App&algorithm=SHA1&digits=6',
      );
      await expectLater(
        secret.openInOtpApp('otpauth://totp/x'),
        throwsAuthCode('unimplemented'),
      );
    });

    test('a wrong code or a missing display name does not enrol', () async {
      final FirebaseAuth auth = await newAuth();
      await auth.signInWithEmailAndPassword(
        email: 'wrong@example.com',
        password: 'p',
      );
      final MultiFactor multiFactor = auth.currentUser!.multiFactor;
      final TotpSecret secret = await TotpMultiFactorGenerator.generateSecret(
        await multiFactor.getSession(),
      );
      await expectLater(
        multiFactor.enroll(
          await TotpMultiFactorGenerator.getAssertionForEnrollment(
            secret,
            '000000',
          ),
          displayName: 'Phone',
        ),
        throwsAuthCode('invalid-verification-code'),
      );
      backend.requests.clear();
      await expectLater(
        multiFactor.enroll(
          await TotpMultiFactorGenerator.getAssertionForEnrollment(
            secret,
            backend.totpCode,
          ),
        ),
        throwsAuthCode('argument-error'),
      );
      expect(backend.requests, isEmpty);
      expect(await multiFactor.getEnrolledFactors(), isEmpty);
    });

    test('a TOTP code resolves a sign-in with a second factor', () async {
      final FirebaseAuth auth = await newAuth();
      final MultiFactorInfo factor = await enrollTotp(auth, 'mfa@example.com');
      // A second authenticator app: the resolver must name the factor.
      backend.factors['uid-of-mfa@example.com']!.insert(0, <String, Object?>{
        'mfaEnrollmentId': 'totp-other',
        'totpInfo': <String, Object?>{},
      });
      await auth.signOut();
      try {
        await auth.signInWithEmailAndPassword(
          email: 'mfa@example.com',
          password: 'p',
        );
        fail('expected a FirebaseAuthMultiFactorException');
      } on FirebaseAuthMultiFactorException catch (e) {
        expect(e.code, 'multi-factor-auth-required');
        expect(e.resolver.hints, everyElement(isA<TotpMultiFactorInfo>()));
        expect(
          <String>[for (final h in e.resolver.hints) h.uid],
          <String>['totp-other', factor.uid],
        );
        // The session id is opaque: never the pending credential.
        expect(e.resolver.session.id, matches(RegExp(r'^sign-in-\d+$')));
        expect(
          '${e.resolver.session.id} ${e.resolver}',
          isNot(contains('pending')),
        );
        expect(auth.currentUser, isNull);
        await expectLater(
          e.resolver.resolveSignIn(
            await TotpMultiFactorGenerator.getAssertionForSignIn(
              factor.uid,
              '000000',
            ),
          ),
          throwsAuthCode('invalid-verification-code'),
        );
        final UserCredential result = await e.resolver.resolveSignIn(
          await TotpMultiFactorGenerator.getAssertionForSignIn(
            factor.uid,
            backend.totpCode,
          ),
        );
        expect(result.user!.uid, 'uid-of-mfa@example.com');
        expect(auth.currentUser!.uid, 'uid-of-mfa@example.com');
        expect(backend.bodyOf('mfaSignIn:finalize'), <String, Object?>{
          'mfaPendingCredential': 'pending:uid-of-mfa@example.com',
          'mfaEnrollmentId': factor.uid,
          'totpVerificationInfo': <String, Object?>{
            'verificationCode': backend.totpCode,
          },
        });
      }
    });

    test('a reauthentication with a second factor is resolved', () async {
      final FirebaseAuth auth = await newAuth();
      final MultiFactorInfo factor = await enrollTotp(
        auth,
        'reauth@example.com',
      );
      final User user = auth.currentUser!;
      try {
        await user.reauthenticateWithCredential(
          EmailAuthProvider.credential(
            email: 'reauth@example.com',
            password: 'p',
          ),
        );
        fail('expected a FirebaseAuthMultiFactorException');
      } on FirebaseAuthMultiFactorException catch (e) {
        final UserCredential result = await e.resolver.resolveSignIn(
          await TotpMultiFactorGenerator.getAssertionForSignIn(
            factor.uid,
            backend.totpCode,
          ),
        );
        expect(result.user!.uid, user.uid);
        expect(auth.currentUser!.uid, user.uid);
      }
    });

    test('wrong assertions, sessions and secrets are refused', () async {
      final FirebaseAuth auth = await newAuth();
      final MultiFactorInfo factor = await enrollTotp(auth, 'kind@example.com');
      final MultiFactor multiFactor = auth.currentUser!.multiFactor;
      await expectLater(
        TotpMultiFactorGenerator.generateSecret(MultiFactorSession('made-up')),
        throwsAuthCode('argument-error'),
      );
      await expectLater(
        multiFactor.enroll(
          await TotpMultiFactorGenerator.getAssertionForSignIn(
            factor.uid,
            backend.totpCode,
          ),
          displayName: 'Phone',
        ),
        throwsAuthCode('argument-error'),
      );
      final TotpSecret secret = await TotpMultiFactorGenerator.generateSecret(
        await multiFactor.getSession(),
      );
      await auth.signOut();
      try {
        await auth.signInWithEmailAndPassword(
          email: 'kind@example.com',
          password: 'p',
        );
        fail('expected a FirebaseAuthMultiFactorException');
      } on FirebaseAuthMultiFactorException catch (e) {
        await expectLater(
          e.resolver.resolveSignIn(
            await TotpMultiFactorGenerator.getAssertionForEnrollment(
              secret,
              backend.totpCode,
            ),
          ),
          throwsAuthCode('argument-error'),
        );
      }
    });

    test('a signed-out user cannot use its multi-factor API', () async {
      final FirebaseAuth auth = await newAuth();
      await auth.signInWithEmailAndPassword(
        email: 'gone@example.com',
        password: 'p',
      );
      final MultiFactor multiFactor = auth.currentUser!.multiFactor;
      final MultiFactorSession session = await multiFactor.getSession();
      await auth.signOut();
      await expectLater(
        multiFactor.getSession(),
        throwsAuthCode('no-current-user'),
      );
      await expectLater(
        multiFactor.getEnrolledFactors(),
        throwsAuthCode('no-current-user'),
      );
      await expectLater(
        TotpMultiFactorGenerator.generateSecret(session),
        throwsAuthCode('no-current-user'),
      );
    });
  });

  group('provider sign-in', () {
    test(
      'signInWithProvider runs the loopback flow of the provider passed to '
      'use, with the scopes and parameters of the FlutterFire provider',
      () async {
        final FirebaseAuth auth = await newAuth();
        backend.override = providerTokens;
        final UserCredential result = await auth.signInWithProvider(
          GoogleAuthProvider()
            ..addScope('https://www.googleapis.com/auth/drive.file')
            ..addScope('email')
            ..setCustomParameters(<String, String>{
              'prompt': 'consent',
              'login_hint': 'bob@example.com',
            }),
        );
        expect(result.user!.uid, 'google-user');
        expect(result.credential?.providerId, 'google.com');

        final Uri url = presented.single;
        expect(url.host, 'accounts.google.com');
        expect(url.queryParameters['client_id'], 'desktop-client');
        expect(
          url.queryParameters['scope'],
          'openid email profile https://www.googleapis.com/auth/drive.file',
        );
        expect(url.queryParameters['prompt'], 'consent');
        expect(url.queryParameters['login_hint'], 'bob@example.com');
        final Map<String, String> exchange = backend.requests
            .singleWhere(
              (http.Request r) => r.url.host == 'oauth2.googleapis.com',
            )
            .bodyFields;
        expect(exchange['code'], 'the-code');
        expect(exchange['client_secret'], 'desktop-secret');
        final Map<String, String> post = Uri.splitQueryString(
          backend.bodyOf('accounts:signInWithIdp')['postBody']! as String,
        );
        expect(post['providerId'], 'google.com');
        expect(post['access_token'], 'google-access-token');

        // The provider passed to use is not changed by the request.
        await auth.signOut();
        await auth.signInWithProvider(GoogleAuthProvider());
        expect(presented.last.queryParameters['scope'], 'openid email profile');
        expect(presented.last.queryParameters['login_hint'], 'ada@example.com');
        expect(presented.last.queryParameters.containsKey('prompt'), isFalse);
      },
    );

    test(
      'linkWithProvider and reauthenticateWithProvider act on the user',
      () async {
        final FirebaseAuth auth = await newAuth();
        await auth.signInAnonymously();
        final String uid = auth.currentUser!.uid;
        backend.override = (http.Request r) =>
            providerTokens(r) ??
            (r.url.path.endsWith('accounts:signInWithIdp')
                ? jsonResponse(<String, Object?>{
                    'localId': uid,
                    'providerId': 'github.com',
                    'idToken': idToken(uid, provider: 'github.com'),
                    'refreshToken': 'refresh:$uid',
                    'expiresIn': '3600',
                  })
                : null);

        final UserCredential linked = await auth.currentUser!.linkWithProvider(
          GithubAuthProvider()..addScope('repo'),
        );
        expect(linked.user!.uid, uid);
        final Uri url = presented.single;
        expect(url.host, 'github.com');
        expect(url.queryParameters['client_id'], 'github-client');
        expect(url.queryParameters['scope'], 'read:user user:email repo');
        expect(url.queryParameters.containsKey('nonce'), isFalse);
        final Map<String, Object?> body = backend.bodyOf(
          'accounts:signInWithIdp',
        );
        expect(body['idToken'], isNotNull);
        final Map<String, String> post = Uri.splitQueryString(
          body['postBody']! as String,
        );
        expect(post['providerId'], 'github.com');
        expect(post['access_token'], 'github-access-token');

        final UserCredential again = await auth.currentUser!
            .reauthenticateWithProvider(GithubAuthProvider());
        expect(again.user!.uid, uid);
        expect(presented, hasLength(2));
        expect(presented.last.queryParameters['scope'], 'read:user user:email');
      },
    );

    test('a provider id that was not passed to use throws unimplemented '
        'before the browser opens', () async {
      final FirebaseAuth auth = await newAuth();
      await expectLater(
        auth.signInWithProvider(OAuthProvider('oidc.none')),
        throwsA(
          isA<FirebaseAuthException>()
              .having(
                (FirebaseAuthException e) => e.code,
                'code',
                'unimplemented',
              )
              .having(
                (FirebaseAuthException e) => e.message,
                'message',
                allOf(contains('"oidc.none"'), contains('oauthProviders')),
              ),
        ),
      );
      await auth.signInAnonymously();
      await expectLater(
        auth.currentUser!.linkWithProvider(MicrosoftAuthProvider()),
        throwsAuthCode('unimplemented'),
      );
      await expectLater(
        auth.currentUser!.reauthenticateWithProvider(YahooAuthProvider()),
        throwsAuthCode('unimplemented'),
      );
      expect(presented, isEmpty);
    });

    test(
      'errors of the flow are FirebaseAuthExceptions with their code',
      () async {
        final FirebaseAuth auth = await newAuth();
        backend.override = (http.Request r) =>
            r.url.host == 'oauth2.googleapis.com'
            ? jsonResponse(<String, Object?>{'error': 'invalid_grant'}, 400)
            : null;
        await expectLater(
          auth.signInWithProvider(GoogleAuthProvider()),
          throwsAuthCode('invalid-credential'),
        );
        expect(auth.currentUser, isNull);

        // A user that is no longer signed in fails before the browser opens.
        backend.override = null;
        await auth.signInAnonymously();
        final User stale = auth.currentUser!;
        await auth.signOut();
        presented.clear();
        await expectLater(
          stale.linkWithProvider(GoogleAuthProvider()),
          throwsAuthCode('no-current-user'),
        );
        expect(presented, isEmpty);
      },
    );

    test(
      'without a presenter, Android and iOS throw before the flow starts',
      () async {
        final DartAuthConfig configured = DartFirebaseAuth.config;
        DartFirebaseAuth.config = DartAuthConfig(
          httpClient: backend.client,
          storageFor: (FirebaseApp app) => InMemoryAuthStorage(),
          oauthProviders: <String, dart_auth.OAuthLoopbackProvider>{
            'google.com': oauthProviders.first,
          },
        );
        final FirebaseAuth auth;
        try {
          auth = await newAuth();
          await auth.signInAnonymously();
        } finally {
          DartFirebaseAuth.config = configured;
        }
        for (final TargetPlatform platform in <TargetPlatform>[
          TargetPlatform.android,
          TargetPlatform.iOS,
        ]) {
          debugDefaultTargetPlatformOverride = platform;
          try {
            await expectLater(
              auth.signInWithProvider(GoogleAuthProvider()),
              throwsA(
                isA<FirebaseAuthException>()
                    .having(
                      (FirebaseAuthException e) => e.code,
                      'code',
                      'operation-not-supported-in-this-environment',
                    )
                    .having(
                      (FirebaseAuthException e) => e.message,
                      'message',
                      contains('presenter'),
                    ),
              ),
            );
            await expectLater(
              auth.currentUser!.linkWithProvider(GoogleAuthProvider()),
              throwsAuthCode('operation-not-supported-in-this-environment'),
            );
          } finally {
            debugDefaultTargetPlatformOverride = TargetPlatform.linux;
          }
        }
        expect(
          backend.paths.where((String p) => p.endsWith('/token')),
          isEmpty,
        );
      },
    );

    test(
      'oauthProvidersFor adds to oauthProviders and replaces an id',
      () async {
        final DartAuthConfig shared = DartFirebaseAuth.config;
        final List<String> asked = <String>[];
        DartFirebaseAuth.config = DartAuthConfig(
          httpClient: shared.httpClient,
          storageFor: shared.storageFor,
          oauthProviders: shared.oauthProviders,
          presenter: shared.presenter,
          oauthProvidersFor: (FirebaseApp app) {
            asked.add(app.name);
            return <dart_auth.OAuthLoopbackProvider>[
              dart_auth.OAuthLoopbackProvider.google(
                clientId: 'client-of-${app.name}',
                clientSecret: 'secret-of-${app.name}',
              ),
            ];
          },
        );
        addTearDown(() => DartFirebaseAuth.config = shared);
        final FirebaseAuth auth = await newAuth();
        backend.override = providerTokens;
        await auth.signInWithProvider(GoogleAuthProvider());
        expect(
          presented.last.queryParameters['client_id'],
          'client-of-${auth.app.name}',
        );
        await auth.signOut();
        // GitHub comes from oauthProviders.
        await auth.signInWithProvider(GithubAuthProvider());
        expect(presented.last.queryParameters['client_id'], 'github-client');
        expect(asked, <String>[auth.app.name], reason: 'called once per app');
      },
    );

    test(
      'oauthProvidersFor with two providers of one id fails at first use',
      () async {
        final DartAuthConfig shared = DartFirebaseAuth.config;
        DartFirebaseAuth.config = DartAuthConfig(
          httpClient: shared.httpClient,
          storageFor: shared.storageFor,
          oauthProvidersFor: (FirebaseApp app) =>
              <dart_auth.OAuthLoopbackProvider>[
                oauthProviders.first,
                oauthProviders.first,
              ],
        );
        addTearDown(() => DartFirebaseAuth.config = shared);
        final FirebaseApp app = await Firebase.initializeApp(
          name: 'app${_apps++}',
          options: _options,
        );
        expect(() => DartFirebaseAuth.forApp(app), throwsArgumentError);
      },
    );

    test('use rejects two providers with one id', () {
      expect(
        () => FirebaseAuthDart.use(
          oauthProviders: <dart_auth.OAuthLoopbackProvider>[
            oauthProviders.first,
            oauthProviders.first,
          ],
        ),
        throwsArgumentError,
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

    test(
      'after setPersistence(SESSION) a new instance restores nothing',
      () async {
        final FirebaseAuth first = await newAuth();
        await first.signInAnonymously();
        await first.setPersistence(Persistence.SESSION);
        expect(first.currentUser?.uid, 'anon-user');
        final String name = first.app.name;
        await first.app.delete();
        final FirebaseApp app = await Firebase.initializeApp(
          name: name,
          options: _options,
        );
        final FirebaseAuth second = FirebaseAuth.instanceFor(app: app);
        expect(await second.authStateChanges().first, isNull);
      },
    );

    test('setPersistence works after a failed write of the storage', () async {
      storageOverrides['app$_apps'] = _FailingStorage();
      final FirebaseAuth auth = await newAuth();
      await auth.signInAnonymously();
      await auth.setPersistence(Persistence.NONE);
      expect(auth.currentUser?.uid, 'anon-user');
      await auth.setPersistence(Persistence.LOCAL);
      expect(auth.currentUser?.uid, 'anon-user');
      await auth.signOut();
      expect(auth.currentUser, isNull);
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
        guard<void>(DartFirebaseAuth(), () => throw StateError('state')),
        throwsAuthCode('internal-error'),
      );
      await expectLater(
        guard<void>(
          DartFirebaseAuth(),
          () => throw dart_auth.FirebaseUserAuthDisposedError(),
        ),
        throwsAuthCode('app-deleted'),
      );
      await expectLater(
        guard<void>(DartFirebaseAuth(), () => throw ArgumentError('argument')),
        throwsAuthCode('argument-error'),
      );
      await expectLater(
        guard<void>(
          DartFirebaseAuth(),
          () => throw UnsupportedError('no loopback server on the web'),
        ),
        throwsA(
          isA<FirebaseAuthException>()
              .having(
                (FirebaseAuthException e) => e.code,
                'code',
                'unimplemented',
              )
              .having(
                (FirebaseAuthException e) => e.message,
                'message',
                contains('no loopback server on the web'),
              ),
        ),
      );
      await expectLater(
        guard<void>(
          DartFirebaseAuth(),
          () => throw const FileSystemException('disk full'),
        ),
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

  group('phone', () {
    const String number = '+15555550100';

    setUp(() {
      backend.factors.clear();
      backend.phones.clear();
      backend.phone.requireProof = false;
    });
    tearDown(() => backend.phone.requireProof = true);

    /// What one verifyPhoneNumber call reported.
    Future<({String? id, FirebaseAuthException? error})> sendCode(
      FirebaseAuth auth, {
      String? phoneNumber = number,
      MultiFactorSession? session,
      PhoneMultiFactorInfo? hint,
    }) async {
      final Completer<({String? id, FirebaseAuthException? error})> done =
          Completer<({String? id, FirebaseAuthException? error})>();
      await auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        multiFactorSession: session,
        multiFactorInfo: hint,
        verificationCompleted: (_) => fail('no instant verification'),
        verificationFailed: (FirebaseAuthException e) =>
            done.complete((id: null, error: e)),
        codeSent: (String id, int? resendToken) {
          expect(resendToken, isNull);
          done.complete((id: id, error: null));
        },
        codeAutoRetrievalTimeout: (_) {},
      );
      return done.future;
    }

    /// The FirebaseAuth of a new app whose phone requests carry no proof.
    Future<FirebaseAuth> newPhoneAuth() async {
      final FirebaseAuth auth = await newAuth();
      await auth.setSettings(appVerificationDisabledForTesting: true);
      return auth;
    }

    Future<String> verificationIdOf(
      FirebaseAuth auth, {
      String phoneNumber = number,
      MultiFactorSession? session,
      PhoneMultiFactorInfo? hint,
    }) async {
      final ({String? id, FirebaseAuthException? error}) sent = await sendCode(
        auth,
        phoneNumber: phoneNumber,
        session: session,
        hint: hint,
      );
      expect(sent.error, isNull);
      return sent.id!;
    }

    test('verifyPhoneNumber sends the code without a proof after setSettings, '
        'then the credential signs in', () async {
      final FirebaseAuth auth = await newAuth();
      await auth.setSettings(appVerificationDisabledForTesting: true);
      final List<String> timedOut = <String>[];
      final Completer<String> sent = Completer<String>();
      await auth.verifyPhoneNumber(
        phoneNumber: number,
        timeout: const Duration(milliseconds: 10),
        verificationCompleted: (_) => fail('no instant verification'),
        verificationFailed: (FirebaseAuthException e) => fail('$e'),
        codeSent: (String id, int? _) => sent.complete(id),
        codeAutoRetrievalTimeout: timedOut.add,
      );
      final String verificationId = await sent.future;
      expect(backend.bodyOf('accounts:sendVerificationCode'), <String, Object?>{
        'phoneNumber': number,
      });
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(timedOut, <String>[verificationId]);

      final UserCredential result = await auth.signInWithCredential(
        PhoneAuthProvider.credential(
          verificationId: verificationId,
          smsCode: smsCode,
        ),
      );
      expect(result.user!.phoneNumber, number);
      expect(result.additionalUserInfo!.providerId, 'phone');
      expect(auth.currentUser!.providerData.single.providerId, 'phone');
    });

    test('the emulator gets no proof by default', () async {
      final FirebaseAuth auth = await newAuth();
      await auth.useAuthEmulator('127.0.0.1', 9099);
      await verificationIdOf(auth);
      expect(
        backend.requests.last.url.path,
        endsWith(
          '/identitytoolkit.googleapis.com/v1/accounts:sendVerificationCode',
        ),
      );
      expect(backend.bodyOf('accounts:sendVerificationCode'), <String, Object?>{
        'phoneNumber': number,
      });
    });

    test('the appVerification of use goes with every request', () async {
      backend.phone.requireProof = true;
      final DartAuthConfig shared = DartFirebaseAuth.config;
      final List<dart_auth.RecaptchaAction> actions =
          <dart_auth.RecaptchaAction>[];
      DartFirebaseAuth.config = DartAuthConfig(
        httpClient: backend.client,
        storageFor: (FirebaseApp app) => InMemoryAuthStorage(),
        appVerification: dart_auth.AppVerification.recaptchaV2((
          dart_auth.RecaptchaV2Request request,
        ) {
          expect(request.siteKey, recaptchaSiteKey);
          actions.add(request.action);
          return 'token-${actions.length}';
        }),
      );
      final FirebaseAuth auth;
      try {
        auth = await newAuth();
        // The instance of the app, created now, reads the configuration.
        await auth.setSettings();
      } finally {
        DartFirebaseAuth.config = shared;
      }
      final ConfirmationResult confirmation = await auth.signInWithPhoneNumber(
        number,
      );
      expect(backend.bodyOf('accounts:sendVerificationCode'), <String, Object?>{
        'phoneNumber': number,
        'recaptchaToken': 'token-1',
      });
      await confirmation.confirm(smsCode);
      expect(auth.currentUser!.phoneNumber, number);
      // The test switch wins over the configured proof.
      await auth.setSettings(appVerificationDisabledForTesting: true);
      backend.phone.requireProof = false;
      await verificationIdOf(auth);
      expect(actions, <dart_auth.RecaptchaAction>[
        dart_auth.RecaptchaAction.sendVerificationCode,
      ]);
    });

    /// The FirebaseAuth of a new app whose instance reads [config].
    Future<FirebaseAuth> authWith(DartAuthConfig config) async {
      final DartAuthConfig shared = DartFirebaseAuth.config;
      DartFirebaseAuth.config = config;
      try {
        final FirebaseAuth auth = await newAuth();
        // The instance of the app, created now, reads the configuration.
        await auth.setSettings();
        return auth;
      } finally {
        DartFirebaseAuth.config = shared;
      }
    }

    test(
      'the default reCAPTCHA page is shown by the presenter of use',
      () async {
        backend.phone.requireProof = true;
        final List<Uri> shown = <Uri>[];
        final FirebaseAuth auth = await authWith(
          DartAuthConfig(
            httpClient: backend.client,
            storageFor: (FirebaseApp app) => InMemoryAuthStorage(),
            presenter: CallbackPresenter((Uri url) async {
              shown.add(url);
              await postPageForm(url, <String, String>{'token': 'page-token'});
            }),
          ),
        );
        final ConfirmationResult confirmation = await auth
            .signInWithPhoneNumber(number);
        expect(shown, hasLength(1));
        expect(
          backend.bodyOf('accounts:sendVerificationCode')['recaptchaToken'],
          'page-token',
        );
        await confirmation.confirm(smsCode);
        expect(auth.currentUser!.phoneNumber, number);
      },
    );

    test('an error of a token source reaches verificationFailed', () async {
      final FirebaseAuth auth = await authWith(
        DartAuthConfig(
          httpClient: backend.client,
          storageFor: (FirebaseApp app) => InMemoryAuthStorage(),
          appVerification: dart_auth.AppVerification.recaptchaV2(
            (dart_auth.RecaptchaV2Request request) =>
                throw const FormatException('no token for +15555550100'),
          ),
        ),
      );
      final ({String? id, FirebaseAuthException? error}) sent = await sendCode(
        auth,
      );
      expect(sent.id, isNull);
      expect(sent.error!.code, 'internal-error');
      expect(sent.error!.message, contains('FormatException'));
      expect(sent.error!.message, isNot(contains('5555550100')));
    });

    test('verificationFailed gets the errors, without the number', () async {
      final FirebaseAuth auth = await newPhoneAuth();
      final ({String? id, FirebaseAuthException? error}) sent = await sendCode(
        auth,
        phoneNumber: '5555550100',
      );
      expect(sent.id, isNull);
      expect(sent.error!.code, 'invalid-phone-number');
      expect(sent.error!.message, isNot(contains('5555550100')));
      expect(sent.error!.phoneNumber, isNull);

      backend.phone.requireProof = true;
      final ({String? id, FirebaseAuthException? error}) refused =
          await sendCode(auth);
      expect(refused.error!.code, 'missing-app-credential');
      expect('${refused.error}', isNot(contains(number)));
    });

    test('signInWithPhoneNumber confirms with the code', () async {
      final FirebaseAuth auth = await newPhoneAuth();
      final ConfirmationResult confirmation = await auth.signInWithPhoneNumber(
        number,
      );
      expect(confirmation.verificationId, startsWith('session-'));
      await expectLater(
        confirmation.confirm('000000'),
        throwsAuthCode('invalid-verification-code'),
      );
      final UserCredential result = await confirmation.confirm(smsCode);
      expect(result.user!.uid, 'uid-of-$number');
      expect(result.additionalUserInfo!.isNewUser, isTrue);
    });

    test('linkWithPhoneNumber links the number to the user', () async {
      final FirebaseAuth auth = await newPhoneAuth();
      await auth.signInWithEmailAndPassword(
        email: 'link@example.com',
        password: 'p',
      );
      final ConfirmationResult confirmation = await auth.currentUser!
          .linkWithPhoneNumber(number);
      final UserCredential result = await confirmation.confirm(smsCode);
      expect(result.user!.uid, 'uid-of-link@example.com');
      expect(
        auth.currentUser!.providerData.map((UserInfo i) => i.providerId),
        containsAll(<String>['password', 'phone']),
      );
      expect(
        backend.bodyOf('accounts:signInWithPhoneNumber')['idToken'],
        isA<String>(),
      );
    });

    test('linkWithPhoneNumber refuses a user with a phone number before any '
        'SMS', () async {
      final FirebaseAuth auth = await newPhoneAuth();
      await auth.signInWithEmailAndPassword(
        email: 'twice@example.com',
        password: 'p',
      );
      backend.phones['uid-of-twice@example.com'] = '+15555550199';
      await expectLater(
        auth.currentUser!.linkWithPhoneNumber(number),
        throwsAuthCode('provider-already-linked'),
      );
      expect(
        backend.paths.where((String p) => p.endsWith('sendVerificationCode')),
        isEmpty,
      );
    });

    test('a number of another account comes with a credential that signs in '
        'to it', () async {
      final FirebaseAuth auth = await newPhoneAuth();
      await auth.signInWithEmailAndPassword(
        email: 'taken@example.com',
        password: 'p',
      );
      backend.phones['phone-owner'] = number;
      final ConfirmationResult confirmation = await auth.currentUser!
          .linkWithPhoneNumber(number);
      try {
        await confirmation.confirm(smsCode);
        fail('expected credential-already-in-use');
      } on FirebaseAuthException catch (e) {
        expect(e.code, 'credential-already-in-use');
        expect(e.credential, isA<DartPhoneProofCredential>());
        expect(
          '${e.credential} ${e.credential!.asMap()}',
          isNot(contains('5555550100')),
        );
        expect(e.message, isNot(contains('5555550100')));
        final UserCredential owner = await auth.signInWithCredential(
          e.credential!,
        );
        expect(owner.user!.uid, 'phone-owner');
      }
    });

    test('updatePhoneNumber and reauthenticateWithCredential', () async {
      final FirebaseAuth auth = await newPhoneAuth();
      await auth.signInWithEmailAndPassword(
        email: 'update@example.com',
        password: 'p',
      );
      await auth.currentUser!.updatePhoneNumber(
        PhoneAuthProvider.credential(
          verificationId: await verificationIdOf(auth),
          smsCode: smsCode,
        ),
      );
      expect(auth.currentUser!.phoneNumber, number);
      final UserCredential again = await auth.currentUser!
          .reauthenticateWithCredential(
            PhoneAuthProvider.credential(
              verificationId: await verificationIdOf(auth),
              smsCode: smsCode,
            ),
          );
      expect(again.user!.uid, 'uid-of-update@example.com');
      expect(
        backend.bodyOf('accounts:signInWithPhoneNumber')['operation'],
        'REAUTH',
      );
      backend.phones['someone-else'] = '+15555550199';
      await expectLater(
        auth.currentUser!.updatePhoneNumber(
          PhoneAuthProvider.credential(
            verificationId: await verificationIdOf(
              auth,
              phoneNumber: '+15555550199',
            ),
            smsCode: smsCode,
          ),
        ),
        throwsAuthCode('credential-already-in-use'),
      );
    });

    test('a credential from a token is an argument-error', () async {
      final FirebaseAuth auth = await newAuth();
      await expectLater(
        auth.signInWithCredential(PhoneAuthProvider.credentialFromToken(1)),
        throwsAuthCode('argument-error'),
      );
    });

    test('the RecaptchaVerifier renders nothing', () async {
      final RecaptchaVerifier verifier = RecaptchaVerifier(
        auth: FirebaseAuthPlatform.instance,
      );
      expect(verifier.type, 'recaptcha');
      expect(await verifier.render(), 0);
      verifier.clear();
      await expectLater(verifier.verify(), throwsAuthCode('unimplemented'));
    });

    test('enrol an SMS factor and sign in with it', () async {
      final FirebaseAuth auth = await newPhoneAuth();
      await auth.signInWithEmailAndPassword(
        email: 'sms@example.com',
        password: 'p',
      );
      final MultiFactor multiFactor = auth.currentUser!.multiFactor;
      final String enrolId = await verificationIdOf(
        auth,
        session: await multiFactor.getSession(),
      );
      expect(
        backend.bodyOf('mfaEnrollment:start')['phoneEnrollmentInfo'],
        <String, Object?>{'phoneNumber': number},
      );
      await multiFactor.enroll(
        PhoneMultiFactorGenerator.getAssertion(
          PhoneAuthProvider.credential(
            verificationId: enrolId,
            smsCode: smsCode,
          ),
        ),
        displayName: 'Work phone',
      );
      final MultiFactorInfo factor =
          (await multiFactor.getEnrolledFactors()).single;
      expect(factor, isA<PhoneMultiFactorInfo>());
      expect((factor as PhoneMultiFactorInfo).phoneNumber, number);
      expect(factor.displayName, 'Work phone');

      await auth.signOut();
      try {
        await auth.signInWithEmailAndPassword(
          email: 'sms@example.com',
          password: 'p',
        );
        fail('expected a FirebaseAuthMultiFactorException');
      } on FirebaseAuthMultiFactorException catch (e) {
        final PhoneMultiFactorInfo hint =
            e.resolver.hints.single as PhoneMultiFactorInfo;
        expect(hint.phoneNumber, '+*******0100');
        final String signInId = await verificationIdOf(
          auth,
          session: e.resolver.session,
          hint: hint,
        );
        expect(
          backend.bodyOf('mfaSignIn:start')['mfaEnrollmentId'],
          factor.uid,
        );
        final UserCredential result = await e.resolver.resolveSignIn(
          PhoneMultiFactorGenerator.getAssertion(
            PhoneAuthProvider.credential(
              verificationId: signInId,
              smsCode: smsCode,
            ),
          ),
        );
        expect(result.user!.uid, 'uid-of-sms@example.com');
      }
      expect(auth.currentUser!.uid, 'uid-of-sms@example.com');
    });

    test(
      'verifyPhoneNumber refuses a session of another implementation',
      () async {
        final FirebaseAuth auth = await newAuth();
        final ({String? id, FirebaseAuthException? error}) sent =
            await sendCode(auth, session: MultiFactorSession('elsewhere'));
        expect(sent.error!.code, 'argument-error');
      },
    );

    test('getAssertion refuses a credential from a token', () {
      expect(
        () => PhoneMultiFactorGenerator.getAssertion(
          PhoneAuthProvider.credentialFromToken(1),
        ),
        throwsAuthCode('argument-error'),
      );
    });
  });

  group('not available', () {
    test('popup, redirect and the reCAPTCHA configuration throw '
        'unimplemented', () async {
      final FirebaseAuth auth = await newAuth();
      await expectLater(
        auth.signInWithPopup(GoogleAuthProvider()),
        throwsAuthCode('unimplemented'),
      );
      await expectLater(
        auth.initializeRecaptchaConfig(),
        throwsAuthCode('unimplemented'),
      );
      await auth.signInAnonymously();
      await expectLater(
        auth.currentUser!.linkWithPopup(GoogleAuthProvider()),
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
