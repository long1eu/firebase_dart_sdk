// File created by
// Lung Razvan <long1eu>
// on 11/12/2019

part of firebase_auth_example;

class FirebaseAuthOptions {
  const FirebaseAuthOptions._(this.i, this.name, this.description);

  final int i;
  final String name;
  final String description;

  // @formatter:off

  // Auth
  static const FirebaseAuthOptions languageCode = FirebaseAuthOptions._(0, 'Language Code', 'Change the language code.');
  static const FirebaseAuthOptions fetchSignInMethodsForEmail = FirebaseAuthOptions._(1, 'Fetch sign in methods for email', 'Show a list of sign-in methods that can be used to sign in by an email address.');
  static const FirebaseAuthOptions createUserWithEmailAndPassword = FirebaseAuthOptions._(2, 'Create user with email and password', 'Don\'t have an account yet? No prob. You can create on very easily.');
  static const FirebaseAuthOptions signInWithEmailAndPassword = FirebaseAuthOptions._(3, 'Sign in with email and password', 'Sign you in with email and password.');
  static const FirebaseAuthOptions sendSignInWithEmailLink = FirebaseAuthOptions._(4, 'Sign in with email and link', 'Sign you in with email and… That\'s it just the email. How cool is that!');
  static const FirebaseAuthOptions signInAnonymously = FirebaseAuthOptions._(5, 'Sign in anonymously', 'Wanna go off radar? No problem. Sign in as a anonymously.');
  static const FirebaseAuthOptions signInWithCustomToken = FirebaseAuthOptions._(6, 'Sign in with custom token', 'If you have a custom token, you are a true haker.');
  static const FirebaseAuthOptions signInWithCredential = FirebaseAuthOptions._(7, 'Sign in with provider', 'You can chosse to sign in with your social media account like Facebook or Tweeter.');
  static const FirebaseAuthOptions verifyPhoneNumber = FirebaseAuthOptions._(8, 'Sign in with phone number', 'You can login with your phone number, though keep in mind it\'s less secure.');
  static const FirebaseAuthOptions sendPasswordResetEmail = FirebaseAuthOptions._(9, 'Send password reset email', 'In case you forgot your password we can help you reset it.');
  static const FirebaseAuthOptions isSignInWithEmailLink = FirebaseAuthOptions._(10, 'Check sign in with email link', 'Wanna make sure your link is good? Pick me!');

  // User
  static const FirebaseAuthOptions currentUser = FirebaseAuthOptions._(11, 'Account Info', 'Show your current user data.');
  static const FirebaseAuthOptions sendEmailVerification = FirebaseAuthOptions._(12, 'Send verification email', 'Stills not verified. Let\'s send a verification email.');
  static const FirebaseAuthOptions delete = FirebaseAuthOptions._(13, 'Delete account', 'Our journy was awesome. We are glad we were togheter. Come back soon.');
  static const FirebaseAuthOptions updateAccount = FirebaseAuthOptions._(14, 'Update account', 'Changing homes? No prob. Let\'s update that email.');
  static const FirebaseAuthOptions reauthenticateWithCredential = FirebaseAuthOptions._(15, 'Reauthenticate', 'It might be that it has been a long time since you proved your identity. Let\'s do that now.');
  static const FirebaseAuthOptions linkProvider = FirebaseAuthOptions._(16, 'Link a new Provider', 'You can chosse to add another social media account, like Facebook or Tweeter, to this account.');
  static const FirebaseAuthOptions unlinkProvider = FirebaseAuthOptions._(17, 'UnlinkFromProvider', 'Remove a social media account so you can no loger use it to login.');
  static const FirebaseAuthOptions signOut = FirebaseAuthOptions._(18, 'Sign Out', 'See you later.');

  // Update account
  static const FirebaseAuthOptions updateEmail = FirebaseAuthOptions._(19, 'Email', 'Changing homes? No prob. Let\'s update that email.');
  static const FirebaseAuthOptions updatePassword = FirebaseAuthOptions._(20, 'Password', 'Security breach? Let\'s change that password.');
  static const FirebaseAuthOptions updateDisplayName = FirebaseAuthOptions._(21, 'Display name', 'You can change your name, it\'s free :D.');
  static const FirebaseAuthOptions updatePhotoUrl = FirebaseAuthOptions._(22, 'Photo', 'Have a new fancy picture?');
  static const FirebaseAuthOptions updatePhoneNumberCredential = FirebaseAuthOptions._(23, 'Phone number', 'You can change your phone number.');
  // @formatter:on

  static const List<FirebaseAuthOptions> authValues = <FirebaseAuthOptions>[
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

  static const List<FirebaseAuthOptions> userValues = <FirebaseAuthOptions>[
    currentUser,
    sendEmailVerification,
    delete,
    updateAccount,
    reauthenticateWithCredential,
    linkProvider,
    unlinkProvider,
    signOut,
  ];

  static const List<FirebaseAuthOptions> updateAccountValues = <FirebaseAuthOptions>[
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
    'verifyPhoneNumber',
    'sendPasswordResetEmail',
    'isSignInWithEmailLink',
    'currentUser',
    'sendEmailVerification',
    'delete',
    'updateAccount',
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
  String toString() {
    return 'FirebaseAuthOptions.${_names[i]}';
  }
}