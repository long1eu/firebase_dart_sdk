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
  const List<FirebaseAuthOption> options = FirebaseAuthOption.userValues;
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
    try {
      console.clearScreen();
      final FirebaseAuthOption option = options[optionIndex];
      switch (option) {
        case FirebaseAuthOption.currentUser:
          signOut = await _currentUser(option);
          break;
        case FirebaseAuthOption.sendEmailVerification:
          if (FirebaseAuth.instance.currentUser.isAnonymous) {
            throw StateError('Anonymous users don\'t have a email address to verify. :D');
          }
          signOut = await _sendEmailVerification(option);
          break;
        case FirebaseAuthOption.delete:
          console.println('Are you sure you want to delete your account? (yes/no)');
          final String response = await console.nextLine;
          if (response == 'yes') {
            await FirebaseAuth.instance.currentUser.delete();
            signOut = true;
            console //
              ..println('Account deleted')
              ..print('Press Enter to return.');

            await console.nextLine;
          }
          console.clearScreen();
          break;
        case FirebaseAuthOption.updateAccount:
          signOut = await _updateProfile(option);
          break;
        case FirebaseAuthOption.createCustomToken:
          signOut = await _createCustomToken(option);
          break;
        case FirebaseAuthOption.reauthenticateWithCredential:
          final AuthResult result = await _reauthenticateWithCredential(option);
          signOut = result == null;
          break;
        case FirebaseAuthOption.linkProvider:
          final AuthResult result = await _linkProvider(option);
          signOut = result == null;
          break;
        case FirebaseAuthOption.unlinkProvider:
          await _unlinkProvider(option);
          signOut = false;
          break;
        case FirebaseAuthOption.signOut:
          await FirebaseAuth.instance.signOut();
          console.clearScreen();
          signOut = true;
          break;
      }
    } on FirebaseAuthError catch (error) {
      await _stopAllProgress();
      console.clearScreen();
      if (error == FirebaseAuthError.userTokenExpired) {
        signOut = true;
        console.println('Your session has expired you need to login again.');
      } else {
        console.println(error.message.red.reset);
      }

      console.print('Press Enter to return.');
      await console.nextLine;
      console.clearScreen();
    } on StateError catch (error) {
      await _stopAllProgress();
      console //
        ..clearScreen()
        ..println('${'ERROR:'.bold.red.reset} ${error.message.red}'.reset)
        ..print('Press Enter to return.');

      await console.nextLine;
      console.clearScreen();
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
