// The client features of 0.3 against the Firebase Auth emulator: the full user record, the auth streams, the
// language and tenants, email link sign-in, credentials (federated sign-in with fake ID tokens), linking and
// unlinking, and the ready-made storages. What the emulator does not implement is said in each group.
//
//     tool/start_auth_emulators.sh        # repository root; prints the export
//     FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9197 dart test test/auth_client_emulator_test.dart
//
// Skipped unless FIREBASE_AUTH_EMULATOR_HOST is set. The project of the emulator is demo-test (the one
// tool/start_auth_emulators.sh starts), or FIREBASE_AUTH_EMULATOR_PROJECT. Never talks to the real service.

@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:test/test.dart';

int _counter = 0;
String uniqueEmail([String prefix = 'user']) =>
    '$prefix${DateTime.now().microsecondsSinceEpoch}x${_counter++}@example.com';

Matcher throwsAuth(Object code) => throwsA(
  isA<FirebaseAuthException>().having(
    (FirebaseAuthException e) => e.code,
    'code',
    code,
  ),
);

final String? host = FirebaseUserAuth.emulatorHostFromEnvironment;
final String project =
    Platform.environment['FIREBASE_AUTH_EMULATOR_PROJECT'] ?? 'demo-test';

/// A request to the emulator's own REST endpoints (as the project owner where it needs one).
Future<Map<String, Object?>> emulatorCall(
  String method,
  String path, [
  Map<String, Object?>? body,
]) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.openUrl(
      method,
      Uri.parse('http://$host/$path'),
    );
    request.headers
      ..set('Authorization', 'Bearer owner')
      ..contentType = ContentType.json;
    if (body != null) {
      request.write(jsonEncode(body));
    }
    final HttpClientResponse response = await request.close();
    final String text = await utf8.decodeStream(response);
    return text.isEmpty
        ? <String, Object?>{}
        : jsonDecode(text) as Map<String, Object?>;
  } finally {
    client.close();
  }
}

/// The last action code the emulator "sent" to [email] for [requestType], as the whole entry (`oobCode`,
/// `oobLink`, ...).
Future<Map<String, Object?>> lastOob(String email, String requestType) async {
  final Map<String, Object?> body = await emulatorCall(
    'GET',
    'emulator/v1/projects/$project/oobCodes',
  );
  final List<Map<String, Object?>> codes =
      (body['oobCodes'] as List<Object?>? ?? const <Object?>[])
          .cast<Map<String, Object?>>()
          .where(
            (Map<String, Object?> c) =>
                c['email'] == email && c['requestType'] == requestType,
          )
          .toList();
  expect(codes, isNotEmpty, reason: 'no $requestType code for $email');
  return codes.last;
}

void main() {
  final String? skip = host == null
      ? 'FIREBASE_AUTH_EMULATOR_HOST is not set (start the emulators with tool/start_auth_emulators.sh)'
      : null;

  late InMemoryAuthStorage storage;
  final List<FirebaseUserAuth> created = <FirebaseUserAuth>[];

  FirebaseUserAuth create({AuthStorage? withStorage}) {
    final FirebaseUserAuth auth = FirebaseUserAuth(
      apiKey: 'fake-api-key',
      emulatorHost: host,
      storage: withStorage ?? storage,
    );
    created.add(auth);
    return auth;
  }

  setUp(() => storage = InMemoryAuthStorage());

  tearDown(() async {
    for (final FirebaseUserAuth auth in created) {
      await auth.dispose();
    }
    created.clear();
  });

  group('user record', () {
    test(
      'sign-up and sign-in read metadata, providers and AdditionalUserInfo',
      () async {
        final FirebaseUserAuth auth = create();
        final String email = uniqueEmail();
        final DateTime before = DateTime.now().toUtc().subtract(
          const Duration(seconds: 5),
        );
        final UserCredential signUp = await auth.createUserWithEmailAndPassword(
          email: email,
          password: 'correct horse',
        );
        expect(signUp.additionalUserInfo?.isNewUser, isTrue);
        expect(signUp.additionalUserInfo?.providerId, 'password');
        expect(signUp.metadata.creationTime, isNotNull);
        expect(signUp.metadata.creationTime!.isAfter(before), isTrue);
        expect(signUp.metadata.lastSignInTime, isNotNull);
        expect(signUp.providerData.single.providerId, 'password');
        expect(signUp.providerData.single.email, email);
        expect(signUp.providerData.single.uid, email);
        expect(signUp.phoneNumber, isNull);
        expect(signUp.tenantId, isNull);
        await auth.signOut();

        final UserCredential signIn = await auth.signInWithEmailAndPassword(
          email: email,
          password: 'correct horse',
        );
        expect(signIn.additionalUserInfo?.isNewUser, isFalse);
        expect(signIn.additionalUserInfo?.providerId, 'password');
        expect(signIn.metadata.creationTime, signUp.metadata.creationTime);

        final UserCredential anonymous = await auth.signInAnonymously();
        expect(anonymous.additionalUserInfo?.isNewUser, isTrue);
        expect(anonymous.additionalUserInfo?.providerId, isNull);
        expect(anonymous.providerData, isEmpty);
        expect(anonymous.isAnonymous, isTrue);
      },
      skip: skip,
    );

    test('the stored record is restored by a new instance', () async {
      final FirebaseUserAuth first = create();
      final UserCredential signUp = await first.createUserWithEmailAndPassword(
        email: uniqueEmail(),
        password: 'correct horse',
      );
      await first.updateProfile(displayName: 'Ada');
      final FirebaseUserAuth second = create();
      await second.restore();
      expect(second.currentUser!.metadata, signUp.metadata);
      expect(second.currentUser!.providerData, signUp.providerData);
      expect(second.currentUser!.displayName, 'Ada');
      await second.reload();
      // The emulator copies the new display name into the password provider's entry.
      expect(second.currentUser!.providerData.single.providerId, 'password');
      expect(second.currentUser!.providerData.single.displayName, 'Ada');
    }, skip: skip);
  });

  group('streams and state', () {
    test(
      'authStateChanges, idTokenChanges and updateCurrentUser with real tokens',
      () async {
        final FirebaseUserAuth first = create();
        final FirebaseUserAuth second = create(
          withStorage: InMemoryAuthStorage(),
        );
        final List<String?> states = <String?>[];
        final List<String?> tokens = <String?>[];
        second.authStateChanges().listen((AuthUser? u) => states.add(u?.uid));
        second.idTokenChanges().listen((AuthUser? u) => tokens.add(u?.uid));
        final UserCredential signedIn = await first
            .createUserWithEmailAndPassword(
              email: uniqueEmail(),
              password: 'correct horse',
            );
        await second.updateCurrentUser(first.currentUser);
        expect(second.uid, signedIn.uid);
        // The copied session refreshes on its own.
        await Future<void>.delayed(const Duration(milliseconds: 1100));
        final String token = (await second.getAccessToken(
          forceRefresh: true,
        )).token;
        expect(
          token,
          isNot((await first.getAccessToken(forceRefresh: false)).token),
        );
        await second.reload();
        await second.signOut();
        await Future<void>.delayed(Duration.zero);
        expect(states, <String?>[null, signedIn.uid, null]);
        expect(tokens, <String?>[null, signedIn.uid, signedIn.uid, null]);
        expect(first.uid, signedIn.uid);
      },
      skip: skip,
    );
  });

  group('tenants (the emulator implements them)', () {
    late String tenant;

    setUpAll(() async {
      if (host == null) {
        return;
      }
      final Map<String, Object?> created = await emulatorCall(
        'POST',
        'identitytoolkit.googleapis.com/v2/projects/$project/tenants',
        <String, Object?>{
          'displayName': 'tier1',
          'allowPasswordSignup': true,
          'enableEmailLinkSignin': true,
          'enableAnonymousUser': true,
        },
      );
      tenant = created['tenantId']! as String;
    });

    test('sign-up, sign-in and password reset in a tenant', () async {
      final FirebaseUserAuth auth = create()..tenantId = tenant;
      auth.languageCode = 'fr';
      final String email = uniqueEmail('tenant');
      final UserCredential signUp = await auth.createUserWithEmailAndPassword(
        email: email,
        password: 'correct horse',
      );
      expect(signUp.tenantId, tenant);
      final GetTokenResult token = await auth.getAccessToken(
        forceRefresh: false,
      );
      expect(
        (token.claims['firebase'] as Map<String, dynamic>)['tenant'],
        tenant,
      );
      await auth.signOut();
      expect(
        (await auth.signInWithEmailAndPassword(
          email: email,
          password: 'correct horse',
        )).tenantId,
        tenant,
      );
      expect((await auth.signInAnonymously()).tenantId, tenant);

      // The user does not exist for the project itself.
      final FirebaseUserAuth projectAuth = create();
      await expectLater(
        projectAuth.signInWithEmailAndPassword(
          email: email,
          password: 'correct horse',
        ),
        throwsAuth(anyOf('user-not-found', 'invalid-credential')),
      );

      await auth.sendPasswordResetEmail(email: email);
      final Map<String, Object?> codes = await emulatorCall(
        'GET',
        'emulator/v1/projects/$project/tenants/$tenant/oobCodes',
      );
      final List<Map<String, Object?>> entries =
          (codes['oobCodes']! as List<Object?>).cast<Map<String, Object?>>();
      final String code =
          entries.lastWhere(
                (Map<String, Object?> c) => c['email'] == email,
              )['oobCode']!
              as String;
      expect(await auth.verifyPasswordResetCode(code), email);
      await auth.confirmPasswordReset(code: code, newPassword: 'new horse');
      expect(
        (await auth.signInWithEmailAndPassword(
          email: email,
          password: 'new horse',
        )).uid,
        signUp.uid,
      );
    }, skip: skip);

    test('updateCurrentUser across tenants is a tenant-id-mismatch', () async {
      final FirebaseUserAuth tenantAuth = create()..tenantId = tenant;
      await tenantAuth.signInAnonymously();
      final FirebaseUserAuth projectAuth = create(
        withStorage: InMemoryAuthStorage(),
      );
      await expectLater(
        projectAuth.updateCurrentUser(tenantAuth.currentUser),
        throwsAuth('tenant-id-mismatch'),
      );
    }, skip: skip);
  });

  group('email link', () {
    const ActionCodeSettings settings = ActionCodeSettings(
      url: 'https://example.com/finish',
      handleCodeInApp: true,
    );

    Future<String> sendLink(FirebaseUserAuth auth, String email) async {
      await auth.sendSignInLinkToEmail(
        email: email,
        actionCodeSettings: settings,
      );
      return (await lastOob(email, 'EMAIL_SIGNIN'))['oobLink']! as String;
    }

    test('send, check and sign in with a link', () async {
      final FirebaseUserAuth auth = create();
      final String email = uniqueEmail('link');
      final String emailLink = await sendLink(auth, email);
      expect(auth.isSignInWithEmailLink(emailLink), isTrue);
      final ActionCodeURL url = ActionCodeURL.parseLink(emailLink)!;
      expect(url.continueUrl, 'https://example.com/finish');
      final ActionCodeInfo info = await auth.checkActionCode(url.code);
      expect(info.operation, ActionCodeOperation.emailSignIn);
      // The JS SDK allows an EMAIL_SIGNIN answer without the address; the emulator sends none.
      expect(info.email, anyOf(isNull, email));

      final UserCredential result = await auth.signInWithEmailLink(
        email: email,
        emailLink: emailLink,
      );
      expect(result.email, email);
      expect(result.emailVerified, isTrue);
      expect(result.additionalUserInfo?.isNewUser, isTrue);
      expect(result.providerData.single.providerId, 'password');
      // A link is used once.
      await auth.signOut();
      await expectLater(
        auth.signInWithEmailLink(email: email, emailLink: emailLink),
        throwsAuth('invalid-action-code'),
      );
      // A new link signs the same account in.
      final UserCredential again = await auth.signInWithEmailLink(
        email: email,
        emailLink: await sendLink(auth, email),
      );
      expect(again.uid, result.uid);
      expect(again.additionalUserInfo?.isNewUser, isFalse);
      // Reauthentication with a third link.
      final UserCredential reauthenticated = await auth
          .reauthenticateWithCredential(
            EmailAuthProvider.credentialWithLink(
              email: email,
              emailLink: await sendLink(auth, email),
            ),
          );
      expect(reauthenticated.uid, result.uid);
    }, skip: skip);

    test('link an email link and a password to anonymous users', () async {
      final FirebaseUserAuth auth = create();
      final UserCredential anonymous = await auth.signInAnonymously();
      final String email = uniqueEmail('linked');
      final UserCredential linked = await auth.linkWithCredential(
        EmailAuthProvider.credentialWithLink(
          email: email,
          emailLink: await sendLink(auth, email),
        ),
      );
      expect(linked.uid, anonymous.uid);
      expect(linked.isAnonymous, isFalse);
      expect(linked.email, email);
      expect(linked.providerData.single.providerId, 'password');
      await expectLater(
        auth.linkWithCredential(
          EmailAuthProvider.credential(email: email, password: 'secret1'),
        ),
        throwsAuth('provider-already-linked'),
      );

      final UserCredential second = await auth.signInAnonymously();
      final String other = uniqueEmail('linked');
      final UserCredential withPassword = await auth.linkWithCredential(
        EmailAuthProvider.credential(email: other, password: 'secret1'),
      );
      expect(withPassword.uid, second.uid);
      expect(withPassword.isAnonymous, isFalse);
      await auth.signOut();
      expect(
        (await auth.signInWithCredential(
          EmailAuthProvider.credential(email: other, password: 'secret1'),
        )).uid,
        second.uid,
      );
      await expectLater(
        auth.reauthenticateWithCredential(
          EmailAuthProvider.credential(email: email, password: 'nope'),
        ),
        throwsAuth(
          anyOf('user-mismatch', 'wrong-password', 'invalid-credential'),
        ),
      );
    }, skip: skip);
  });
}
