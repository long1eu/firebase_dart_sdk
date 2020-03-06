// File created by
// Lung Razvan <long1eu>
// on 16/12/2019

part of firebase_auth_example;

Future<AuthResult> _signInWithEmailAndPasswordCredential(
    FirebaseAuthOption option) async {
  final AuthCredential credential = await _getEmailPasswordAuthCredential();
  return _presentSignInWithCredential(credential);
}

Future<AuthResult> _sendSignInWithPhoneNumberCredential(
    FirebaseAuthOption option) async {
  final PhoneAuthCredential credential = await _getPhoneAuthCredential();
  return __signInWithPhoneCredential(credential);
}

Future<AuthResult> __signInWithPhoneCredential(
    PhoneAuthCredential credential) async {
  try {
    return _presentSignInWithCredential(credential);
  } on FirebaseAuthError catch (error) {
    await _stopAllProgress();
    if (error == FirebaseAuthError.invalidVerificationCode) {
      console //
        ..println('The SMS verification code is invalid. Try again.'.red.reset)
        ..println();
      return __signInWithPhoneCredential(credential);
    }

    rethrow;
  }
}

Future<AuthResult> _signInWithGoogleCredential(
    FirebaseAuthOption option) async {
  final AuthCredential credential = await _getGoogleAuthCredential();
  return _presentSignInWithCredential(credential);
}

Future<AuthResult> _signInWithFacebookCredential(
    FirebaseAuthOption option) async {
  final FacebookAuthCredential credential = await _getFacebookAuthCredential();
  return _presentSignInWithCredential(credential);
}

Future<AuthResult> _signInWithCredentialGitHub(
    FirebaseAuthOption option) async {
  final AuthCredential credential = await _getGithubAuthCredential();
  return _presentSignInWithCredential(credential);
}

Future<AuthResult> _signInWithCredentialTwitter(
    FirebaseAuthOption option) async {
  final TwitterAuthCredential credential = await _getTwitterAuthCredential();
  return _presentSignInWithCredential(credential);
}

Future<AuthResult> _signInWithYahooCredential(FirebaseAuthOption option) async {
  final OAuthCredential credential = await _getYahooAuthCredential();
  return _presentSignInWithCredential(credential);
}

Future<AuthResult> _signInWithMicrosoftCredential(
    FirebaseAuthOption option) async {
  final AuthCredential credential = await _getMicrosoftAuthCredential();
  return _presentSignInWithCredential(credential);
}
