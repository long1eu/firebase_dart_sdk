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
  const List<FirebaseAuthOption> options = FirebaseAuthOption.authValues;
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
    try {
      final FirebaseAuthOption option = options[optionIndex];
      switch (option) {
        case FirebaseAuthOption.languageCode:
          await _changeLanguageCode(option);
          break;
        case FirebaseAuthOption.fetchSignInMethodsForEmail:
          await _fetchSignInMethod(option);
          break;
        case FirebaseAuthOption.createUserWithEmailAndPassword:
          result = await _createUser(option);
          break;
        case FirebaseAuthOption.signInWithEmailAndPassword:
          result = await _signInWithEmailAndPassword(option);
          break;
        case FirebaseAuthOption.sendSignInWithEmailLink:
          result = await _sendSignInWithEmailLink(option);
          break;
        case FirebaseAuthOption.signInAnonymously:
          result = await _signInAnonymously(option);
          break;
        case FirebaseAuthOption.signInWithCustomToken:
          result = await _singInWithCustomToken(option);
          break;
        case FirebaseAuthOption.signInWithPhoneNumber:
          result = await _sendSignInWithPhoneNumber(option);
          break;
        case FirebaseAuthOption.signInWithCredential:
          break;
      }
    } on FirebaseAuthError catch (error) {
      await _stopAllProgress();
      console //
        ..clearScreen()
        ..println('${'ERROR:'.bold.red.reset} ${error.message.red}'.reset)
        ..print('Press Enter to return.');

      await console.nextLine;
      console.clearScreen();
    }

    if (result == null) {
      return noUserOptionsDialog();
    } else {
      return userWelcome();
    }
  }
}
