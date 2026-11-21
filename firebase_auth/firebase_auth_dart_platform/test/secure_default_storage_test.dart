// The default storage of the sessions: the secure store, against a fake of the
// flutter_secure_storage plugin's method channel, with the session file (in a
// temporary directory) as the place it moves from and falls back to.
//
// On Android, iOS, macOS and Linux the plugin talks to native code over that
// channel, so the fake stands where the native side is. The Windows
// implementation is Dart (FFI): one DPAPI-encrypted map in
// flutter_secure_storage.dat, plus the legacy C++ Credential Manager path over
// the channel on every read and write. WindowsLikePlatform below reproduces
// that, with the map in memory and DPAPI's failure thrown in the shape of
// package:win32's WindowsException; DPAPI itself is not run.

import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_dart_platform/firebase_auth_dart_platform.dart';
import 'package:firebase_auth_dart_platform/src/secure_default_storage.dart';
import 'package:firebase_auth_dart_platform/src/storage.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart'
    show AuthStorage, FileAuthStorage;
import 'package:firebase_auth_secure_storage_flutter/firebase_auth_secure_storage_flutter.dart'
    show SecureAuthStorageException;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

const MethodChannel _channel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// The native side of the plugin: values by key, the calls it received, and
/// failures to inject (thrown at every call until removed).
class FakeSecureStore {
  final Map<String, String> values = <String, String>{};
  final List<String> calls = <String>[];

  /// Failures by method, for every key.
  final Map<String, Exception> failures = <String, Exception>{};

  /// Failures of a read of one session key (whatever the namespace).
  final Map<String, Exception> readFailures = <String, Exception>{};

  /// What a read of one session key returns instead of the stored value.
  final Map<String, String> readOverride = <String, String>{};

  Future<Object?> handle(MethodCall call) async {
    calls.add(call.method);
    final Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    final String key = args['key']! as String;
    final String sessionKey = key.substring(key.indexOf('/') + 1);
    final Exception? failure =
        failures[call.method] ??
        (call.method == 'read' ? readFailures[sessionKey] : null);
    if (failure != null) {
      throw failure;
    }
    switch (call.method) {
      case 'read':
        final String? stored = values[key];
        return stored == null ? null : readOverride[sessionKey] ?? stored;
      case 'write':
        values[key] = args['value']! as String;
        return null;
      case 'delete':
        values.remove(key);
        return null;
    }
    throw MissingPluginException(call.method);
  }

  /// The value stored for the session key [key], whatever the namespace.
  String? valueOf(String key) {
    for (final MapEntry<String, String> entry in values.entries) {
      if (entry.key.endsWith('/$key')) {
        return entry.value;
      }
    }
    return null;
  }
}

/// A storage that records the keys it was asked for.
class RecordingStorage implements AuthStorage {
  RecordingStorage(this._inner);

  final AuthStorage _inner;
  final List<String> calls = <String>[];

  @override
  FutureOr<String?> read(String key) {
    calls.add('read $key');
    return _inner.read(key);
  }

  @override
  FutureOr<void> write(String key, String? value) {
    calls.add('write $key');
    return _inner.write(key, value);
  }
}

/// The shape of `WindowsException` of `package:win32` 6.x (the same
/// `toString()`); the class itself needs `dart:ffi`.
class WindowsException implements Exception {
  const WindowsException(this.hr, this.message);

  final int hr;
  final String message;

  @override
  String toString() =>
      'WindowsException HRESULT(0x${hr.toRadixString(16).toUpperCase()}): '
      '$message';
}

/// Behaves like `FlutterSecureStorageWindows` of flutter_secure_storage_windows
/// 4.2.2: the values live in one map (the DPAPI file, [dat] here), saved whole
/// at every change; a read of a key the map lacks asks the legacy channel
/// (then deletes it there), and every read and write deletes the key there.
/// [protectFailure] is thrown where `CryptProtectData` fails, and
/// [unprotectFailure] where `CryptUnprotectData` fails on a non-empty file,
/// which the plugin then deletes ("Delete corrupt file").
class WindowsLikePlatform extends MethodChannelFlutterSecureStorage {
  final Map<String, String> dat = <String, String>{};
  Exception? protectFailure;
  Exception? unprotectFailure;

  Map<String, String> _load() {
    final Exception? failure = unprotectFailure;
    if (failure != null && dat.isNotEmpty) {
      dat.clear();
      throw failure;
    }
    return Map<String, String>.of(dat);
  }

  void _save(Map<String, String> map) {
    final Exception? failure = protectFailure;
    if (failure != null) {
      throw failure;
    }
    dat
      ..clear()
      ..addAll(map);
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    final Map<String, String> map = _load();
    String? result = map[key];
    if (result == null) {
      final String? legacy = await super.read(key: key, options: options);
      if (legacy != null) {
        result = map[key] = legacy;
        _save(map);
      }
    }
    await super.delete(key: key, options: options);
    return result;
  }

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    _save(_load()..[key] = value);
    await super.delete(key: key, options: options);
  }

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    final Map<String, String> map = _load();
    if (map.remove(key) != null) {
      _save(map);
    }
    await super.delete(key: key, options: options);
  }
}

const String _key = 'firebase_auth_providers_dart:api-key:[DEFAULT]';
const String _other = 'firebase_auth_providers_dart:api-key:second';
const String _session = '{"version":2,"refreshToken":"file"}';
const String _secureSession = '{"version":2,"refreshToken":"secure"}';

/// The calls of a probe that succeeds.
const List<String> _probeCalls = <String>['write', 'read', 'delete'];

PlatformException _keyringLocked() => PlatformException(code: 'KeyringLocked');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeSecureStore store;
  late Directory dir;
  late String sessionFile;
  late List<String> printed;
  late DebugPrintCallback savedDebugPrint;

  setUp(() {
    store = FakeSecureStore();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, store.handle);
    dir = Directory.systemTemp.createTempSync('secure_default_storage');
    sessionFile = '${dir.path}/app/firebase_auth_dart_platform/sessions.json';
    printed = <String>[];
    savedDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => printed.add('$message');
    resetFallbackAnnouncement();
  });

  tearDown(() {
    FlutterSecureStoragePlatform.instance = MethodChannelFlutterSecureStorage();
    debugPrint = savedDebugPrint;
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    dir.deleteSync(recursive: true);
  });

  Future<void> seedFile(String key, String value) =>
      FileAuthStorage(sessionFile).write(key, value);

  Future<String?> fileValue(String key) =>
      FileAuthStorage(sessionFile).read(key);

  void seedSecure(String key, String value) =>
      store.values['firebase_auth_secure_storage:sandbox/$key'] = value;

  group('the secure store is the default', () {
    test('defaultStorage is the secure default, one object, no I/O', () {
      expect(defaultStorage(), isA<SecureDefaultStorage>());
      expect(defaultStorage(), same(defaultStorage()));
      expect(store.calls, isEmpty);
    });

    test('a write goes to the secure store, not to the file', () async {
      final SecureDefaultStorage storage = secureDefaultStorage(sessionFile);
      await storage.write(_key, _session);
      expect(store.valueOf(_key), _session);
      expect(await storage.read(_key), _session);
      expect(File(sessionFile).existsSync(), isFalse);
      expect(storage.usesFallback, isFalse);
      expect(printed, isEmpty);
    });

    test(
      'without a file system nothing is read but the secure store',
      () async {
        final SecureDefaultStorage storage = secureDefaultStorage(null);
        expect(await storage.read(_key), isNull);
        expect(store.calls, <String>[..._probeCalls, 'read']);
      },
    );
  });

  group('migration from the session file', () {
    test('a session in the file moves to the secure store', () async {
      await seedFile(_key, _session);
      final SecureDefaultStorage storage = secureDefaultStorage(sessionFile);
      expect(await storage.read(_key), _session);
      expect(store.valueOf(_key), _session);
      // Read back and compared before the file lost it.
      expect(store.calls, <String>[..._probeCalls, 'read', 'write', 'read']);
      expect(File(sessionFile).existsSync(), isFalse);
    });

    test('when both hold a session, the secure one wins and the file is left '
        'alone', () async {
      await seedFile(_key, _session);
      seedSecure(_key, _secureSession);
      final SecureDefaultStorage storage = secureDefaultStorage(sessionFile);
      expect(await storage.read(_key), _secureSession);
      expect(store.valueOf(_key), _secureSession);
      expect(await fileValue(_key), _session);
    });
  });

  group('the probe', () {
    test('macOS without the entitlement: reads answer null, writes fail; the '
        'session in the file is restored, with one line', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      store.failures['write'] = PlatformException(
        code: 'Unexpected security result code',
        message: 'A required entitlement is not present.',
        details: -34018,
      );
      await seedFile(_key, _session);
      final SecureDefaultStorage storage = secureDefaultStorage(sessionFile);

      expect(await storage.read(_key), _session);
      expect(storage.usesFallback, isTrue);
      await storage.write(_key, _secureSession);
      expect(await fileValue(_key), _secureSession);
      expect(store.calls, <String>['write']);
      expect(store.values, isEmpty);
      expect(printed, hasLength(1));
      expect(printed.single, contains('-34018'));
      expect(printed.single, contains('kept in $sessionFile instead'));
    });

    test('a successful probe leaves no entry behind', () async {
      final SecureDefaultStorage storage = secureDefaultStorage(sessionFile);
      expect(await storage.read(_key), isNull);
      expect(store.calls, <String>[..._probeCalls, 'read']);
      expect(store.values, isEmpty);
      // The probe never touches the session file.
      expect(File(sessionFile).existsSync(), isFalse);
    });

    test('a read-back that fails as unavailable: the entry is deleted, and '
        'the run uses the file', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      store.readFailures[SecureDefaultStorage.probeKey] = _keyringLocked();
      await seedFile(_key, _session);
      final SecureDefaultStorage storage = secureDefaultStorage(sessionFile);
      expect(await storage.read(_key), _session);
      expect(storage.usesFallback, isTrue);
      expect(store.calls, <String>['write', 'read', 'delete']);
      expect(store.values, isEmpty);
      expect(printed, hasLength(1));
    });

    test('a read-back that differs: the entry is deleted and the error is '
        'thrown; the next operation probes again', () async {
      store.readOverride[SecureDefaultStorage.probeKey] = 'something else';
      final SecureDefaultStorage storage = secureDefaultStorage(sessionFile);
      await expectLater(
        storage.read(_key),
        throwsA(
          isA<SecureAuthStorageException>().having(
            (SecureAuthStorageException e) => '$e',
            'message',
            contains('probe value read back'),
          ),
        ),
      );
      expect(store.values, isEmpty);
      expect(storage.usesFallback, isFalse);
      expect(printed, isEmpty);

      store.readOverride.clear();
      store.calls.clear();
      await storage.write(_key, _secureSession);
      expect(store.calls, <String>[..._probeCalls, 'write']);
      expect(store.valueOf(_key), _secureSession);
    });

    test('a probe error that is not "unavailable" is thrown: no fallback, the '
        'entry deleted, the file not used', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      store.readFailures[SecureDefaultStorage.probeKey] = PlatformException(
        code: 'Libsecret error',
        message: 'secret_password_lookupv_sync: timeout',
      );
      await seedFile(_key, _session);
      final SecureDefaultStorage storage = secureDefaultStorage(sessionFile);
      await expectLater(
        storage.read(_key),
        throwsA(isA<SecureAuthStorageException>()),
      );
      expect(storage.usesFallback, isFalse);
      expect(store.values, isEmpty);
      expect(printed, isEmpty);
      expect(await fileValue(_key), _session);
    });

    test('callers that start while the probe runs wait for it: one probe, '
        'and the store when it succeeds', () async {
      seedSecure(_key, _secureSession);
      final SecureDefaultStorage storage = secureDefaultStorage(sessionFile);
      final List<String?> values = await Future.wait(<Future<String?>>[
        storage.read(_key),
        storage.read(_other),
      ]);
      expect(values, <String?>[_secureSession, null]);
      expect(store.calls.where((String c) => c == 'write'), hasLength(1));
      expect(store.calls.where((String c) => c == 'delete'), hasLength(1));
    });
  });

  group('Windows (DPAPI)', () {
    late WindowsLikePlatform windows;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      windows = WindowsLikePlatform();
      FlutterSecureStoragePlatform.instance = windows;
    });

    test(
      'without an interactive logon (SSH, a service) CryptProtectData is '
      'refused: the session in the file is restored, with one line',
      () async {
        windows.protectFailure = const WindowsException(
          0x80070005,
          'Failure on CryptProtectData()',
        );
        await seedFile(_key, _session);
        final SecureDefaultStorage storage = secureDefaultStorage(sessionFile);

        expect(await storage.read(_key), _session);
        expect(storage.usesFallback, isTrue);
        await storage.write(_key, _secureSession);
        expect(await fileValue(_key), _secureSession);
        expect(windows.dat, isEmpty);
        // The probe's write failed before the legacy path was reached.
        expect(store.calls, isEmpty);
        expect(printed, hasLength(1));
        expect(printed.single, contains('HRESULT(0x80070005)'));
        expect(printed.single, contains('interactive logon'));
        expect(printed.single, contains('kept in $sessionFile instead'));
      },
    );

    test(
      'without an interactive logon, a file of an earlier desktop session '
      'cannot be decrypted either: fallback, and the plugin has deleted it',
      () async {
        windows
          ..dat['firebase_auth_secure_storage:x/$_key'] = _secureSession
          ..protectFailure = const WindowsException(
            0x80070005,
            'Failure on CryptProtectData()',
          )
          ..unprotectFailure = const WindowsException(
            0x80070005,
            'Failure on CryptUnprotectData()',
          );
        await seedFile(_key, _session);
        final SecureDefaultStorage storage = secureDefaultStorage(sessionFile);
        expect(await storage.read(_key), _session);
        expect(storage.usesFallback, isTrue);
        expect(printed.single, contains('CryptUnprotectData'));
        expect(windows.dat, isEmpty);
      },
    );

    test(
      'another DPAPI failure of the probe is thrown, not a fallback',
      () async {
        windows.protectFailure = const WindowsException(
          0x8007000E,
          'Failure on CryptProtectData()',
        );
        final SecureDefaultStorage storage = secureDefaultStorage(sessionFile);
        await expectLater(
          storage.read(_key),
          throwsA(isA<SecureAuthStorageException>()),
        );
        expect(storage.usesFallback, isFalse);
        expect(printed, isEmpty);
      },
    );

    test('with an interactive logon the session goes to the DPAPI map, and '
        'the legacy channel is asked on every read and write', () async {
      await seedFile(_key, _session);
      final SecureDefaultStorage storage = secureDefaultStorage(sessionFile);

      expect(await storage.read(_key), _session);
      expect(storage.usesFallback, isFalse);
      expect(windows.dat.length, 1);
      expect(windows.dat.keys.single, endsWith('/$_key'));
      expect(windows.dat.values.single, _session);
      expect(File(sessionFile).existsSync(), isFalse);
      // Probe: write (delete legacy), read (delete legacy), delete (delete
      // legacy); the session: read (legacy read, delete), move (write,
      // delete), read back (delete).
      expect(store.calls, <String>[
        'delete',
        'delete',
        'delete',
        'read',
        'delete',
        'delete',
        'delete',
      ]);
      expect(printed, isEmpty);
    });
  });

  group('an unavailable secure store', () {
    test('reads and writes go to the file, with one line', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      store.failures['read'] = _keyringLocked();
      store.failures['write'] = _keyringLocked();
      await seedFile(_key, _session);
      final SecureDefaultStorage storage = secureDefaultStorage(sessionFile);

      expect(await storage.read(_key), _session);
      expect(storage.usesFallback, isTrue);
      await storage.write(_other, _secureSession);
      expect(await storage.read(_other), _secureSession);

      expect(await fileValue(_other), _secureSession);
      // The probe's write was the only call: nothing is copied into the
      // store afterwards.
      expect(store.calls, <String>['write']);
      expect(printed, hasLength(1));
      expect(printed.single, contains('secure store is unavailable'));
      expect(printed.single, contains('KeyringLocked'));
      expect(printed.single, contains('kept in $sessionFile instead'));
      expect(printed.single, isNot(contains('\n')));
    });

    test('no plugin (flutter test) falls back too', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null);
      await seedFile(_key, _session);
      final SecureDefaultStorage storage = secureDefaultStorage(sessionFile);
      expect(await storage.read(_key), _session);
      expect(printed.single, contains('MissingPluginException'));
    });

    test('without a file system the fallback is memory', () async {
      store.failures['read'] = MissingPluginException('read');
      final SecureDefaultStorage storage = secureDefaultStorage(null);
      expect(await storage.read(_key), isNull);
      await storage.write(_key, _session);
      expect(await storage.read(_key), _session);
      expect(printed.single, contains('in memory until the program ends'));
    });

    test('one line per process, not per storage or per call', () async {
      store.failures['read'] = MissingPluginException('read');
      final SecureDefaultStorage first = secureDefaultStorage(sessionFile);
      final SecureDefaultStorage second = secureDefaultStorage(sessionFile);
      await first.read(_key);
      await first.read(_other);
      await second.read(_key);
      expect(second.usesFallback, isTrue);
      expect(printed, hasLength(1));
    });

    test(
      'operations started before the first answer go to the same place',
      () async {
        store.failures['read'] = MissingPluginException('read');
        await seedFile(_other, _session);
        final SecureDefaultStorage storage = secureDefaultStorage(sessionFile);
        final List<String?> values = await Future.wait(<Future<String?>>[
          storage.read(_key),
          storage.read(_other),
        ]);
        expect(values, <String?>[null, _session]);
        // One probe (write, failed read, delete of the entry) for both.
        expect(store.calls, <String>['write', 'read', 'delete']);
        expect(store.values, isEmpty);
      },
    );

    test('a store unavailable at the next start: signed out on the file, and '
        'at the start after, the secure session wins', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      // A first run stored the session in the secure store.
      await secureDefaultStorage(sessionFile).write(_key, _secureSession);
      final String storedKey = store.values.keys.single;

      // The next run finds the keyring locked: no session, and a new sign-in
      // goes to the file.
      store.failures['read'] = _keyringLocked();
      final SecureDefaultStorage locked = secureDefaultStorage(sessionFile);
      expect(await locked.read(_key), isNull);
      await locked.write(_key, _session);
      expect(store.values, <String, String>{storedKey: _secureSession});
      expect(await fileValue(_key), _session);

      // The run after that reaches the store again.
      store.failures.clear();
      final SecureDefaultStorage unlocked = secureDefaultStorage(sessionFile);
      expect(await unlocked.read(_key), _secureSession);
      expect(await fileValue(_key), _session);
    });
  });

  group('errors that are not "unavailable" are thrown', () {
    final Map<String, (TargetPlatform, PlatformException)> errors =
        <String, (TargetPlatform, PlatformException)>{
          'Linux, a value that cannot be parsed': (
            TargetPlatform.linux,
            PlatformException(code: 'StorageError', message: 'parse error'),
          ),
          'iOS, a locked device': (
            TargetPlatform.iOS,
            PlatformException(
              code: 'Unexpected security result code',
              details: -25308,
            ),
          ),
          'Android, a key that cannot be unwrapped': (
            TargetPlatform.android,
            PlatformException(
              code: 'Exception encountered',
              message: 'Failed to unwrap key',
            ),
          ),
        };
    for (final MapEntry<String, (TargetPlatform, PlatformException)> entry
        in errors.entries) {
      test('${entry.key}: the read of a session throws, the file is not '
          'used', () async {
        debugDefaultTargetPlatformOverride = entry.value.$1;
        store.readFailures[_key] = entry.value.$2;
        await seedFile(_other, _session);
        final SecureDefaultStorage storage = secureDefaultStorage(sessionFile);
        await expectLater(
          storage.read(_key),
          throwsA(isA<SecureAuthStorageException>()),
        );
        expect(storage.usesFallback, isFalse);
        expect(printed, isEmpty);

        // The store stays the place of the sessions: no session in the file
        // replaces the stored one, and the next sign-in goes to the store,
        // even when the store then fails as if it were unavailable.
        store.readFailures.clear();
        store.failures['write'] = MissingPluginException('write');
        await expectLater(
          storage.write(_key, _secureSession),
          throwsA(isA<SecureAuthStorageException>()),
        );
        store.failures.clear();
        await storage.write(_key, _secureSession);
        expect(store.valueOf(_key), _secureSession);
        expect(await fileValue(_key), isNull);
      });
    }

    test('a store that becomes unavailable after it answered: the error is '
        'thrown, and FallbackStorage keeps the session in memory', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final SecureDefaultStorage storage = secureDefaultStorage(sessionFile);
      expect(await storage.read(_key), isNull);

      store.failures['write'] = _keyringLocked();
      await expectLater(
        storage.write(_key, _session),
        throwsA(isA<SecureAuthStorageException>()),
      );
      expect(storage.usesFallback, isFalse);

      final FallbackStorage app = FallbackStorage(storage);
      await app.write(_key, _session);
      expect(await app.read(_key), _session);
      expect(File(sessionFile).existsSync(), isFalse);
      expect(printed.single, contains('kept in memory until the program ends'));
    });

    test('FallbackStorage keeps the session in memory when the fallback file '
        'cannot be written', () async {
      store.failures['read'] = MissingPluginException('read');
      // A file where the directory of the session file should be.
      File('${dir.path}/app').writeAsStringSync('');
      final FallbackStorage app = FallbackStorage(
        secureDefaultStorage(sessionFile),
      );
      expect(await app.read(_key), isNull);
      await app.write(_key, _session);
      expect(await app.read(_key), _session);
      expect(printed, hasLength(2));
      expect(printed.last, contains('kept in memory until the program ends'));
    });
  });

  test(
    'storageFor overrides the default: the secure store is not used',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final RecordingStorage file = RecordingStorage(
        FileAuthStorage(sessionFile),
      );
      FirebaseAuthDart.use(
        storageFor: (FirebaseApp app) => file,
        useDartCore: true,
      );
      final FirebaseApp app = await Firebase.initializeApp(
        name: 'override',
        options: const FirebaseOptions(
          apiKey: 'api-key',
          appId: '1:1:web:1',
          messagingSenderId: '1',
          projectId: 'demo-unit',
        ),
      );
      expect(
        await FirebaseAuth.instanceFor(app: app).authStateChanges().first,
        isNull,
      );
      expect(file.calls, <String>[
        'read ${DartFirebaseAuth.storageKeyOf(app)}',
      ]);
      expect(store.calls, isEmpty);
    },
  );
}
