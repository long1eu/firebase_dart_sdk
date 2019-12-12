// File created by
// Lung Razvan <long1eu>
// on 11/12/2019

part of firebase_auth_example;


// @formatter:off
const List<AppOption> firebaseAuthOptions = <AppOption>[
  AppOption(FirebaseAuthOptions.languageCode, 'Language Code', 'Change the language code.'),
  AppOption(FirebaseAuthOptions.fetchSignInMethodsForEmail, 'Fetch sign in methods for email', 'Show a list of sign-in methods that can be used to sign in by an email address.'),
  AppOption(FirebaseAuthOptions.createUserWithEmailAndPassword, 'Create user with email and password', 'Don\'t have an account yet? No prob. You can create on very easily.'),
  AppOption(FirebaseAuthOptions.signInWithEmailAndPassword, 'Sign in with email and password', 'Sign you in with email and password.'),
  AppOption(FirebaseAuthOptions.sendSignInWithEmailLink, 'Sign in with email and link', 'Sign you in with email and… That\'s it just the email. How cool is that!'),
  AppOption(FirebaseAuthOptions.signInAnonymously, 'Sign in anonymously', 'Wanna go off radar? No problem. Sign in as a anonymously.'),
  AppOption(FirebaseAuthOptions.signInWithCustomToken, 'Sign in with custom token', 'If you have a custom token, you are a true haker.'),
  AppOption(FirebaseAuthOptions.signInWithCredential, 'Sign in with provider', 'You can chosse to sign in with your social media account like Facebook or Tweeter.'),
  AppOption(FirebaseAuthOptions.verifyPhoneNumber, 'Sign in with phone number', 'You can login with your phone number, though keep in mind it\'s less secure.'),
  AppOption(FirebaseAuthOptions.sendPasswordResetEmail, 'Send password reset email', 'In case you forgot your password we can help you reset it.'),
  AppOption(FirebaseAuthOptions.isSignInWithEmailLink, 'Check sign in with email link', 'Wanna make sure your link is good? Pick me!'),
];

const List<AppOption> firebaseUserOptions = <AppOption>[
  AppOption(null,'currentUser', 'Show your current user data.'),
  AppOption(null,'sendEmailVerification', 'Stil not verified. Let\'s send a verification email.'),
  AppOption(null,'reload', 'Let\'s see if you have new data from another device.'),
  AppOption(null,'delete', 'Our journy was awesome. We are glad we were togheter. Come back soon.'),
  AppOption(null,'updateEmail', 'Changing homes? No prob. Let\'s update that email.'),
  AppOption(null,'updatePhoneNumberCredential', ''),
  AppOption(null,'updatePassword', 'Security breach. Let\' change that password.'),
  AppOption(null,'updateProfile', 'Have a bew fancy picture? Or a new name idea? Try this.'),
  AppOption(null,'reauthenticateWithCredential', 'It might be that it has been a long time since you proved your identity. Let\'s do that now.'),
  AppOption(null,'unlinkFromProvider', ''),
  AppOption(null,'signOut', 'See you later.'),
];
// @formatter:on

class AppOption {
  const AppOption(this.option, this.name, this.description);

  final String name;
  final String description;
  final FirebaseAuthOptions option;
}


class FirebaseAuthOptions {
  const FirebaseAuthOptions._(this.i);

  final int i;

  static const FirebaseAuthOptions languageCode = FirebaseAuthOptions._(0);
  static const FirebaseAuthOptions fetchSignInMethodsForEmail = FirebaseAuthOptions._(1);
  static const FirebaseAuthOptions createUserWithEmailAndPassword = FirebaseAuthOptions._(2);
  static const FirebaseAuthOptions signInWithEmailAndPassword = FirebaseAuthOptions._(3);
  static const FirebaseAuthOptions sendSignInWithEmailLink = FirebaseAuthOptions._(4);
  static const FirebaseAuthOptions signInAnonymously = FirebaseAuthOptions._(5);
  static const FirebaseAuthOptions signInWithCustomToken = FirebaseAuthOptions._(6);
  static const FirebaseAuthOptions signInWithCredential = FirebaseAuthOptions._(7);
  static const FirebaseAuthOptions verifyPhoneNumber = FirebaseAuthOptions._(8);
  static const FirebaseAuthOptions sendPasswordResetEmail = FirebaseAuthOptions._(9);
  static const FirebaseAuthOptions isSignInWithEmailLink = FirebaseAuthOptions._(10);

  static const List<FirebaseAuthOptions> values = <FirebaseAuthOptions>[
    languageCode,
    fetchSignInMethodsForEmail,
    createUserWithEmailAndPassword,
    signInWithEmailAndPassword,
    sendSignInWithEmailLink,
    signInAnonymously,
    signInWithCustomToken,
    signInWithCredential,
    verifyPhoneNumber,
    sendPasswordResetEmail,
    isSignInWithEmailLink,
  ];

  static const List<String> _names = <String>[
    'languageCode',
    'fetchSignInMethodsForEmail',
    'createUserWithEmailAndPassword',
    'signInWithEmailAndPassword',
    'sendSignInWithEmailLink',
    'signInAnonymously',
    'signInWithCustomToken',
    'signInWithCredential',
    'verifyPhoneNumber',
    'sendPasswordResetEmail',
    'isSignInWithEmailLink',
  ];

  static FirebaseAuthOptions valueOf(int i) => values[i];

  @override
  String toString() {
    return 'FirebaseAuthOptions.${_names[i]}';
  }
}