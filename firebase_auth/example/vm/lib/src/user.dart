// File created by
// Lung Razvan <long1eu>
// on 12/12/2019

part of firebase_auth_example;

Future<void> userWelcome() async {
  final FirebaseUser user = FirebaseAuth.instance.currentUser;

  console //
    ..println('Welcome ${getUserName(user).cyan.reset}'.bold + '!'.bold.reset)
    ..println();

  return userOptionsDialog();
}

Future<void> userOptionsDialog() async {
  const List<FirebaseAuthOptions> options = FirebaseAuthOptions.userValues;
  console.println('User'.bold.red.reset);
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

  bool signOut = false;
  final int optionIndex = await multipleOptions.show();
  if (optionIndex == -1) {
    close();
  } else {
    console.clearScreen();
    final FirebaseAuthOptions option = options[optionIndex];
    switch (option) {
      case FirebaseAuthOptions.currentUser:
        signOut = await _currentUser(option);
        break;
      case FirebaseAuthOptions.sendEmailVerification:
        signOut = await _sendEmailVerification(option);
        break;
      case FirebaseAuthOptions.delete:
        break;
      case FirebaseAuthOptions.updateAccount:
        break;
      case FirebaseAuthOptions.reauthenticateWithCredential:
        break;
      case FirebaseAuthOptions.linkProvider:
        break;
      case FirebaseAuthOptions.unlinkProvider:
        break;
      case FirebaseAuthOptions.signOut:
        await FirebaseAuth.instance.signOut();
        console.clearScreen();
        signOut = true;
        break;
    }
  }

  // We use this so we allow the user to observe the completion message.
  await Future<void>.delayed(const Duration(seconds: 1));
  if (signOut) {
    return noUserOptionsDialog();
  } else {
    return userWelcome();
  }
}


