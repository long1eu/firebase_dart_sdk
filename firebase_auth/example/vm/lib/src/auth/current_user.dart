// File created by
// Lung Razvan <long1eu>
// on 12/12/2019

part of firebase_auth_example;

Future<bool> _currentUser(FirebaseAuthOptions option) async {
  final FirebaseUser user = FirebaseAuth.instance.currentUser;
  final Progress progress = Progress('Getting latest account info')..show();
  await user.reload();
  await progress.cancel();

  console //
    ..println('Account Info'.bold.reset)
    ..println()
    ..println('Profile'.bold.yellow.reset)
    ..printlnTabbed(_field('uid', user.uid))
    ..printlnTabbed(_field('isAnonymous', user.isAnonymous.toString()));

  if (user.email != null) {
    console.printlnTabbed(_field('email', user.email));
  }
  if (user.phoneNumber != null) {
    console.printlnTabbed(_field('phoneNumber', user.phoneNumber));
  }

  if (user.isEmailVerified != null) {
    console.printlnTabbed(_field('isEmailVerified', user.isEmailVerified.toString()));
  }
  if (user.photoUrl != null) {
    console.printlnTabbed(_field('photoUrl', user.photoUrl));
  }

  final DateFormat format = DateFormat.yMMMMd().add_Hm();
  console
    ..println('Metadata'.bold.yellow.reset)
    ..printlnTabbed(_field('creationDate', format.format(user.metadata.creationDate)))
    ..printlnTabbed(_field('lastSignInDate', format.format(user.metadata.lastSignInDate)));

  if (user.providerData.isNotEmpty) {
    console.println('Providers'.bold.yellow.reset);
    user.providerData.forEach(_printProvider);
  }

  console //
    ..println()
    ..print('Press any Enter to return.');

  await console.nextLine;
  console.clearScreen();
  return false;
}

String _field(String fieldName, String value) {
  return '$fieldName: ${value.bold.cyan.reset}';
}

void _printProvider(UserInfo user) {
  console.printlnTabbed(user.providerId.underline.reset);

  if (user.uid != null) {
    console.printlnTabbed(_field('federatedId', user.uid), 6);
  }
  if (user.displayName != null) {
    console.printlnTabbed(_field('displayName', user.displayName), 6);
  }
  if (user.photoUrl != null) {
    console.printlnTabbed(_field('photoUrl', user.photoUrl), 6);
  }
  if (user.email != null) {
    console.printlnTabbed(_field('email', user.email), 6);
  }
  if (user.phoneNumber != null) {
    console.printlnTabbed(_field('phoneNumber', user.phoneNumber), 6);
  }
  if (user.isEmailVerified != null) {
    console.printlnTabbed(_field('isEmailVerified', user.isEmailVerified.toString()), 6);
  }
}
