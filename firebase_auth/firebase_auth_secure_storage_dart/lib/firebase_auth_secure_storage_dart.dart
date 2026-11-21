/// Keeps the Firebase Auth session of `firebase_auth_providers_dart` in the
/// secure store of the system, for command line tools and servers, without
/// Flutter: the login keychain on macOS, the Secret Service (libsecret) on
/// Linux, files encrypted with DPAPI on Windows, all through `dart:ffi`.
///
/// `SecureAuthStorage` is an `AuthStorage`: pass it to `FirebaseUserAuth`
/// (`storage:`, or `setStorage`).
///
/// ```dart
/// final SecureAuthStorage storage = SecureAuthStorage(namespace: 'com.example.tool');
/// final FirebaseUserAuth auth = FirebaseUserAuth(
///   apiKey: apiKey,
///   storage: await storage.isAvailable() ? storage : FileAuthStorage(sessionPath),
/// );
/// await auth.restore();
/// ```
library;

export 'src/exceptions.dart'
    show
        MigrationStep,
        SecureAuthStorageException,
        SecureAuthStorageMigrationException,
        SecureAuthStorageMigrationIssue;
export 'src/secret_store.dart' show SecretStore, SecretStoreError;
export 'src/secure_auth_storage.dart'
    show MigrationIssueHandler, SecureAuthStorage;
