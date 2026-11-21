// AppVerification: the request fields of each shape, and getRecaptchaSiteKey against the fake
// backend (real service and emulator).

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:firebase_auth_providers_dart/src/app_verification.dart'
    show appVerificationFields;
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'harness.dart';

void main() {
  group('appVerificationFields', () {
    int siteKeyCalls = 0;
    Future<String> siteKey() async {
      siteKeyCalls++;
      return 'site-key-1';
    }

    setUp(() => siteKeyCalls = 0);

    test(
      'v2 sends the token as recaptchaToken, made for the site key',
      () async {
        final List<RecaptchaV2Request> requests = <RecaptchaV2Request>[];
        final Map<String, Object?> fields = await appVerificationFields(
          AppVerification.recaptchaV2((RecaptchaV2Request request) {
            requests.add(request);
            return 'v2-token';
          }),
          action: RecaptchaAction.sendVerificationCode,
          siteKey: siteKey,
          languageCode: 'ro',
        );
        expect(fields, <String, Object?>{'recaptchaToken': 'v2-token'});
        expect(siteKeyCalls, 1);
        expect(requests, hasLength(1));
        expect(requests.single.siteKey, 'site-key-1');
        expect(requests.single.languageCode, 'ro');
        expect(requests.single.action, RecaptchaAction.sendVerificationCode);
      },
    );

    test(
      'Enterprise sends captchaResponse, clientType and recaptchaVersion',
      () async {
        final List<RecaptchaEnterpriseRequest> requests =
            <RecaptchaEnterpriseRequest>[];
        final Map<String, Object?> fields = await appVerificationFields(
          AppVerification.recaptchaEnterprise((
            RecaptchaEnterpriseRequest request,
          ) async {
            requests.add(request);
            return 'enterprise-token';
          }),
          action: RecaptchaAction.mfaSmsEnrollment,
          siteKey: siteKey,
        );
        expect(fields, <String, Object?>{
          'captchaResponse': 'enterprise-token',
          'clientType': 'CLIENT_TYPE_WEB',
          'recaptchaVersion': 'RECAPTCHA_ENTERPRISE',
        });
        expect(requests.single.action.value, 'mfaSmsEnrollment');
        expect(siteKeyCalls, 0, reason: 'the v2 site key is not needed');
      },
    );

    test('Enterprise takes the client type of the token', () async {
      final Map<String, Object?> fields = await appVerificationFields(
        const RecaptchaEnterpriseVerification(
          _enterpriseToken,
          clientType: RecaptchaClientType.ios,
        ),
        action: RecaptchaAction.mfaSmsSignIn,
        siteKey: siteKey,
      );
      expect(fields['clientType'], 'CLIENT_TYPE_IOS');
      expect(fields['captchaResponse'], 'mfaSmsSignIn-token');
    });

    test('none sends no field and asks for no site key', () async {
      expect(
        await appVerificationFields(
          const AppVerification.none(),
          action: RecaptchaAction.sendVerificationCode,
          siteKey: siteKey,
        ),
        isEmpty,
      );
      expect(siteKeyCalls, 0);
    });

    test('an empty token is missing-app-credential', () async {
      await expectLater(
        appVerificationFields(
          AppVerification.recaptchaV2((_) => ''),
          action: RecaptchaAction.sendVerificationCode,
          siteKey: siteKey,
        ),
        throwsAuth('missing-app-credential'),
      );
      await expectLater(
        appVerificationFields(
          AppVerification.recaptchaEnterprise((_) => ''),
          action: RecaptchaAction.sendVerificationCode,
          siteKey: siteKey,
        ),
        throwsAuth('missing-app-credential'),
      );
    });

    test(
      'errors of the token source and of the site key are rethrown as they are',
      () async {
        await expectLater(
          appVerificationFields(
            AppVerification.recaptchaV2((_) => throw StateError('no WebView')),
            action: RecaptchaAction.sendVerificationCode,
            siteKey: siteKey,
          ),
          throwsStateError,
        );
        await expectLater(
          appVerificationFields(
            AppVerification.recaptchaV2((_) => 'unused'),
            action: RecaptchaAction.sendVerificationCode,
            siteKey: () async => throw const FirebaseAuthException(
              code: 'network-request-failed',
              message: 'offline',
            ),
          ),
          throwsAuth('network-request-failed'),
        );
      },
    );

    test('the requests do not print what they carry beyond the action', () {
      const RecaptchaV2Request request = RecaptchaV2Request(
        siteKey: 'site-key-1',
        action: RecaptchaAction.sendVerificationCode,
      );
      expect(
        request.toString(),
        'RecaptchaV2Request(action: sendVerificationCode)',
      );
      expect(
        const RecaptchaEnterpriseRequest(
          action: RecaptchaAction.mfaSmsSignIn,
        ).toString(),
        'RecaptchaEnterpriseRequest(action: mfaSmsSignIn)',
      );
    });
  });

  group('getRecaptchaSiteKey', () {
    late FakeBackend backend;

    setUp(() {
      backend = FakeBackend()
        ..on(
          'recaptchaParams',
          (_) => jsonResponse(<String, Object?>{
            'kind': 'identitytoolkit#GetRecaptchaParamResponse',
            'recaptchaSiteKey': 'site-key-1',
          }),
        );
    });

    test('GETs v1/recaptchaParams with the API key, without a tenant', () async {
      final FirebaseUserAuth auth = backend.create()
        ..tenantId = 'tenant-1'
        ..languageCode = 'ro';
      addTearDown(auth.dispose);
      expect(await auth.getRecaptchaSiteKey(), 'site-key-1');
      final http.Request request = backend.requests.single;
      expect(request.method, 'GET');
      expect(
        request.url.toString(),
        'https://identitytoolkit.googleapis.com/v1/recaptchaParams?key=$apiKey',
      );
      expect(request.headers['X-Firebase-Locale'], 'ro');
    });

    test('goes to the emulator when one is set', () async {
      final FirebaseUserAuth auth = backend.create(
        emulatorHost: '127.0.0.1:9099',
      );
      addTearDown(auth.dispose);
      expect(await auth.getRecaptchaSiteKey(), 'site-key-1');
      expect(
        backend.requests.single.url.toString(),
        'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/recaptchaParams?key=$apiKey',
      );
    });

    test('an answer without a site key is internal-error', () async {
      backend.on(
        'recaptchaParams',
        (_) => jsonResponse(<String, Object?>{'kind': 'x'}),
      );
      final FirebaseUserAuth auth = backend.create();
      addTearDown(auth.dispose);
      await expectLater(
        auth.getRecaptchaSiteKey(),
        throwsAuth('internal-error'),
      );
      backend.on(
        'recaptchaParams',
        (_) => jsonResponse(<String, Object?>{'recaptchaSiteKey': ''}),
      );
      await expectLater(
        auth.getRecaptchaSiteKey(),
        throwsAuth('internal-error'),
      );
    });

    test('an error answer is mapped like any other request', () async {
      backend.on(
        'recaptchaParams',
        (_) => errorResponse('API_KEY_INVALID', 400),
      );
      final FirebaseUserAuth auth = backend.create();
      addTearDown(auth.dispose);
      await expectLater(
        auth.getRecaptchaSiteKey(),
        throwsA(
          isA<FirebaseAuthException>().having(
            (FirebaseAuthException e) => e.toString(),
            'toString',
            isNot(contains(apiKey)),
          ),
        ),
      );
    });

    test('feeds the v2 token source through appVerificationFields', () async {
      final FirebaseUserAuth auth = backend.create();
      addTearDown(auth.dispose);
      final Map<String, Object?> fields = await appVerificationFields(
        AppVerification.recaptchaV2(
          (RecaptchaV2Request r) => 'token-for-${r.siteKey}',
        ),
        action: RecaptchaAction.sendVerificationCode,
        siteKey: auth.getRecaptchaSiteKey,
      );
      expect(fields, <String, Object?>{
        'recaptchaToken': 'token-for-site-key-1',
      });
    });
  });
}

String _enterpriseToken(RecaptchaEnterpriseRequest request) =>
    '${request.action.value}-token';
