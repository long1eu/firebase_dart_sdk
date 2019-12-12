// File created by
// Lung Razvan <long1eu>
// on 12/12/2019

part of firebase_auth_example;

Future<AuthResult> _signInWithEmailAndPassword(FirebaseAuthOptions option) async {
  final MultipleStringOption option = MultipleStringOption(
    question: 'Great! Please enter your credentials.',
    fieldsCount: 2,
    fieldBuilder: (int i) {
      if (i == 0) {
        return 'email: ';
      } else {
        final StringBuffer buffer = StringBuffer()
          ..writeln(
              'If you ${'forgot your password'.yellow.reset} just hit enter an we will send a reset password email.')
          ..write('password: ');
        return buffer.toString();
      }
    },
    validator: (int fieldIndex, String response) {
      if (fieldIndex == 0 && !EmailValidator.validate(response)) {
        return 'Try a valid email address.';
      } else {
        if (response.isEmpty) {
          // when the password is null we send a reset password email
          return null;
        } else if (response.length < 6) {
          return 'Try a passwprd with at least 6 characters.';
        }
      }

      return null;
    },
  );

  final List<String> results = await option.show();
  final String email = results[0];
  final String password = results[1];

  if (password.isNotEmpty) {
    return _signIn(email, password);
  } else {
    return _resetPassword(email);
  }
}

Future<AuthResult> _signIn(String email, String password) async {
  final Progress progress = Progress('Siging in')..show();
  final AuthResult user = await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
  await progress.cancel();
  console.clearScreen();
  return user;
}

Future<AuthResult> _resetPassword(String email) async {
  console.println();
  Progress progress = Progress('Sending email')..show();
  await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
  await progress.cancel();

  final String oobCode =
      await _actionCode('We just sent you an email with a link. Paste the link here to complete the verification.');

  console.println();
  final StringOption option = StringOption(
    question: 'The code seems good. You can now pick a new password.',
    fieldBuilder: () => 'newPassword: ',
    validator: (String response) {
      if (response.isEmpty || response.length < 6) {
        return 'Try a password with at least 6 characters.';
      }

      return null;
    },
  );
  final String newPassword = await option.show();

  progress = Progress('Resetting password')..show();
  await FirebaseAuth.instance.confirmPasswordReset(oobCode: oobCode, newPassword: newPassword);
  await progress.cancel();

  return _signIn(email, newPassword);
}
