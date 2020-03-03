// File created by
// Lung Razvan <long1eu>
// on 12/12/2019

part of firebase_auth_example;

Future<AuthResult> _sendSignInWithEmailLink(FirebaseAuthOption option) async {
  final StringOption option = StringOption(
    question: 'Great! Please enter your email.',
    fieldBuilder: () => 'email: ',
    validator: (String response) {
      if (!EmailValidator.validate(response)) {
        return 'Try a valid email address.';
      }

      return null;
    },
  );

  final String email = await option.show();
  console.println();
  Progress progress = Progress('Sending email')..show();
  await FirebaseAuth.instance.sendSignInWithEmailLink(email: email, settings: ActionCodeSettings());
  await progress.cancel();

  final String link =
      await _actionCodeLink('We just sent you an email with a link. Paste the link here to complete the verification.');

  console.println();
  progress = Progress('Siging in')..show();
  final AuthResult result = await FirebaseAuth.instance.signInWithEmailAndLink(email: email, link: link);
  await progress.cancel();
  console.clearScreen();
  return result;
}
