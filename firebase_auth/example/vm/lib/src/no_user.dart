// File created by
// Lung Razvan <long1eu>
// on 11/12/2019

part of firebase_auth_example;

Future<void> noUserWelcome() async {
  console //
    ..println('Hi. Welcome!'.bold.reset)
    ..println('');

  return showOptionsDialog();
}

Future<void> showOptionsDialog() async {
  final MultipleOptions multipleOptions = MultipleOptions(
    question: 'What do you want to do?',
    optionsCount: firebaseAuthOptions.length,
    builder: (int i) => firebaseAuthOptions[i].name,
    descriptionBuilder: (int i) => firebaseAuthOptions[i].description,
    validator: (String response) {
      String value = response;
      if (value.startsWith('@')) {
        value = value.substring(1);
      }

      final int option = int.tryParse(value);
      final int exitOption = firebaseAuthOptions.length + 1;
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
    final FirebaseAuthOptions option = FirebaseAuthOptions.valueOf(optionIndex);
    switch (option) {
      case FirebaseAuthOptions.languageCode:
        await _changeLanguageCode(firebaseAuthOptions[optionIndex]);
        break;
      case FirebaseAuthOptions.fetchSignInMethodsForEmail:
        await _fetchSignInMethod(firebaseAuthOptions[optionIndex]);
        break;
      case FirebaseAuthOptions.createUserWithEmailAndPassword:
        await _createUser(firebaseAuthOptions[optionIndex]);
        break;
      case FirebaseAuthOptions.signInWithEmailAndPassword:
        break;
      case FirebaseAuthOptions.sendSignInWithEmailLink:
        break;
      case FirebaseAuthOptions.signInAnonymously:
        break;
      case FirebaseAuthOptions.signInWithCustomToken:
        break;
      case FirebaseAuthOptions.signInWithCredential:
        break;
      case FirebaseAuthOptions.verifyPhoneNumber:
        break;
      case FirebaseAuthOptions.sendPasswordResetEmail:
        break;
      case FirebaseAuthOptions.isSignInWithEmailLink:
        break;
    }
  }

  // We use this so we allow the user to observe the completion message.
  await Future<void>.delayed(const Duration(seconds: 1));
  return showOptionsDialog();
}
