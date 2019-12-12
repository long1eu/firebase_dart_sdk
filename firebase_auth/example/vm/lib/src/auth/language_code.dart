// File created by
// Lung Razvan <long1eu>
// on 12/12/2019

part of firebase_auth_example;

Future<void> _changeLanguageCode(AppOption option) async {
  final String currentLanguage = _getLanguageMessage();
  final StringOption option = StringOption(
    question: 'Great. $currentLanguage What is the new language?',
    validator: (String response) {
      if (response.length != 2) {
        return 'This time try something like en, fr etc.';
      } else if (!RegExp('^[ A-Za-z]+\$').hasMatch(response)) {
        return 'This time try something like en, fr and stick to letters. :D';
      }

      return null;
    },
  );

  final String result = await option.show();

  FirebaseAuth.instance.languageCode = result;
  console
    ..removeLines(4)
    ..print(' > '.bold.cyan.reset)
    ..println(_getLanguageMessage())
    ..println();

  return showOptionsDialog();
}

String _getLanguageMessage() {
  final String languageCode = FirebaseAuth.instance.languageCode;
  return languageCode == null
      ? 'You didn\'t set any language.'
      : 'Your current language is ${languageCode.bold.cyan.reset}.';
}
