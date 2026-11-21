// SMS second factors against a fake Identity Platform: enrolment (mfaEnrollment:start and finalize
// with the phone fields), sign-in and reauthentication with the resolver (mfaSignIn:start and
// finalize), unenrolment, the request bodies, the multi-factor errors, and that no error holds a
// phone number, a verification id, an SMS code or a reCAPTCHA token.

import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'harness.dart';
import 'phone_harness.dart';

/// The multi-factor and phone errors the SMS factor calls can meet, and their codes.
const Map<String, String> multiFactorErrors = <String, String>{
  'INVALID_MFA_PENDING_CREDENTIAL': 'invalid-multi-factor-session',
  'MFA_ENROLLMENT_NOT_FOUND': 'multi-factor-info-not-found',
  'MISSING_MFA_ENROLLMENT_ID': 'missing-multi-factor-info',
  'MISSING_MFA_PENDING_CREDENTIAL': 'missing-multi-factor-session',
  'SECOND_FACTOR_EXISTS': 'second-factor-already-in-use',
  'SECOND_FACTOR_LIMIT_EXCEEDED': 'maximum-second-factor-count-exceeded',
  'UNSUPPORTED_FIRST_FACTOR': 'unsupported-first-factor',
  'UNVERIFIED_EMAIL': 'unverified-email',
  'CREDENTIAL_TOO_OLD_LOGIN_AGAIN': 'requires-recent-login',
  'INVALID_CODE': 'invalid-verification-code',
  'INVALID_SESSION_INFO': 'invalid-verification-id',
  'SESSION_EXPIRED': 'code-expired',
  'CODE_EXPIRED': 'code-expired',
  'MISSING_CODE': 'missing-verification-code',
  'MISSING_SESSION_INFO': 'missing-verification-id',
  'INVALID_PHONE_NUMBER': 'invalid-phone-number',
  'MISSING_PHONE_NUMBER': 'missing-phone-number',
  'QUOTA_EXCEEDED': 'quota-exceeded',
  'TOO_MANY_ATTEMPTS_TRY_LATER': 'too-many-requests',
  'MISSING_APP_CREDENTIAL': 'missing-app-credential',
  'INVALID_APP_CREDENTIAL': 'invalid-app-credential',
  'CAPTCHA_CHECK_FAILED': 'captcha-check-failed',
};

const String verificationIdSecret = 'session-secret-42';

/// Checks that [e] holds none of [secrets] in any field or in its text.
void expectNoSecrets(FirebaseAuthException e, List<String> secrets) {
  final String all = <String?>[
    e.message,
    e.serverCode,
    e.toString(),
    e.phoneNumber,
    '${e.serverResponse}',
    '${e.credential}',
    '${e.cause}',
  ].join('\n');
  for (final String secret in secrets) {
    expect(all, isNot(contains(secret)));
    if (secret.startsWith('+')) {
      expect(all, isNot(contains(secret.substring(1))));
    }
  }
  expect(e.phoneNumber, isNull);
  expect(e.serverResponse, isNull);
}

Future<T> caught<T extends Object>(Future<Object?> operation) async {
  try {
    await operation;
  } on Object catch (e) {
    if (e is T) {
      return e;
    }
    rethrow;
  }
  fail('Nothing was thrown');
}

void main() {
  late PhoneBackend server;
  late FakeBackend backend;
  late FirebaseUserAuth auth;
  int tokenCount = 0;
  final List<RecaptchaAction> actions = <RecaptchaAction>[];

  final AppVerification verification = AppVerification.recaptchaV2((
    RecaptchaV2Request request,
  ) {
    actions.add(request.action);
    return 'v2-token-${++tokenCount}';
  });

  setUp(() {
    server = PhoneBackend();
    backend = server.backend;
    auth = backend.create();
    tokenCount = 0;
    actions.clear();
  });

  tearDown(() => auth.dispose());

  Future<void> signIn() =>
      auth.signInWithEmailAndPassword(email: email, password: 'pw');

  Future<void> enroll({String number = phone, String? displayName}) async {
    final String verificationId = await auth.startPhoneEnrollment(
      number,
      appVerification: verification,
    );
    await auth.finalizePhoneEnrollment(
      PhoneAuthProvider.credential(
        verificationId: verificationId,
        verificationCode: code,
      ),
      displayName: displayName,
    );
  }

  group('enrolment', () {
    setUp(signIn);

    test('start sends the number with a token and returns the verification '
        'id', () async {
      final String verificationId = await auth.startPhoneEnrollment(
        phone,
        appVerification: verification,
      );
      expect(verificationId, startsWith('session-'));
      final Map<String, Object?> body = backend
          .bodiesOf('mfaEnrollment:start')
          .single;
      expect(body['idToken'], isA<String>());
      expect(body['phoneEnrollmentInfo'], <String, Object?>{
        'phoneNumber': phone,
        'recaptchaToken': 'v2-token-1',
      });
      expect(actions, <RecaptchaAction>[RecaptchaAction.mfaSmsEnrollment]);
    });

    test('finalize enrols the factor and renews the session', () async {
      final String verificationId = await auth.startPhoneEnrollment(
        phone,
        appVerification: verification,
      );
      await auth.finalizePhoneEnrollment(
        PhoneAuthProvider.credential(
          verificationId: verificationId,
          verificationCode: code,
        ),
        displayName: 'Work phone',
      );
      expect(
        backend.bodiesOf('mfaEnrollment:finalize').single,
        <String, Object?>{
          'idToken': isA<String>(),
          'displayName': 'Work phone',
          'phoneVerificationInfo': <String, Object?>{
            'sessionInfo': verificationId,
            'code': code,
          },
        },
      );
      final MultiFactorInfo factor = auth.currentUser!.enrolledFactors.single;
      expect(factor.factorId, MultiFactorInfo.phoneFactorId);
      expect(factor.phoneNumber, phone);
      expect(factor.displayName, 'Work phone');
      expect(
        backend.storage.read('firebase_auth_providers_dart:$apiKey'),
        contains('refresh:$uid:enrolled'),
      );
    });

    test('a rejected ID token is retried without a second reCAPTCHA', () async {
      final FutureOr<http.Response> Function(Map<String, Object?> body) start =
          backend.overrides['mfaEnrollment:start']!;
      int failures = 1;
      backend.on(
        'mfaEnrollment:start',
        (Map<String, Object?> body) =>
            failures-- > 0 ? errorResponse('INVALID_ID_TOKEN') : start(body),
      );
      final String verificationId = await auth.startPhoneEnrollment(
        phone,
        appVerification: verification,
      );
      expect(verificationId, startsWith('session-'));
      expect(backend.bodiesOf('mfaEnrollment:start'), hasLength(2));
      expect(actions, <RecaptchaAction>[RecaptchaAction.mfaSmsEnrollment]);
      expect(
        backend.bodiesOf('mfaEnrollment:start').last['phoneEnrollmentInfo'],
        containsPair('recaptchaToken', 'v2-token-1'),
      );
    });

    test('a display name may be left out', () async {
      await enroll();
      expect(
        backend.bodiesOf('mfaEnrollment:finalize').single,
        isNot(contains('displayName')),
      );
      expect(auth.currentUser!.enrolledFactors.single.displayName, isNull);
    });

    test('the tenant goes into both requests', () async {
      auth.tenantId = 'tenant-1';
      // The account read after the enrolment may refuse the user of another tenant; only the
      // requests count.
      await enroll().catchError((Object _) {});
      expect(
        backend.bodiesOf('mfaEnrollment:start').single['tenantId'],
        'tenant-1',
      );
      expect(
        backend.bodiesOf('mfaEnrollment:finalize').single['tenantId'],
        'tenant-1',
      );
    });

    test('a wrong code is refused and nothing changes', () async {
      final String verificationId = await auth.startPhoneEnrollment(
        phone,
        appVerification: verification,
      );
      final FirebaseAuthException e = await caught(
        auth.finalizePhoneEnrollment(
          PhoneAuthProvider.credential(
            verificationId: verificationId,
            verificationCode: '000000',
          ),
        ),
      );
      expect(e.code, 'invalid-verification-code');
      expectNoSecrets(e, <String>[verificationId, '000000']);
      expect(auth.currentUser!.enrolledFactors, isEmpty);
    });

    test('the same number twice is second-factor-already-in-use', () async {
      await enroll();
      await expectLater(enroll(), throwsAuth('second-factor-already-in-use'));
    });

    test(
      'an empty number or credential fails before anything is sent',
      () async {
        final int sent = backend.requests.length;
        await expectLater(
          auth.startPhoneEnrollment('', appVerification: verification),
          throwsAuth('missing-phone-number'),
        );
        await expectLater(
          auth.finalizePhoneEnrollment(
            PhoneAuthProvider.credential(
              verificationId: '',
              verificationCode: code,
            ),
          ),
          throwsAuth('missing-verification-id'),
        );
        expect(backend.requests.length, sent);
        expect(actions, isEmpty);
      },
    );

    test('needs a signed-in user', () async {
      await auth.signOut();
      await expectLater(
        auth.startPhoneEnrollment(phone, appVerification: verification),
        throwsAuth('null-user'),
      );
      await expectLater(
        auth.finalizePhoneEnrollment(
          PhoneAuthProvider.credential(
            verificationId: 'session-1',
            verificationCode: code,
          ),
        ),
        throwsAuth('null-user'),
      );
    });

    test('an answer without a verification id is an internal-error', () async {
      backend.on(
        'mfaEnrollment:start',
        (Map<String, Object?> body) => jsonResponse(<String, Object?>{
          'phoneSessionInfo': <String, Object?>{},
        }),
      );
      await expectLater(
        auth.startPhoneEnrollment(phone, appVerification: verification),
        throwsAuth('internal-error'),
      );
    });

    test('unenrolment removes an SMS factor', () async {
      await enroll();
      final String id = auth.currentUser!.enrolledFactors.single.uid;
      await auth.unenrollMultiFactor(id);
      expect(auth.currentUser!.enrolledFactors, isEmpty);
      expect(
        backend.bodiesOf('mfaEnrollment:withdraw').single['mfaEnrollmentId'],
        id,
      );
    });
  });

  group('sign-in with an SMS factor', () {
    setUp(() => server.addPhoneFactor(phone));

    Future<FirebaseAuthMultiFactorException> challenge() =>
        caught<FirebaseAuthMultiFactorException>(signIn());

    test('the exception lists the factor with a masked number', () async {
      final FirebaseAuthMultiFactorException e = await challenge();
      expect(e.message, FirebaseAuthMultiFactorException.defaultMessage);
      expect(e.hints.single.factorId, MultiFactorInfo.phoneFactorId);
      expect(e.hints.single.phoneNumber, '+*******0100');
      expect(e.toString(), isNot(contains(phone)));
    });

    test('the resolver sends the SMS and signs in with its code', () async {
      final FirebaseAuthMultiFactorException e = await challenge();
      final String verificationId = await e.resolver!.startPhoneSignIn(
        appVerification: verification,
      );
      expect(backend.bodiesOf('mfaSignIn:start').single, <String, Object?>{
        'mfaPendingCredential': 'pending:$uid',
        'mfaEnrollmentId': 'phone-1',
        'phoneSignInInfo': <String, Object?>{'recaptchaToken': 'v2-token-1'},
      });
      expect(actions, <RecaptchaAction>[RecaptchaAction.mfaSmsSignIn]);
      final UserCredential result = await e.resolver!.resolveSignInWithPhone(
        PhoneAuthProvider.credential(
          verificationId: verificationId,
          verificationCode: code,
        ),
      );
      expect(backend.bodiesOf('mfaSignIn:finalize').single, <String, Object?>{
        'mfaPendingCredential': 'pending:$uid',
        'phoneVerificationInfo': <String, Object?>{
          'sessionInfo': verificationId,
          'code': code,
        },
      });
      expect(result.user!.uid, uid);
      expect(result.operationType, OperationType.signIn);
      expect(auth.uid, uid);
    });

    test('a wrong code is refused and nobody is signed in', () async {
      final FirebaseAuthMultiFactorException e = await challenge();
      final String verificationId = await e.resolver!.startPhoneSignIn(
        appVerification: verification,
      );
      final FirebaseAuthException error = await caught(
        e.resolver!.resolveSignInWithPhone(
          PhoneAuthProvider.credential(
            verificationId: verificationId,
            verificationCode: '000000',
          ),
        ),
      );
      expect(error.code, 'invalid-verification-code');
      expectNoSecrets(error, <String>[verificationId, '000000']);
      expect(auth.currentUser, isNull);
    });

    test('with two SMS factors the enrolment id must be given', () async {
      server.addPhoneFactor('+15555550199', id: 'phone-2');
      final FirebaseAuthMultiFactorException e = await challenge();
      await expectLater(
        e.resolver!.startPhoneSignIn(appVerification: verification),
        throwsAuth('argument-error'),
      );
      await e.resolver!.startPhoneSignIn(
        enrollmentId: 'phone-2',
        appVerification: verification,
      );
      expect(
        backend.bodiesOf('mfaSignIn:start').single['mfaEnrollmentId'],
        'phone-2',
      );
    });

    test(
      'an enrolment id of a TOTP factor is multi-factor-info-not-found',
      () async {
        server.totp.addFactor(uid, <String, Object?>{
          'mfaEnrollmentId': 'totp-1',
          'totpInfo': <String, Object?>{},
        });
        final FirebaseAuthMultiFactorException e = await challenge();
        await expectLater(
          e.resolver!.startPhoneSignIn(
            enrollmentId: 'totp-1',
            appVerification: verification,
          ),
          throwsAuth('multi-factor-info-not-found'),
        );
        await expectLater(
          e.resolver!.resolveSignInWithTotp('123456', enrollmentId: 'phone-1'),
          throwsAuth('multi-factor-info-not-found'),
        );
        expect(actions, isEmpty);
      },
    );

    test('a TOTP-only account has no SMS factor to start', () async {
      server.totp.writeFactors(uid, <Map<String, Object?>>[
        <String, Object?>{
          'mfaEnrollmentId': 'totp-1',
          'totpInfo': <String, Object?>{},
        },
      ]);
      final FirebaseAuthMultiFactorException e = await challenge();
      final FirebaseAuthException error = await caught(
        e.resolver!.startPhoneSignIn(appVerification: verification),
      );
      expect(error.code, 'multi-factor-info-not-found');
      expect(error.message, contains('authenticator app (TOTP)'));
    });

    test('an empty credential fails before anything is sent', () async {
      final FirebaseAuthMultiFactorException e = await challenge();
      final int sent = backend.requests.length;
      await expectLater(
        e.resolver!.resolveSignInWithPhone(
          PhoneAuthProvider.credential(
            verificationId: 'session-1',
            verificationCode: '',
          ),
        ),
        throwsAuth('missing-verification-code'),
      );
      expect(backend.requests.length, sent);
    });

    test('reauthentication with the resolver keeps the user', () async {
      server.totp.writeFactors(uid, <Map<String, Object?>>[]);
      await signIn();
      server.addPhoneFactor(phone);
      final FirebaseAuthMultiFactorException e =
          await caught<FirebaseAuthMultiFactorException>(
            auth.reauthenticateWithCredential(
              EmailAuthProvider.credential(email: email, password: 'pw'),
            ),
          );
      final String verificationId = await e.resolver!.startPhoneSignIn(
        appVerification: verification,
      );
      final UserCredential result = await e.resolver!.resolveSignInWithPhone(
        PhoneAuthProvider.credential(
          verificationId: verificationId,
          verificationCode: code,
        ),
      );
      expect(result.operationType, OperationType.reauthenticate);
      expect(result.user!.uid, uid);
    });
  });

  test('an account whose factors are all unknown says so', () async {
    server.totp.addFactor(uid, <String, Object?>{
      'mfaEnrollmentId': 'other-1',
      'webAuthnInfo': <String, Object?>{},
    });
    final FirebaseAuthMultiFactorException e =
        await caught<FirebaseAuthMultiFactorException>(signIn());
    expect(
      e.message,
      FirebaseAuthMultiFactorException.unsupportedFactorsMessage,
    );
  });

  group('errors', () {
    void failWith(String method, String serverCode) => backend.on(
      method,
      (Map<String, Object?> body) => errorResponse(
        '$serverCode : rejected ${jsonEncode(body)} for 15555550100',
      ),
    );

    for (final MapEntry<String, String> error in multiFactorErrors.entries) {
      test(
        '${error.key} is ${error.value} on each call, without secrets',
        () async {
          await signIn();
          failWith('mfaEnrollment:start', error.key);
          failWith('mfaEnrollment:finalize', error.key);
          final FirebaseAuthException start = await caught(
            auth.startPhoneEnrollment(phone, appVerification: verification),
          );
          expect(start.code, error.value);
          expectNoSecrets(start, <String>[phone, 'v2-token-1']);
          final FirebaseAuthException finalize = await caught(
            auth.finalizePhoneEnrollment(
              PhoneAuthProvider.credential(
                verificationId: verificationIdSecret,
                verificationCode: code,
              ),
            ),
          );
          expect(finalize.code, error.value);
          expectNoSecrets(finalize, <String>[verificationIdSecret, code]);

          await auth.signOut();
          server.addPhoneFactor(phone);
          final FirebaseAuthMultiFactorException e =
              await caught<FirebaseAuthMultiFactorException>(signIn());
          failWith('mfaSignIn:start', error.key);
          failWith('mfaSignIn:finalize', error.key);
          final FirebaseAuthException signInStart = await caught(
            e.resolver!.startPhoneSignIn(appVerification: verification),
          );
          expect(signInStart.code, error.value);
          expectNoSecrets(signInStart, <String>['v2-token-2', phone]);
          final FirebaseAuthException signInFinalize = await caught(
            e.resolver!.resolveSignInWithPhone(
              PhoneAuthProvider.credential(
                verificationId: verificationIdSecret,
                verificationCode: code,
              ),
            ),
          );
          expect(signInFinalize.code, error.value);
          expectNoSecrets(signInFinalize, <String>[verificationIdSecret, code]);
        },
      );
    }
  });
}
