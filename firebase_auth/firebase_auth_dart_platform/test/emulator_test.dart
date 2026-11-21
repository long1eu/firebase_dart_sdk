// The official firebase_auth API against the Firebase Auth emulator.
//
//     tool/start_auth_emulators.sh
//     FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9197 flutter test test/emulator_test.dart
//
// Skipped unless FIREBASE_AUTH_EMULATOR_HOST is set. The project is demo-test.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_dart_platform/firebase_auth_dart_platform.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart'
    show InMemoryAuthStorage;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

final String? _host = Platform.environment['FIREBASE_AUTH_EMULATOR_HOST'];

/// A request to the emulator's own endpoints, as the project owner.
Future<Map<String, Object?>> _emulatorCall(
  String method,
  String path, [
  Map<String, Object?>? body,
]) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.openUrl(
      method,
      Uri.parse('http://$_host/$path'),
    );
    request.headers
      ..set('Authorization', 'Bearer owner')
      ..contentType = ContentType.json;
    if (body != null) {
      request.write(jsonEncode(body));
    }
    final String text = await utf8.decodeStream(await request.close());
    return text.isEmpty
        ? <String, Object?>{}
        : jsonDecode(text) as Map<String, Object?>;
  } finally {
    client.close();
  }
}

/// The SMS code the emulator "sent" for [verificationId].
Future<String> _codeFor(String verificationId) async {
  final Map<String, Object?> body = await _emulatorCall(
    'GET',
    'emulator/v1/projects/demo-test/verificationCodes',
  );
  return (body['verificationCodes']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .lastWhere(
            (Map<String, Object?> c) => c['sessionInfo'] == verificationId,
            orElse: () => throw StateError(
              'The emulator lists no verification code for the verification '
              'id that verifyPhoneNumber returned.',
            ),
          )['code']!
      as String;
}

/// The verification id of an SMS sent by `verifyPhoneNumber`.
Future<String> _sendCode(
  FirebaseAuth auth, {
  String? phoneNumber,
  MultiFactorSession? session,
  PhoneMultiFactorInfo? hint,
}) {
  final Completer<String> sent = Completer<String>();
  auth.verifyPhoneNumber(
    phoneNumber: phoneNumber,
    multiFactorSession: session,
    multiFactorInfo: hint,
    verificationCompleted: (_) {},
    verificationFailed: sent.completeError,
    codeSent: (String id, int? _) => sent.complete(id),
    codeAutoRetrievalTimeout: (_) {},
  );
  return sent.future;
}

/// A phone number no other run uses.
/// +1 555 and seven digits (a valid NANP length).
String _uniquePhone() =>
    '+1555${(DateTime.now().microsecondsSinceEpoch % 10000000).toString().padLeft(7, '0')}';

void main() {
  final String? skip = _host == null
      ? 'FIREBASE_AUTH_EMULATOR_HOST is not set (tool/start_auth_emulators.sh)'
      : null;
  late FirebaseAuth auth;
  final String email =
      'user${DateTime.now().microsecondsSinceEpoch}@example.com';

  setUpAll(() async {
    if (_host == null) {
      return;
    }
    // flutter_test replaces the HTTP client with one that answers 400.
    HttpOverrides.global = null;
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    FirebaseAuthDart.registerWith();
    FirebaseAuthDart.use(
      storageFor: (FirebaseApp app) => InMemoryAuthStorage(),
    );
    final FirebaseApp app = await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'fake-api-key',
        appId: '1:1:web:1',
        messagingSenderId: '1',
        projectId: 'demo-test',
      ),
    );
    auth = FirebaseAuth.instanceFor(app: app);
    final List<String> parts = _host!.split(':');
    await auth.useAuthEmulator(parts[0], int.parse(parts[1]));
  });

  tearDownAll(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('anonymous sign-in, then link a password', () async {
    final UserCredential anonymous = await auth.signInAnonymously();
    expect(anonymous.user!.isAnonymous, isTrue);
    final UserCredential linked = await anonymous.user!.linkWithCredential(
      EmailAuthProvider.credential(email: email, password: 'first-password'),
    );
    expect(linked.user!.uid, anonymous.user!.uid);
    expect(auth.currentUser!.isAnonymous, isFalse);
    expect(auth.currentUser!.email, email);
  }, skip: skip);

  test('sign out, sign in with the password, read the token', () async {
    await auth.signOut();
    expect(auth.currentUser, isNull);
    final UserCredential credential = await auth.signInWithEmailAndPassword(
      email: email,
      password: 'first-password',
    );
    final IdTokenResult token = await credential.user!.getIdTokenResult();
    expect(token.claims!['email'], email);
    expect(token.signInProvider, 'password');
  }, skip: skip);

  test('a wrong password maps to the official code', () async {
    await expectLater(
      auth.signInWithEmailAndPassword(email: email, password: 'nope-nope'),
      throwsA(
        isA<FirebaseAuthException>().having(
          (FirebaseAuthException e) => e.code,
          'code',
          anyOf('wrong-password', 'invalid-credential'),
        ),
      ),
    );
  }, skip: skip);

  // The emulator checks no reCAPTCHA: with it, the phone requests carry no
  // proof by default.
  test('phone: verifyPhoneNumber, then signInWithPhoneNumber', () async {
    await auth.signOut();
    final String phone = _uniquePhone();
    final String verificationId = await _sendCode(auth, phoneNumber: phone);
    final UserCredential first = await auth.signInWithCredential(
      PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: await _codeFor(verificationId),
      ),
    );
    expect(first.user!.phoneNumber, phone);
    await auth.signOut();

    final ConfirmationResult confirmation = await auth.signInWithPhoneNumber(
      phone,
    );
    final UserCredential again = await confirmation.confirm(
      await _codeFor(confirmation.verificationId),
    );
    expect(again.user!.uid, first.user!.uid);
    await auth.currentUser!.delete();
  }, skip: skip);

  test('phone: enrol an SMS second factor and sign in with it', () async {
    await auth.signOut();
    final String mfaEmail =
        'sms${DateTime.now().microsecondsSinceEpoch}@example.com';
    final UserCredential created = await auth.createUserWithEmailAndPassword(
      email: mfaEmail,
      password: 'secret123',
    );
    await _emulatorCall(
      'POST',
      'identitytoolkit.googleapis.com/v1/projects/demo-test/accounts:update',
      <String, Object?>{'localId': created.user!.uid, 'emailVerified': true},
    );
    await auth.currentUser!.reload();
    final MultiFactor multiFactor = auth.currentUser!.multiFactor;
    final String enrolId = await _sendCode(
      auth,
      phoneNumber: _uniquePhone(),
      session: await multiFactor.getSession(),
    );
    await multiFactor.enroll(
      PhoneMultiFactorGenerator.getAssertion(
        PhoneAuthProvider.credential(
          verificationId: enrolId,
          smsCode: await _codeFor(enrolId),
        ),
      ),
      displayName: 'Work phone',
    );
    expect(await multiFactor.getEnrolledFactors(), hasLength(1));

    await auth.signOut();
    try {
      await auth.signInWithEmailAndPassword(
        email: mfaEmail,
        password: 'secret123',
      );
      fail('expected a FirebaseAuthMultiFactorException');
    } on FirebaseAuthMultiFactorException catch (e) {
      final String signInId = await _sendCode(
        auth,
        session: e.resolver.session,
        hint: e.resolver.hints.single as PhoneMultiFactorInfo,
      );
      await e.resolver.resolveSignIn(
        PhoneMultiFactorGenerator.getAssertion(
          PhoneAuthProvider.credential(
            verificationId: signInId,
            smsCode: await _codeFor(signInId),
          ),
        ),
      );
    }
    expect(auth.currentUser!.uid, created.user!.uid);
    await auth.currentUser!.delete();
    await auth.signInWithEmailAndPassword(
      email: email,
      password: 'first-password',
    );
  }, skip: skip);

  test('profile update, Google credential, streams and delete', () async {
    final User user = auth.currentUser!;
    await user.updateDisplayName('Ada');
    await user.reload();
    expect(auth.currentUser!.displayName, 'Ada');

    // The emulator accepts an unsigned JSON ID token.
    final UserCredential google = await auth.currentUser!.linkWithCredential(
      GoogleAuthProvider.credential(
        idToken:
            '{"sub":"g-${DateTime.now().microsecondsSinceEpoch}",'
            '"email":"$email","email_verified":true}',
      ),
    );
    expect(
      google.user!.providerData.map((UserInfo i) => i.providerId),
      containsAll(<String>['password', 'google.com']),
    );

    final Future<User?> signedOut = auth.authStateChanges().firstWhere(
      (User? u) => u == null,
    );
    await auth.currentUser!.delete();
    expect(await signedOut, isNull);
    await expectLater(
      auth.signInWithEmailAndPassword(email: email, password: 'first-password'),
      throwsA(isA<FirebaseAuthException>()),
    );
  }, skip: skip);
}
