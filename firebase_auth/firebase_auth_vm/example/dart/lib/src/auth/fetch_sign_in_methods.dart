// File created by
// Lung Razvan <long1eu>
// on 12/12/2019

part of firebase_auth_example;

Future<void> _fetchSignInMethod(FirebaseAuthOption option) async {
  final StringOption option = StringOption(
    question: 'What is the email address?',
    validator: (String response) {
      if (!EmailValidator.validate(response)) {
        return 'Try a valid email address.';
      }

      return null;
    },
  );

  final String result = await option.show();
  final Progress progress = Progress('Fetching sing in methods for $result')..show();
  final List<String> providers = await FirebaseAuth.instance.fetchSignInMethodsForEmail(result);
  await progress.cancel();

  console
    ..removeLines()
    ..println(_getResultMessage(result, providers))
    ..println()
    ..print('Press Enter to return.');

  await console.nextLine;
  console.clearScreen();
  return false;
}

String _getResultMessage(String email, List<String> providers) {
  if (providers.isEmpty) {
    return '${email.bold.cyan.reset} has no account yet.';
  } else if (providers.length == 1) {
    return '${email.bold.cyan.reset} can login with ${providers.first.bold.yellow.reset}.';
  } else {
    final StringBuffer buffer = StringBuffer('${email.bold.cyan.reset} can login with ');
    for (int i = 0; i < providers.length; i++) {
      final String provider = providers[i];

      if (i != 0) {
        if (i == providers.length - 1) {
          buffer.write(' and ');
        } else {
          buffer.write(', ');
        }
      }
      buffer.write(provider.bold.yellow.reset);
    }
    buffer.write('.');

    return buffer.toString();
  }
}
