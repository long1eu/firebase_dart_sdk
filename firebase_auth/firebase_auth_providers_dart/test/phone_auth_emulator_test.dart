// Phone sign-in and SMS second factors against the Firebase Auth emulator: sending the code,
// signing in, linking, reauthenticating, updating the number, a wrong code, and enrolling and
// signing in with an SMS factor. The codes come from the emulator's GET
// /emulator/v1/projects/{project}/verificationCodes; the emulator needs no reCAPTCHA
// (AppVerification.none).
//
//     tool/start_auth_emulators.sh        # repository root; prints the export
//     FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9197 dart test test/phone_auth_emulator_test.dart
//
// Skipped unless FIREBASE_AUTH_EMULATOR_HOST is set. The project of the emulator is demo-test (the
// one tool/start_auth_emulators.sh starts), or FIREBASE_AUTH_EMULATOR_PROJECT. Never talks to the
// real service.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:test/test.dart';

final String? host = FirebaseUserAuth.emulatorHostFromEnvironment;
final String project =
    Platform.environment['FIREBASE_AUTH_EMULATOR_PROJECT'] ?? 'demo-test';

int _counter = 0;

/// A phone number no other test uses: +1 555 01xx xxxx.
String uniquePhone() {
  final int n = (DateTime.now().microsecondsSinceEpoch + _counter++) % 1000000;
  return '+155501${n.toString().padLeft(6, '0')}';
}

String uniqueEmail() =>
    'phone${DateTime.now().microsecondsSinceEpoch}x${_counter++}@example.com';

Matcher throwsAuth(Object code) => throwsA(
  isA<FirebaseAuthException>().having(
    (FirebaseAuthException e) => e.code,
    'code',
    code,
  ),
);

/// A request to the emulator's own endpoints, as the project owner.
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

/// The code the emulator "sent" for [verificationId].
Future<String> codeFor(String verificationId) async {
  final Map<String, Object?> body = await emulatorCall(
    'GET',
    'emulator/v1/projects/$project/verificationCodes',
  );
  final List<Map<String, Object?>> codes =
      (body['verificationCodes'] as List<Object?>? ?? const <Object?>[])
          .cast<Map<String, Object?>>()
          .where((Map<String, Object?> c) => c['sessionInfo'] == verificationId)
          .toList();
  expect(codes, isNotEmpty, reason: 'no code for the verification id');
  return codes.last['code']! as String;
}

void main() {
  final String? skip = host == null
      ? 'FIREBASE_AUTH_EMULATOR_HOST is not set (start the emulators with '
            'tool/start_auth_emulators.sh)'
      : null;

  final List<FirebaseUserAuth> created = <FirebaseUserAuth>[];

  FirebaseUserAuth create() {
    final FirebaseUserAuth auth = FirebaseUserAuth(
      apiKey: 'fake-api-key',
      emulatorHost: host,
      storage: InMemoryAuthStorage(),
    );
    created.add(auth);
    return auth;
  }

  tearDown(() async {
    for (final FirebaseUserAuth auth in created) {
      await auth.dispose();
    }
    created.clear();
  });

  Future<PhoneAuthCredential> credentialFor(
    FirebaseUserAuth auth,
    String phone,
  ) async {
    final String verificationId = await auth.verifyPhoneNumber(
      phone,
      appVerification: const AppVerification.none(),
    );
    return PhoneAuthProvider.credential(
      verificationId: verificationId,
      verificationCode: await codeFor(verificationId),
    );
  }

  group('phone sign-in on the emulator', () {
    test('sign in, sign in again, reauthenticate', () async {
      final String phone = uniquePhone();
      final FirebaseUserAuth auth = create();
      final UserCredential first = await auth.signInWithCredential(
        await credentialFor(auth, phone),
      );
      expect(first.additionalUserInfo!.isNewUser, isTrue);
      expect(first.additionalUserInfo!.providerId, 'phone');
      expect(first.user!.phoneNumber, phone);
      expect(auth.currentUser!.providerData.single.providerId, 'phone');

      await auth.signOut();
      final UserCredential again = await auth.signInWithCredential(
        await credentialFor(auth, phone),
      );
      expect(again.user!.uid, first.user!.uid);
      expect(again.additionalUserInfo!.isNewUser, isFalse);

      final UserCredential reauthenticated = await auth
          .reauthenticateWithCredential(await credentialFor(auth, phone));
      expect(reauthenticated.operationType, OperationType.reauthenticate);
      expect(auth.uid, first.user!.uid);

      await expectLater(
        auth.reauthenticateWithCredential(
          await credentialFor(auth, uniquePhone()),
        ),
        throwsAuth('user-mismatch'),
      );
    });

    test('a wrong code and a made-up verification id are refused', () async {
      final FirebaseUserAuth auth = create();
      final String verificationId = await auth.verifyPhoneNumber(
        uniquePhone(),
        appVerification: const AppVerification.none(),
      );
      await expectLater(
        auth.signInWithCredential(
          PhoneAuthProvider.credential(
            verificationId: verificationId,
            verificationCode: '000000',
          ),
        ),
        throwsAuth('invalid-verification-code'),
      );
      await expectLater(
        auth.signInWithCredential(
          PhoneAuthProvider.credential(
            verificationId: 'made-up',
            verificationCode: '123456',
          ),
        ),
        throwsAuth('invalid-verification-id'),
      );
      expect(auth.uid, isNull);
    });

    test('a number that is not E.164 is invalid-phone-number', () async {
      await expectLater(
        create().verifyPhoneNumber(
          '5555550100',
          appVerification: const AppVerification.none(),
        ),
        throwsAuth('invalid-phone-number'),
      );
    });

    test('link to an email account, then update the number', () async {
      final FirebaseUserAuth auth = create();
      await auth.createUserWithEmailAndPassword(
        email: uniqueEmail(),
        password: 'secret123',
      );
      final String phone = uniquePhone();
      final UserCredential linked = await auth.linkWithCredential(
        await credentialFor(auth, phone),
      );
      expect(linked.operationType, OperationType.link);
      expect(auth.currentUser!.phoneNumber, phone);
      expect(
        auth.currentUser!.providerData.map((UserInfo i) => i.providerId),
        containsAll(<String>['password', 'phone']),
      );

      final String next = uniquePhone();
      await auth.updatePhoneNumber(await credentialFor(auth, next));
      expect(auth.currentUser!.phoneNumber, next);
    });

    test('a number of another account cannot be linked', () async {
      final String phone = uniquePhone();
      final FirebaseUserAuth owner = create();
      await owner.signInWithCredential(await credentialFor(owner, phone));

      final FirebaseUserAuth auth = create();
      await auth.createUserWithEmailAndPassword(
        email: uniqueEmail(),
        password: 'secret123',
      );
      await expectLater(
        auth.linkWithCredential(await credentialFor(auth, phone)),
        throwsAuth(anyOf('credential-already-in-use', 'phone-number-exists')),
      );
    });
  }, skip: skip);

  group('SMS second factor on the emulator', () {
    test('enrol, sign in with the resolver, unenrol', () async {
      final String email = uniqueEmail();
      final FirebaseUserAuth auth = create();
      final UserCredential created = await auth.createUserWithEmailAndPassword(
        email: email,
        password: 'secret123',
      );
      // Enrolling needs a verified email address.
      await emulatorCall(
        'POST',
        'identitytoolkit.googleapis.com/v1/projects/$project/accounts:update',
        <String, Object?>{'localId': created.user!.uid, 'emailVerified': true},
      );
      await auth.reload();

      final String phone = uniquePhone();
      final String enrolmentId = await auth.startPhoneEnrollment(
        phone,
        appVerification: const AppVerification.none(),
      );
      await auth.finalizePhoneEnrollment(
        PhoneAuthProvider.credential(
          verificationId: enrolmentId,
          verificationCode: await codeFor(enrolmentId),
        ),
        displayName: 'Work phone',
      );
      final MultiFactorInfo factor = auth.currentUser!.enrolledFactors.single;
      expect(factor.factorId, MultiFactorInfo.phoneFactorId);
      expect(factor.phoneNumber, phone);

      final FirebaseUserAuth other = create();
      try {
        await other.signInWithEmailAndPassword(
          email: email,
          password: 'secret123',
        );
        fail('expected a FirebaseAuthMultiFactorException');
      } on FirebaseAuthMultiFactorException catch (e) {
        final String signInId = await e.resolver!.startPhoneSignIn(
          appVerification: const AppVerification.none(),
        );
        final UserCredential result = await e.resolver!.resolveSignInWithPhone(
          PhoneAuthProvider.credential(
            verificationId: signInId,
            verificationCode: await codeFor(signInId),
          ),
        );
        expect(result.user!.uid, created.user!.uid);
      }
      expect(other.uid, created.user!.uid);

      await other.unenrollMultiFactor(factor.uid);
      expect(other.currentUser!.enrolledFactors, isEmpty);
    });
  }, skip: skip);
}
