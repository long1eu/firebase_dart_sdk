/// Firebase App Check for pure Dart: debug and custom providers, token caching and refresh, on
/// the VM and the web.
///
/// Create one [FirebaseAppCheck] per app, before the Firebase services of that app, with a
/// [DebugAppCheckProvider] or a [CustomAppCheckProvider]. The services then send its token with
/// their requests. To keep the token across restarts pass a [KeyValueStore]; on the VM,
/// `package:firebase_app_check_dart/io.dart` reads the debug token from the environment.
library;

import 'package:firebase_app_check_dart/src/firebase_app_check.dart';
import 'package:firebase_app_check_dart/src/provider.dart';
import 'package:firebase_installations_dart/firebase_installations_dart.dart';

export 'package:firebase_app_check_dart/src/app_check_token.dart'
    show AppCheckToken;
export 'package:firebase_app_check_dart/src/exception.dart'
    show FirebaseAppCheckException, firebaseAppCheckExceptionCodes;
export 'package:firebase_app_check_dart/src/firebase_app_check.dart'
    show FirebaseAppCheck;
export 'package:firebase_app_check_dart/src/logger.dart'
    show AppCheckLogLevel, AppCheckLogger;
export 'package:firebase_app_check_dart/src/provider.dart'
    show AppCheckProvider, CustomAppCheckProvider, DebugAppCheckProvider;
export 'package:firebase_installations_dart/firebase_installations_dart.dart'
    show KeyValueStore, MemoryKeyValueStore;
