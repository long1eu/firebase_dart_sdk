// File created by
// Lung Razvan <long1eu>
// on 12/12/2019

part of firebase_auth_example;

Future<AuthResult> _signInWithEmailAndPassword(
    FirebaseAuthOption option) async {
  final EmailAndPassword result =
      await getEmailAndPassword(enableForgetPassword: true);
  if (result.password.isNotEmpty) {
    return _signIn(result.email, result.password);
  } else {
    return _resetPassword(result.email);
  }
}

Future<AuthResult> _signIn(String email, String password) async {
  final Progress progress = Progress('Siging in')..show();
  final AuthResult user = await FirebaseAuth.instance
      .signInWithEmailAndPassword(email: email, password: password);
  await progress.cancel();
  console.clearScreen();
  return user;
}

Future<AuthResult> _resetPassword(String email) async {
  console.println();
  Progress progress = Progress('Sending email')..show();
  await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
  await progress.cancel();

  final String oobCode = await _actionCode(
      'We just sent you an email with a link. Paste the link here to complete the verification.');

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
  await FirebaseAuth.instance
      .confirmPasswordReset(oobCode: oobCode, newPassword: newPassword);
  await progress.cancel();

  return _signIn(email, newPassword);
}
