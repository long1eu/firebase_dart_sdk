// File created by
// Lung Razvan <long1eu>
// on 14/12/2019

part of firebase_auth_example;

// ignore_for_file: dead_code, missing_return
Future<AuthResult> _signInWithCredential(FirebaseAuthOption option) async {
  const List<FirebaseAuthOption> options = FirebaseAuthOption.credentialsValues;
  final MultipleOptions multipleOptions = MultipleOptions(
    question: 'Pick the provider you want to user ',
    optionsCount: options.length,
    builder: (int i) => options[i].name,
    validator: (String response) {
      final String value = response;
      final int option = int.tryParse(value);
      final int exitOption = options.length + 1;
      if (option == null || option.isNegative || option > exitOption) {
        return 'This time with a number between 1-$exitOption';
      }

      return null;
    },
  );

  final int optionIndex = await multipleOptions.show();
  if (optionIndex == -1) {
    close();
  } else {
    console.clearScreen();

    final FirebaseAuthOption option = options[optionIndex];
    switch (option) {
      case FirebaseAuthOption.emailAndPasswordCredentials:
        return _signInWithEmailAndPasswordCredential(option);
        break;
      case FirebaseAuthOption.phoneCredentials:
        return _sendSignInWithPhoneNumberCredential(option);
        break;
      case FirebaseAuthOption.googleCredentials:
        return _signInWithGoogleCredential(option);
        break;
      case FirebaseAuthOption.facebookCredentials:
        return _signInWithFacebookCredential(option);
        break;
      case FirebaseAuthOption.twitterCredentials:
        return _signInWithCredentialTwitter(option);
        break;
      case FirebaseAuthOption.githubCredentials:
        return _signInWithCredentialGitHub(option);
        break;
      case FirebaseAuthOption.yahooCredentials:
        throw StateError('Not yet implemented.');
        return _signInWithYahooCredential(option);
        break;
      case FirebaseAuthOption.microsoftCredentials:
        throw StateError('Not yet implemented.');
        return _signInWithMicrosoftCredential(option);
        break;
      case FirebaseAuthOption.appleCredentials:
        throw StateError('Not yet implemented.');
        break;
    }
  }
}
