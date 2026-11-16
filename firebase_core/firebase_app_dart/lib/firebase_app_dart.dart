/// A pure-Dart `FirebaseApp` for the Dart VM and Flutter, with experimental
/// web support.
///
/// Create an app with [FirebaseApp.withOptions] and a set of
/// [FirebaseOptions], then hand it to a service such as
/// `package:cloud_firestore_dart`. Platform specific services (storage,
/// connectivity, auth and App Check tokens) are supplied through
/// `PlatformDependencies` from `package:firebase_app_dart/platform_dependencies.dart`.
///
/// ```dart
/// import 'package:firebase_app_dart/firebase_app_dart.dart';
///
/// void main() {
///   final FirebaseApp app = FirebaseApp.withOptions(
///     const FirebaseOptions(
///       apiKey: '<YOUR_API_KEY>',
///       appId: '1:1234567890:dart:example',
///       projectId: 'my-project',
///     ),
///   );
///   print(app.options.projectId); // my-project
/// }
/// ```
///
/// The examples in the `example/` folder of the package cover named apps,
/// options from JSON, platform dependencies and app deletion.
library;

// Imported for the references in the documentation above.
import 'src/firebase_app.dart';
import 'src/firebase_options.dart';

export 'src/firebase_app.dart';
export 'src/firebase_error.dart';
export 'src/firebase_options.dart';
export 'src/internal/app_check.dart'
    show AppCheckTokenResult, AppCheckTokenProvider;
export 'src/internal/auth.dart' show GetTokenResult;
export 'src/internal/internal.dart' show AuthTokenProvider, AuthTokenChange;
export 'src/platform_js.dart' if (dart.library.io) 'src/platform_io.dart';
