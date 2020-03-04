// File created by
// Lung Razvan <long1eu>
// on 14/12/2019

part of firebase_auth_example;

Future<EmailAndPassword> getEmailAndPassword({bool enableForgetPassword = false}) async {
  final MultipleStringOption option = MultipleStringOption(
    question: 'Great! Please enter your credentials.',
    fieldsCount: 2,
    fieldBuilder: (int i) {
      if (i == 0) {
        return 'email: ';
      } else {
        if (enableForgetPassword) {
          final StringBuffer buffer = StringBuffer()
            ..writeln(
                'If you ${'forgot your password'.yellow.reset} just hit enter an we will send a reset password email.')
            ..write('password: ');
          return buffer.toString();
        } else {
          return 'password: ';
        }
      }
    },
    validator: (int fieldIndex, String response) {
      if (fieldIndex == 0 && !EmailValidator.validate(response)) {
        return 'Try a valid email address.';
      } else {
        if (enableForgetPassword && response.isEmpty) {
          // when the password is null we send a reset password email
          return null;
        } else if (response.length < 6) {
          return 'Try a passwprd with at least 6 characters.';
        }
      }

      return null;
    },
  );

  final List<String> results = await option.show();
  final String email = results[0];
  final String password = results[1];
  return EmailAndPassword(email, password);
}

class EmailAndPassword {
  const EmailAndPassword(this.email, this.password);

  final String email;
  final String password;
}
