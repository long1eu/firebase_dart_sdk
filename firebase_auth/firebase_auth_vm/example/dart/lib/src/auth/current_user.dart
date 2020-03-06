// File created by
// Lung Razvan <long1eu>
// on 12/12/2019

part of firebase_auth_example;

Future<bool> _currentUser(FirebaseAuthOption option) async {
  console.clearScreen();
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
    console.printlnTabbed(
        _field('isEmailVerified', user.isEmailVerified.toString()));
  }
  if (user.photoUrl != null) {
    console.printlnTabbed(_field('photoUrl', user.photoUrl));
  }

  final DateFormat format = DateFormat.yMMMMd().add_Hm();
  console
    ..println('Metadata'.bold.yellow.reset)
    ..printlnTabbed(
        _field('creationDate', format.format(user.metadata.creationDate)))
    ..printlnTabbed(
        _field('lastSignInDate', format.format(user.metadata.lastSignInDate)));

  if (user.providerData.isNotEmpty) {
    console.println('Providers'.bold.yellow.reset);
    user.providerData.forEach(_printProvider);
  }

  final GetTokenResult token = await user.getIdToken();
  console.println('Token'.bold.yellow.reset);
  _printTokenResult(token);

  console //
    ..println()
    ..print('Press Enter to return.');

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
    console.printlnTabbed(
        _field('isEmailVerified', user.isEmailVerified.toString()), 6);
  }
}

void _printTokenResult(GetTokenResult token) {
  final DateFormat format = DateFormat.yMMMMd().add_Hm();

  if (token.claims.containsKey('auth_time')) {
    console.printlnTabbed(
        _field('authentication', format.format(token.authTimestamp)));
  }
  console
    ..printlnTabbed(_field('issuedAt', format.format(token.issuedAtTimestamp)))
    ..printlnTabbed(
        _field('expiration', format.format(token.expirationTimestamp)))
    ..printlnTabbed(_field('signInProvider', token.signInProvider));

  if (token.extraClaims != null) {
    console.printlnTabbed('claims'.underline.reset);
    for (MapEntry<String, dynamic> entry in token.extraClaims.entries) {
      console
        ..printTabbed('${entry.key}: ', 6)
        ..println(entry.value.toString().bold.cyan.reset);
    }
  }

  final List<List<int>> chunks = _split('token: ${token.token}'.codeUnits, 80);
  final String firstLine =
      String.fromCharCodes(chunks.removeAt(0)).split('token: ')[1];
  console.printlnTabbed('token: ${firstLine.bold.cyan.reset}');
  chunks
      .map((List<int> it) => String.fromCharCodes(it).bold.cyan.reset)
      .forEach(console.printlnTabbed);
}

List<List<int>> _split(List<int> list, int size) {
  final int len = list.length;
  final List<List<int>> chunks = <List<int>>[];
  for (int i = 0; i < len; i += size) {
    final int end = (i + size < len) ? i + size : len;
    chunks.add(list.sublist(i, end));
  }
  return chunks;
}
