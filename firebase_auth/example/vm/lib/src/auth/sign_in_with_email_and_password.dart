// File created by
// Lung Razvan <long1eu>
// on 12/12/2019

part of firebase_auth_example;

Future<AuthResult> _signInWithEmailAndPassword(FirebaseAuthOptions option) async {
  final MultipleStringOption option = MultipleStringOption(
    question: 'Great! Please enter your credentials.',
    fieldsCount: 2,
    fieldBuilder: (int i) {
      if (i == 0) {
        return 'email: ';
      } else {
        return 'password: ';
      }
    },
    validator: (int fieldIndex, String response) {
      if (fieldIndex == 0 && !EmailValidator.validate(response)) {
        return 'Try a valid email address.';
      } else {
        if (response.isEmpty || response.length < 6) {
          return 'Try a passwprd with at least 6 characters.';
        }
      }

      return null;
    },
  );

  final List<String> results = await option.show();
  final String email = results[0];
  final String password = results[1];

  final Progress progress = Progress('Siging in')..show();
  final AuthResult user = await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
  await progress.cancel();
  console.clearScreen();
  return user;
}
