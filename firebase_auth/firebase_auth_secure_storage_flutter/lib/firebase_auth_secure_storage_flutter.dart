/// Keeps the Firebase Auth session of `firebase_auth_providers_dart` in the
/// secure store of the platform, through `flutter_secure_storage`.
///
/// [SecureAuthStorage] is an `AuthStorage`: pass it to `FirebaseUserAuth`
/// (`storage:`, or `setStorage`) or, with `firebase_auth_dart_platform`, to
/// `FirebaseAuthDart.use(storageFor: ...)`.
///
/// ```dart
/// Future<void> main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   final SecureAuthStorage storage = SecureAuthStorage();
///   FirebaseAuthDart.use(storageFor: (FirebaseApp app) => storage);
///   await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
///   runApp(const MyApp());
/// }
/// ```
library;

export 'package:flutter_secure_storage/flutter_secure_storage.dart'
    show
        AndroidOptions,
        FlutterSecureStorage,
        IOSOptions,
        KeychainAccessibility,
        LinuxOptions,
        MacOsOptions,
        WindowsOptions;

export 'src/exceptions.dart'
    show
        MigrationStep,
        SecureAuthStorageException,
        SecureAuthStorageMigrationException,
        SecureAuthStorageMigrationIssue;
export 'src/secure_auth_storage.dart'
    show MigrationIssueHandler, SecureAuthStorage;
