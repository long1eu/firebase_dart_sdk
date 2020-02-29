// File created by
// Lung Razvan <long1eu>
// on 12/12/2019

part of firebase_auth_example;

Future<String> _actionCodeLink(String question) async {
  final StringOption option = StringOption(
    question: question,
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

  final Progress progress = Progress('Checking code')..show();
  final ActionCodeInfo value = await FirebaseAuth.instance.checkActionCode(oobCode);
  await progress.cancel();
  _printActionCodeInfo(value);
  return url;
}

Future<String> _actionCode(String question) async {
  final String url = await _actionCodeLink(question);
  return Uri.parse(url).queryParameters['oobCode'];
}
