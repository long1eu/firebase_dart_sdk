import 'package:firebase_auth_secure_storage_dart/firebase_auth_secure_storage_dart.dart';

/// Run by linux_libsecret_test.dart with a session bus that does not exist:
/// prints whether the store reports itself unavailable.
Future<void> main() async {
  final SecureAuthStorage storage = SecureAuthStorage(namespace: 'no-bus');
  try {
    await storage.read('key');
    print('isUnavailable=false (the read succeeded)');
  } on SecureAuthStorageException catch (e) {
    print('isUnavailable=${e.isUnavailable} $e');
  }
}
