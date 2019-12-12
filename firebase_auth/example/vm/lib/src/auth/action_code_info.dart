// File created by
// Lung Razvan <long1eu>
// on 12/12/2019

part of firebase_auth_example;

void _printActionCodeInfo(ActionCodeInfo value) {
  switch (value.operation) {
    case ActionCodeOperation.passwordReset:
      console.println('This link will ${'reset the password'.bold.yellow.reset} for ${value.email}.');
      break;
    case ActionCodeOperation.verifyEmail:
      console.println('This link will ${'verify the email'.bold.yellow.reset} ${value.email}.');
      break;
    case ActionCodeOperation.recoverEmail:
      console
          .println('This link will ${'recover the email'.bold.yellow.reset} from ${value.forEmail} to ${value.email}.');
      break;
    case ActionCodeOperation.emailSignIn:
      console.println('This link will ${'sign in with email'.bold.yellow.reset} ${value.email}.');
      break;
  }
}
