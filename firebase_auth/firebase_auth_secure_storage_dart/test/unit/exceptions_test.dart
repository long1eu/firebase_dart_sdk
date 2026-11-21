import 'package:firebase_auth_secure_storage_dart/firebase_auth_secure_storage_dart.dart';
import 'package:test/test.dart';

SecureAuthStorageException _on(
  String platform,
  String function, {
  int? status,
  String? domain,
}) => SecureAuthStorageException(
  platform: platform,
  operation: 'read',
  cause: SecretStoreError(
    function: function,
    status: status,
    domain: domain,
    message: 'system message',
  ),
);

void main() {
  group('isUnavailable', () {
    test('the library cannot be loaded, on every platform', () {
      for (final String platform in <String>['macOS', 'linux', 'windows']) {
        expect(_on(platform, 'dlopen').isUnavailable, isTrue, reason: platform);
      }
    });

    test('a system without a supported store', () {
      expect(_on('fuchsia', 'SecretStore.platform').isUnavailable, isTrue);
    });

    test('macOS: no keychain, no default keychain', () {
      expect(_on('macOS', 'SecItemAdd', status: -25291).isUnavailable, isTrue);
      expect(_on('macOS', 'SecItemAdd', status: -25307).isUnavailable, isTrue);
    });

    test('macOS: a locked keychain, a denied or cancelled prompt are not', () {
      for (final int status in <int>[-25308, -25293, -128, -25300, -34018]) {
        expect(
          _on('macOS', 'SecItemCopyMatching', status: status).isUnavailable,
          isFalse,
          reason: '$status',
        );
      }
    });

    test('Linux: no D-Bus session bus or no Secret Service', () {
      expect(
        _on(
          'linux',
          'secret_password_lookup_sync',
          status: 2,
          domain: 'g-dbus-error-quark',
        ).isUnavailable,
        isTrue,
      );
      expect(
        _on(
          'linux',
          'secret_password_store_sync',
          status: 0,
          domain: 'g-io-error-quark',
        ).isUnavailable,
        isTrue,
      );
    });

    test('Linux: a locked collection', () {
      expect(
        _on(
          'linux',
          'secret_password_store_sync',
          status: 2,
          domain: 'secret-error',
        ).isUnavailable,
        isTrue,
      );
    });

    test('Linux: other libsecret errors and bad text are not', () {
      expect(
        _on(
          'linux',
          'secret_password_lookup_sync',
          status: 1,
          domain: 'secret-error',
        ).isUnavailable,
        isFalse,
      );
      expect(
        _on('linux', 'secret_password_lookup_sync').isUnavailable,
        isFalse,
      );
    });

    test('Windows: DPAPI refuses access without an interactive logon', () {
      expect(
        _on('windows', 'CryptProtectData', status: 5).isUnavailable,
        isTrue,
      );
      expect(
        _on('windows', 'CryptUnprotectData', status: 5).isUnavailable,
        isTrue,
      );
      expect(_on('windows', 'LOCALAPPDATA').isUnavailable, isTrue);
    });

    test('Windows: a value that does not decrypt, a file error are not', () {
      expect(
        _on('windows', 'CryptUnprotectData', status: 13).isUnavailable,
        isFalse,
      );
      expect(_on('windows', 'File.read', status: 5).isUnavailable, isFalse);
      expect(_on('windows', 'File.write', status: 32).isUnavailable, isFalse);
    });

    test('a status of one platform means nothing on another', () {
      expect(_on('linux', 'SecItemAdd', status: -25291).isUnavailable, isFalse);
      expect(
        _on('macOS', 'CryptProtectData', status: 5).isUnavailable,
        isFalse,
      );
    });

    test('an exception that is not a SecretStoreError is not', () {
      final SecureAuthStorageException e = SecureAuthStorageException(
        platform: 'linux',
        operation: 'write',
        cause: Exception('custom store'),
      );
      expect(e.isUnavailable, isFalse);
      expect(e.function, isNull);
      expect(e.status, isNull);
    });
  });

  group('remedy and message', () {
    test('names platform, operation, function, status and remedy', () {
      final String text =
          '${_on('macOS', 'SecItemCopyMatching', status: -25308)}';
      expect(text, contains('macOS'));
      expect(text, contains('could not read'));
      expect(text, contains('SecItemCopyMatching failed status -25308'));
      expect(text, contains('security unlock-keychain'));
    });

    test('macOS: a denied prompt explains the access list', () {
      expect(
        _on('macOS', 'SecItemCopyMatching', status: -25293).remedy,
        contains('Always Allow'),
      );
    });

    test('Linux: a locked keyring, or no Secret Service', () {
      expect(
        _on('linux', 'x', status: 2, domain: 'secret-error').remedy,
        contains('unlock the login keyring'),
      );
      expect(
        _on('linux', 'x', status: 2, domain: 'g-dbus-error-quark').remedy,
        contains('dbus-run-session'),
      );
      expect(
        '${_on('linux', 'x', status: 2, domain: 'g-dbus-error-quark')}',
        contains('g-dbus-error-quark status 2'),
      );
    });

    test('Windows: no interactive logon, not a directory permission', () {
      final String remedy = _on(
        'windows',
        'CryptProtectData',
        status: 5,
      ).remedy;
      expect(remedy, contains('interactive logon'));
      expect(remedy, contains('FileAuthStorage'));
      expect(_on('windows', 'File.write').remedy, contains('%LOCALAPPDATA%'));
    });

    test('an unsupported system points at FileAuthStorage', () {
      expect(
        _on('fuchsia', 'SecretStore.platform').remedy,
        contains('FileAuthStorage'),
      );
    });
  });

  group('migration messages', () {
    test('name the step and the key', () {
      const SecureAuthStorageMigrationIssue read =
          SecureAuthStorageMigrationIssue(
            key: 'k',
            step: MigrationStep.readOld,
            error: 'boom',
          );
      const SecureAuthStorageMigrationIssue delete =
          SecureAuthStorageMigrationIssue(
            key: 'k',
            step: MigrationStep.deleteOld,
            error: 'boom',
          );
      expect('$read', contains('could not be read from the old storage'));
      expect('$delete', contains('a copy of it remains there'));
    });

    test('the migration exception says whether the copy was deleted', () {
      expect(
        '${SecureAuthStorageMigrationException(key: 'k')}',
        contains('was deleted'),
      );
      expect(
        '${SecureAuthStorageMigrationException(key: 'k', cleanupError: 'x')}',
        contains('could not be deleted (x)'),
      );
    });
  });
}
