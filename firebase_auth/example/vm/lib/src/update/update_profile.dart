// File created by
// Lung Razvan <long1eu>
// on 14/12/2019

part of firebase_auth_example;

Future<bool> _updateProfile(FirebaseAuthOption option) async {
  final FirebaseUser user = FirebaseAuth.instance.currentUser;
  const List<FirebaseAuthOption> options = FirebaseAuthOption.updateAccountValues;
  final MultipleOptions multipleOptions = MultipleOptions(
    question: 'What do you want to update?',
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
      case FirebaseAuthOption.updateEmail:
        // changing the email invalidate the token, the user must sign in again
        await _updateEmail(option);
        return true;
      case FirebaseAuthOption.updatePassword:
        await _updatePassword(option);
        return true;
      case FirebaseAuthOption.updateDisplayName:
        await _updateDisplayName(option);
        await user.reload();
        return false;
      case FirebaseAuthOption.updatePhotoUrl:
        await _updatePhotoUrl(option);
        await user.reload();
        return false;
      case FirebaseAuthOption.updatePhoneNumberCredential:
        await _updatePhoneNumberCredential(option);
        await user.reload();
        return false;
    }
  }

  return false;
}

Future<void> _updateEmail(FirebaseAuthOption option) async {
  final FirebaseUser user = FirebaseAuth.instance.currentUser;
  final StringOption option = StringOption(
    question: 'What is the new email address?',
    fieldBuilder: () => 'new email: ',
    validator: (String response) {
      if (!EmailValidator.validate(response)) {
        return 'Try a valid email address.';
      }

      return null;
    },
  );

  final String email = await option.show();

  final Progress progress = Progress('Changing email')..show();
  await user.updateEmail(email);
  await progress.cancel();

  console //
    ..clearScreen()
    ..println('Email changed to ${email.bold.cyan.reset}. You can now login with the ${'new email'.cyan.reset}.')
    ..print('Press Enter to return.');

  await console.nextLine;
}

Future<void> _updatePassword(FirebaseAuthOption option) async {
  final FirebaseUser user = FirebaseAuth.instance.currentUser;
  final StringOption option = StringOption(
    question: 'Type in the new password.',
    fieldBuilder: () => 'new password: ',
    validator: (String response) {
      if (response.isEmpty) {
        return 'Try a password with at least 6 characters.';
      }

      return null;
    },
  );

  final String password = await option.show();

  final Progress progress = Progress('Changing password')..show();
  await user.updatePassword(password);
  await progress.cancel();

  console //
    ..clearScreen()
    ..println('Password changed. You can now login with the ${'new password'.cyan.reset}.')
    ..print('Press Enter to return.');

  await console.nextLine;
  console.clearScreen();
}

Future<void> _updateDisplayName(FirebaseAuthOption option) async {
  final FirebaseUser user = FirebaseAuth.instance.currentUser;
  final StringOption option = StringOption(
    question: 'Type in the new display name.',
    fieldBuilder: () => 'display name: ',
    validator: (String response) {
      return null;
    },
  );

  final String displayName = await option.show();

  final Progress progress = Progress('Changing display name')..show();
  await user.updateProfile(UserUpdateInfo()..displayName = displayName);
  await progress.cancel();

  console //
    ..clearScreen()
    ..println('Display name changed to ${displayName.bold.cyan.reset}.')
    ..print('Press Enter to return.');

  await console.nextLine;
  console.clearScreen();
}

Future<void> _updatePhotoUrl(FirebaseAuthOption option) async {
  final FirebaseUser user = FirebaseAuth.instance.currentUser;
  final StringOption option = StringOption(
    question: 'Type in the new photo url.',
    fieldBuilder: () => 'photo url: ',
    validator: (String response) {
      if (Uri.tryParse(response) == null) {
        return 'Try to type in a valid url';
      }
      return null;
    },
  );

  final String photoUrl = await option.show();

  final Progress progress = Progress('Changing display name')..show();
  await user.updateProfile(UserUpdateInfo()..photoUrl = photoUrl);
  await progress.cancel();

  console //
    ..clearScreen()
    ..println('Photo url changed to $photoUrl.')
    ..print('Press Enter to return.');

  await console.nextLine;
  console.clearScreen();
}

Future<void> _updatePhoneNumberCredential(FirebaseAuthOption option) async {
  final FirebaseUser user = FirebaseAuth.instance.currentUser;
  final PhoneAuthCredential credential = await _getPhoneAuthCredential();

  final Progress progress = Progress('Changing phone number')..show();
  await user.updatePhoneNumberCredential(credential);
  await progress.cancel();

  console //
    ..clearScreen()
    ..println('Phone number changed to ${user.phoneNumber.bold.cyan.reset}.')
    ..print('Press Enter to return.');

  await console.nextLine;
  console.clearScreen();
}
