import 'dart:async';
import 'dart:io';

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:firebase_auth_secure_storage_dart/firebase_auth_secure_storage_dart.dart';
import 'package:firebase_auth_secure_storage_dart/src/linux/libsecret_store.dart';
import 'package:firebase_auth_secure_storage_dart/src/macos/keychain_store.dart';
import 'package:firebase_auth_secure_storage_dart/src/windows/dpapi_store.dart';
import 'package:test/test.dart';

import '../fakes.dart';

const String _key = 'firebase_auth_providers_dart:api-key';
const String _session = '{"version":2,"refreshToken":"secret-refresh-token"}';
const String _ns = 'test-ns';
const String _account = '$_ns/$_key';

const SecretStoreError _storeDown = SecretStoreError(
  function: 'dlopen',
  message: 'not loaded',
);
const SecretStoreError _perValue = SecretStoreError(
  function: 'SecItemCopyMatching',
  status: -25308,
  message: 'interaction not allowed',
);

void main() {
  late FakeSecretStore store;
  late FakeOldStorage old;
  late List<SecureAuthStorageMigrationIssue> issues;

  setUp(() {
    store = FakeSecretStore();
    old = FakeOldStorage();
    issues = <SecureAuthStorageMigrationIssue>[];
  });

  SecureAuthStorage storage({bool migrate = false}) => SecureAuthStorage(
    namespace: _ns,
    store: store,
    migrateFrom: migrate ? old : null,
    onMigrationIssue: issues.add,
  );

  group('read, write, delete', () {
    test('write stores the value under the namespaced key', () async {
      await storage().write(_key, _session);
      expect(store.secrets, <String, String>{_account: _session});
    });

    test('read returns the stored value, or null', () async {
      expect(await storage().read(_key), isNull);
      store.secrets[_account] = _session;
      expect(await storage().read(_key), _session);
    });

    test('write of null deletes the value', () async {
      store.secrets[_account] = _session;
      await storage().write(_key, null);
      expect(store.secrets, isEmpty);
      expect(store.calls, <String>['delete $_account']);
    });

    test('a value stored without the namespace is not read', () async {
      store.secrets[_key] = _session;
      expect(await storage().read(_key), isNull);
    });

    test('works as the AuthStorage of FirebaseUserAuth', () {
      expect(storage(), isA<AuthStorage>());
    });
  });

  group('namespace', () {
    test('two namespaces keep separate sessions', () async {
      final SecureAuthStorage a = SecureAuthStorage(
        namespace: 'a',
        store: store,
      );
      final SecureAuthStorage b = SecureAuthStorage(
        namespace: 'b',
        store: store,
      );
      await a.write(_key, 'session a');
      await b.write(_key, 'session b');
      expect(await a.read(_key), 'session a');
      expect(await b.read(_key), 'session b');
    });

    test('an empty namespace is rejected', () {
      expect(
        () => SecureAuthStorage(namespace: '', store: store),
        throwsArgumentError,
      );
    });

    test('default: a hash of the executable path, as the Flutter package', () {
      // The same input gives the same value the Flutter package computes on
      // desktop: the first 16 hex digits of SHA-256 of the path.
      expect(
        SecureAuthStorage.namespaceFor(executable: '/usr/local/bin/tool'),
        'firebase_auth_secure_storage:$_toolHash',
      );
      expect(
        SecureAuthStorage.namespaceFor(executable: '/usr/local/bin/tool'),
        SecureAuthStorage.namespaceFor(executable: '/usr/local/bin/tool'),
      );
      expect(
        SecureAuthStorage.namespaceFor(executable: '/usr/local/bin/tool'),
        isNot(
          SecureAuthStorage.namespaceFor(executable: '/usr/local/bin/other'),
        ),
      );
    });

    test('the default is the one of the running program', () {
      final SecureAuthStorage s = SecureAuthStorage(store: store);
      expect(s.namespace, SecureAuthStorage.defaultNamespace());
      expect(
        SecureAuthStorage.defaultNamespace(),
        SecureAuthStorage.namespaceFor(executable: Platform.resolvedExecutable),
      );
    });

    test('the constructor does no I/O; the first use does', () async {
      final SecureAuthStorage s = storage(migrate: true);
      expect(store.calls, isEmpty);
      expect(old.calls, isEmpty);
      await s.read(_key);
      expect(store.calls, isNotEmpty);
    });

    test('the platform store is created without loading anything', () {
      expect(SecureAuthStorage.new, returnsNormally);
      expect(SecretStore.platform, returnsNormally);
    });
  });

  // The layout of the stored items. A change here makes every user sign in
  // again, and must stay in step with firebase_auth_secure_storage_flutter
  // (SecureAuthStorage.namespaceFor and keychainService in its
  // lib/src/secure_auth_storage.dart, desktop branch). The expected values
  // are literals, not built from the package's constants.
  group('stored layout (pinned)', () {
    test('default namespace: prefix, colon, 16 hex digits of SHA-256', () {
      // printf %s <path> | shasum -a 256 | cut -c1-16
      expect(
        SecureAuthStorage.namespaceFor(executable: '/usr/local/bin/tool'),
        'firebase_auth_secure_storage:a0c305c6d0861338',
      );
      expect(
        SecureAuthStorage.namespaceFor(
          executable: r'C:\Program Files\tool\tool.exe',
        ),
        'firebase_auth_secure_storage:0b2d8f2bcdf79e86',
      );
      expect(
        SecureAuthStorage.defaultNamespace(),
        matches(RegExp(r'^firebase_auth_secure_storage:[0-9a-f]{16}$')),
      );
    });

    test('account of a session: <namespace>/<key>', () async {
      final SecureAuthStorage explicit = storage();
      expect(
        explicit.storageKeyFor('firebase_auth_providers_dart:api-key'),
        'test-ns/firebase_auth_providers_dart:api-key',
      );
      await explicit.write('firebase_auth_providers_dart:api-key', 'v');
      expect(store.secrets.keys, <String>[
        'test-ns/firebase_auth_providers_dart:api-key',
      ]);

      final SecureAuthStorage byDefault = SecureAuthStorage(store: store);
      await byDefault.write('k', 'v');
      expect(
        store.secrets.keys.last,
        matches(RegExp(r'^firebase_auth_secure_storage:[0-9a-f]{16}/k$')),
      );
    });

    test('probe account: <namespace>/.probe', () async {
      expect(SecureAuthStorage.probeKey, '.probe');
      await storage().isAvailable();
      expect(store.calls.first, 'write test-ns/.probe');
    });

    test('keychain service: firebase_auth_secure_storage', () {
      expect(SecureAuthStorage.keychainService, 'firebase_auth_secure_storage');
      expect(SecretStore.defaultService, 'firebase_auth_secure_storage');
    });

    test('the platform store uses that service by default', () {
      final SecretStore platform = SecretStore.platform();
      if (platform is KeychainSecretStore) {
        expect(platform.service, 'firebase_auth_secure_storage');
      } else if (platform is LibsecretSecretStore) {
        expect(platform.service, 'firebase_auth_secure_storage');
      } else if (platform is DpapiSecretStore) {
        expect(
          platform.fileOf('a'),
          contains(r'\firebase_auth_secure_storage\'),
        );
      }
    });
  });

  group('the store fails', () {
    test(
      'wrapped with platform, operation and cause, never the value',
      () async {
        store.failures['write'] = _storeDown;
        final Object error = await _errorOf(storage().write(_key, _session));
        expect(error, isA<SecureAuthStorageException>());
        final SecureAuthStorageException e =
            error as SecureAuthStorageException;
        expect(e.operation, 'write');
        expect(e.cause, same(_storeDown));
        expect(e.function, 'dlopen');
        expect(e.isUnavailable, isTrue);
        expect(
          e.platform,
          Platform.isMacOS ? 'macOS' : Platform.operatingSystem,
        );
        expect('$e', isNot(contains('secret-refresh-token')));
      },
    );

    test('a failed delete names the operation', () async {
      store.failures['delete'] = _perValue;
      final Object error = await _errorOf(storage().write(_key, null));
      expect((error as SecureAuthStorageException).operation, 'delete');
    });

    test('nothing is written to the old storage instead', () async {
      store.failures['write'] = _storeDown;
      await _errorOf(storage(migrate: true).write(_key, _session));
      expect(old.calls, isEmpty);
    });

    test('a failed operation does not block the next one', () async {
      final SecureAuthStorage s = storage();
      store.failures['write'] = _storeDown;
      await _errorOf(s.write(_key, _session));
      store.failures.clear();
      await s.write(_key, _session);
      expect(await s.read(_key), _session);
    });
  });

  group('isAvailable', () {
    const String probe = '$_ns/.probe';

    test('writes, reads back and deletes the probe entry', () async {
      expect(await storage().isAvailable(), isTrue);
      expect(store.calls, <String>[
        'write $probe',
        'read $probe',
        'delete $probe',
      ]);
      expect(store.secrets, isEmpty);
    });

    test('false when the store is unavailable, nothing left behind', () async {
      store.failures['read'] = _storeDown;
      expect(await storage().isAvailable(), isFalse);
      expect(store.calls.last, 'delete $probe');
      expect(store.secrets, isEmpty);
    });

    test('false when the write is refused as unavailable', () async {
      store.failures['write'] = _storeDown;
      expect(await storage().isAvailable(), isFalse);
      expect(store.calls, <String>['write $probe']);
    });

    test('another failure is thrown', () async {
      store.failures['read'] = _perValue;
      final Object error = await _errorOf(storage().isAvailable());
      expect((error as SecureAuthStorageException).isUnavailable, isFalse);
      expect(store.secrets, isEmpty);
    });

    test('a probe that reads back different is thrown', () async {
      store.readFilter = (String? stored) => 'other';
      final Object error = await _errorOf(storage().isAvailable());
      expect(error, isA<SecureAuthStorageException>());
      expect((error as SecureAuthStorageException).operation, 'read');
      expect(error.isUnavailable, isFalse);
      expect(store.secrets, isEmpty);
    });

    test(
      'a failed delete after a failed read does not hide the read',
      () async {
        store.failures['read'] = _storeDown;
        store.failures['delete'] = _perValue;
        expect(await storage().isAvailable(), isFalse);
      },
    );
  });

  group('migration', () {
    test('moves the session: write, read back, then delete the old', () async {
      old.values[_key] = _session;
      expect(await storage(migrate: true).read(_key), _session);
      expect(store.calls, <String>[
        'read $_account',
        'write $_account',
        'read $_account',
      ]);
      expect(old.calls, <String>['read $_key', 'write $_key null']);
      expect(store.secrets[_account], _session);
      expect(old.values, isEmpty);
      expect(issues, isEmpty);
    });

    test('the old storage is not read when the store has it', () async {
      store.secrets[_account] = _session;
      old.values[_key] = 'older';
      expect(await storage(migrate: true).read(_key), _session);
      expect(old.calls, isEmpty);
    });

    test('nothing in either storage: null, nothing written', () async {
      expect(await storage(migrate: true).read(_key), isNull);
      expect(store.calls, <String>['read $_account']);
      expect(old.calls, <String>['read $_key']);
    });

    test('without migrateFrom nothing else is read', () async {
      old.values[_key] = _session;
      expect(await storage().read(_key), isNull);
      expect(old.calls, isEmpty);
    });

    test('the store write fails: thrown, old kept', () async {
      old.values[_key] = _session;
      store.failures['write'] = _perValue;
      await _errorOf(storage(migrate: true).read(_key));
      expect(old.values[_key], _session);
      expect(old.calls, <String>['read $_key']);
    });

    test('the read-back differs: new copy deleted, old kept, thrown', () async {
      old.values[_key] = _session;
      store.readFilter = (String? stored) => stored == null ? null : 'garbled';
      final Object error = await _errorOf(storage(migrate: true).read(_key));
      expect(error, isA<SecureAuthStorageMigrationException>());
      expect(
        (error as SecureAuthStorageMigrationException).cleanupError,
        isNull,
      );
      expect('$error', isNot(contains('secret-refresh-token')));
      expect(store.secrets, isEmpty);
      expect(old.values[_key], _session);
    });

    test('the read-back differs and the delete fails: both reported', () async {
      old.values[_key] = _session;
      store.readFilter = (String? stored) => stored == null ? null : 'garbled';
      store.failures['delete'] = _perValue;
      final Object error = await _errorOf(storage(migrate: true).read(_key));
      expect(
        (error as SecureAuthStorageMigrationException).cleanupError,
        isA<SecureAuthStorageException>(),
      );
      expect(old.values[_key], _session);
    });

    test('the read-back fails: thrown, old kept', () async {
      old.values[_key] = _session;
      int reads = 0;
      store.readFilter = (String? stored) {
        reads++;
        if (reads == 2) {
          throw _perValue;
        }
        return stored;
      };
      final Object error = await _errorOf(storage(migrate: true).read(_key));
      expect(error, isA<SecureAuthStorageException>());
      expect(old.values[_key], _session);
    });

    test('the old storage cannot be read: null, reported', () async {
      old.readFailure = const FileSystemException('unreadable');
      expect(await storage(migrate: true).read(_key), isNull);
      expect(issues.single.step, MigrationStep.readOld);
      expect(issues.single.key, _key);
      expect(store.calls, <String>['read $_account']);
    });

    test('the old delete fails: value returned, reported', () async {
      old.values[_key] = _session;
      old.writeFailure = const FileSystemException('read-only');
      expect(await storage(migrate: true).read(_key), _session);
      expect(issues.single.step, MigrationStep.deleteOld);
      expect('${issues.single}', isNot(contains('secret-refresh-token')));
    });

    test('sign-out deletes the key from the old storage too', () async {
      old.values[_key] = _session;
      await storage(migrate: true).write(_key, null);
      expect(old.values, isEmpty);
      expect(old.calls, <String>['write $_key null']);
    });

    test('sign-in does not touch the old storage', () async {
      await storage(migrate: true).write(_key, _session);
      expect(old.calls, isEmpty);
    });

    test('sign-out with a failing old storage completes, reported', () async {
      old.writeFailure = const FileSystemException('read-only');
      await storage(migrate: true).write(_key, null);
      expect(issues.single.step, MigrationStep.deleteOld);
    });

    test('a write queued behind a move is not overwritten by it', () async {
      old.values[_key] = 'old session';
      final SecureAuthStorage s = storage(migrate: true);
      final Future<String?> moving = s.read(_key);
      final Future<void> writing = s.write(_key, 'new session');
      expect(await moving, 'old session');
      await writing;
      expect(await s.read(_key), 'new session');
    });

    test('from a real FileAuthStorage, which deletes its file', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'ssd_migration',
      );
      addTearDown(() => dir.delete(recursive: true));
      final String path = '${dir.path}/session.json';
      final FileAuthStorage file = FileAuthStorage(path);
      await file.write(_key, _session);
      final SecureAuthStorage s = SecureAuthStorage(
        namespace: _ns,
        store: store,
        migrateFrom: file,
        onMigrationIssue: issues.add,
      );
      expect(await s.read(_key), _session);
      expect(store.secrets[_account], _session);
      expect(File(path).existsSync(), isFalse);
      expect(issues, isEmpty);
    });
  });
}

Future<Object> _errorOf(Future<Object?> future) async {
  try {
    await future;
  } on Object catch (e) {
    return e;
  }
  fail('expected an error');
}

/// The first 16 hex digits of the SHA-256 of `/usr/local/bin/tool`
/// (`printf %s /usr/local/bin/tool | shasum -a 256`).
const String _toolHash = 'a0c305c6d0861338';
