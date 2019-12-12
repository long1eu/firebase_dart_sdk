// File created by
// Lung Razvan <long1eu>
// on 11/12/2019

part of firebase_auth_example;

Future<void> noUserWelcome() async {
  console //
    ..println('Welcome!'.bold.reset)
    ..println('');

  return noUserOptionsDialog();
}

Future<void> noUserOptionsDialog() async {
  const List<FirebaseAuthOptions> options = FirebaseAuthOptions.authValues;
  console.println('Auth'.bold.red.reset);
  final MultipleOptions multipleOptions = MultipleOptions(
    question: 'What do you want to do?',
    optionsCount: options.length,
    builder: (int i) => options[i].name,
    descriptionBuilder: (int i) => options[i].description,
    validator: (String response) {
      String value = response;
      if (value.startsWith('@')) {
        value = value.substring(1);
      }

      final int option = int.tryParse(value);
      final int exitOption = options.length + 1;
      if (option == null || option.isNegative || option > exitOption) {
        return 'This time with a number between 1-$exitOption';
      }

      return null;
    },
  );

  AuthResult result;
  final int optionIndex = await multipleOptions.show();
  if (optionIndex == -1) {
    close();
  } else {
    console.clearScreen();
    final FirebaseAuthOptions option = options[optionIndex];
    switch (option) {
      case FirebaseAuthOptions.languageCode:
        await _changeLanguageCode(option);
        break;
      case FirebaseAuthOptions.fetchSignInMethodsForEmail:
        await _fetchSignInMethod(option);
        break;
      case FirebaseAuthOptions.createUserWithEmailAndPassword:
        result = await _createUser(option);
        break;
      case FirebaseAuthOptions.signInWithEmailAndPassword:
        result = await _signInWithEmailAndPassword(option);
        break;
      case FirebaseAuthOptions.sendSignInWithEmailLink:
        break;
      case FirebaseAuthOptions.signInAnonymously:
        break;
      case FirebaseAuthOptions.signInWithCustomToken:
        break;
      case FirebaseAuthOptions.verifyPhoneNumber:
        break;
      case FirebaseAuthOptions.signInWithCredential:
        break;
    }
  }

  // We use this so we allow the user to observe the completion message.
  await Future<void>.delayed(const Duration(seconds: 1));
  if (result == null) {
    return noUserOptionsDialog();
  } else {
    return userWelcome();
  }
}
