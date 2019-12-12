// File created by
// Lung Razvan <long1eu>
// on 12/12/2019

part of firebase_auth_example;

Future<bool> _sendEmailVerification(FirebaseAuthOptions option) async {
  final FirebaseUser user = FirebaseAuth.instance.currentUser;
  await user.sendEmailVerification();
  final StringOption option = StringOption(
    question: 'We just sent you an email with a link. Paste the link here to complete the verification.',
    fieldBuilder: () => 'link: ',
    validator: (String response) {
      if (response.isEmpty) {
        return 'You need to peste the link you got in your email';
      } else if (Uri.tryParse(response) == null) {
        return 'This doesn\'t look like a link. You need to peste the link you got in your email';
      } else if (!Uri.tryParse(response).queryParameters.containsKey('oobCode')) {
        return 'This link doesn\'t look right. You need to peste the link you got in your email';
      } else {
        return null;
      }
    },
  );
  final String url = await option.show();
  final String oobCode = Uri.parse(url).queryParameters['oobCode'];

  Progress progress = Progress('Checking code')..show();
  final ActionCodeInfo value = await FirebaseAuth.instance.checkActionCode(oobCode);
  await progress.cancel();
  _printActionCodeInfo(value);

  progress = Progress('Validating code')..show();
  await FirebaseAuth.instance.applyActionCode(oobCode);
  await progress.cancel();
  console //
    ..println('${user.email.bold.cyan.reset} successfuly was verified.')
    ..println()
    ..print('Press any Enter to return.');

  await console.nextLine;
  console.clearScreen();

  return false;
}
