// validatePassword: the v2/passwordPolicy request, the checks of the JS SDK's PasswordPolicyImpl, the cache per
// tenant, and the refetch after password-does-not-meet-requirements. The Auth emulator does not implement
// v2/passwordPolicy (it answers 501), so this is tested with the fake backend only.

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'fakes.dart';
import 'harness.dart';

void main() {
  late FakeBackend backend;
  late FirebaseUserAuth auth;
  late Map<String, Object?> policy;

  final Map<String, Object?> strict = <String, Object?>{
    'customStrengthOptions': <String, Object?>{
      'minPasswordLength': 8,
      'maxPasswordLength': 12,
      'containsLowercaseCharacter': true,
      'containsUppercaseCharacter': true,
      'containsNumericCharacter': true,
      'containsNonAlphanumericCharacter': true,
    },
    'allowedNonAlphanumericCharacters': <Object?>['!', r'$', '%'],
    'enforcementState': 'ENFORCE',
    'forceUpgradeOnSignin': true,
    'schemaVersion': 1,
  };

  setUp(() {
    backend = FakeBackend();
    auth = backend.create();
    policy = strict;
    backend.on('passwordPolicy', (_) => jsonResponse(policy));
  });

  tearDown(() => auth.dispose());

  List<http.Request> policyRequests() => <http.Request>[
    for (final http.Request r in backend.requests)
      if (r.url.pathSegments.last == 'passwordPolicy') r,
  ];

  test('the request of the JS SDK', () async {
    auth.languageCode = 'de';
    await auth.validatePassword('x');
    final http.Request request = policyRequests().single;
    expect(request.method, 'GET');
    expect(
      request.url.toString(),
      'https://identitytoolkit.googleapis.com/v2/passwordPolicy?key=$apiKey',
    );
    expect(request.headers['X-Firebase-Locale'], 'de');
    expect(request.headers['X-Client-Version'], FirebaseUserAuth.clientVersion);

    await auth.dispose();
    auth = backend.create(emulatorHost: '127.0.0.1:9099')
      ..tenantId = 'tenant 1';
    await auth.validatePassword('x');
    expect(
      policyRequests().last.url.toString(),
      'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v2/passwordPolicy?tenantId=tenant+1&key=$apiKey',
    );
  });

  test('each requirement', () async {
    Future<PasswordValidationStatus> check(String password) =>
        auth.validatePassword(password);
    PasswordValidationStatus status = await check('Abcdef1!');
    expect(status.isValid, isTrue);
    expect(status.passwordPolicy.minPasswordLength, 8);
    expect(status.passwordPolicy.enforcementState, 'ENFORCE');
    expect(status.passwordPolicy.forceUpgradeOnSignin, isTrue);

    status = await check('Ab1!');
    expect(status.isValid, isFalse);
    expect(status.meetsMinPasswordLength, isFalse);
    expect(status.meetsMaxPasswordLength, isTrue);

    status = await check('Abcdefghijk1!');
    expect(status.meetsMaxPasswordLength, isFalse);

    status = await check('abcdefg1!');
    expect(status.meetsUppercaseRequirement, isFalse);
    expect(status.meetsLowercaseRequirement, isTrue);
    status = await check('ABCDEFG1!');
    expect(status.meetsLowercaseRequirement, isFalse);
    status = await check('Abcdefgh!');
    expect(status.meetsDigitsRequirement, isFalse);
    // '#' is not one of the allowed symbols.
    status = await check('Abcdefg1#');
    expect(status.meetsSymbolsRequirement, isFalse);
    expect(status.isValid, isFalse);

    // An empty password fails the length, as in the JS SDK; no exception.
    status = await check('');
    expect(status.isValid, isFalse);
    expect(status.meetsMinPasswordLength, isFalse);
    // Fetched once.
    expect(policyRequests(), hasLength(1));
  });

  test('defaults of a policy that says little', () async {
    policy = <String, Object?>{
      'customStrengthOptions': <String, Object?>{},
      'enforcementState': 'ENFORCEMENT_STATE_UNSPECIFIED',
      'schemaVersion': 1,
    };
    final PasswordValidationStatus short = await auth.validatePassword('12345');
    expect(short.isValid, isFalse);
    expect(short.passwordPolicy.minPasswordLength, 6);
    expect(short.passwordPolicy.enforcementState, 'OFF');
    expect(short.passwordPolicy.maxPasswordLength, isNull);
    final PasswordValidationStatus ok = await auth.validatePassword('123456');
    expect(ok.isValid, isTrue);
    expect(ok.meetsSymbolsRequirement, isTrue);
  });

  test('an unknown schema version', () async {
    policy = <String, Object?>{...strict, 'schemaVersion': 2};
    await expectLater(
      auth.validatePassword('x'),
      throwsAuth('unsupported-password-policy-schema-version'),
    );
  });

  test('cached per tenant', () async {
    await auth.validatePassword('x');
    auth.tenantId = 'tenant-1';
    await auth.validatePassword('x');
    await auth.validatePassword('y');
    auth.tenantId = null;
    await auth.validatePassword('z');
    expect(policyRequests(), hasLength(2));
    expect(policyRequests().last.url.queryParameters['tenantId'], 'tenant-1');
  });

  test(
    'fetched again after password-does-not-meet-requirements, when cached',
    () async {
      backend.on(
        'accounts:signUp',
        (_) => errorResponse(
          'PASSWORD_DOES_NOT_MEET_REQUIREMENTS : Missing password requirements: [Password must contain a numeric character]',
        ),
      );
      backend.on(
        'accounts:resetPassword',
        (_) => errorResponse('PASSWORD_DOES_NOT_MEET_REQUIREMENTS'),
      );
      // Nothing cached: nothing fetched.
      await expectLater(
        auth.createUserWithEmailAndPassword(
          email: 'a@example.com',
          password: 'x',
        ),
        throwsAuth('password-does-not-meet-requirements'),
      );
      await pump();
      expect(policyRequests(), isEmpty);

      await auth.validatePassword('x');
      policy = <String, Object?>{
        ...strict,
        'customStrengthOptions': <String, Object?>{'minPasswordLength': 10},
      };
      await expectLater(
        auth.createUserWithEmailAndPassword(
          email: 'a@example.com',
          password: 'x',
        ),
        throwsAuth('password-does-not-meet-requirements'),
      );
      await pump();
      expect(policyRequests(), hasLength(2));
      expect(
        (await auth.validatePassword('x')).passwordPolicy.minPasswordLength,
        10,
      );
      await expectLater(
        auth.confirmPasswordReset(code: 'c', newPassword: 'x'),
        throwsAuth('password-does-not-meet-requirements'),
      );
      await pump();
      expect(policyRequests(), hasLength(3));
      // Other errors do not refetch.
      backend.on(
        'accounts:signInWithPassword',
        (_) => errorResponse('INVALID_PASSWORD'),
      );
      await expectLater(
        auth.signInWithEmailAndPassword(email: 'a@example.com', password: 'x'),
        throwsAuth('wrong-password'),
      );
      await pump();
      expect(policyRequests(), hasLength(3));
    },
  );

  test('a policy that cannot be fetched is an error', () async {
    backend.on('passwordPolicy', (_) => errorResponse('INVALID_TENANT_ID'));
    await expectLater(
      auth.validatePassword('x'),
      throwsAuth('invalid-tenant-id'),
    );
  });
}
