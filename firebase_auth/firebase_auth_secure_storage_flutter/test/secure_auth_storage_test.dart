// Unit tests against a fake of the plugin's method channel: the calls go
// through the real FlutterSecureStorage and MethodChannelFlutterSecureStorage,
// and errors come back as the PlatformExceptions the native plugins send.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart'
    show AuthStorage, InMemoryAuthStorage;
import 'package:firebase_auth_secure_storage_flutter/firebase_auth_secure_storage_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const MethodChannel _channel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// The native side of the plugin: values by key, the calls it received, and
/// failures to inject per method.
class FakeSecureStore {
  final Map<String, String> values = <String, String>{};
  final List<MethodCall> calls = <MethodCall>[];

  /// Thrown (once per call) by the method of that name.
  final Map<String, Exception> failures = <String, Exception>{};

  /// Replaces the value `read` returns for a stored key (a corrupted write).
  final Map<String, String> readOverride = <String, String>{};

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    final Exception? failure = failures[call.method];
    if (failure != null) {
      throw failure;
    }
    final Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    final String? key = args['key'] as String?;
    switch (call.method) {
      case 'read':
        return values.containsKey(key)
            ? readOverride[key] ?? values[key]
            : null;
      case 'write':
        values[key!] = args['value']! as String;
        return null;
      case 'delete':
        values.remove(key);
        return null;
    }
    throw MissingPluginException(call.method);
  }

  List<String> get methods => <String>[
    for (final MethodCall c in calls) c.method,
  ];

  Map<Object?, Object?> optionsOf(MethodCall call) =>
      (call.arguments as Map<Object?, Object?>)['options']!
          as Map<Object?, Object?>;
}

/// An old storage that records its calls and can fail them.
class RecordingStorage implements AuthStorage {
  final InMemoryAuthStorage _inner = InMemoryAuthStorage();
  final List<String> calls = <String>[];
  Exception? readFailure;
  Exception? writeFailure;

  @override
  FutureOr<String?> read(String key) {
    calls.add('read $key');
    final Exception? failure = readFailure;
    if (failure != null) {
      throw failure;
    }
    return _inner.read(key);
  }

  @override
  FutureOr<void> write(String key, String? value) {
    calls.add('write $key ${value ?? 'null'}');
    final Exception? failure = writeFailure;
    if (failure != null) {
      throw failure;
    }
    _inner.write(key, value);
  }

  String? peek(String key) => _inner.read(key);
  void seed(String key, String value) => _inner.write(key, value);
}

/// The shape of `WindowsException` of `package:win32` 6.x, which the Windows
/// implementation (Dart FFI, not the method channel) throws: the same
/// `toString()`. The class itself needs `dart:ffi`, so the tests use this.
class WindowsException implements Exception {
  const WindowsException(this.hr, {this.message = ''});

  final int hr;
  final String message;

  @override
  String toString() {
    final String code = '0x${hr.toRadixString(16).toUpperCase()}';
    return message.isEmpty
        ? 'WindowsException HRESULT($code)'
        : 'WindowsException HRESULT($code): $message';
  }
}

const int _accessDenied = 0x80070005;

const String _key = 'firebase_auth_providers_dart:api-key:[DEFAULT]';
const String _session = '{"version":2,"refreshToken":"r"}';
// The default namespace under flutter_test, whose platform is Android.
const String _stored = 'firebase_auth_secure_storage:sandbox/$_key';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeSecureStore store;
  late List<SecureAuthStorageMigrationIssue> issues;

  setUp(() {
    store = FakeSecureStore();
    issues = <SecureAuthStorageMigrationIssue>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, store.handle);
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  SecureAuthStorage storage({AuthStorage? migrateFrom, String? namespace}) =>
      SecureAuthStorage(
        namespace: namespace,
        migrateFrom: migrateFrom,
        onMigrationIssue: issues.add,
      );

  group('read, write, delete', () {
    test('write stores the value under the namespaced key', () async {
      await storage().write(_key, _session);
      expect(store.values, <String, String>{_stored: _session});
    });

    test('read returns the stored value, or null', () async {
      final SecureAuthStorage s = storage();
      expect(await s.read(_key), isNull);
      store.values[_stored] = _session;
      expect(await s.read(_key), _session);
    });

    test('write of null deletes the value', () async {
      store.values[_stored] = _session;
      await storage().write(_key, null);
      expect(store.values, isEmpty);
      expect(store.methods, <String>['delete']);
    });

    test('a value stored without the namespace is not read', () async {
      store.values[_key] = 'the app own value';
      expect(await storage().read(_key), isNull);
    });
  });

  group('namespace', () {
    test('two namespaces keep separate sessions', () async {
      final SecureAuthStorage a = storage(namespace: 'com.example.a');
      final SecureAuthStorage b = storage(namespace: 'com.example.b');
      await a.write(_key, 'session a');
      await b.write(_key, 'session b');
      expect(await a.read(_key), 'session a');
      expect(await b.read(_key), 'session b');
      expect(store.values.keys, <String>[
        'com.example.a/$_key',
        'com.example.b/$_key',
      ]);
      expect(a.storageKeyFor('k'), 'com.example.a/k');
    });

    test('an empty namespace is rejected', () {
      expect(() => SecureAuthStorage(namespace: ''), throwsArgumentError);
    });

    test('desktop default: a hash of the executable path, stable', () {
      for (final String platform in <String>['macOS', 'linux', 'windows']) {
        final String a = SecureAuthStorage.namespaceFor(
          platform: platform,
          executable: '/Applications/A.app/Contents/MacOS/A',
        );
        expect(
          a,
          matches(RegExp(r'^firebase_auth_secure_storage:[0-9a-f]{16}$')),
        );
        expect(a, isNot(contains('Applications')));
        expect(
          SecureAuthStorage.namespaceFor(
            platform: platform,
            executable: '/Applications/A.app/Contents/MacOS/A',
          ),
          a,
        );
        expect(
          SecureAuthStorage.namespaceFor(
            platform: platform,
            executable: '/Applications/B.app/Contents/MacOS/B',
          ),
          isNot(a),
        );
      }
    });

    test('mobile and web default: the sandbox of the platform', () {
      for (final String platform in <String>['android', 'iOS']) {
        expect(
          SecureAuthStorage.namespaceFor(platform: platform, executable: '/x'),
          'firebase_auth_secure_storage:sandbox',
        );
      }
      expect(
        SecureAuthStorage.namespaceFor(platform: 'web'),
        'firebase_auth_secure_storage:web',
      );
    });

    test('two desktop programs do not see each other\'s sessions', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final SecureAuthStorage a = storage(
        namespace: SecureAuthStorage.namespaceFor(
          platform: 'linux',
          executable: '/opt/a/a',
        ),
      );
      final SecureAuthStorage b = storage(
        namespace: SecureAuthStorage.namespaceFor(
          platform: 'linux',
          executable: '/opt/b/b',
        ),
      );
      await a.write(_key, 'session a');
      expect(await b.read(_key), isNull);
      await b.write(_key, null);
      expect(await a.read(_key), 'session a');
    });

    test('the default is the one of the running program', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final SecureAuthStorage s = SecureAuthStorage();
      await s.write(_key, _session);
      final String expected = SecureAuthStorage.namespaceFor(
        platform: 'linux',
        executable: Platform.resolvedExecutable,
      );
      expect(s.namespace, expected);
      expect(store.values.keys.single, '$expected/$_key');
    });

    test('the constructor calls no plugin; the first use does', () async {
      final SecureAuthStorage s = SecureAuthStorage(
        migrateFrom: RecordingStorage(),
      );
      expect(store.calls, isEmpty);
      await s.read(_key);
      expect(store.calls, isNotEmpty);
    });
  });

  group('platform options', () {
    test('macOS: the data-protection keychain, a fixed service', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await storage(namespace: 'ns').write(_key, _session);
      final Map<Object?, Object?> options = store.optionsOf(store.calls.single);
      expect(options['usesDataProtectionKeychain'], 'true');
      expect(options['accountName'], SecureAuthStorage.keychainService);
      expect(options.containsKey('groupId'), isFalse);
    });

    test('iOS: a fixed service', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await storage().read(_key);
      final Map<Object?, Object?> options = store.optionsOf(store.calls.single);
      expect(options['accountName'], SecureAuthStorage.keychainService);
    });

    test('Android: the plugin defaults', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await storage().read(_key);
      expect(
        store.optionsOf(store.calls.single),
        const AndroidOptions().toMap(),
      );
    });

    test('a storage passed in is used as it is', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final SecureAuthStorage s = SecureAuthStorage(
        storage: const FlutterSecureStorage(
          mOptions: MacOsOptions(usesDataProtectionKeychain: false),
        ),
      );
      await s.read(_key);
      final Map<Object?, Object?> options = store.optionsOf(store.calls.single);
      expect(options['usesDataProtectionKeychain'], 'false');
    });
  });

  group('the secure store is not available', () {
    test('Linux without a Secret Service: platform, cause, remedy', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      store.failures['read'] = PlatformException(
        code: 'Libsecret error',
        message: 'secret_service_get_sync: Cannot autolaunch D-Bus',
      );
      final Object error = await _errorOf(storage().read(_key));
      expect(error, isA<SecureAuthStorageException>());
      final SecureAuthStorageException e = error as SecureAuthStorageException;
      expect(e.platform, 'linux');
      expect(e.operation, 'read');
      expect(e.code, 'Libsecret error');
      expect(e.cause, isA<PlatformException>());
      expect(e.toString(), contains('Cannot autolaunch D-Bus'));
      expect(e.toString(), contains('gnome-keyring-daemon --unlock'));
      expect(e.toString(), contains('FileAuthStorage'));
    });

    test('Linux with a locked keyring', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      store.failures['write'] = PlatformException(code: 'KeyringLocked');
      final Object error = await _errorOf(storage().write(_key, _session));
      final SecureAuthStorageException e = error as SecureAuthStorageException;
      expect(e.operation, 'write');
      expect(e.remedy, contains('unlock the login keyring'));
    });

    test('a failed delete names the operation', () async {
      store.failures['delete'] = PlatformException(code: 'x');
      final Object error = await _errorOf(storage().write(_key, null));
      expect((error as SecureAuthStorageException).operation, 'delete');
    });

    test('macOS without the entitlement', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      store.failures['write'] = PlatformException(
        code: 'Unexpected security result code',
        message: 'A required entitlement isn\'t present.',
        details: -34018,
      );
      final Object error = await _errorOf(storage().write(_key, _session));
      final SecureAuthStorageException e = error as SecureAuthStorageException;
      expect(e.platform, 'macOS');
      expect(e.remedy, contains('keychain-access-groups'));
      expect(e.remedy, contains('usesDataProtectionKeychain: false'));
      expect(e.toString(), contains('status -34018'));
    });

    test('iOS while the device is locked', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      store.failures['read'] = PlatformException(
        code: 'Unexpected security result code',
        details: -25308,
      );
      final Object error = await _errorOf(storage().read(_key));
      expect(
        (error as SecureAuthStorageException).remedy,
        contains('first_unlock'),
      );
    });

    test('Android Keystore failure points at Auto Backup', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      store.failures['read'] = PlatformException(
        code: 'Exception encountered',
        message: 'Failed to unwrap key',
      );
      final Object error = await _errorOf(storage().read(_key));
      expect(
        (error as SecureAuthStorageException).remedy,
        contains('allowBackup'),
      );
    });

    test('Windows without an interactive logon (SSH, a service)', () {
      final SecureAuthStorageException e = SecureAuthStorageException(
        platform: 'windows',
        operation: 'write',
        cause: const WindowsException(
          _accessDenied,
          message: 'Failure on CryptProtectData()',
        ),
      );
      expect(e.isUnavailable, isTrue);
      expect(e.remedy, contains('interactive logon'));
      expect(e.remedy, contains('SSH session or a Windows service'));
      expect(e.remedy, contains('not a permission problem of a directory'));
      expect(e.toString(), contains('HRESULT(0x80070005)'));
    });

    test('other Windows failures point at the DPAPI file', () {
      final SecureAuthStorageException e = SecureAuthStorageException(
        platform: 'windows',
        operation: 'read',
        cause: const WindowsException(
          0x8009000B,
          message: 'Failure on CryptUnprotectData()',
        ),
      );
      expect(e.isUnavailable, isFalse);
      expect(e.remedy, contains('flutter_secure_storage.dat'));
      expect(e.remedy, isNot(contains('interactive logon')));
    });

    test('the plugin is not registered', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null);
      final Object error = await _errorOf(storage().read(_key));
      final SecureAuthStorageException e = error as SecureAuthStorageException;
      expect(e.cause, isA<MissingPluginException>());
      expect(e.code, isNull);
      expect(e.remedy, contains('not registered'));
    });

    test('nothing is written to the old storage instead', () async {
      final RecordingStorage old = RecordingStorage();
      store.failures['write'] = PlatformException(code: 'KeyringLocked');
      await _errorOf(storage(migrateFrom: old).write(_key, _session));
      expect(old.calls, isEmpty);
    });

    test('a failed operation does not block the next one', () async {
      final SecureAuthStorage s = storage();
      store.failures['write'] = PlatformException(code: 'x');
      await _errorOf(s.write(_key, _session));
      store.failures.clear();
      await s.write(_key, _session);
      expect(await s.read(_key), _session);
    });
  });

  group('isUnavailable', () {
    SecureAuthStorageException error(String platform, Exception cause) =>
        SecureAuthStorageException(
          platform: platform,
          operation: 'read',
          cause: cause,
        );
    PlatformException apple(int status) => PlatformException(
      code: 'Unexpected security result code',
      details: status,
    );

    test('the store as a whole is missing or locked', () {
      final List<SecureAuthStorageException> unavailable =
          <SecureAuthStorageException>[
            error('android', MissingPluginException('read')),
            error('windows', MissingPluginException('read')),
            error('linux', PlatformException(code: 'KeyringLocked')),
            error(
              'linux',
              PlatformException(
                code: 'Libsecret error',
                message: 'secret_service_get_sync: Cannot autolaunch D-Bus',
              ),
            ),
            error('macOS', apple(-34018)),
            error('iOS', apple(-34018)),
            error('macOS', apple(-25291)),
            error('macOS', apple(-25307)),
            error(
              'windows',
              const WindowsException(
                _accessDenied,
                message: 'Failure on CryptProtectData()',
              ),
            ),
            error(
              'windows',
              const WindowsException(
                _accessDenied,
                message: 'Failure on CryptUnprotectData()',
              ),
            ),
          ];
      for (final SecureAuthStorageException e in unavailable) {
        expect(e.isUnavailable, isTrue, reason: '$e');
      }
    });

    test('a failure that may concern a stored value is not', () {
      final List<SecureAuthStorageException> available =
          <SecureAuthStorageException>[
            error('linux', PlatformException(code: 'StorageError')),
            error(
              'linux',
              PlatformException(
                code: 'Libsecret error',
                message: 'secret_password_lookupv_sync: timeout',
              ),
            ),
            error('linux', PlatformException(code: 'Libsecret error')),
            error('iOS', apple(-25308)),
            error('macOS', apple(-25300)),
            error(
              'android',
              PlatformException(
                code: 'Exception encountered',
                message: 'Failed to unwrap key',
              ),
            ),
            error('windows', PlatformException(code: 'KeyringLocked')),
            // Another DPAPI error: about a value, not the store.
            error(
              'windows',
              const WindowsException(
                0x8009000B,
                message: 'Failure on CryptUnprotectData()',
              ),
            ),
            error(
              'windows',
              const WindowsException(
                _accessDenied,
                message: 'Failure on LocalFree()',
              ),
            ),
            error(
              'windows',
              const WindowsException(
                0x8007000E,
                message: 'Failure on CryptProtectData()',
              ),
            ),
            error(
              'linux',
              const WindowsException(
                _accessDenied,
                message: 'Failure on CryptProtectData()',
              ),
            ),
            error('linux', Exception('not a platform exception')),
          ];
      for (final SecureAuthStorageException e in available) {
        expect(e.isUnavailable, isFalse, reason: '$e');
      }
    });
  });

  group('migration', () {
    test('moves the session: write, read back, then delete the old', () async {
      final RecordingStorage old = RecordingStorage()..seed(_key, _session);
      final SecureAuthStorage s = storage(migrateFrom: old);
      expect(await s.read(_key), _session);
      expect(store.values, <String, String>{_stored: _session});
      expect(old.peek(_key), isNull);
      expect(store.methods, <String>['read', 'write', 'read']);
      expect(old.calls, <String>['read $_key', 'write $_key null']);
      expect(issues, isEmpty);
    });

    test('the old storage is not read when the secure store has it', () async {
      final RecordingStorage old = RecordingStorage()..seed(_key, 'older');
      store.values[_stored] = _session;
      expect(await storage(migrateFrom: old).read(_key), _session);
      expect(old.calls, isEmpty);
      expect(old.peek(_key), 'older');
    });

    test('nothing in either storage: null, nothing written', () async {
      final RecordingStorage old = RecordingStorage();
      expect(await storage(migrateFrom: old).read(_key), isNull);
      expect(store.methods, <String>['read']);
      expect(old.calls, <String>['read $_key']);
    });

    test('without migrateFrom nothing else is read', () async {
      expect(await storage().read(_key), isNull);
      expect(store.methods, <String>['read']);
    });

    test('the secure write fails: rethrown, old kept', () async {
      final RecordingStorage old = RecordingStorage()..seed(_key, _session);
      store.failures['write'] = PlatformException(code: 'KeyringLocked');
      final Object error = await _errorOf(storage(migrateFrom: old).read(_key));
      expect(error, isA<SecureAuthStorageException>());
      expect((error as SecureAuthStorageException).operation, 'write');
      expect(old.peek(_key), _session);
      expect(old.calls, <String>['read $_key']);
    });

    test('the read-back differs: new copy deleted, old kept, thrown', () async {
      final RecordingStorage old = RecordingStorage()..seed(_key, _session);
      store.readOverride[_stored] = 'truncated';
      final Object error = await _errorOf(storage(migrateFrom: old).read(_key));
      expect(error, isA<SecureAuthStorageMigrationException>());
      expect(
        (error as SecureAuthStorageMigrationException).cleanupError,
        isNull,
      );
      expect(store.values, isEmpty);
      expect(old.peek(_key), _session);
      expect(old.calls, <String>['read $_key']);
    });

    test(
      'the read-back differs and the cleanup fails: both reported',
      () async {
        final RecordingStorage old = RecordingStorage()..seed(_key, _session);
        store.readOverride[_stored] = 'truncated';
        store.failures['delete'] = PlatformException(code: 'x');
        final Object error = await _errorOf(
          storage(migrateFrom: old).read(_key),
        );
        final SecureAuthStorageMigrationException e =
            error as SecureAuthStorageMigrationException;
        expect(e.cleanupError, isA<SecureAuthStorageException>());
        expect(e.toString(), contains('could not be deleted'));
        expect(old.peek(_key), _session);
      },
    );

    test('the read-back fails: rethrown, old kept', () async {
      final RecordingStorage old = RecordingStorage()..seed(_key, _session);
      final SecureAuthStorage s = storage(migrateFrom: old);
      var reads = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (MethodCall call) {
            if (call.method == 'read' && ++reads == 2) {
              throw PlatformException(code: 'x');
            }
            return store.handle(call);
          });
      final Object error = await _errorOf(s.read(_key));
      expect(error, isA<SecureAuthStorageException>());
      expect(old.peek(_key), _session);
    });

    test('the old storage cannot be read: null, reported', () async {
      final RecordingStorage old = RecordingStorage()..seed(_key, _session);
      old.readFailure = const FormatException('permission denied');
      expect(await storage(migrateFrom: old).read(_key), isNull);
      expect(store.values, isEmpty);
      expect(issues.single.step, MigrationStep.readOld);
      expect(issues.single.key, _key);
      expect(issues.single.toString(), contains('permission denied'));
    });

    test('the old delete fails: value returned, reported', () async {
      final RecordingStorage old = RecordingStorage()..seed(_key, _session);
      old.writeFailure = const FormatException('read-only');
      expect(await storage(migrateFrom: old).read(_key), _session);
      expect(store.values, <String, String>{_stored: _session});
      expect(old.peek(_key), _session);
      expect(issues.single.step, MigrationStep.deleteOld);
      expect(issues.single.toString(), contains('a copy of it remains'));
    });

    test('sign-out deletes the key from the old storage too', () async {
      final RecordingStorage old = RecordingStorage()..seed(_key, _session);
      store.values[_stored] = _session;
      await storage(migrateFrom: old).write(_key, null);
      expect(store.values, isEmpty);
      expect(old.peek(_key), isNull);
    });

    test('sign-in does not touch the old storage', () async {
      final RecordingStorage old = RecordingStorage()..seed(_key, 'older');
      await storage(migrateFrom: old).write(_key, _session);
      expect(old.calls, isEmpty);
    });

    test('sign-out with a failing old storage completes, reported', () async {
      final RecordingStorage old = RecordingStorage()..seed(_key, _session);
      old.writeFailure = const FormatException('read-only');
      await storage(migrateFrom: old).write(_key, null);
      expect(issues.single.step, MigrationStep.deleteOld);
    });

    test('a write queued behind a move is not overwritten by it', () async {
      final RecordingStorage old = RecordingStorage()..seed(_key, 'older');
      final SecureAuthStorage s = storage(migrateFrom: old);
      final Future<String?> read = s.read(_key);
      final Future<void> write = s.write(_key, _session);
      expect(await read, 'older');
      await write;
      expect(store.values[_stored], _session);
    });

    test('issues are printed by default', () async {
      final List<String?> printed = <String?>[];
      final DebugPrintCallback saved = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) => printed.add(message);
      addTearDown(() => debugPrint = saved);
      final RecordingStorage old = RecordingStorage()
        ..readFailure = const FormatException('boom');
      await SecureAuthStorage(migrateFrom: old).read(_key);
      expect(
        printed.single,
        startsWith('firebase_auth_secure_storage_flutter:'),
      );
      expect(printed.single, contains('boom'));
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
