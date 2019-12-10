import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_internal/firebase_internal.dart';
import 'package:hive/hive.dart';
import 'package:meta/meta.dart';

Future<void> init() async {
  Hive.init('./hives');

  final Box<dynamic> box =
      await Hive.openBox<dynamic>('firebase_auth', encryptionKey: 'dEtk7JiOCJirguAJEM7wOSkcNtfZO0DG'.codeUnits);

  final Dependencies dependencies = Dependencies(box: box);
  final FirebaseOptions options =
      FirebaseOptions(apiKey: 'AIzaSyDsSL36xeTPP-JdGZBdadhEm2bxNpMqlUQ', applicationId: 'appId');
  FirebaseApp.withOptions(options, dependencies);
}

class Dependencies extends PlatformDependencies {
  Dependencies({@required this.box}) : headersBuilder = null;

  @override
  final Box<dynamic> box;

  @override
  final HeaderBuilder headersBuilder;

  @override
  InternalTokenProvider get authProvider => null;

  @override
  AuthUrlPresenter get authUrlPresenter => null;

  @override
  bool get isBackground => false;

  @override
  Future<bool> get isNetworkConnected => Future<bool>.value(true);

  @override
  String get locale => 'en';

  @override
  Stream<bool> get isBackgroundChanged => Stream<bool>.fromIterable(<bool>[false]);
}

String getUserName(FirebaseUser user) {
  if (user.isAnonymous) {
    return 'Stranger';
  } else if (user.providerId == ProviderType.phone) {
    return user.phoneNumber;
  } else {
    return user.displayName;
  }
}

const List<AppOption> firebaseAuthOptions = <AppOption>[
  AppOption('languageCode', 'Change the language code.'),
  AppOption(
      'fetchSignInMethodsForEmail', 'Show a list of sign-in methods that can be used to sign in by an email address.'),
  AppOption('createUserWithEmailAndPassword', 'Don\'t have an account yet? No prob. You can create on very easily.'),
  AppOption('signInWithEmailAndPassword', 'Sign you in with email and password.'),
  AppOption('signInWithEmailAndLink', 'Sign you in with email and ... That\'s it just the email. How cool is that!'),
  AppOption('signInAnonymously', 'Wanna go off radar? No problem. Sign in as a anonymously.'),
  AppOption('signInWithCustomToken', 'If you have a custom token, you are a true haker.'),
  // AppOption('signInWithCredential', 'description'),
  // AppOption('confirmPasswordReset', 'description'),
  // AppOption('checkActionCode', 'description'),
  // AppOption('verifyPasswordReset', 'description'),
  // AppOption('applyActionCode', 'description'),
  AppOption('sendPasswordResetEmail', 'description'),
  // AppOption('sendSignInWithEmailLink', 'description'),
  AppOption('isSignInWithEmailLink', 'description'),
  // AppOption('verifyPhoneNumber', 'description'),
];

const List<AppOption> firebaseUserOptions = <AppOption>[
  AppOption('currentUser', 'Show your current user data.'),
  AppOption('sendEmailVerification', 'Stil not verified. Let\'s send a verification email.'),
  AppOption('reload', 'Let\'s see if you have new data from another device.'),
  AppOption('delete', 'Our journy was awesome. We are glad we were togheter. Come back soon.'),
  AppOption('updateEmail', 'Changing homes? No prob. Let\'s update that email.'),
  // AppOption('updatePhoneNumberCredential', ''),
  AppOption('updatePassword', 'Security breach. Let\' change that password.'),
  AppOption('updateProfile', 'Have a bew fancy picture? Or a new name idea? Try this.'),
  AppOption('reauthenticateWithCredential',
      'It might be that it has been a long time since you proved your identity. Let\'s do that now.'),
  // AppOption('unlinkFromProvider', ''),
  AppOption('signOut', 'See you later.'),
];

class AppOption {
  const AppOption(this.name, this.description);

  final String name;
  final String description;
}
