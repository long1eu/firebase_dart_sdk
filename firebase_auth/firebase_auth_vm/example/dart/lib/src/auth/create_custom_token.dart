// File created by
// Lung Razvan <long1eu>
// on 13/12/2019

part of firebase_auth_example;

Future<bool> _createCustomToken(FirebaseAuthOption option) async {
  final MultipleStringOption option = MultipleStringOption(
    question: 'First create the custom token.\n'
        'You can add custom claims like this: ${'claim:value'.bold.yellow.reset}. Leave empty when done and press Enter.',
    fieldsCount: -1,
    fieldBuilder: (_) => 'claim: ',
    validator: (_, String response) {
      if (response.isEmpty) {
        return null;
      } else if (response.split(':').length != 2) {
        return 'You need to pass in a key-value pair like this ${'claim:value'.bold.yellow.reset}.';
      }

      return null;
    },
  );

  final Map<String, String> claims =
      (await option.show()).asMap().map((_, String value) {
    final List<String> values = value.split(':');
    return MapEntry<String, String>(values[0].trim(), values[1].trim());
  });

  final Progress progress =
      Progress('Creating custom token with claims ${jsonEncode(claims)}')
        ..show();
  console.println();
  final GetTokenResult token = await FirebaseAuth.instance.getAccessToken();
  final Response response = await Client().post(
    'https://us-central1-flutter-sdk.cloudfunctions.net/createCustomToken',
    headers: <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      'Authorization': 'Bearer ${token.token}',
    },
    body: jsonEncode(<String, dynamic>{'data': claims}),
  );
  await progress.cancel();

  if (response.statusCode != 200) {
    throw FirebaseAuthError('', response.body);
  }

  final String customToken = jsonDecode(response.body)['result'];
  console
    ..println(
        'Here is your custom token. We have signed you out so you can test it. Save it and the hit Enter.')
    ..println(customToken.bold.cyan.reset);

  await FirebaseAuth.instance.signOut();
  console //
    ..println()
    ..print('Press Enter to return.');

  await console.nextLine;
  console.clearScreen();
  return true;
}
