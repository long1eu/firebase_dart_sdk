// File created by
// Lung Razvan <long1eu>
// on 14/12/2019

part of firebase_auth_example;

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
        return _signInWithCredentialEmailAndPassword(option);
        break;
      case FirebaseAuthOption.phoneCredentials:
        return _sendSignInWithPhoneNumber(option);
        break;
      case FirebaseAuthOption.googleCredentials:
        return _signInWithCredentialGoogle(option);
        break;
      case FirebaseAuthOption.facebookCredentials:
        return _signInWithCredentialFacebook(option);
        break;
      case FirebaseAuthOption.twitterCredentials:
        return _signInWithCredentialTwitter(option);
        break;
      case FirebaseAuthOption.githubCredentials:
        return _signInWithCredentialGitHub(option);
        break;
      case FirebaseAuthOption.yahooCredentials:
        break;
      case FirebaseAuthOption.microsoftCredentials:
        break;
      case FirebaseAuthOption.appleCredentials:
        break;
    }
  }
}
