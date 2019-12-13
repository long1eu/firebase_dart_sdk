// File created by
// Lung Razvan <long1eu>
// on 12/12/2019

part of firebase_auth_example;

Future<AuthResult> _createUser(FirebaseAuthOption option) async {
  final MultipleStringOption option = MultipleStringOption(
    question: 'Let\'s create you account.',
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
          return 'Try a password with at least 6 characters.';
        }
      }

      return null;
    },
  );

  final List<String> results = await option.show();
  final String email = results[0];
  final String password = results[1];

  final Progress progress = Progress('Creating Account')..show();
  final AuthResult user = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: password);
  await progress.cancel();
  console.clearScreen();
  return user;
}
