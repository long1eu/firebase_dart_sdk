// File created by
// Lung Razvan <long1eu>
// on 12/12/2019

part of firebase_auth_example;

Future<bool> _sendEmailVerification(FirebaseAuthOption option) async {
  final FirebaseUser user = FirebaseAuth.instance.currentUser;

  Progress progress = Progress('Sending email')..show();
  await user.sendEmailVerification();
  await progress.cancel();

  final String oobCode = await _actionCode(
      'We just sent you an email with a link. Paste the link here to complete the verification.');

  progress = Progress('Validating code')..show();
  await FirebaseAuth.instance.applyActionCode(oobCode);
  await progress.cancel();
  console //
    ..println('${user.email.bold.cyan.reset} successfuly was verified.')
    ..println()
    ..print('Press Enter to return.');

  await console.nextLine;
  console.clearScreen();

  return false;
}
