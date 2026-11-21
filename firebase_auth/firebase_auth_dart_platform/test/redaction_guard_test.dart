// The redaction guard of the shim: every type of this package that holds a secret (a token, a
// code, a pending credential, a proof, a TOTP secret), filled with sentinel values, and the check
// that no sentinel reaches a string that ends up in logs: `toString`, the message of an exception
// and the string form of what an exception carries. The client's own types have their guard in
// firebase_auth_providers_dart/test/redaction_guard_test.dart.
//
// Adding a type that holds a secret? Add one line to `_holders`. If it carries another object that
// holds a secret, add that object to `_stringsOf`.
//
// Not checked here, as they are FlutterFire's own classes and print the same on its native
// platforms: `User.toString()` of `firebase_auth` (the refresh token), `AdditionalUserInfo`
// (the provider's profile) and `AuthCredential.asMap()` (the serialization of a credential).

import 'package:firebase_auth_dart_platform/src/convert.dart';
import 'package:firebase_auth_dart_platform/src/firebase_auth.dart'
    show DartFirebaseAuth;
import 'package:firebase_auth_dart_platform/src/multi_factor.dart';
import 'package:firebase_auth_dart_platform/src/phone.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart'
    as dart_auth;
import 'package:flutter_test/flutter_test.dart';

/// What every secret below contains; no checked string may contain it (in any case).
const String _sentinel = 'sentinel';

/// A client credential with every token field set.
dart_auth.OAuthCredential _oauth() => const dart_auth.OAuthCredential(
  providerId: 'oidc.example',
  signInMethod: 'oidc.example',
  idToken: 'sentinel-id-token',
  accessToken: 'sentinel-access-token',
  secret: 'sentinel-token-secret',
  rawNonce: 'sentinel-raw-nonce',
  pendingToken: 'sentinel-pending-token',
);

/// A client TOTP secret whose key and session are sentinels.
dart_auth.TotpSecret _totpSecret() =>
    dart_auth.TotpSecret.fromResponse(<String, Object?>{
      'sharedSecretKey': 'sentinel-shared-secret',
      'sessionInfo': 'sentinel-session-info',
    }, accountName: 'sentinel@example.com')!;

/// A client phone credential of a temporary proof.
dart_auth.PhoneAuthCredential _proof() =>
    dart_auth.PhoneAuthCredential.fromJson(<String, Object?>{
      'temporaryProof': 'sentinel-temporary-proof',
      'phoneNumber': 'sentinel-phone',
    })!;

/// The objects to check, one line per type (or per form of a type).
final List<(String, Object Function())>
_holders = <(String, Object Function())>[
  ('DartOAuthCredential', () => credentialOf(_oauth())!),
  ('DartPhoneProofCredential', () => credentialOf(_proof())!),
  (
    'EmailAuthCredential (from the client)',
    () => credentialOf(
      dart_auth.EmailAuthProvider.credential(
        email: 'sentinel@example.com',
        password: 'sentinel-password',
      ),
    )!,
  ),
  (
    'PhoneAuthCredential of the interface, through getAssertion',
    () => DartPhoneMultiFactorGenerator().getAssertion(
      PhoneAuthProvider.credential(
        verificationId: 'sentinel-verification-id',
        smsCode: 'sentinel-sms-code',
      ),
    ),
  ),
  ('DartTotpSecret', () => DartTotpSecret(_totpSecret(), 'issuer')),
  (
    'DartTotpEnrollmentAssertion',
    () => DartTotpEnrollmentAssertion(_totpSecret(), 'sentinel-otp'),
  ),
  (
    'DartTotpSignInAssertion',
    () => DartTotpSignInAssertion('enrollment-1', 'sentinel-otp'),
  ),
  ('DartMultiFactorSignInSession', () => DartMultiFactorSignInSession(null)),
  (
    'DartConfirmationResult',
    () => DartConfirmationResult(
      DartFirebaseAuth(),
      'sentinel-verification-id',
      (dart_auth.PhoneAuthCredential credential) => throw UnimplementedError(),
    ),
  ),
  (
    'DartFirebaseAuthException (tagged answer of the backend)',
    () => exceptionOf(
      dart_auth.FirebaseAuthException.fromServer(
        'FEDERATED_USER_ID_ALREADY_LINKED',
        response: const <String, Object?>{
          'providerId': 'google.com',
          'oauthIdToken': 'sentinel-id-token',
          'oauthAccessToken': 'sentinel-access-token',
          'email': 'sentinel@example.com',
        },
      ),
      DartFirebaseAuth(),
    ),
  ),
  (
    'DartFirebaseAuthException (phone proof)',
    () => exceptionOf(
      dart_auth.FirebaseAuthException(
        code: 'credential-already-in-use',
        message: 'This credential is already associated with another account.',
        phoneNumber: 'sentinel-phone',
        credential: _proof(),
      ),
      DartFirebaseAuth(),
    ),
  ),
  (
    'FirebaseAuthMultiFactorExceptionPlatform',
    () => exceptionOf(
      const dart_auth.FirebaseAuthMultiFactorException(
        pendingCredential: 'sentinel-pending-credential',
        hints: <dart_auth.MultiFactorInfo>[
          dart_auth.MultiFactorInfo(
            uid: 'enrollment-1',
            factorId: dart_auth.MultiFactorInfo.phoneFactorId,
            phoneNumber: 'sentinel-phone',
          ),
        ],
      ),
      DartFirebaseAuth(),
    ),
  ),
];

/// The strings of [value] that may end up in logs: its own string form, and those of what it
/// carries.
List<String> _stringsOf(Object value) => <String>[
  '$value',
  if (value is FirebaseAuthException) ...<String>[
    '${value.message}',
    '${value.credential}',
  ],
  if (value is FirebaseAuthMultiFactorExceptionPlatform) ...<String>[
    '${value.resolver.hints}',
    '${value.resolver}',
    '${value.resolver.session}',
    value.resolver.session.id,
  ],
  if (value is MultiFactorSession) value.id,
  if (value is DartPhoneAssertion) '${value.credential}',
  if (value is DartTotpEnrollmentAssertion) '${value.secret}',
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

  test(
    'the sentinels are really in the objects (the guard checks something)',
    () {
      final AuthCredential credential = credentialOf(_oauth())!;
      expect(credential.accessToken, 'sentinel-access-token');
      expect(
        (credential as DartOAuthCredential).source.pendingToken,
        'sentinel-pending-token',
      );
    },
  );
}
