// reCAPTCHA Enterprise against the fake backend: reading v2/recaptchaConfig, the token on the
// email and password requests under ENFORCE, AUDIT and OFF, the retry after
// MISSING_RECAPTCHA_TOKEN, and the SMS requests with their AUDIT fallback to the v2 token, as the
// JS SDK's handleRecaptchaFlow does them. No network; no browser.

import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_dart/internal.dart' show InternalLogLevel, Log;
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'harness.dart';

const String _enterpriseKey = 'enterprise-site-key';
const String _phone = '+15555550100';

/// An answer of `v2/recaptchaConfig` with the states of the two providers.
http.Response _config({
  String? email,
  String? phone,
  String? key = 'projects/my-project/keys/$_enterpriseKey',
}) => jsonResponse(<String, Object?>{
  'recaptchaKey': ?key,
  'recaptchaEnforcementState': <Object?>[
    if (email != null)
      <String, Object?>{
        'provider': 'EMAIL_PASSWORD_PROVIDER',
        'enforcementState': email,
      },
    if (phone != null)
      <String, Object?>{
        'provider': 'PHONE_PROVIDER',
        'enforcementState': phone,
      },
  ],
});

/// An Enterprise token source that records its requests and answers `enterprise-1`, `enterprise-2`,
/// ... unless [answer] says otherwise.
class _Tokens {
  _Tokens({this.answer});

  final FutureOr<String> Function(int call)? answer;
  final List<RecaptchaEnterpriseRequest> requests =
      <RecaptchaEnterpriseRequest>[];

  RecaptchaEnterpriseVerification source({
    RecaptchaClientType clientType = RecaptchaClientType.web,
  }) => RecaptchaEnterpriseVerification((RecaptchaEnterpriseRequest request) {
    requests.add(request);
    final int call = requests.length;
    return answer?.call(call) ?? 'enterprise-$call';
  }, clientType: clientType);
}

/// A v2 token source that records its requests and answers `v2-1`, `v2-2`, ...
class _V2Tokens {
  final List<RecaptchaV2Request> requests = <RecaptchaV2Request>[];

  AppVerification get verification =>
      AppVerification.recaptchaV2((RecaptchaV2Request request) {
        requests.add(request);
        return 'v2-${requests.length}';
      });
}

/// The query parameters of the requests to `v2/recaptchaConfig`.
List<Map<String, String>> _configQueries(FakeBackend backend) =>
    <Map<String, String>>[
      for (final http.Request r in backend.requests)
        if (r.url.pathSegments.last == 'recaptchaConfig') r.url.queryParameters,
    ];

/// Answers [method] with [first] once, then with the default answer.
void _firstFails(FakeBackend backend, String method, http.Response first) {
  bool failed = false;
  backend.on(method, (Map<String, Object?> body) async {
    if (!failed) {
      failed = true;
      return first;
    }
    backend.overrides.remove(method);
    return backend.answer(backend.requests.last);
  });
}

void main() {
  late FakeBackend backend;

  setUp(() => backend = FakeBackend());

  group('RecaptchaConfig.fromResponse', () {
    test('the site key is the last part of the key name', () {
      final RecaptchaConfig config = RecaptchaConfig.fromResponse(
        jsonDecode(_config(email: 'ENFORCE', phone: 'AUDIT').body)
            as Map<String, Object?>,
      );
      expect(config.siteKey, _enterpriseKey);
      expect(
        config.enforcementState(RecaptchaProvider.emailPassword),
        RecaptchaEnforcementState.enforce,
      );
      expect(
        config.enforcementState(RecaptchaProvider.phone),
        RecaptchaEnforcementState.audit,
      );
      expect(config.isProviderEnabled(RecaptchaProvider.emailPassword), isTrue);
      expect(config.isProviderEnabled(RecaptchaProvider.phone), isTrue);
      expect(config.isAnyProviderEnabled, isTrue);
      expect(config.toString(), isNot(contains(_enterpriseKey)));
    });

    test('OFF, unknown states, unknown providers, the first entry wins', () {
      final RecaptchaConfig config = RecaptchaConfig.fromResponse(
        <String, Object?>{
          'recaptchaKey': 'projects/p/keys/k',
          'recaptchaEnforcementState': <Object?>[
            <String, Object?>{
              'provider': 'EMAIL_PASSWORD_PROVIDER',
              'enforcementState': 'SOMETHING_NEW',
            },
            <String, Object?>{
              'provider': 'EMAIL_PASSWORD_PROVIDER',
              'enforcementState': 'ENFORCE',
            },
            <String, Object?>{
              'provider': 'PHONE_PROVIDER',
              'enforcementState': 'OFF',
            },
            <String, Object?>{
              'provider': 'FUTURE_PROVIDER',
              'enforcementState': 'ENFORCE',
            },
            'not an object',
          ],
        },
      );
      expect(
        config.enforcementState(RecaptchaProvider.emailPassword),
        RecaptchaEnforcementState.unspecified,
      );
      expect(
        config.enforcementState(RecaptchaProvider.phone),
        RecaptchaEnforcementState.off,
      );
      expect(config.isAnyProviderEnabled, isFalse);
    });

    test('no key, or a key name of another shape, gives no site key', () {
      expect(RecaptchaConfig.fromResponse(<String, Object?>{}).siteKey, isNull);
      expect(
        RecaptchaConfig.fromResponse(<String, Object?>{
          'recaptchaKey': 'just-a-key',
        }).siteKey,
        isNull,
      );
      expect(
        RecaptchaConfig.fromResponse(<String, Object?>{}).enforcementStates,
        isEmpty,
      );
    });
  });

  group('initializeRecaptchaConfig', () {
    test('GET v2/recaptchaConfig with the client type and version', () async {
      backend.on('recaptchaConfig', (_) => _config(email: 'ENFORCE'));
      final FirebaseUserAuth auth = backend.create(
        recaptchaEnterprise: _Tokens().source(
          clientType: RecaptchaClientType.ios,
        ),
      );
      expect(auth.recaptchaConfig, isNull);
      final RecaptchaConfig config = await auth.initializeRecaptchaConfig();
      expect(config.siteKey, _enterpriseKey);
      expect(auth.recaptchaConfig, same(config));
      final http.Request request = backend.requests.single;
      expect(request.method, 'GET');
      expect(request.url.path, '/v2/recaptchaConfig');
      expect(request.url.queryParameters, <String, String>{
        'clientType': 'CLIENT_TYPE_IOS',
        'version': 'RECAPTCHA_ENTERPRISE',
        'key': apiKey,
      });
    });

    test(
      'web is the client type without a source; a tenant has its own',
      () async {
        backend.on('recaptchaConfig', (_) => _config(phone: 'AUDIT'));
        final FirebaseUserAuth auth = backend.create()..tenantId = 'tenant-1';
        await auth.initializeRecaptchaConfig();
        expect(_configQueries(backend).single, <String, String>{
          'clientType': 'CLIENT_TYPE_WEB',
          'version': 'RECAPTCHA_ENTERPRISE',
          'tenantId': 'tenant-1',
          'key': apiKey,
        });
        expect(auth.recaptchaConfig, isNotNull);
        auth.tenantId = null;
        expect(auth.recaptchaConfig, isNull);
      },
    );

    test('goes to the emulator when one is set', () async {
      backend.on('recaptchaConfig', (_) => _config());
      await backend
          .create(emulatorHost: '127.0.0.1:9099')
          .initializeRecaptchaConfig();
      expect(
        backend.requests.single.url.toString(),
        startsWith(
          'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v2/recaptchaConfig?',
        ),
      );
    });

    test('the backend errors keep the JS SDK code names', () async {
      for (final (String server, String code) in <(String, String)>[
        ('RECAPTCHA_NOT_ENABLED', 'recaptcha-not-enabled'),
        ('MISSING_RECAPTCHA_TOKEN', 'missing-recaptcha-token'),
        ('INVALID_RECAPTCHA_TOKEN', 'invalid-recaptcha-token'),
        ('INVALID_RECAPTCHA_ACTION', 'invalid-recaptcha-action'),
        ('MISSING_RECAPTCHA_VERSION', 'missing-recaptcha-version'),
        ('INVALID_RECAPTCHA_VERSION', 'invalid-recaptcha-version'),
      ]) {
        backend.on('recaptchaConfig', (_) => errorResponse(server));
        await expectLater(
          backend.create().initializeRecaptchaConfig(),
          throwsAuth(code),
          reason: server,
        );
      }
    });
  });

  group('email and password', () {
    test('ENFORCE: the sign-in carries a token for its action', () async {
      backend.on('recaptchaConfig', (_) => _config(email: 'ENFORCE'));
      final _Tokens tokens = _Tokens();
      final FirebaseUserAuth auth = backend.create(
        recaptchaEnterprise: tokens.source(),
      );
      await auth.initializeRecaptchaConfig();
      await auth.signInWithEmailAndPassword(email: 'a@b.c', password: 'pw');
      expect(
        backend.bodiesOf('accounts:signInWithPassword').single,
        <String, Object?>{
          'email': 'a@b.c',
          'password': 'pw',
          'returnSecureToken': true,
          'captchaResponse': 'enterprise-1',
          'clientType': 'CLIENT_TYPE_WEB',
          'recaptchaVersion': 'RECAPTCHA_ENTERPRISE',
        },
      );
      expect(tokens.requests.single.action, RecaptchaAction.signInWithPassword);
      expect(tokens.requests.single.siteKey, _enterpriseKey);
    });

    test('AUDIT attaches too; OFF sends none and asks for none', () async {
      final _Tokens tokens = _Tokens();
      FirebaseUserAuth auth = backend.create(
        recaptchaEnterprise: tokens.source(),
      );
      backend.on('recaptchaConfig', (_) => _config(email: 'AUDIT'));
      await auth.initializeRecaptchaConfig();
      await auth.signInWithEmailAndPassword(email: 'a@b.c', password: 'pw');
      expect(
        backend.bodiesOf('accounts:signInWithPassword').last['captchaResponse'],
        'enterprise-1',
      );

      backend = FakeBackend();
      auth = backend.create(recaptchaEnterprise: tokens.source());
      backend.on(
        'recaptchaConfig',
        (_) => _config(email: 'OFF', phone: 'ENFORCE'),
      );
      await auth.initializeRecaptchaConfig();
      await auth.signInWithEmailAndPassword(email: 'a@b.c', password: 'pw');
      expect(
        backend.bodiesOf('accounts:signInWithPassword').single.keys,
        isNot(contains('captchaResponse')),
      );
      expect(tokens.requests, hasLength(1));
    });

    test(
      'sign-up, password reset, email link, credential, link: their actions and fields',
      () async {
        backend.on('recaptchaConfig', (_) => _config(email: 'ENFORCE'));
        final _Tokens tokens = _Tokens();
        final FirebaseUserAuth auth = backend.create(
          recaptchaEnterprise: tokens.source(),
        );
        await auth.initializeRecaptchaConfig();
        await auth.createUserWithEmailAndPassword(
          email: 'new@b.c',
          password: 'pw',
        );
        await auth.sendPasswordResetEmail(email: 'new@b.c');
        await auth.sendSignInLinkToEmail(
          email: 'new@b.c',
          actionCodeSettings: const ActionCodeSettings(
            url: 'https://example.com/finish',
            handleCodeInApp: true,
          ),
        );
        await auth.signInWithCredential(
          EmailAuthProvider.credential(email: 'new@b.c', password: 'pw'),
        );
        await auth.signInAnonymously();
        await auth.linkWithCredential(
          EmailAuthProvider.credential(email: 'linked@b.c', password: 'pw'),
        );
        expect(
          tokens.requests.map((RecaptchaEnterpriseRequest r) => r.action),
          <RecaptchaAction>[
            RecaptchaAction.signUpPassword,
            RecaptchaAction.getOobCode,
            RecaptchaAction.getOobCode,
            RecaptchaAction.signInWithPassword,
            RecaptchaAction.signUpPassword,
          ],
        );
        final List<Map<String, Object?>> signUps = backend.bodiesOf(
          'accounts:signUp',
        );
        expect(signUps[0]['captchaResponse'], 'enterprise-1');
        // The anonymous sign-up is not a password request: no token.
        expect(signUps[1].keys, isNot(contains('captchaResponse')));
        expect(signUps[2]['captchaResponse'], 'enterprise-5');
        expect(signUps[2]['idToken'], isA<String>());
        // getOobCode takes the token as captchaResp, like the JS SDK.
        for (final Map<String, Object?> body in backend.bodiesOf(
          'accounts:sendOobCode',
        )) {
          expect(body['captchaResp'], startsWith('enterprise-'));
          expect(body.keys, isNot(contains('captchaResponse')));
          expect(body['clientType'], 'CLIENT_TYPE_WEB');
          expect(body['recaptchaVersion'], 'RECAPTCHA_ENTERPRISE');
        }
        expect(
          backend
              .bodiesOf('accounts:signInWithPassword')
              .single['captchaResponse'],
          'enterprise-4',
        );
      },
    );

    test('an email verification carries no token, as in the JS SDK', () async {
      backend.on('recaptchaConfig', (_) => _config(email: 'ENFORCE'));
      final _Tokens tokens = _Tokens();
      final FirebaseUserAuth auth = backend.create(
        recaptchaEnterprise: tokens.source(),
      );
      await auth.initializeRecaptchaConfig();
      await auth.signInAnonymously();
      await auth.sendEmailVerification();
      expect(
        backend.bodiesOf('accounts:sendOobCode').single.keys,
        isNot(contains('captchaResp')),
      );
      expect(tokens.requests, isEmpty);
    });

    test(
      'unknown configuration: MISSING_RECAPTCHA_TOKEN sends it again with a token',
      () async {
        backend.on('recaptchaConfig', (_) => _config(email: 'ENFORCE'));
        _firstFails(
          backend,
          'accounts:signInWithPassword',
          errorResponse('MISSING_RECAPTCHA_TOKEN'),
        );
        final _Tokens tokens = _Tokens();
        final List<String> printed = <String>[];
        final FirebaseUserAuth auth = backend.create(
          recaptchaEnterprise: tokens.source(),
        );
        final InternalLogLevel level = Log.level;
        Log.level = InternalLogLevel.i;
        addTearDown(() => Log.level = level);
        await runZoned(
          () => auth.signInWithEmailAndPassword(email: 'a@b.c', password: 'pw'),
          zoneSpecification: ZoneSpecification(
            print: (_, _, _, String line) => printed.add(line),
          ),
        );
        expect(backend.methods.take(3), <String>[
          'accounts:signInWithPassword',
          'recaptchaConfig',
          'accounts:signInWithPassword',
        ]);
        final List<Map<String, Object?>> bodies = backend.bodiesOf(
          'accounts:signInWithPassword',
        );
        expect(bodies.first.keys, isNot(contains('captchaResponse')));
        expect(bodies.last['captchaResponse'], 'enterprise-1');
        expect(auth.recaptchaConfig, isNotNull);
        expect(printed.join('\n'), contains('signInWithPassword'));
        expect(printed.join('\n'), isNot(contains('enterprise-1')));
      },
    );

    test(
      'MISSING_RECAPTCHA_TOKEN without a source, or another error: no retry',
      () async {
        backend.on(
          'accounts:signInWithPassword',
          (_) => errorResponse('MISSING_RECAPTCHA_TOKEN'),
        );
        await expectLater(
          backend.create().signInWithEmailAndPassword(
            email: 'a@b.c',
            password: 'pw',
          ),
          throwsAuth('missing-recaptcha-token'),
        );
        expect(backend.methods, <String>['accounts:signInWithPassword']);

        backend = FakeBackend()
          ..on(
            'accounts:signInWithPassword',
            (_) => errorResponse('INVALID_PASSWORD'),
          );
        final _Tokens tokens = _Tokens();
        await expectLater(
          backend
              .create(recaptchaEnterprise: tokens.source())
              .signInWithEmailAndPassword(email: 'a@b.c', password: 'pw'),
          throwsAuth('wrong-password'),
        );
        expect(backend.methods, <String>['accounts:signInWithPassword']);
        expect(tokens.requests, isEmpty);
      },
    );

    test(
      'protected but no source: the request goes out without a token',
      () async {
        backend.on('recaptchaConfig', (_) => _config(email: 'AUDIT'));
        final FirebaseUserAuth auth = backend.create();
        await auth.initializeRecaptchaConfig();
        await auth.signInWithEmailAndPassword(email: 'a@b.c', password: 'pw');
        expect(
          backend.bodiesOf('accounts:signInWithPassword').single.keys,
          isNot(contains('captchaResponse')),
        );
      },
    );

    test(
      'a failing source: the configuration is read again and the source asked again',
      () async {
        backend.on('recaptchaConfig', (_) => _config(email: 'ENFORCE'));
        final _Tokens tokens = _Tokens(
          answer: (int call) => call == 1
              ? throw const RecaptchaFailure(
                  RecaptchaFailureReason.scriptLoad,
                  'no script',
                )
              : 'second',
        );
        final FirebaseUserAuth auth = backend.create(
          recaptchaEnterprise: tokens.source(),
        );
        await auth.initializeRecaptchaConfig();
        await auth.signInWithEmailAndPassword(email: 'a@b.c', password: 'pw');
        expect(_configQueries(backend), hasLength(2));
        expect(
          backend
              .bodiesOf('accounts:signInWithPassword')
              .single['captchaResponse'],
          'second',
        );
      },
    );

    test(
      'a source failing twice: its failure as a FirebaseAuthException',
      () async {
        backend.on('recaptchaConfig', (_) => _config(email: 'ENFORCE'));
        final FirebaseUserAuth auth = backend.create(
          recaptchaEnterprise: _Tokens(
            answer: (_) => throw const RecaptchaFailure(
              RecaptchaFailureReason.widget,
              'widget error',
            ),
          ).source(),
        );
        await auth.initializeRecaptchaConfig();
        await expectLater(
          auth.signInWithEmailAndPassword(email: 'a@b.c', password: 'pw'),
          throwsA(
            isA<FirebaseAuthException>()
                .having(
                  (FirebaseAuthException e) => e.code,
                  'code',
                  'network-request-failed',
                )
                .having(
                  (FirebaseAuthException e) => e.cause,
                  'cause',
                  isA<RecaptchaFailure>(),
                ),
          ),
        );
        expect(backend.methods, isNot(contains('accounts:signInWithPassword')));
      },
    );

    test('a timeout of the source is not retried', () async {
      backend.on('recaptchaConfig', (_) => _config(email: 'ENFORCE'));
      final _Tokens tokens = _Tokens(
        answer: (_) =>
            throw const FirebaseAuthException(code: 'timeout', message: 'late'),
      );
      final FirebaseUserAuth auth = backend.create(
        recaptchaEnterprise: tokens.source(),
      );
      await auth.initializeRecaptchaConfig();
      await expectLater(
        auth.signInWithEmailAndPassword(email: 'a@b.c', password: 'pw'),
        throwsAuth('timeout'),
      );
      expect(tokens.requests, hasLength(1));
    });

    test('no site key in the configuration: recaptcha-not-enabled', () async {
      backend.on(
        'recaptchaConfig',
        (_) => _config(email: 'ENFORCE', key: null),
      );
      final _Tokens tokens = _Tokens();
      final FirebaseUserAuth auth = backend.create(
        recaptchaEnterprise: tokens.source(),
      );
      await auth.initializeRecaptchaConfig();
      await expectLater(
        auth.signInWithEmailAndPassword(email: 'a@b.c', password: 'pw'),
        throwsAuth('recaptcha-not-enabled'),
      );
      expect(tokens.requests, isEmpty);
    });

    test('an empty token: missing-recaptcha-token, nothing sent', () async {
      backend.on('recaptchaConfig', (_) => _config(email: 'ENFORCE'));
      final FirebaseUserAuth auth = backend.create(
        recaptchaEnterprise: _Tokens(answer: (_) => '').source(),
      );
      await auth.initializeRecaptchaConfig();
      await expectLater(
        auth.signInWithEmailAndPassword(email: 'a@b.c', password: 'pw'),
        throwsAuth('missing-recaptcha-token'),
      );
      expect(backend.methods, isNot(contains('accounts:signInWithPassword')));
    });
  });

  group('SMS', () {
    setUp(() {
      backend
        ..on(
          'recaptchaParams',
          (_) => jsonResponse(<String, Object?>{'recaptchaSiteKey': 'v2-key'}),
        )
        ..on(
          'accounts:sendVerificationCode',
          (_) => jsonResponse(<String, Object?>{'sessionInfo': 'session-1'}),
        );
    });

    test(
      'ENFORCE: the configuration is read first, the Enterprise token replaces v2',
      () async {
        backend.on('recaptchaConfig', (_) => _config(phone: 'ENFORCE'));
        final _Tokens tokens = _Tokens();
        final _V2Tokens v2 = _V2Tokens();
        final FirebaseUserAuth auth = backend.create(
          recaptchaEnterprise: tokens.source(),
        );
        expect(
          await auth.verifyPhoneNumber(
            _phone,
            appVerification: v2.verification,
          ),
          'session-1',
        );
        expect(backend.methods, <String>[
          'recaptchaConfig',
          'accounts:sendVerificationCode',
        ]);
        expect(
          backend.bodiesOf('accounts:sendVerificationCode').single,
          <String, Object?>{
            'phoneNumber': _phone,
            'captchaResponse': 'enterprise-1',
            'clientType': 'CLIENT_TYPE_WEB',
            'recaptchaVersion': 'RECAPTCHA_ENTERPRISE',
          },
        );
        expect(
          tokens.requests.single.action,
          RecaptchaAction.sendVerificationCode,
        );
        expect(v2.requests, isEmpty);

        await auth.verifyPhoneNumber(_phone, appVerification: v2.verification);
        expect(_configQueries(backend), hasLength(1), reason: 'read once');
      },
    );

    test(
      'AUDIT: MISSING_RECAPTCHA_TOKEN or INVALID_APP_CREDENTIAL fall back to v2',
      () async {
        for (final String error in <String>[
          'MISSING_RECAPTCHA_TOKEN',
          'INVALID_APP_CREDENTIAL',
        ]) {
          backend = FakeBackend()
            ..on('recaptchaConfig', (_) => _config(phone: 'AUDIT'))
            ..on(
              'recaptchaParams',
              (_) =>
                  jsonResponse(<String, Object?>{'recaptchaSiteKey': 'v2-key'}),
            );
          int sent = 0;
          backend.on('accounts:sendVerificationCode', (_) {
            sent++;
            return sent == 1
                ? errorResponse(error)
                : jsonResponse(<String, Object?>{'sessionInfo': 'session-2'});
          });
          final _V2Tokens v2 = _V2Tokens();
          final FirebaseUserAuth auth = backend.create(
            recaptchaEnterprise: _Tokens().source(),
          );
          expect(
            await auth.verifyPhoneNumber(
              _phone,
              appVerification: v2.verification,
            ),
            'session-2',
          );
          expect(
            backend.bodiesOf('accounts:sendVerificationCode').last,
            <String, Object?>{
              'phoneNumber': _phone,
              'recaptchaToken': 'v2-1',
              'captchaResponse': 'NO_RECAPTCHA',
              'clientType': 'CLIENT_TYPE_WEB',
              'recaptchaVersion': 'RECAPTCHA_ENTERPRISE',
            },
            reason: error,
          );
          expect(v2.requests.single.siteKey, 'v2-key');
        }
      },
    );

    test(
      'ENFORCE: the same errors are not retried; AUDIT: other errors neither',
      () async {
        backend
          ..on('recaptchaConfig', (_) => _config(phone: 'ENFORCE'))
          ..on(
            'accounts:sendVerificationCode',
            (_) => errorResponse('MISSING_RECAPTCHA_TOKEN'),
          );
        final _V2Tokens v2 = _V2Tokens();
        await expectLater(
          backend
              .create(recaptchaEnterprise: _Tokens().source())
              .verifyPhoneNumber(_phone, appVerification: v2.verification),
          throwsAuth('missing-recaptcha-token'),
        );
        expect(backend.bodiesOf('accounts:sendVerificationCode'), hasLength(1));

        backend = FakeBackend()
          ..on('recaptchaConfig', (_) => _config(phone: 'AUDIT'))
          ..on(
            'accounts:sendVerificationCode',
            (_) => errorResponse('QUOTA_EXCEEDED'),
          );
        await expectLater(
          backend
              .create(recaptchaEnterprise: _Tokens().source())
              .verifyPhoneNumber(_phone, appVerification: v2.verification),
          throwsAuth('quota-exceeded'),
        );
        expect(backend.bodiesOf('accounts:sendVerificationCode'), hasLength(1));
        expect(v2.requests, isEmpty);
      },
    );

    test('not protected, or no configuration: v2 with NO_RECAPTCHA', () async {
      for (final http.Response answer in <http.Response>[
        _config(phone: 'OFF', email: 'ENFORCE'),
        errorResponse('CONFIGURATION_NOT_FOUND'),
      ]) {
        backend.on('recaptchaConfig', (_) => answer);
        backend.requests.clear();
        final _Tokens tokens = _Tokens();
        await backend
            .create(
              recaptchaEnterprise: tokens.source(
                clientType: RecaptchaClientType.android,
              ),
            )
            .verifyPhoneNumber(
              _phone,
              appVerification: _V2Tokens().verification,
            );
        expect(
          backend.bodiesOf('accounts:sendVerificationCode').single,
          <String, Object?>{
            'phoneNumber': _phone,
            'recaptchaToken': 'v2-1',
            'captchaResponse': 'NO_RECAPTCHA',
            'clientType': 'CLIENT_TYPE_ANDROID',
            'recaptchaVersion': 'RECAPTCHA_ENTERPRISE',
          },
        );
        expect(tokens.requests, isEmpty);
      }
    });

    test('without a source, or with another proof, nothing changes', () async {
      await backend.create().verifyPhoneNumber(
        _phone,
        appVerification: _V2Tokens().verification,
      );
      expect(backend.methods, <String>[
        'recaptchaParams',
        'accounts:sendVerificationCode',
      ]);
      expect(
        backend.bodiesOf('accounts:sendVerificationCode').single,
        <String, Object?>{'phoneNumber': _phone, 'recaptchaToken': 'v2-1'},
      );

      backend.requests.clear();
      final FirebaseUserAuth auth = backend.create(
        recaptchaEnterprise: _Tokens().source(),
      );
      await auth.verifyPhoneNumber(
        _phone,
        appVerification: const AppVerification.none(),
      );
      expect(backend.methods, <String>['accounts:sendVerificationCode']);
      expect(
        backend.bodiesOf('accounts:sendVerificationCode').single,
        <String, Object?>{'phoneNumber': _phone},
      );
    });

    test(
      'an explicit Enterprise proof gets the site key once it is known',
      () async {
        backend.on('recaptchaConfig', (_) => _config(phone: 'ENFORCE'));
        final _Tokens explicit = _Tokens();
        final FirebaseUserAuth auth = backend.create()..languageCode = 'ro';
        await auth.verifyPhoneNumber(
          _phone,
          appVerification: explicit.source(clientType: RecaptchaClientType.ios),
        );
        expect(explicit.requests.single.siteKey, isNull);
        expect(backend.methods, <String>['accounts:sendVerificationCode']);
        await auth.initializeRecaptchaConfig();
        await auth.verifyPhoneNumber(
          _phone,
          appVerification: explicit.source(),
        );
        expect(explicit.requests.last.siteKey, _enterpriseKey);
        expect(explicit.requests.last.languageCode, 'ro');
      },
    );

    test('the Enterprise token never shows in an error', () async {
      backend
        ..on('recaptchaConfig', (_) => _config(phone: 'ENFORCE'))
        ..on(
          'accounts:sendVerificationCode',
          (Map<String, Object?> body) => errorResponse(
            'INVALID_APP_CREDENTIAL : ${body['captchaResponse']} for $_phone',
          ),
        );
      try {
        await backend
            .create(recaptchaEnterprise: _Tokens().source())
            .verifyPhoneNumber(
              _phone,
              appVerification: _V2Tokens().verification,
            );
        fail('no error');
      } on FirebaseAuthException catch (e) {
        expect(e.code, 'invalid-app-credential');
        expect(
          '$e ${e.message} ${e.serverCode}',
          isNot(contains('enterprise-1')),
        );
        expect('$e ${e.message} ${e.serverCode}', isNot(contains(_phone)));
      }
    });

    test(
      'an SMS second factor: the fields go inside phoneEnrollmentInfo',
      () async {
        backend
          ..on('recaptchaConfig', (_) => _config(phone: 'ENFORCE'))
          ..on(
            'mfaEnrollment:start',
            (_) => jsonResponse(<String, Object?>{
              'phoneSessionInfo': <String, Object?>{'sessionInfo': 'enrol-1'},
            }),
          );
        final _Tokens tokens = _Tokens();
        final FirebaseUserAuth auth = backend.create(
          recaptchaEnterprise: tokens.source(),
        );
        await auth.signInWithEmailAndPassword(email: 'a@b.c', password: 'pw');
        expect(
          await auth.startPhoneEnrollment(
            _phone,
            appVerification: _V2Tokens().verification,
          ),
          'enrol-1',
        );
        final Map<String, Object?> body = backend
            .bodiesOf('mfaEnrollment:start')
            .single;
        expect(body['phoneEnrollmentInfo'], <String, Object?>{
          'phoneNumber': _phone,
          'captchaResponse': 'enterprise-1',
          'clientType': 'CLIENT_TYPE_WEB',
          'recaptchaVersion': 'RECAPTCHA_ENTERPRISE',
        });
        expect(tokens.requests.single.action, RecaptchaAction.mfaSmsEnrollment);
      },
    );

    test('a tenant reads its own configuration', () async {
      backend.on('recaptchaConfig', (_) => _config(phone: 'ENFORCE'));
      final FirebaseUserAuth auth = backend.create(
        recaptchaEnterprise: _Tokens().source(),
      )..tenantId = 'tenant-2';
      await auth.verifyPhoneNumber(
        _phone,
        appVerification: _V2Tokens().verification,
      );
      expect(_configQueries(backend).single['tenantId'], 'tenant-2');
      expect(
        backend.bodiesOf('accounts:sendVerificationCode').single['tenantId'],
        'tenant-2',
      );
    });
  });

  group('a failing token source', () {
    /// A source that fails with [error] on every call.
    _Tokens failing(Exception error) => _Tokens(answer: (_) => throw error);

    const RecaptchaFailure blocked = RecaptchaFailure(
      RecaptchaFailureReason.scriptLoad,
      'enterprise.js blocked',
    );

    setUp(() {
      backend
        ..on(
          'recaptchaParams',
          (_) => jsonResponse(<String, Object?>{'recaptchaSiteKey': 'v2-key'}),
        )
        ..on(
          'accounts:sendVerificationCode',
          (_) => jsonResponse(<String, Object?>{'sessionInfo': 'session-1'}),
        );
    });

    test('AUDIT, password: the request goes with NO_RECAPTCHA', () async {
      backend.on('recaptchaConfig', (_) => _config(email: 'AUDIT'));
      final _Tokens tokens = failing(blocked);
      final FirebaseUserAuth auth = backend.create(
        recaptchaEnterprise: tokens.source(),
      );
      await auth.initializeRecaptchaConfig();
      await auth.signInWithEmailAndPassword(email: 'a@b.c', password: 'pw');
      await auth.sendPasswordResetEmail(email: 'a@b.c');
      final Map<String, Object?> signIn = backend
          .bodiesOf('accounts:signInWithPassword')
          .single;
      expect(signIn['captchaResponse'], 'NO_RECAPTCHA');
      expect(signIn['clientType'], 'CLIENT_TYPE_WEB');
      expect(signIn['recaptchaVersion'], 'RECAPTCHA_ENTERPRISE');
      expect(
        backend.bodiesOf('accounts:sendOobCode').single['captchaResp'],
        'NO_RECAPTCHA',
      );
      // Each request asked twice (the retry after reading the configuration again).
      expect(tokens.requests, hasLength(4));
    });

    test('ENFORCE, password: the failure is thrown, nothing is sent', () async {
      backend.on('recaptchaConfig', (_) => _config(email: 'ENFORCE'));
      final FirebaseUserAuth auth = backend.create(
        recaptchaEnterprise: failing(blocked).source(),
      );
      await auth.initializeRecaptchaConfig();
      await expectLater(
        auth.signInWithEmailAndPassword(email: 'a@b.c', password: 'pw'),
        throwsAuth('internal-error'),
      );
      expect(backend.methods, isNot(contains('accounts:signInWithPassword')));
    });

    test('AUDIT, SMS: the v2 token goes instead', () async {
      backend.on('recaptchaConfig', (_) => _config(phone: 'AUDIT'));
      final _V2Tokens v2 = _V2Tokens();
      await backend
          .create(recaptchaEnterprise: failing(blocked).source())
          .verifyPhoneNumber(_phone, appVerification: v2.verification);
      expect(
        backend.bodiesOf('accounts:sendVerificationCode').single,
        <String, Object?>{
          'phoneNumber': _phone,
          'recaptchaToken': 'v2-1',
          'captchaResponse': 'NO_RECAPTCHA',
          'clientType': 'CLIENT_TYPE_WEB',
          'recaptchaVersion': 'RECAPTCHA_ENTERPRISE',
        },
      );
      expect(v2.requests, hasLength(1));
    });

    test('ENFORCE, SMS: the failure is thrown, no SMS, no v2 token', () async {
      backend.on('recaptchaConfig', (_) => _config(phone: 'ENFORCE'));
      final _V2Tokens v2 = _V2Tokens();
      await expectLater(
        backend
            .create(
              recaptchaEnterprise: failing(
                const RecaptchaFailure(RecaptchaFailureReason.widget, 'x'),
              ).source(),
            )
            .verifyPhoneNumber(_phone, appVerification: v2.verification),
        throwsAuth('network-request-failed'),
      );
      expect(backend.methods, isNot(contains('accounts:sendVerificationCode')));
      expect(v2.requests, isEmpty);
    });

    test(
      'AUDIT: the person\'s timeout, cancel or a newer check is thrown',
      () async {
        for (final (Exception error, String code) in <(Exception, String)>[
          (
            const FirebaseAuthException(code: 'timeout', message: 'late'),
            'timeout',
          ),
          (
            const FirebaseAuthException(code: 'user-cancelled', message: 'no'),
            'user-cancelled',
          ),
          (
            const RecaptchaFailure(RecaptchaFailureReason.superseded, 'newer'),
            'cancelled',
          ),
        ]) {
          backend = FakeBackend()
            ..on(
              'recaptchaConfig',
              (_) => _config(email: 'AUDIT', phone: 'AUDIT'),
            );
          final _Tokens tokens = failing(error);
          final FirebaseUserAuth auth = backend.create(
            recaptchaEnterprise: tokens.source(),
          );
          await auth.initializeRecaptchaConfig();
          await expectLater(
            auth.signInWithEmailAndPassword(email: 'a@b.c', password: 'pw'),
            throwsAuth(code),
            reason: code,
          );
          await expectLater(
            auth.verifyPhoneNumber(
              _phone,
              appVerification: _V2Tokens().verification,
            ),
            throwsAuth(code),
            reason: code,
          );
          expect(tokens.requests, hasLength(2), reason: 'not retried: $code');
          expect(
            backend.methods,
            everyElement(
              isNot(
                anyOf(
                  'accounts:signInWithPassword',
                  'accounts:sendVerificationCode',
                ),
              ),
            ),
          );
        }
      },
    );
  });

  group('the password token in errors', () {
    test('an echo of the token in an error is redacted', () async {
      backend
        ..on('recaptchaConfig', (_) => _config(email: 'ENFORCE'))
        ..on(
          'accounts:signInWithPassword',
          (Map<String, Object?> body) => errorResponse(
            'INVALID_RECAPTCHA_TOKEN : ${body['captchaResponse']} was refused',
          ),
        )
        ..on(
          'accounts:sendOobCode',
          (Map<String, Object?> body) =>
              errorResponse('INVALID_RECAPTCHA_TOKEN : ${body['captchaResp']}'),
        );
      final FirebaseUserAuth auth = backend.create(
        recaptchaEnterprise: _Tokens().source(),
      );
      await auth.initializeRecaptchaConfig();
      for (final (Future<Object?> Function() call, String token)
          in <(Future<Object?> Function(), String)>[
            (
              () => auth.signInWithEmailAndPassword(
                email: 'a@b.c',
                password: 'pw',
              ),
              'enterprise-1',
            ),
            (() => auth.sendPasswordResetEmail(email: 'a@b.c'), 'enterprise-2'),
          ]) {
        try {
          await call();
          fail('no error');
        } on FirebaseAuthException catch (e) {
          expect(e.code, 'invalid-recaptcha-token');
          expect('$e ${e.message} ${e.serverCode}', isNot(contains(token)));
          expect(e.message, contains('<redacted>'));
        }
      }
    });
  });
}
