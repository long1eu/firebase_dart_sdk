// File created by
// Lung Razvan <long1eu>
// on 11/12/2019

part of firebase_auth_example;

class FirebaseAuthOption {
  const FirebaseAuthOption._(this.i, this.name, this.description);

  final int i;
  final String name;
  final String description;

  // @formatter:off

  // Auth
  static const FirebaseAuthOption languageCode = FirebaseAuthOption._(0, 'Language Code', 'Change the language code.');
  static const FirebaseAuthOption fetchSignInMethodsForEmail = FirebaseAuthOption._(1, 'Fetch sign in methods for email', 'Show a list of sign-in methods that can be used to sign in by an email address.');
  static const FirebaseAuthOption createUserWithEmailAndPassword = FirebaseAuthOption._(2, 'Create user with email and password', 'Don\'t have an account yet? No prob. You can create on very easily.');
  static const FirebaseAuthOption signInWithEmailAndPassword = FirebaseAuthOption._(3, 'Sign in with email and password', 'Sign you in with email and password.');
  static const FirebaseAuthOption sendSignInWithEmailLink = FirebaseAuthOption._(4, 'Sign in with email and link', 'Sign you in with email and… That\'s it just the email. How cool is that!');
  static const FirebaseAuthOption signInAnonymously = FirebaseAuthOption._(5, 'Sign in anonymously', 'Wanna go off radar? No problem. Sign in as a anonymously.');
  static const FirebaseAuthOption signInWithCustomToken = FirebaseAuthOption._(6, 'Sign in with custom token', 'If you have a custom token, you are a true haker. If you don\'t, sign in with any other method. As an authenticated user you have the option to create a custom token for yourself. :D');
  static const FirebaseAuthOption signInWithCredential = FirebaseAuthOption._(7, 'Sign in with provider', 'You can chosse to sign in with your social media account like Facebook or Tweeter.');
  static const FirebaseAuthOption signInWithPhoneNumber = FirebaseAuthOption._(8, 'Sign in with phone number', 'You can login with your phone number, though keep in mind it\'s less secure.');

  // User
  static const FirebaseAuthOption currentUser = FirebaseAuthOption._(9, 'Account Info', 'Show your current user data.');
  static const FirebaseAuthOption sendEmailVerification = FirebaseAuthOption._(10, 'Send verification email', 'Stills not verified. Let\'s send a verification email.');
  static const FirebaseAuthOption delete = FirebaseAuthOption._(11, 'Delete account', 'Our journy was awesome. We are glad we were togheter. Come back soon.');
  static const FirebaseAuthOption updateAccount = FirebaseAuthOption._(12, 'Update account', 'Changing homes? No prob. Let\'s update that email.');
  static const FirebaseAuthOption createCustomToken = FirebaseAuthOption._(13, 'Create custom token', 'Do you want to check the sith in with custom token functionality? Here is the right place to get a valid custom token.');
  static const FirebaseAuthOption reauthenticateWithCredential = FirebaseAuthOption._(14, 'Reauthenticate', 'It might be that it has been a long time since you proved your identity. Let\'s do that now.');
  static const FirebaseAuthOption linkProvider = FirebaseAuthOption._(15, 'Link a new Provider', 'You can chosse to add another social media account, like Facebook or Tweeter, to this account.');
  static const FirebaseAuthOption unlinkProvider = FirebaseAuthOption._(16, 'UnlinkFromProvider', 'Remove a social media account so you can no loger use it to login.');
  static const FirebaseAuthOption signOut = FirebaseAuthOption._(17, 'Sign Out', 'See you later.');

  // Update account
  static const FirebaseAuthOption updateEmail = FirebaseAuthOption._(18, 'Email', 'Changing homes? No prob. Let\'s update that email.');
  static const FirebaseAuthOption updatePassword = FirebaseAuthOption._(19, 'Password', 'Security breach? Let\'s change that password.');
  static const FirebaseAuthOption updateDisplayName = FirebaseAuthOption._(20, 'Display name', 'You can change your name, it\'s free :D.');
  static const FirebaseAuthOption updatePhotoUrl = FirebaseAuthOption._(21, 'Photo', 'Have a new fancy picture?');
  static const FirebaseAuthOption updatePhoneNumberCredential = FirebaseAuthOption._(22, 'Phone number', 'You can change your phone number.');
  // @formatter:on

  static const List<FirebaseAuthOption> authValues = <FirebaseAuthOption>[
    languageCode,
    fetchSignInMethodsForEmail,
    createUserWithEmailAndPassword,
    signInWithEmailAndPassword,
    sendSignInWithEmailLink,
    signInAnonymously,
    signInWithCustomToken,
    signInWithCredential,
    signInWithPhoneNumber,
  ];

  static const List<FirebaseAuthOption> userValues = <FirebaseAuthOption>[
    currentUser,
    sendEmailVerification,
    delete,
    updateAccount,
    createCustomToken,
    reauthenticateWithCredential,
    linkProvider,
    unlinkProvider,
    signOut,
  ];

  static const List<FirebaseAuthOption> updateAccountValues = <FirebaseAuthOption>[
    updateEmail,
    updatePassword,
    updateDisplayName,
    updatePhotoUrl,
    updatePhoneNumberCredential,
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
    'signInWithPhoneNumber',
    'currentUser',
    'sendEmailVerification',
    'delete',
    'updateAccount',
    'createCustomToken',
    'reauthenticateWithCredential',
    'linkProvider',
    'unlinkProvider',
    'signOut',
    'updateEmail',
    'updatePassword',
    'updateDisplayName',
    'updatePhotoUrl',
    'updatePhoneNumberCredential',
  ];

  @override
  String toString() => 'FirebaseAuthOptions.${_names[i]}';
}