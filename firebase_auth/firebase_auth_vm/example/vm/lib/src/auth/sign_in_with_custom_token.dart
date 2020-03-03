// File created by
// Lung Razvan <long1eu>
// on 13/12/2019

part of firebase_auth_example;

Future<AuthResult> _singInWithCustomToken(FirebaseAuthOption option) async {
  final StringOption option = StringOption(
    question: 'Type in your custom token.',
    fieldBuilder: () => 'token: ',
    validator: (String response) {
      if (response.isEmpty) {
        return 'You should try an non empty string. :D';
      }

      return null;
    },
  );
  final String customToken = await option.show();

  final Progress progress = Progress('Siging in')..show();
  final AuthResult result = await FirebaseAuth.instance.signInWithCustomToken(token: customToken);
  await progress.cancel();
  console.clearScreen();
  return result;
}
