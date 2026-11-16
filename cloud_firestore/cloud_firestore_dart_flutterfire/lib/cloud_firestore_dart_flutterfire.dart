/// A bridge from the FlutterFire plugins (`firebase_core`, `firebase_auth`) to `cloud_firestore_dart`.
///
/// A Flutter app that initializes Firebase and signs its users in with the official plugins gets a
/// `cloud_firestore_dart` instance for the same project and the same user, without copying the options and
/// without a second sign-in:
///
/// ```dart
/// await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
/// final FirebaseFirestore firestore = await FlutterFireBridge.firestore();
/// ```
///
/// [FlutterFireBridge] does the common case. The pieces, for wiring by hand: [firebaseOptionsFromFlutterFire] and [dartAppFor] for the app,
/// [FlutterFireAuthTokenProvider] for the user, and [FlutterFireAppCheckProvider] for App Check tokens.
///
/// `firebase_core` and `firebase_app_dart` both export `Firebase`, `FirebaseApp`, `FirebaseOptions` and
/// `FirebaseException`: import one of them with a prefix.
library;

import 'src/app_check_provider.dart';
import 'src/auth_token_provider.dart';
import 'src/bridge.dart';
import 'src/options.dart';

export 'src/app_check_provider.dart' show FlutterFireAppCheckProvider;
export 'src/auth_token_provider.dart'
    show FlutterFireAuthTokenProvider, IdTokenUser;
export 'src/bridge.dart' show FlutterFireBridge;
export 'src/options.dart' show dartAppFor, firebaseOptionsFromFlutterFire;
