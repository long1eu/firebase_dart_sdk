import 'package:flutter/services.dart';

/// `errSecMissingEntitlement`: the app lacks the `keychain-access-groups` entitlement.
const int _errSecMissingEntitlement = -34018;

/// `errSecInteractionNotAllowed`: the item cannot be read while the device is locked.
const int _errSecInteractionNotAllowed = -25308;

/// `errSecNotAvailable`: no keychain is available.
const int _errSecNotAvailable = -25291;

/// `errSecNoDefaultKeychain`: the user has no default keychain.
const int _errSecNoDefaultKeychain = -25307;

/// The context the Linux plugin puts in front of the error of `secret_service_get_sync`, which
/// fails when there is no D-Bus session bus or no Secret Service on it.
const String _secretServiceGetSync = 'secret_service_get_sync';

/// How the Windows implementation (`flutter_secure_storage_windows` 4.x, through `WindowsException`
/// of `package:win32` 6.x) reports that `CryptProtectData` or `CryptUnprotectData` was refused
/// with `E_ACCESSDENIED` (`ERROR_ACCESS_DENIED` as an HRESULT, 0x80070005): the start of
/// `toString()`, lowercased. DPAPI needs the user's interactive logon; an SSH session or a service
/// has none. `package:win32` cannot be imported here (it needs `dart:ffi`, which the web lacks),
/// so the exception is recognised by its text.
const List<String> _dpapiAccessDenied = <String>[
  'windowsexception hresult(0x80070005): failure on cryptprotectdata()',
  'windowsexception hresult(0x80070005): failure on cryptunprotectdata()',
];

/// The secure store of the platform failed: it is missing, locked or refused the operation.
///
/// Thrown by `SecureAuthStorage.read` and `SecureAuthStorage.write` for every exception of
/// `flutter_secure_storage` (a [PlatformException] of the native plugin, a
/// [MissingPluginException] when the plugin is not registered, the exceptions of the Windows
/// implementation). The session is never written anywhere else instead: [toString] names the
/// platform, the cause and what to do.
class SecureAuthStorageException implements Exception {
  /// An exception for [operation] on [platform], caused by [cause].
  SecureAuthStorageException({
    required this.platform,
    required this.operation,
    required this.cause,
  });

  /// The platform the app runs on: `android`, `iOS`, `macOS`, `linux`, `windows` or `web`.
  final String platform;

  /// What failed: `read`, `write` or `delete`.
  final String operation;

  /// The exception of `flutter_secure_storage`.
  final Exception cause;

  /// The error code of the plugin when [cause] is a [PlatformException], for example
  /// `KeyringLocked` on Linux or `Unexpected security result code` on iOS and macOS.
  String? get code {
    final Exception cause = this.cause;
    return cause is PlatformException ? cause.code : null;
  }

  /// What to do about it, for the platform and the error code.
  String get remedy => _remedyFor(platform, cause);

  /// Whether the store as a whole cannot be used in this run, rather than one value or one
  /// call failing.
  ///
  /// True for a [MissingPluginException] (no plugin: `flutter test`, a platform the app was not
  /// built for), on Linux for a locked keyring (`KeyringLocked`) and for no Secret Service or no
  /// D-Bus session bus (`secret_service_get_sync` failed), on iOS and macOS for
  /// `errSecMissingEntitlement`, `errSecNotAvailable` and `errSecNoDefaultKeychain`, and on
  /// Windows when DPAPI refuses access (`CryptProtectData` or `CryptUnprotectData` fails with
  /// `E_ACCESSDENIED`, as in an SSH session or a service, which have no interactive logon).
  ///
  /// False for everything else, which may concern a stored value: a value that cannot be parsed
  /// or decrypted (Linux `StorageError`, an Android Keystore failure, any other DPAPI error on
  /// Windows), and
  /// `errSecInteractionNotAllowed`, a device that is locked for now. A caller that uses another
  /// storage when the store is unavailable must not do it for those: the stored session would
  /// look signed out.
  bool get isUnavailable => _isUnavailable(platform, cause);

  @override
  String toString() =>
      'SecureAuthStorageException: the secure store of $platform could not $operation the '
      'session (${_describe(cause)}). $remedy';
}

/// What `SecureAuthStorage` could not finish while it moved a session from the old storage.
enum MigrationStep {
  /// The old storage could not be read: nothing was moved, and the read returned null.
  readOld,

  /// The session was not removed from the old storage, which still holds a copy of it.
  deleteOld,
}

/// A failed step of the migration that did not fail the operation, given to the
/// `onMigrationIssue` callback of `SecureAuthStorage`.
class SecureAuthStorageMigrationIssue {
  /// An issue of [step] for [key], caused by [error].
  const SecureAuthStorageMigrationIssue({
    required this.key,
    required this.step,
    required this.error,
  });

  /// The key of the session, as `FirebaseUserAuth` passes it (without the namespace).
  final String key;

  /// The step that failed.
  final MigrationStep step;

  /// The exception of the old storage.
  final Object error;

  @override
  String toString() => switch (step) {
    MigrationStep.readOld =>
      'the session "$key" could not be read from the old storage ($error); it was not moved '
          'to the secure store, and the old storage was left as it is.',
    MigrationStep.deleteOld =>
      'the session "$key" could not be removed from the old storage ($error); a copy of it '
          'remains there. Delete it, for example the file of the FileAuthStorage.',
  };
}

/// The session moved to the secure store did not read back as it was written.
///
/// The old storage still holds the session; the copy in the secure store was deleted (unless
/// [cleanupError] says otherwise). The next read tries the move again.
class SecureAuthStorageMigrationException implements Exception {
  /// An exception for [key]; [cleanupError] is the failure to delete the bad copy, if any.
  SecureAuthStorageMigrationException({required this.key, this.cleanupError});

  /// The key of the session, as `FirebaseUserAuth` passes it (without the namespace).
  final String key;

  /// Why the copy written to the secure store could not be deleted; null when it was.
  final Object? cleanupError;

  @override
  String toString() {
    final String cleanup = cleanupError == null
        ? 'The copy in the secure store was deleted.'
        : 'The copy in the secure store could not be deleted ($cleanupError).';
    return 'SecureAuthStorageMigrationException: the session "$key" read back from the secure '
        'store differs from the one written; the old storage still holds it. $cleanup';
  }
}

bool _isUnavailable(String platform, Exception cause) {
  if (cause is MissingPluginException) {
    return true;
  }
  if (platform == 'windows') {
    return _isDpapiAccessDenied(cause);
  }
  if (cause is! PlatformException) {
    return false;
  }
  return switch (platform) {
    'linux' =>
      cause.code == 'KeyringLocked' ||
          (cause.code == 'Libsecret error' &&
              (cause.message ?? '').startsWith(_secretServiceGetSync)),
    'macOS' || 'iOS' => const <Object?>[
      _errSecMissingEntitlement,
      _errSecNotAvailable,
      _errSecNoDefaultKeychain,
    ].contains(cause.details),
    _ => false,
  };
}

bool _isDpapiAccessDenied(Exception cause) {
  if (cause is PlatformException) {
    return false;
  }
  final String text = '$cause'.toLowerCase();
  return _dpapiAccessDenied.any(text.startsWith);
}

String _describe(Exception cause) {
  if (cause is PlatformException) {
    final Object? details = cause.details;
    final String detail = details is int ? ', status $details' : '';
    return '${cause.code}: ${cause.message ?? 'no message'}$detail';
  }
  return '$cause';
}

String _remedyFor(String platform, Exception cause) {
  if (cause is MissingPluginException) {
    return 'The flutter_secure_storage plugin is not registered: run inside a Flutter app built '
        'for this platform after adding the dependency (not in a plain Dart program), or fake '
        'the plugin in tests.';
  }
  final Object? details = cause is PlatformException ? cause.details : null;
  final String? code = cause is PlatformException ? cause.code : null;
  return switch (platform) {
    'linux' => _linuxRemedy(code),
    'macOS' || 'iOS' => _appleRemedy(platform, details),
    'android' =>
      'The Android Keystore could not encrypt or decrypt the value. After a restore from Auto '
          'Backup on another device the key is missing ("Failed to unwrap key"): set '
          'android:allowBackup="false" or exclude FlutterSecureStorage from the backup (see the '
          'README of firebase_auth_secure_storage_flutter).',
    'windows' => _windowsRemedy(cause),
    'web' =>
      'Browsers have no secure store, and flutter_secure_storage on the web is experimental: '
          'prefer InMemoryAuthStorage or WebAuthStorage.session of firebase_auth_providers_dart.',
    _ => 'See the documentation of flutter_secure_storage for this platform.',
  };
}

String _windowsRemedy(Exception cause) {
  if (_isDpapiAccessDenied(cause)) {
    return 'DPAPI refused access (E_ACCESSDENIED): it needs an interactive logon of the user, '
        'and an SSH session or a Windows service has none. This is not a permission problem of '
        'a directory. Run the app in the user\'s desktop session, or pass a FileAuthStorage of '
        'firebase_auth_providers_dart to keep the session in a file instead.';
  }
  return 'flutter_secure_storage keeps the values encrypted with DPAPI in one file '
      '(flutter_secure_storage.dat) of the application support directory: check that the '
      'directory exists and that the user can write it. A file that DPAPI cannot decrypt is '
      'deleted by the plugin.';
}

String _linuxRemedy(String? code) {
  if (code == 'KeyringLocked') {
    return 'The keyring is locked: unlock the login keyring (GNOME Keyring, KDE Wallet) and '
        'try again.';
  }
  return 'Linux needs libsecret (libsecret-1-0) and a running Secret Service '
      '(org.freedesktop.secrets: GNOME Keyring or KDE Wallet) on the D-Bus session bus. SSH '
      'sessions, CI and containers have neither by default: start one (dbus-run-session, then '
      'gnome-keyring-daemon --unlock), or pass a FileAuthStorage of firebase_auth_providers_dart '
      'to keep the session in an owner-only file instead.';
}

String _appleRemedy(String platform, Object? status) {
  if (status == _errSecMissingEntitlement) {
    return platform == 'macOS'
        ? 'errSecMissingEntitlement: the data-protection keychain needs the '
              'keychain-access-groups entitlement in a signed app (see the README of '
              'firebase_auth_secure_storage_flutter). An unsigned build passes a '
              'FlutterSecureStorage with MacOsOptions(usesDataProtectionKeychain: false).'
        : 'errSecMissingEntitlement: sign the app with the keychain-access-groups entitlement '
              '(Keychain Sharing).';
  }
  if (status == _errSecInteractionNotAllowed) {
    return 'errSecInteractionNotAllowed: the keychain item cannot be used while the device is '
        'locked. Pass a FlutterSecureStorage whose accessibility is '
        'KeychainAccessibility.first_unlock to use it after the first unlock.';
  }
  return 'The Keychain refused the operation; the status is an OSStatus of Security.framework.';
}
