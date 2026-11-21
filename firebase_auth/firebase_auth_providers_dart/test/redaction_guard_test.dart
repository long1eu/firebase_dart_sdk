// The redaction guard: every type of this package that holds a secret (a password, a token, a
// code, a nonce, a pending credential, a proof) or personal data that its string form leaves out,
// filled with sentinel values, and the check that no sentinel reaches a string that ends up in
// logs: `toString`, the message of an exception, the string form of what an exception or a result
// carries, and the `toJson` of types whose JSON is not meant to carry secrets.
//
// Adding a type that holds a secret? Add one line to `_holders` (or to `_jsonWithoutSecrets` when
// its `toJson` must stay free of secrets). If it carries another object that holds a secret, add
// that object to `_stringsOf`.

import 'dart:convert';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:firebase_auth_providers_dart/src/multi_factor.dart'
    show createMultiFactorResolver;
import 'package:test/test.dart';

/// What every secret below contains; no checked string may contain it (in any case).
const String _sentinel = 'sentinel';

/// An OAuth credential with every token field set.
OAuthCredential _oauth() => const OAuthCredential(
  providerId: 'oidc.example',
  signInMethod: 'oidc.example',
  idToken: 'sentinel-id-token',
  accessToken: 'sentinel-access-token',
  secret: 'sentinel-token-secret',
  rawNonce: 'sentinel-raw-nonce',
  pendingToken: 'sentinel-pending-token',
  appleFullPersonName: AppleFullPersonName(
    givenName: 'sentinel-given-name',
    familyName: 'sentinel-family-name',
  ),
);

/// A JWT (unsigned) whose claims hold sentinels.
String _jwt() {
  String part(Map<String, Object?> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  final String claims = part(<String, Object?>{
    'sub': 'sentinel-uid',
    'email': 'sentinel@example.com',
    'exp': 2000000000,
  });
  return '${part(<String, Object?>{'alg': 'none'})}.$claims.sentinel-signature';
}

/// A resolver whose pending credential is a sentinel; its callbacks are never called here.
MultiFactorResolver _resolver() => createMultiFactorResolver(
  const <MultiFactorInfo>[
    MultiFactorInfo(
      uid: 'enrollment-1',
      factorId: MultiFactorInfo.phoneFactorId,
      phoneNumber: 'sentinel-phone',
      displayName: 'sentinel-display-name',
    ),
  ],
  pendingCredential: 'sentinel-pending-credential',
  resolveTotp: (String pending, String enrollmentId, String code) =>
      throw UnimplementedError(),
  startPhone: (String pending, String enrollmentId, AppVerification proof) =>
      throw UnimplementedError(),
  resolvePhone: (String pending, PhoneAuthCredential credential) =>
      throw UnimplementedError(),
);

/// An answer of the backend for a tagged error: the credential fields and personal data are
/// sentinels.
const Map<String, Object?> _taggedAnswer = <String, Object?>{
  'providerId': 'google.com',
  'oauthIdToken': 'sentinel-id-token',
  'oauthAccessToken': 'sentinel-access-token',
  'email': 'sentinel@example.com',
  'phoneNumber': 'sentinel-phone',
  'rawUserInfo': 'sentinel-raw-user-info',
};

/// The objects to check, one line per type (or per form of a type).
final List<(String, Object Function())>
_holders = <(String, Object Function())>[
  (
    'EmailAuthCredential (password)',
    () => EmailAuthProvider.credential(
      email: 'sentinel@example.com',
      password: 'sentinel-password',
    ),
  ),
  (
    'EmailAuthCredential (link)',
    () => EmailAuthProvider.credentialWithLink(
      email: 'sentinel@example.com',
      emailLink:
          'https://example.firebaseapp.com/__/auth/action?apiKey=key&mode=signIn'
          '&oobCode=sentinel-oob-code',
    ),
  ),
  ('OAuthCredential (every field)', _oauth),
  (
    'OAuthCredential (OAuthProvider.credential)',
    () => OAuthProvider('oidc.example').credential(
      idToken: 'sentinel-id-token',
      accessToken: 'sentinel-access-token',
      secret: 'sentinel-token-secret',
      rawNonce: 'sentinel-raw-nonce',
    ),
  ),
  (
    'OAuthCredential (fromJson with a pending token)',
    () => OAuthCredential.fromJson(<String, Object?>{
      'providerId': 'google.com',
      'signInMethod': 'google.com',
      'pendingToken': 'sentinel-pending-token',
      'nonce': 'sentinel-raw-nonce',
    })!,
  ),
  (
    'PhoneAuthCredential (verification id and code)',
    () => PhoneAuthProvider.credential(
      verificationId: 'sentinel-verification-id',
      verificationCode: 'sentinel-sms-code',
    ),
  ),
  (
    'PhoneAuthCredential (temporary proof)',
    () => PhoneAuthCredential.fromJson(<String, Object?>{
      'temporaryProof': 'sentinel-temporary-proof',
      'phoneNumber': 'sentinel-phone',
    })!,
  ),
  (
    'TotpSecret',
    () => TotpSecret.fromResponse(<String, Object?>{
      'sharedSecretKey': 'sentinel-shared-secret',
      'sessionInfo': 'sentinel-session-info',
    }, accountName: 'sentinel@example.com')!,
  ),
  ('MultiFactorResolver', _resolver),
  ('MultiFactorSession', () => _resolver().session),
  (
    'MultiFactorInfo',
    () => const MultiFactorInfo(
      uid: 'enrollment-1',
      factorId: MultiFactorInfo.phoneFactorId,
      phoneNumber: 'sentinel-phone',
      displayName: 'sentinel-display-name',
    ),
  ),
  (
    'OAuthLoopbackResult',
    () => OAuthLoopbackResult(
      credential: _oauth(),
      idToken: 'sentinel-id-token',
      accessToken: 'sentinel-access-token',
      refreshToken: 'sentinel-refresh-token',
      rawNonce: 'sentinel-raw-nonce',
    ),
  ),
  (
    'OAuthAuthorizationCode',
    () => const OAuthAuthorizationCode(
      code: 'sentinel-authorization-code',
      codeVerifier: 'sentinel-code-verifier',
      redirectUri: 'http://127.0.0.1:1',
      clientId: 'client',
    ),
  ),
  (
    'OAuthAccessToken',
    () => OAuthAccessToken('sentinel-access-token', DateTime.utc(2030)),
  ),
  ('GetTokenResult', () => GetTokenResult(_jwt())),
  (
    'ActionCodeURL',
    () => ActionCodeURL.parseLink(
      'https://example.firebaseapp.com/__/auth/action?apiKey=key&mode=resetPassword'
      '&oobCode=sentinel-oob-code',
    )!,
  ),
  (
    'AdditionalUserInfo',
    () => const AdditionalUserInfo(
      isNewUser: true,
      providerId: 'google.com',
      profile: <String, Object?>{'email': 'sentinel@example.com'},
    ),
  ),
  (
    'UserCredential',
    () => UserCredential(
      const AuthUser(uid: 'uid-1'),
      credential: _oauth(),
      additionalUserInfo: const AdditionalUserInfo(
        isNewUser: false,
        profile: <String, Object?>{'token': 'sentinel-profile'},
      ),
    ),
  ),
  (
    'InMemoryAuthStorage',
    () => InMemoryAuthStorage()..write('key', 'sentinel-session'),
  ),
  (
    'FirebaseAuthException (constructor)',
    () => FirebaseAuthException(
      code: 'credential-already-in-use',
      message: 'This credential is already associated with another account.',
      email: 'sentinel@example.com',
      phoneNumber: 'sentinel-phone',
      credential: _oauth(),
    ),
  ),
  (
    'FirebaseAuthException (tagged answer of the backend)',
    () => FirebaseAuthException.fromServer(
      'FEDERATED_USER_ID_ALREADY_LINKED',
      httpStatus: 400,
      response: _taggedAnswer,
    ),
  ),
  (
    'FirebaseAuthException (needConfirmation)',
    () => FirebaseAuthException.needConfirmation(const <String, Object?>{
      'needConfirmation': true,
      ..._taggedAnswer,
    }),
  ),
  (
    'FirebaseAuthMultiFactorException (fromResponse)',
    () => FirebaseAuthMultiFactorException.fromResponse(<String, Object?>{
      'mfaPendingCredential': 'sentinel-pending-credential',
      'mfaInfo': <Object?>[
        <String, Object?>{
          'mfaEnrollmentId': 'enrollment-1',
          'phoneInfo': 'sentinel-phone',
        },
      ],
    })!,
  ),
  (
    'FirebaseAuthMultiFactorException (with a resolver)',
    () => FirebaseAuthMultiFactorException(
      pendingCredential: 'sentinel-pending-credential',
      hints: _resolver().hints,
      resolver: _resolver(),
    ),
  ),
];

/// The `toJson` of types whose JSON is not meant to carry secrets.
final List<(String, Map<String, Object?> Function())> _jsonWithoutSecrets =
    <(String, Map<String, Object?> Function())>[
      (
        'UserCredential.toJson (credential and profile left out)',
        () => UserCredential(
          const AuthUser(uid: 'uid-1'),
          credential: _oauth(),
          additionalUserInfo: const AdditionalUserInfo(
            isNewUser: false,
            profile: <String, Object?>{'token': 'sentinel-profile'},
          ),
        ).toJson(),
      ),
    ];

/// The strings of [value] that may end up in logs: its own string form, and those of what it
/// carries.
List<String> _stringsOf(Object value) => <String>[
  '$value',
  if (value is FirebaseException) '${value.message}',
  if (value is FirebaseAuthException) ...<String>[
    '${value.credential}',
    '${value.serverResponse}',
  ],
  if (value is FirebaseAuthMultiFactorException) ...<String>[
    '${value.hints}',
    '${value.resolver}',
    '${value.resolver?.session}',
  ],
  if (value is MultiFactorResolver) ...<String>[
    '${value.hints}',
    '${value.session}',
  ],
  if (value is UserCredential) ...<String>[
    '${value.credential}',
    '${value.additionalUserInfo}',
    '${value.user}',
  ],
  if (value is OAuthLoopbackResult) '${value.credential}',
];

void main() {
  group('no sentinel in a string form', () {
    for (final (String name, Object Function() make) in _holders) {
      test(name, () {
        for (final String text in _stringsOf(make())) {
          expect(text.toLowerCase(), isNot(contains(_sentinel)));
        }
      });
    }
  });

  group('no sentinel in a toJson that is not meant to carry secrets', () {
    for (final (String name, Map<String, Object?> Function() make)
        in _jsonWithoutSecrets) {
      test(name, () {
        expect(jsonEncode(make()).toLowerCase(), isNot(contains(_sentinel)));
      });
    }
  });

  test(
    'the sentinels are really in the objects (the guard checks something)',
    () {
      final FirebaseAuthException tagged = FirebaseAuthException.fromServer(
        'FEDERATED_USER_ID_ALREADY_LINKED',
        response: _taggedAnswer,
      );
      expect(
        (tagged.credential! as OAuthCredential).accessToken,
        'sentinel-access-token',
      );
      expect(tagged.serverResponse!['rawUserInfo'], 'sentinel-raw-user-info');
      expect(_oauth().pendingToken, contains(_sentinel));
      expect(jsonEncode(_oauth().toJson()), contains(_sentinel));
    },
  );
}
