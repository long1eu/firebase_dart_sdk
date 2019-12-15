// File created by
// Lung Razvan <long1eu>
// on 14/12/2019

part of firebase_auth_example;

Future<AuthResult> _signInWithCredentialEmailAndPassword(FirebaseAuthOption option) async {
  final EmailAndPassword result = await getEmailAndPassword();
  final AuthCredential credential = EmailAuthProvider.getCredential(email: result.email, password: result.password);

  console.println();
  final Progress progress = Progress('Siging in')..show();
  final AuthResult auth = await FirebaseAuth.instance.signInWithCredential(credential);
  await progress.cancel();
  console.clearScreen();
  return auth;
}
