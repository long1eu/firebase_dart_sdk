import 'dart:io';

import 'package:firebase_auth_secure_storage_dart/src/linux/libsecret_store.dart';
import 'package:firebase_auth_secure_storage_dart/src/macos/keychain_store.dart';
import 'package:firebase_auth_secure_storage_dart/src/windows/dpapi_store.dart';

/// The secret store of the operating system, as `SecureAuthStorage` uses it:
/// one secret (a UTF-8 string) per account name.
///
/// [SecretStore.platform] is the store of the running system. Implement this
/// to keep the sessions in another store, or to fake the store in tests.
abstract interface class SecretStore {
  /// The store of the running operating system, for the items of [service]:
  ///
  /// * macOS: generic-password items of the login keychain (the legacy,
  ///   file-based keychain) with the Keychain service [service]
  ///   (`kSecAttrService`) and the account name as `kSecAttrAccount`.
  /// * Linux: libsecret, loaded at the first call, with the attributes
  ///   `service` = [service] and `account` = the account name, in the default
  ///   collection of the Secret Service.
  /// * Windows: one file per account, encrypted with DPAPI for the current
  ///   user, in `%LOCALAPPDATA%\<service>`.
  /// * Anywhere else: a store whose every call fails with a
  ///   [SecretStoreError] that `SecureAuthStorageException.isUnavailable`
  ///   reports as unavailable.
  ///
  /// Creating it does no I/O: nothing is loaded or opened before the first
  /// call.
  factory SecretStore.platform({String service = defaultService}) {
    if (Platform.isMacOS) {
      return KeychainSecretStore(service: service);
    }
    if (Platform.isLinux) {
      return LibsecretSecretStore(service: service);
    }
    if (Platform.isWindows) {
      return DpapiSecretStore.forService(service);
    }
    return const _UnsupportedSecretStore();
  }

  /// The service of the items when none is given:
  /// `firebase_auth_secure_storage`, the Keychain service of the Flutter
  /// package `firebase_auth_secure_storage_flutter` too.
  static const String defaultService = 'firebase_auth_secure_storage';

  /// The secret of [account], or null when there is none.
  Future<String?> read(String account);

  /// Stores [secret] for [account], replacing the one it had.
  Future<void> write(String account, String secret);

  /// Deletes the secret of [account]; nothing happens when there is none.
  Future<void> delete(String account);
}

/// A call into the secret store of the operating system failed.
///
/// It never holds a stored secret: only the name of the function, the status
/// it returned and the message of the system.
class SecretStoreError implements Exception {
  /// A failure of [function] with [message], and the [status] and [domain]
  /// the system reported, if any.
  const SecretStoreError({
    required this.function,
    required this.message,
    this.status,
    this.domain,
  });

  /// The function that failed, for example `SecItemAdd`,
  /// `secret_password_store_sync`, `CryptProtectData`, or `dlopen` when the
  /// library could not be loaded.
  final String function;

  /// The status the system returned: an `OSStatus` on macOS, the code of the
  /// `GError` on Linux, the `GetLastError()` value on Windows; null when there
  /// is none.
  final int? status;

  /// The domain of the `GError` on Linux, for example `g-dbus-error-quark`;
  /// null elsewhere.
  final String? domain;

  /// The message of the system, or one of this package.
  final String message;

  @override
  String toString() {
    final StringBuffer details = StringBuffer();
    if (domain != null) {
      details.write(' $domain');
    }
    if (status != null) {
      details.write(' status $status');
    }
    return '$function failed$details: $message';
  }
}

/// The store of a system without a secret store this package supports.
class _UnsupportedSecretStore implements SecretStore {
  const _UnsupportedSecretStore();

  SecretStoreError get _error => SecretStoreError(
    function: 'SecretStore.platform',
    message:
        'no secret store is supported on ${Platform.operatingSystem} '
        '(only macOS, Linux and Windows)',
  );

  @override
  Future<String?> read(String account) => Future<String?>.error(_error);

  @override
  Future<void> write(String account, String secret) =>
      Future<void>.error(_error);

  @override
  Future<void> delete(String account) => Future<void>.error(_error);
}
