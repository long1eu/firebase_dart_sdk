// File created by
// Lung Razvan <long1eu>
// on 12/12/2019

part of firebase_auth_example;

Future<AuthResult> _signInAnonymously(FirebaseAuthOption option) async {
  final Progress progress = Progress('Siging in')..show();
  final AuthResult result = await FirebaseAuth.instance.signInAnonymously();
  await progress.cancel();
  console.clearScreen();
  return result;
}
