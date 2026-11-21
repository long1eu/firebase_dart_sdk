// Phone sign-in on top of the client's verifyPhoneNumber and phone credentials:
// the ConfirmationResult of signInWithPhoneNumber and linkWithPhoneNumber, and
// the RecaptchaVerifier that firebase_auth creates for them.

import 'package:firebase_auth_dart_platform/src/convert.dart';
import 'package:firebase_auth_dart_platform/src/firebase_auth.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart'
    as dart_auth;

/// What a [DartConfirmationResult] does with the credential of its code: sign
/// in, or link it to the user that asked.
typedef PhoneConfirmation =
    Future<dart_auth.UserCredential> Function(
      dart_auth.PhoneAuthCredential credential,
    );

/// The result of `signInWithPhoneNumber` and `User.linkWithPhoneNumber`: the
/// SMS was sent; [confirm] finishes with its code.
class DartConfirmationResult extends ConfirmationResultPlatform {
  DartConfirmationResult(this._auth, super.verificationId, this._confirmation);

  final DartFirebaseAuth _auth;
  final PhoneConfirmation _confirmation;

  /// Signs in (or links) with [verificationCode], the code of the SMS.
  @override
  Future<UserCredentialPlatform> confirm(String verificationCode) => guard(
    _auth,
    () async => _auth.resultOf(
      await _confirmation(
        dart_auth.PhoneAuthProvider.credential(
          verificationId: verificationId,
          verificationCode: verificationCode,
        ),
      ),
    ),
  );
}

/// The `RecaptchaVerifier` that `firebase_auth` creates for
/// `signInWithPhoneNumber` and `linkWithPhoneNumber` when the app passes none.
///
/// It renders nothing: the proof of a phone request is the `AppVerification`
/// passed to `FirebaseAuthDart.use` (by default the reCAPTCHA page of the
/// client in the system browser), which the phone members use whatever
/// verifier they get. [verify] throws `unimplemented`.
class DartRecaptchaVerifierFactory extends RecaptchaVerifierFactoryPlatform {
  @override
  RecaptchaVerifierFactoryPlatform delegateFor({
    required FirebaseAuthPlatform auth,
    String? container,
    RecaptchaVerifierSize size = RecaptchaVerifierSize.normal,
    RecaptchaVerifierTheme theme = RecaptchaVerifierTheme.light,
    RecaptchaVerifierOnSuccess? onSuccess,
    RecaptchaVerifierOnError? onError,
    RecaptchaVerifierOnExpired? onExpired,
  }) => this;

  @override
  String get type => 'recaptcha';

  @override
  void clear() {}

  @override
  Future<int> render() async => 0;

  @override
  Future<String> verify() async => throw unimplemented(
    'RecaptchaVerifier.verify',
    'the reCAPTCHA token of a phone request comes from the AppVerification '
        'passed to FirebaseAuthDart.use.',
  );
}
