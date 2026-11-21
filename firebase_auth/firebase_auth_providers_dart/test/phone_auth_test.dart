// Phone sign-in against a fake Identity Toolkit backend: sending the code with each kind of app
// verification, signing in, linking, reauthenticating and updating the phone number with the
// credential, the program helper with secure_flow, every error the phone requests map, and that no
// error holds a phone number, a verification id, an SMS code or a reCAPTCHA token.

@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';

import 'dart:io';

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:firebase_auth_providers_dart/src/phone_auth.dart'
    show redactPhoneSecrets;
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'fakes.dart';
import 'harness.dart';
import 'phone_harness.dart';

/// A reCAPTCHA v2 token source that records its requests.
class Tokens {
  final List<RecaptchaV2Request> requests = <RecaptchaV2Request>[];

  AppVerification get verification =>
      AppVerification.recaptchaV2((RecaptchaV2Request request) {
        requests.add(request);
        return 'v2-token-${requests.length}';
      });
}

/// The phone errors of the backend and the codes they map to (JS SDK and FlutterFire names).
const Map<String, String> phoneErrors = <String, String>{
  'INVALID_CODE': 'invalid-verification-code',
  'INVALID_SESSION_INFO': 'invalid-verification-id',
  'SESSION_EXPIRED': 'code-expired',
  'CODE_EXPIRED': 'code-expired',
  'TOO_MANY_ATTEMPTS_TRY_LATER': 'too-many-requests',
  'INVALID_PHONE_NUMBER': 'invalid-phone-number',
  'MISSING_PHONE_NUMBER': 'missing-phone-number',
  'QUOTA_EXCEEDED': 'quota-exceeded',
  'MISSING_APP_CREDENTIAL': 'missing-app-credential',
  'INVALID_APP_CREDENTIAL': 'invalid-app-credential',
  'CAPTCHA_CHECK_FAILED': 'captcha-check-failed',
  'MISSING_CODE': 'missing-verification-code',
  'MISSING_SESSION_INFO': 'missing-verification-id',
  'INVALID_TEMPORARY_PROOF': 'invalid-credential',
  'OPERATION_NOT_ALLOWED': 'operation-not-allowed',
  'PHONE_NUMBER_EXISTS': 'credential-already-in-use',
};

/// The secrets a request of the tests carries, which an error must never show.
const String verificationIdSecret = 'session-secret-42';
const String tokenSecret = 'v2-token-1';

/// Checks that [e] holds none of [secrets] in any field or in its text.
void expectNoSecrets(FirebaseAuthException e, List<String> secrets) {
  final List<String?> texts = <String?>[
    e.message,
    e.serverCode,
    e.toString(),
    e.phoneNumber,
    e.email,
    e.tenantId,
    '${e.serverResponse}',
    '${e.credential}',
    '${e.cause}',
  ];
  for (final String secret in secrets) {
    final String digits = secret.replaceAll(RegExp(r'\D'), '');
    for (final String? text in texts) {
      expect(text ?? '', isNot(contains(secret)), reason: '$secret in $text');
      if (secret.startsWith('+')) {
        expect(text ?? '', isNot(contains(digits)), reason: 'digits in $text');
      }
    }
  }
  expect(e.phoneNumber, isNull);
  expect(e.serverResponse, isNull);
}

/// Posts the form of a secure_flow page at [url], as the page would.
Future<void> postForm(Uri url, Map<String, String> fields) async {
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

FirebaseAuthException redact(String message, List<String?> secrets) =>
    redactPhoneSecrets(
      FirebaseAuthException(code: 'internal-error', message: message),
      secrets,
    );

Future<FirebaseAuthException> authError(Future<Object?> operation) async {
  try {
    await operation;
  } on FirebaseAuthException catch (e) {
    return e;
  }
  fail('No FirebaseAuthException');
}

void main() {
  late PhoneBackend server;
  late FakeBackend backend;
  late FirebaseUserAuth auth;
  late Tokens tokens;

  setUp(() {
    server = PhoneBackend();
    backend = server.backend;
    auth = backend.create();
    tokens = Tokens();
  });

  tearDown(() => auth.dispose());

  Future<String> send([String number = phone]) =>
      auth.verifyPhoneNumber(number, appVerification: tokens.verification);

  Future<PhoneAuthCredential> credential([String number = phone]) async =>
      PhoneAuthProvider.credential(
        verificationId: await send(number),
        verificationCode: code,
      );

  group('verifyPhoneNumber', () {
    test('sends the number with a reCAPTCHA v2 token and returns the '
        'verification id', () async {
      auth.languageCode = 'ro';
      final String verificationId = await send();
      expect(verificationId, startsWith('session-'));
      expect(backend.methods, <String>[
        'recaptchaParams',
        'accounts:sendVerificationCode',
      ]);
      expect(
        backend.bodiesOf('accounts:sendVerificationCode').single,
        <String, Object?>{'phoneNumber': phone, 'recaptchaToken': 'v2-token-1'},
      );
      expect(tokens.requests.single.siteKey, siteKey);
      expect(
        tokens.requests.single.action,
        RecaptchaAction.sendVerificationCode,
      );
      expect(tokens.requests.single.languageCode, 'ro');
      expect(backend.requests.last.headers['X-Firebase-Locale'], 'ro');
    });

    test('a reCAPTCHA Enterprise token goes with its client type', () async {
      final List<RecaptchaAction> actions = <RecaptchaAction>[];
      await auth.verifyPhoneNumber(
        phone,
        appVerification: AppVerification.recaptchaEnterprise((
          RecaptchaEnterpriseRequest request,
        ) {
          actions.add(request.action);
          return 'enterprise-token';
        }, clientType: RecaptchaClientType.ios),
      );
      expect(backend.methods, <String>['accounts:sendVerificationCode']);
      expect(
        backend.bodiesOf('accounts:sendVerificationCode').single,
        <String, Object?>{
          'phoneNumber': phone,
          'captchaResponse': 'enterprise-token',
          'clientType': 'CLIENT_TYPE_IOS',
          'recaptchaVersion': 'RECAPTCHA_ENTERPRISE',
        },
      );
      expect(actions, <RecaptchaAction>[RecaptchaAction.sendVerificationCode]);
    });

    test('no proof sends the number alone', () async {
      server.platform.requireProof = false;
      await auth.verifyPhoneNumber(
        phone,
        appVerification: const AppVerification.none(),
      );
      expect(
        backend.bodiesOf('accounts:sendVerificationCode').single,
        <String, Object?>{'phoneNumber': phone},
      );
    });

    test('the tenant goes into the request', () async {
      auth.tenantId = 'tenant-1';
      await send();
      expect(
        backend.bodiesOf('accounts:sendVerificationCode').single['tenantId'],
        'tenant-1',
      );
    });

    test('an empty number fails before a token is asked for', () async {
      await expectLater(send(' '), throwsAuth('missing-phone-number'));
      expect(backend.requests, isEmpty);
      expect(tokens.requests, isEmpty);
    });

    test('an empty token is missing-app-credential', () async {
      await expectLater(
        auth.verifyPhoneNumber(
          phone,
          appVerification: AppVerification.recaptchaV2(
            (RecaptchaV2Request request) => '',
          ),
        ),
        throwsAuth('missing-app-credential'),
      );
      expect(backend.methods, <String>['recaptchaParams']);
    });

    test('an answer without a verification id is an internal-error', () async {
      backend.on(
        'accounts:sendVerificationCode',
        (Map<String, Object?> body) => jsonResponse(<String, Object?>{}),
      );
      await expectLater(send(), throwsAuth('internal-error'));
    });

    test('the backend refuses a number that is not E.164', () async {
      final FirebaseAuthException e = await authError(send('5555550100'));
      expect(e.code, 'invalid-phone-number');
      expectNoSecrets(e, <String>['5555550100', tokenSecret]);
    });
  });

  group('sign-in', () {
    test('signs in with the verification id and the code', () async {
      final List<AuthUser?> users = <AuthUser?>[];
      final StreamSubscription<AuthUser?> sub = auth.authStateChanges().listen(
        users.add,
      );
      final PhoneAuthCredential phoneCredential = await credential();
      final UserCredential result = await auth.signInWithCredential(
        phoneCredential,
      );
      expect(
        backend.bodiesOf('accounts:signInWithPhoneNumber').single,
        <String, Object?>{
          'sessionInfo': phoneCredential.verificationId,
          'code': code,
        },
      );
      expect(result.user!.uid, 'uid-of-$phone');
      expect(result.user!.phoneNumber, phone);
      expect(result.operationType, OperationType.signIn);
      expect(result.additionalUserInfo!.providerId, 'phone');
      expect(result.additionalUserInfo!.isNewUser, isTrue);
      expect(auth.currentUser!.providerData.single.providerId, 'phone');
      await pump();
      expect(users.last?.uid, 'uid-of-$phone');
      await sub.cancel();
    });

    test('a second sign-in finds the same account', () async {
      await auth.signInWithCredential(await credential());
      await auth.signOut();
      final UserCredential again = await auth.signInWithCredential(
        await credential(),
      );
      expect(again.user!.uid, 'uid-of-$phone');
      expect(again.additionalUserInfo!.isNewUser, isFalse);
    });

    test('the tenant goes into the sign-in', () async {
      auth.tenantId = 'tenant-1';
      backend.on(
        'accounts:signInWithPhoneNumber',
        (Map<String, Object?> body) => errorResponse('INVALID_CODE'),
      );
      await expectLater(
        auth.signInWithCredential(await credential()),
        throwsAuth('invalid-verification-code'),
      );
      expect(
        backend.bodiesOf('accounts:signInWithPhoneNumber').single['tenantId'],
        'tenant-1',
      );
    });

    test('a wrong code is refused and nobody is signed in', () async {
      final String verificationId = await send();
      final FirebaseAuthException e = await authError(
        auth.signInWithCredential(
          PhoneAuthProvider.credential(
            verificationId: verificationId,
            verificationCode: '000000',
          ),
        ),
      );
      expect(e.code, 'invalid-verification-code');
      expect(auth.currentUser, isNull);
      expectNoSecrets(e, <String>[verificationId, '000000']);
    });

    test('a verification id the backend did not give is refused', () async {
      await expectLater(
        auth.signInWithCredential(
          PhoneAuthProvider.credential(
            verificationId: 'made-up',
            verificationCode: code,
          ),
        ),
        throwsAuth('invalid-verification-id'),
      );
    });

    test('an empty verification id or code fails before anything is sent', () {
      expect(
        () => auth.signInWithCredential(
          PhoneAuthProvider.credential(
            verificationId: '',
            verificationCode: code,
          ),
        ),
        throwsAuth('missing-verification-id'),
      );
      expect(
        () => auth.signInWithCredential(
          PhoneAuthProvider.credential(
            verificationId: 'session-1',
            verificationCode: '',
          ),
        ),
        throwsAuth('missing-verification-code'),
      );
      expect(backend.requests, isEmpty);
    });

    test('the credential prints no secret', () {
      final PhoneAuthCredential c = PhoneAuthProvider.credential(
        verificationId: verificationIdSecret,
        verificationCode: code,
      );
      expect(c.toString(), isNot(contains(verificationIdSecret)));
      expect(c.toString(), isNot(contains(code)));
      expect(c.providerId, PhoneAuthProvider.PROVIDER_ID);
      expect(c.signInMethod, PhoneAuthProvider.PHONE_SIGN_IN_METHOD);
    });
  });

  group('link', () {
    setUp(() => auth.signInWithEmailAndPassword(email: email, password: 'pw'));

    test('links the number to the signed-in user', () async {
      final UserCredential result = await auth.linkWithCredential(
        await credential(),
      );
      final Map<String, Object?> body = backend
          .bodiesOf('accounts:signInWithPhoneNumber')
          .single;
      expect(body['idToken'], isA<String>());
      expect(body.containsKey('operation'), isFalse);
      expect(result.operationType, OperationType.link);
      expect(result.user!.uid, uid);
      expect(auth.currentUser!.phoneNumber, phone);
      expect(
        auth.currentUser!.providerData.map((UserInfo i) => i.providerId),
        containsAll(<String>['password', 'phone']),
      );
    });

    test('a user with a phone number cannot link another', () async {
      await auth.linkWithCredential(await credential());
      await expectLater(
        auth.linkWithCredential(await credential('+15555550199')),
        throwsAuth('provider-already-linked'),
      );
    });

    test('a number of another account is credential-already-in-use, with a '
        'credential that signs in to that account', () async {
      backend.accounts['someone-else'] = <String, Object?>{
        'phoneNumber': phone,
      };
      final FirebaseAuthException e = await authError(
        auth.linkWithCredential(await credential()),
      );
      expect(e.code, 'credential-already-in-use');
      expect(auth.currentUser!.phoneNumber, isNull);
      final PhoneAuthCredential proof = e.credential! as PhoneAuthCredential;
      expect(proof.temporaryProof, 'proof-of-$phone');
      expect(proof.phoneNumber, phone);
      expect(proof.verificationId, isNull);
      expect(<String?>[
        e.message,
        e.toString(),
        proof.toString(),
        e.phoneNumber,
      ], everyElement(isNot(contains('5555550100'))));
      expect(e.toString(), isNot(contains('proof-of')));

      final UserCredential other = await auth.signInWithCredential(proof);
      expect(other.user!.uid, 'someone-else');
      expect(
        backend.bodiesOf('accounts:signInWithPhoneNumber').last,
        <String, Object?>{
          'temporaryProof': 'proof-of-$phone',
          'phoneNumber': phone,
        },
      );
    });

    test('needs a signed-in user', () async {
      await auth.signOut();
      await expectLater(
        auth.linkWithCredential(
          PhoneAuthProvider.credential(
            verificationId: 'session-1',
            verificationCode: code,
          ),
        ),
        throwsAuth('null-user'),
      );
    });
  });

  group('reauthentication', () {
    setUp(() async => auth.signInWithCredential(await credential()));

    test('sends the operation REAUTH and keeps the user', () async {
      final UserCredential result = await auth.reauthenticateWithCredential(
        await credential(),
      );
      expect(
        backend.bodiesOf('accounts:signInWithPhoneNumber').last['operation'],
        'REAUTH',
      );
      expect(result.operationType, OperationType.reauthenticate);
      expect(result.user!.uid, 'uid-of-$phone');
    });

    test('a number of no account is user-mismatch', () async {
      final PhoneAuthCredential other = await credential('+15555550199');
      await expectLater(
        auth.reauthenticateWithCredential(other),
        throwsAuth('user-mismatch'),
      );
      expect(auth.uid, 'uid-of-$phone');
    });

    test('the number of another account is user-mismatch', () async {
      backend.accounts['someone-else'] = <String, Object?>{
        'phoneNumber': '+15555550199',
      };
      await expectLater(
        auth.reauthenticateWithCredential(await credential('+15555550199')),
        throwsAuth('user-mismatch'),
      );
    });
  });

  group('updatePhoneNumber', () {
    setUp(() => auth.signInWithEmailAndPassword(email: email, password: 'pw'));

    test('sets the number and emits the new user', () async {
      final List<AuthUser?> changes = <AuthUser?>[];
      final StreamSubscription<AuthUser?> sub = auth.userChanges().listen(
        changes.add,
      );
      await auth.updatePhoneNumber(await credential());
      expect(
        backend.bodiesOf('accounts:signInWithPhoneNumber').single['idToken'],
        isA<String>(),
      );
      expect(auth.currentUser!.phoneNumber, phone);
      await pump();
      expect(changes.last?.phoneNumber, phone);
      await sub.cancel();
    });

    test('replaces a number the user had', () async {
      await auth.updatePhoneNumber(await credential());
      await auth.updatePhoneNumber(await credential('+15555550199'));
      expect(auth.currentUser!.phoneNumber, '+15555550199');
    });

    test('a number of another account is credential-already-in-use', () async {
      backend.accounts['someone-else'] = <String, Object?>{
        'phoneNumber': phone,
      };
      final FirebaseAuthException e = await authError(
        auth.updatePhoneNumber(await credential()),
      );
      expect(e.code, 'credential-already-in-use');
      expect(e.message, isNot(contains('5555550100')));
      expect(
        (e.credential! as PhoneAuthCredential).temporaryProof,
        'proof-of-$phone',
      );
    });

    test('needs a signed-in user', () async {
      await auth.signOut();
      await expectLater(
        auth.updatePhoneNumber(
          PhoneAuthProvider.credential(
            verificationId: 'session-1',
            verificationCode: code,
          ),
        ),
        throwsAuth('null-user'),
      );
    });

    test('an empty code fails before anything is sent', () async {
      final int sent = backend.requests.length;
      await expectLater(
        auth.updatePhoneNumber(
          PhoneAuthProvider.credential(
            verificationId: 'session-1',
            verificationCode: '',
          ),
        ),
        throwsAuth('missing-verification-code'),
      );
      expect(backend.requests.length, sent);
    });
  });

  group('verifyPhoneNumberInteractively', () {
    test('asks for the code and returns the credential', () async {
      final StringBuffer shown = StringBuffer();
      final PhoneAuthCredential c = await auth.verifyPhoneNumberInteractively(
        phone,
        appVerification: tokens.verification,
        codePresenter: ConsolePresenter(
          sink: shown,
          input: Stream<String>.value(' $code '),
        ),
        prompt: 'The code:',
      );
      expect(shown.toString(), contains('The code:'));
      expect(c.verificationCode, code);
      final UserCredential result = await auth.signInWithCredential(c);
      expect(result.user!.phoneNumber, phone);
    });

    test('the code presenter also shows the default reCAPTCHA page', () async {
      final List<Uri> shown = <Uri>[];
      final PhoneAuthCredential c = await auth.verifyPhoneNumberInteractively(
        phone,
        codePresenter: CallbackPresenter((Uri url) async {
          shown.add(url);
          // The first page is the reCAPTCHA one, the second asks for the code.
          await postForm(url, <String, String>{
            if (shown.length == 1) 'token': 'page-token' else 'code': code,
          });
        }),
        timeout: const Duration(seconds: 20),
      );
      expect(shown, hasLength(2));
      expect(
        backend.bodiesOf('accounts:sendVerificationCode').single,
        containsPair('recaptchaToken', 'page-token'),
      );
      expect(c.verificationCode, code);
    });

    test('no code within the timeout is timeout', () async {
      await expectLater(
        auth.verifyPhoneNumberInteractively(
          phone,
          appVerification: tokens.verification,
          codePresenter: ConsolePresenter(
            sink: StringBuffer(),
            input: StreamController<String>().stream,
          ),
          timeout: const Duration(milliseconds: 50),
        ),
        throwsAuth('timeout'),
      );
    });
  });

  group('errors', () {
    /// Answers [method] with the error [serverCode], its detail quoting every secret of the
    /// request.
    void failWith(String method, String serverCode) => backend.on(
      method,
      (Map<String, Object?> body) => errorResponse(
        '$serverCode : rejected ${jsonEncode(body)} for 15555550100',
      ),
    );

    for (final MapEntry<String, String> error in phoneErrors.entries) {
      test('${error.key} on sendVerificationCode is ${error.value}, without '
          'secrets', () async {
        failWith('accounts:sendVerificationCode', error.key);
        final FirebaseAuthException e = await authError(send());
        expect(e.code, error.value);
        expect(e.serverCode, error.key);
        expectNoSecrets(e, <String>[phone, tokenSecret]);
      });

      test('${error.key} on signInWithPhoneNumber is ${error.value}, without '
          'secrets', () async {
        failWith('accounts:signInWithPhoneNumber', error.key);
        final FirebaseAuthException e = await authError(
          auth.signInWithCredential(
            PhoneAuthProvider.credential(
              verificationId: verificationIdSecret,
              verificationCode: code,
            ),
          ),
        );
        expect(e.code, error.value);
        expectNoSecrets(e, <String>[verificationIdSecret, code]);
      });
    }

    test('the errors of link, reauthentication and update hold no secret '
        'either', () async {
      await auth.signInWithEmailAndPassword(email: email, password: 'pw');
      failWith('accounts:signInWithPhoneNumber', 'SESSION_EXPIRED');
      final PhoneAuthCredential c = PhoneAuthProvider.credential(
        verificationId: verificationIdSecret,
        verificationCode: code,
      );
      for (final Future<Object?> Function() operation
          in <Future<Object?> Function()>[
            () => auth.linkWithCredential(c),
            () => auth.reauthenticateWithCredential(c),
            () => auth.updatePhoneNumber(c),
          ]) {
        final FirebaseAuthException e = await authError(operation());
        expect(e.code, 'code-expired');
        expectNoSecrets(e, <String>[verificationIdSecret, code]);
      }
    });

    test('a token source error passes through, without the number', () async {
      final FirebaseAuthException e = await authError(
        auth.verifyPhoneNumber(
          phone,
          appVerification: AppVerification.recaptchaV2(
            (RecaptchaV2Request request) => throw FirebaseAuthException(
              code: 'user-cancelled',
              message: 'cancelled for $phone',
            ),
          ),
        ),
      );
      expect(e.code, 'user-cancelled');
      expectNoSecrets(e, <String>[phone]);
    });

    test('a network failure is network-request-failed', () async {
      backend.handler = (http.Request request) async =>
          throw http.ClientException('down: $phone', request.url);
      final FirebaseAuthException e = await authError(send());
      expect(e.code, 'network-request-failed');
      expectNoSecrets(e, <String>[phone]);
    });
  });

  group('redaction', () {
    test('a short code or id is not looked for, so words stay whole', () {
      for (final String secret in <String>['e', '1', '12345']) {
        expect(
          redact('The code 12345 was entered at 1 pm', <String>[
            secret,
          ]).message,
          'The code 12345 was entered at 1 pm',
        );
      }
    });

    test('a secret is cut as a whole token only', () {
      expect(
        redact('code abcdef, not xabcdefx', <String>['abcdef']).message,
        'code <redacted>, not xabcdefx',
      );
      expect(
        redact('session sess-42-abc and code 123456.', <String>[
          'sess-42-abc',
          '123456',
        ]).message,
        'session <redacted> and code <redacted>.',
      );
    });

    test('the 403 of a disabled API keeps its project number and URL', () {
      const String text =
          'Identity Toolkit API has not been used in project 123456789012 before or '
          'it is disabled. Enable it by visiting https://console.developers.google.com/'
          'apis/api/identitytoolkit.googleapis.com/overview?project=123456789012 then '
          'retry.';
      expect(redact(text, <String>[phone]).message, text);
      expect(
        redact('see projects/123456789012/config', <String>[]).message,
        'see projects/123456789012/config',
      );
    });

    test('dates and IPv4 addresses survive', () {
      const String text =
          'at 2026-11-21 10:00:00, 2026-11-21T10:00:00Z and 21/11/2026 from '
          '192.168.0.153 and 10.0.0.1:8080';
      expect(redact(text, <String>[]).message, text);
    });

    test('a phone number with any separators is cut', () {
      for (final String written in <String>[
        '+44 7911/123456',
        '+44 7911 123456',
        '+44 7911–123456',
        '(555) 555-0100',
        '555.555.0100',
        '+1 555 555 0100',
      ]) {
        expect(
          redact('number $written refused', <String>[]).message,
          'number <redacted> refused',
          reason: written,
        );
      }
    });

    test('both rules together, and the markers stay whole', () {
      expect(
        redact(
          'code 654321 for +15555550100 (15555550100) in project 123456789012 '
          'on 2026-11-21 via 192.168.0.1',
          <String>[phone, '654321', 'e'],
        ).message,
        'code <redacted> for <redacted> (<redacted>) in project 123456789012 on '
        '2026-11-21 via 192.168.0.1',
      );
    });
  });
}
