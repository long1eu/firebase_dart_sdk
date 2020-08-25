// File created by
// Lung Razvan <long1eu>
// on 12/12/2019

part of firebase_auth_example;

Future<AuthResult> _linkProvider(FirebaseAuthOption option) async {
  final FirebaseUser user = FirebaseAuth.instance.currentUser;
  await user.reload();

  final List<String> providers = user.providerData
      .map((UserInfo userInfo) => userInfo.providerId)
      .toList();
  final List<FirebaseAuthOption> options =
      FirebaseAuthOption.credentialsValues.toList();
  for (String provider in providers) {
    switch (provider) {
      case ProviderType.password:
        options.remove(FirebaseAuthOption.emailAndPasswordCredentials);
        break;
      case ProviderType.phone:
        options.remove(FirebaseAuthOption.phoneCredentials);
        break;
      case ProviderType.google:
        options.remove(FirebaseAuthOption.googleCredentials);
        break;
      case ProviderType.facebook:
        options.remove(FirebaseAuthOption.facebookCredentials);
        break;
      case ProviderType.twitter:
        options.remove(FirebaseAuthOption.twitterCredentials);
        break;
      case ProviderType.github:
        options.remove(FirebaseAuthOption.githubCredentials);
        break;
    }
  }

  final MultipleOptions multipleOptions = MultipleOptions(
    question: 'Pick the provider you want to use ',
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
    return null;
  } else {
    console.clearScreen();

    String providerId;
    AuthCredential credential;
    final FirebaseAuthOption option = options[optionIndex];
    switch (option) {
      case FirebaseAuthOption.emailAndPasswordCredentials:
        credential = await _getEmailPasswordAuthCredential();
        providerId = ProviderType.password;
        break;
      case FirebaseAuthOption.phoneCredentials:
        credential = await _getPhoneAuthCredential();
        providerId = ProviderType.phone;
        break;
      case FirebaseAuthOption.googleCredentials:
        credential = await _getGoogleAuthCredential();
        providerId = ProviderType.google;
        break;
      case FirebaseAuthOption.facebookCredentials:
        credential = await _getFacebookAuthCredential();
        providerId = ProviderType.facebook;
        break;
      case FirebaseAuthOption.twitterCredentials:
        credential = await _getTwitterAuthCredential();
        providerId = ProviderType.twitter;
        break;
      case FirebaseAuthOption.githubCredentials:
        credential = await _getGithubAuthCredential();
        providerId = ProviderType.github;
        break;
    }

    final AuthResult result = await user.linkWithCredential(credential);

    console //
      ..clearScreen()
      ..println(
          'You\'re account is now linked with ${providerId.bold.yellow.reset}.')
      ..print('Press Enter to return.');

    await console.nextLine;
    console.clearScreen();
    return result;
  }
}
