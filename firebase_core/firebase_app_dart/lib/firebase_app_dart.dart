/// A pure-Dart `FirebaseApp` for the Dart VM and Flutter (no web).
///
/// Create an app with [FirebaseApp.withOptions] and a set of
/// [FirebaseOptions], then hand it to a service such as
/// `package:cloud_firestore_dart`. Platform specific services (storage,
/// connectivity, auth and App Check tokens) are supplied through
/// `PlatformDependencies` from `package:firebase_app_dart/platform_dependencies.dart`.
library firebase_app_dart;

export 'src/firebase_app.dart';
export 'src/firebase_error.dart';
export 'src/firebase_options.dart';
export 'src/internal/app_check.dart'
    show AppCheckTokenResult, InternalAppCheckTokenProvider;
export 'src/internal/auth.dart' show GetTokenResult;
export 'src/internal/internal.dart'
    show InternalTokenProvider, InternalTokenResult;
export 'src/platform_js.dart' if (dart.library.io) 'src/platform_io.dart';
