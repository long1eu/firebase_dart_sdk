// The provider id and sign-in method names are FlutterFire's (and the JS SDK's) constants, in their
// upper case.
// ignore_for_file: constant_identifier_names

import 'package:firebase_auth_providers_dart/src/auth_credential.dart';
import 'package:firebase_auth_providers_dart/src/auth_exception.dart';
import 'package:firebase_auth_providers_dart/src/firebase_user_auth.dart';

/// Makes the credential of a phone number verified by an SMS code (`FIRPhoneAuthProvider` of the
/// iOS SDK, `PhoneAuthProvider` of the JS SDK and of FlutterFire).
///
/// [FirebaseUserAuth.verifyPhoneNumber] sends the code and returns a verification id; [credential]
/// pairs that id with the code the user typed in, for [FirebaseUserAuth.signInWithCredential],
/// [FirebaseUserAuth.linkWithCredential], [FirebaseUserAuth.reauthenticateWithCredential] and
/// [FirebaseUserAuth.updatePhoneNumber]. The same pair finishes an SMS second factor
/// ([FirebaseUserAuth.finalizePhoneEnrollment], `MultiFactorResolver.resolveSignInWithPhone`).
///
/// ```dart
/// final String verificationId = await auth.verifyPhoneNumber(
///   '+15555550100',
///   appVerification: AppVerification.recaptchaV2Loopback(),
/// );
/// final String code = await askTheUserForTheCode(); // your own code field
/// await auth.signInWithCredential(
///   PhoneAuthProvider.credential(verificationId: verificationId, verificationCode: code),
/// );
/// ```
abstract final class PhoneAuthProvider {
  /// The provider id: `phone`.
  static const String PROVIDER_ID = 'phone';

  /// The sign-in method of a phone number: `phone`.
  static const String PHONE_SIGN_IN_METHOD = 'phone';

  /// The credential of [verificationId] (what [FirebaseUserAuth.verifyPhoneNumber] returned) and
  /// [verificationCode] (the code of the SMS), like
  /// `credential(withVerificationID:verificationCode:)` of the iOS SDK. Nothing is checked until
  /// the credential is used.
  static PhoneAuthCredential credential({
    required String verificationId,
    required String verificationCode,
  }) => PhoneAuthCredential._(verificationId, verificationCode);
}

/// A credential of the phone provider: a verification id and the code of its SMS
/// (`FIRPhoneAuthCredential` of the iOS SDK). Make it with [PhoneAuthProvider.credential].
///
/// Both values are secrets: [toString] leaves them out, and no error of this package quotes them.
class PhoneAuthCredential extends AuthCredential {
  const PhoneAuthCredential._(this.verificationId, this.verificationCode)
    : super(
        providerId: PhoneAuthProvider.PROVIDER_ID,
        signInMethod: PhoneAuthProvider.PHONE_SIGN_IN_METHOD,
      );

  /// The verification id of [FirebaseUserAuth.verifyPhoneNumber] (the `sessionInfo` of the REST
  /// API). Not part of [toString].
  final String verificationId;

  /// The code of the SMS. Not part of [toString].
  final String verificationCode;
}

/// What replaces a secret in the text of an error.
const String _redacted = '<redacted>';

/// A run of digits with the separators of a written phone number.
final RegExp _phoneShaped = RegExp(r'\+?\d[\d ().-]{5,}\d');

/// [error] without any of [secrets] (a phone number, a verification id, an SMS code, a reCAPTCHA
/// token), for the errors of the phone requests: each secret in [FirebaseAuthException.message] and
/// [FirebaseAuthException.serverCode] is replaced by `<redacted>` (a phone number also in its
/// digits-only form), and so is anything shaped like a phone number (seven digits or more), such as
/// the number of an SMS second factor, which the client knows only masked; and
/// [FirebaseAuthException.phoneNumber] and [FirebaseAuthException.serverResponse] are dropped. A
/// [FirebaseAuthMultiFactorException] is returned as it is: its message is one of the package's,
/// and its hints carry masked phone numbers only. Not exported.
FirebaseAuthException redactPhoneSecrets(
  FirebaseAuthException error,
  Iterable<String?> secrets,
) {
  if (error is FirebaseAuthMultiFactorException) {
    return error;
  }
  final List<String> forms = _formsOf(secrets);
  String scrub(String text) {
    for (final String secret in forms) {
      text = text.replaceAll(secret, _redacted);
    }
    return text.replaceAllMapped(
      _phoneShaped,
      (Match m) =>
          m[0]!.replaceAll(RegExp(r'\D'), '').length >= 7 ? _redacted : m[0]!,
    );
  }

  final String? serverCode = error.serverCode;
  return FirebaseAuthException(
    code: error.code,
    message: scrub(error.message),
    serverCode: serverCode == null ? null : scrub(serverCode),
    httpStatus: error.httpStatus,
    email: error.email,
    tenantId: error.tenantId,
    credential: error.credential,
    cause: error.cause,
  );
}

/// The non-empty [secrets] and, for a phone number (one that starts with `+`), its digits alone (it
/// may come back without its `+` and spaces); longest first, so that a secret inside another is
/// replaced after it.
List<String> _formsOf(Iterable<String?> secrets) {
  final Set<String> forms = <String>{};
  for (final String? secret in secrets) {
    if (secret == null || secret.isEmpty) {
      continue;
    }
    forms.add(secret);
    final String digits = secret.replaceAll(RegExp(r'\D'), '');
    if (secret.startsWith('+') && digits.length >= 4) {
      forms.add(digits);
    }
  }
  return forms.toList()
    ..sort((String a, String b) => b.length.compareTo(a.length));
}
