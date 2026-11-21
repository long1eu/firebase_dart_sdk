import 'package:firebase_auth_secure_storage_dart/src/secret_store.dart';

/// `errSecNotAvailable`: no keychain is available.
const int _errSecNotAvailable = -25291;

/// `errSecNoDefaultKeychain`: the user has no default keychain.
const int _errSecNoDefaultKeychain = -25307;

/// `errSecInteractionNotAllowed`: the keychain is locked and macOS may not
/// ask the user to unlock it (no window server: SSH, a daemon).
const int _errSecInteractionNotAllowed = -25308;

/// `errSecAuthFailed`: the user denied access, or entered a wrong password.
const int _errSecAuthFailed = -25293;

/// `errSecUserCanceled`: the user cancelled the prompt.
const int _errSecUserCanceled = -128;

/// `ERROR_ACCESS_DENIED`, which DPAPI sets without an interactive logon.
const int _errorAccessDenied = 5;

/// `SECRET_ERROR_IS_LOCKED` of libsecret.
const int _secretErrorIsLocked = 2;

/// The secure store of the system failed: it is missing, locked or refused
/// the operation.
///
/// Thrown by `SecureAuthStorage.read` and `SecureAuthStorage.write` for every
/// exception of the [SecretStore]. The session is never written anywhere
/// else instead: [toString] names the platform, the cause and what to do. It
/// never holds a stored value.
class SecureAuthStorageException implements Exception {
  /// An exception for [operation] on [platform], caused by [cause].
  SecureAuthStorageException({
    required this.platform,
    required this.operation,
    required this.cause,
  });

  /// The system the program runs on: `macOS`, `linux`, `windows`, or the
  /// value of `Platform.operatingSystem` elsewhere.
  final String platform;

  /// What failed: `read`, `write` or `delete`.
  final String operation;

  /// The exception of the store: a [SecretStoreError] for the stores of this
  /// package.
  final Exception cause;

  /// The function of the system that failed, when [cause] is a
  /// [SecretStoreError]; for example `SecItemAdd`, `dlopen` or
  /// `CryptProtectData`.
  String? get function {
    final Exception cause = this.cause;
    return cause is SecretStoreError ? cause.function : null;
  }

  /// The status the system returned, when [cause] is a [SecretStoreError]
  /// that has one (an `OSStatus`, a `GError` code, a Win32 error).
  int? get status {
    final Exception cause = this.cause;
    return cause is SecretStoreError ? cause.status : null;
  }

  /// What to do about it, for the platform and the cause.
  String get remedy => _remedyFor(platform, cause);

  /// Whether the store as a whole cannot be used in this run, rather than one
  /// value or one call failing.
  ///
  /// True when the native library could not be loaded (`dlopen`), on a
  /// system without a supported store, on macOS for `errSecNotAvailable` and
  /// `errSecNoDefaultKeychain`, on Linux for a failure to reach the Secret
  /// Service (a `GError` of the `g-dbus-error-quark` or `g-io-error-quark`
  /// domain: no D-Bus session bus, no Secret Service on it) and for a locked
  /// collection (`secret-error` code 2), and on Windows when DPAPI refuses
  /// access (`CryptProtectData` or `CryptUnprotectData` fails with
  /// `ERROR_ACCESS_DENIED`, as in an SSH session or a service, which have no
  /// interactive logon) or `LOCALAPPDATA` is not set.
  ///
  /// False for everything else, which may concern a stored value: a value
  /// that cannot be decrypted or is not UTF-8, a file that cannot be read,
  /// and on macOS `errSecInteractionNotAllowed` (a locked keychain that
  /// cannot prompt), `errSecAuthFailed` and `errSecUserCanceled`. A caller
  /// that uses another storage when the store is unavailable must not do it
  /// for those: the stored session would look signed out.
  bool get isUnavailable => _isUnavailable(platform, cause);

  @override
  String toString() =>
      'SecureAuthStorageException: the secure store of $platform could not '
      '$operation the session ($cause). $remedy';
}

/// What `SecureAuthStorage` could not finish while it moved a session from
/// the old storage.
enum MigrationStep {
  /// The old storage could not be read: nothing was moved, and the read
  /// returned null.
  readOld,

  /// The session was not removed from the old storage, which still holds a
  /// copy of it.
  deleteOld,
}

/// A failed step of the migration that did not fail the operation, given to
/// the `onMigrationIssue` callback of `SecureAuthStorage`.
class SecureAuthStorageMigrationIssue {
  /// An issue of [step] for [key], caused by [error].
  const SecureAuthStorageMigrationIssue({
    required this.key,
    required this.step,
    required this.error,
  });

  /// The key of the session, as `FirebaseUserAuth` passes it (without the
  /// namespace).
  final String key;

  /// The step that failed.
  final MigrationStep step;

  /// The exception of the old storage.
  final Object error;

  @override
  String toString() => switch (step) {
    MigrationStep.readOld =>
      'the session "$key" could not be read from the old storage ($error); '
          'it was not moved to the secure store, and the old storage was left '
          'as it is.',
    MigrationStep.deleteOld =>
      'the session "$key" could not be removed from the old storage '
          '($error); a copy of it remains there. Delete it, for example the '
          'file of the FileAuthStorage.',
  };
}

/// The session moved to the secure store did not read back as it was
/// written.
///
/// The old storage still holds the session; the copy in the secure store was
/// deleted (unless [cleanupError] says otherwise). The next read tries the
/// move again.
class SecureAuthStorageMigrationException implements Exception {
  /// An exception for [key]; [cleanupError] is the failure to delete the bad
  /// copy, if any.
  SecureAuthStorageMigrationException({required this.key, this.cleanupError});

  /// The key of the session, as `FirebaseUserAuth` passes it (without the
  /// namespace).
  final String key;

  /// Why the copy written to the secure store could not be deleted; null
  /// when it was.
  final Object? cleanupError;

  @override
  String toString() {
    final String cleanup = cleanupError == null
        ? 'The copy in the secure store was deleted.'
        : 'The copy in the secure store could not be deleted ($cleanupError).';
    return 'SecureAuthStorageMigrationException: the session "$key" read back '
        'from the secure store differs from the one written; the old storage '
        'still holds it. $cleanup';
  }
}

bool _isUnavailable(String platform, Exception cause) {
  if (cause is! SecretStoreError) {
    return false;
  }
  if (cause.function == 'dlopen' || cause.function == 'SecretStore.platform') {
    return true;
  }
  return switch (platform) {
    'macOS' =>
      cause.status == _errSecNotAvailable ||
          cause.status == _errSecNoDefaultKeychain,
    'linux' =>
      cause.domain == 'g-dbus-error-quark' ||
          cause.domain == 'g-io-error-quark' ||
          (cause.domain == 'secret-error' &&
              cause.status == _secretErrorIsLocked),
    'windows' =>
      cause.function == 'LOCALAPPDATA' || _isDpapiAccessDenied(cause),
    _ => false,
  };
}

bool _isDpapiAccessDenied(SecretStoreError cause) =>
    (cause.function == 'CryptProtectData' ||
        cause.function == 'CryptUnprotectData') &&
    cause.status == _errorAccessDenied;

String _remedyFor(String platform, Exception cause) {
  if (cause is SecretStoreError && cause.function == 'SecretStore.platform') {
    return 'Only macOS, Linux and Windows have a secure store here: pass a '
        'FileAuthStorage of firebase_auth_providers_dart instead.';
  }
  return switch (platform) {
    'macOS' => _macRemedy(cause),
    'linux' => _linuxRemedy(cause),
    'windows' => _windowsRemedy(cause),
    _ => 'Pass a FileAuthStorage of firebase_auth_providers_dart instead.',
  };
}

String _macRemedy(Exception cause) {
  final int? status = cause is SecretStoreError ? cause.status : null;
  return switch (status) {
    _errSecInteractionNotAllowed =>
      'errSecInteractionNotAllowed: the login keychain is locked and macOS '
          'cannot ask to unlock it (an SSH session or a daemon has no window '
          'server). Unlock it first (security unlock-keychain), or run the '
          'program in the user\'s desktop session.',
    _errSecAuthFailed || _errSecUserCanceled =>
      'The user denied this program access to the keychain item. The item '
          'trusts the program that created it; a rebuilt or moved program is '
          'another one to macOS. Allow it when asked ("Always Allow"), or '
          'delete the item in Keychain Access.',
    _errSecNotAvailable || _errSecNoDefaultKeychain =>
      'The user has no usable login keychain (a daemon or a user without a '
          'login session). Run the program as a logged-in user, or pass a '
          'FileAuthStorage of firebase_auth_providers_dart.',
    _ =>
      'The Keychain refused the operation; the status is an OSStatus of '
          'Security.framework (security error <status> explains it).',
  };
}

String _linuxRemedy(Exception cause) {
  if (cause is SecretStoreError &&
      cause.domain == 'secret-error' &&
      cause.status == _secretErrorIsLocked) {
    return 'The keyring is locked: unlock the login keyring (GNOME Keyring, '
        'KDE Wallet) and try again.';
  }
  return 'Linux needs libsecret (libsecret-1-0) and a running Secret Service '
      '(org.freedesktop.secrets: GNOME Keyring, KDE Wallet or KeePassXC) on '
      'the D-Bus session bus. SSH sessions, CI and containers have neither by '
      'default: start one (dbus-run-session, then gnome-keyring-daemon '
      '--unlock), or pass a FileAuthStorage of firebase_auth_providers_dart '
      'to keep the session in an owner-only file instead.';
}

String _windowsRemedy(Exception cause) {
  if (cause is SecretStoreError && _isDpapiAccessDenied(cause)) {
    return 'DPAPI refused access (ERROR_ACCESS_DENIED): it needs an '
        'interactive logon of the user, and an SSH session or a Windows '
        'service has none. This is not a permission problem of a directory. '
        'Run the program in the user\'s desktop session, or pass a '
        'FileAuthStorage of firebase_auth_providers_dart instead.';
  }
  if (cause is SecretStoreError && cause.function == 'LOCALAPPDATA') {
    return 'The sessions are kept under %LOCALAPPDATA%: run the program with '
        'the environment of a user profile.';
  }
  return 'The sessions are kept encrypted with DPAPI, one file per session, '
      'in a directory of %LOCALAPPDATA% (firebase_auth_secure_storage by '
      'default): check that the user can write there. A file that DPAPI '
      'cannot decrypt (written by another user, or before a reset of the '
      'password by an administrator) can be deleted; the user then signs in '
      'again.';
}
