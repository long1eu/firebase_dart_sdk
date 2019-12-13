// File created by
// Lung Razvan <long1eu>
// on 12/12/2019

part of firebase_auth_example;

Future<AuthResult> _sendSignInWithPhoneNumber(FirebaseAuthOption option) async {
  final StringOption option = StringOption(
    question: 'Please enter your phone number.',
    fieldBuilder: () => 'phone: ',
    validator: (String response) {
      if (response.isEmpty) {
        return 'Try a valid phone number.';
      }

      return null;
    },
  );

  final String phoneNumber = await option.show();
  console.println();

  final String verificationId = await FirebaseAuth.instance.verifyPhoneNumber(
    phoneNumber: phoneNumber,
    presenter: (Uri uri) {
      console
        ..println('In order to verify the app please complete the recaptcha change by clicking the link below.')
        ..println(uri.toString().bold.cyan.reset);
    },
  );

  return _signInWithPhoneCredential(phoneNumber, verificationId);
}

Future<AuthResult> _signInWithPhoneCredential(String phoneNumber, String verificationId) async {
  try {
    final AuthCredential credential = await getCredential(phoneNumber, verificationId);

    console.println();
    final Progress progress = Progress('Siging in')..show();
    final AuthResult result = await FirebaseAuth.instance.signInWithCredential(credential);
    await progress.cancel();
    console.clearScreen();
    return result;
  } on FirebaseAuthError catch (error) {
    await _stopAllProgress();
    if (error == FirebaseAuthError.invalidVerificationCode) {
      console //
        ..println('The SMS verification code is invalid. Try again.'.red.reset)
        ..println();
      return _signInWithPhoneCredential(phoneNumber, verificationId);
    }

    rethrow;
  }
}

Future<AuthCredential> getCredential(String phoneNumber, String verificationId) async {
  console.println();
  final StringOption option = StringOption(
    question:
        'Great! A SMS was sent to ${phoneNumber.yellow.reset}. Please type the ${'code'.yellow.reset} you receive.',
    fieldBuilder: () => 'code: ',
    validator: (String response) {
      if (response.isEmpty) {
        return 'Try a non empty code';
      }

      return null;
    },
  );

  final String code = await option.show();
  return PhoneAuthProvider.getCredential(verificationId: verificationId, verificationCode: code);
}
