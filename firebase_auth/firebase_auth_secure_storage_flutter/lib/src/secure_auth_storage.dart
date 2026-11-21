import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart'
    show AuthStorage;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'exceptions.dart';
import 'executable_stub.dart' if (dart.library.io) 'executable_io.dart';

/// Receives the failed migration steps that did not fail the operation.
typedef MigrationIssueHandler =
    void Function(SecureAuthStorageMigrationIssue issue);

/// An `AuthStorage` in the secure store of the platform, through
/// `flutter_secure_storage`: the Keychain on iOS and macOS, a Keystore-wrapped
/// key on Android, libsecret on Linux, DPAPI on Windows.
///
/// Each value is stored under `<namespace>/<key>` ([storageKeyFor]). The key
/// that `FirebaseUserAuth` passes already names the project (its API key) and,
/// in `firebase_auth_dart_platform`, the FlutterFire app name, so one instance
/// can serve every app of the program. The namespace names the program: on
/// desktop the secure store is shared by every program of the user, and
/// without it two programs on this library would read and overwrite each
/// other's sessions. See [defaultNamespace] for what it is made of.
///
/// The constructor does no I/O and calls no plugin: the namespace is worked
/// out, and the store first used, at the first [read] or [write]. A store that
/// is missing or locked fails that call with a [SecureAuthStorageException], so
/// a caller that uses this storage by default can catch it and choose another.
///
/// With [migrateFrom], a read of a key that the secure store does not have
/// moves the session from that storage: it is read there, written to the
/// secure store, read back and compared, and only then deleted there. A write
/// of null (a sign-out) deletes the key from [migrateFrom] too, so that a
/// session the move never reached cannot come back later. Nothing is read from
/// a storage that was not passed.
///
/// Failures:
///
/// * Every exception of the secure store becomes a
///   [SecureAuthStorageException] that names the platform and the remedy. The
///   value is never written anywhere else instead.
/// * The secure store fails while a session is moved: the exception is thrown,
///   and [migrateFrom] is left as it was.
/// * The value read back differs: the copy in the secure store is deleted,
///   [migrateFrom] is left as it was, and a
///   [SecureAuthStorageMigrationException] is thrown.
/// * [migrateFrom] cannot be read: the read returns null (the user signs in
///   again), and [onMigrationIssue] gets [MigrationStep.readOld].
/// * [migrateFrom] cannot delete the key: the read returns the value (or the
///   sign-out completes), and [onMigrationIssue] gets
///   [MigrationStep.deleteOld]: a copy remains there.
///
/// The operations of one instance run one at a time, in order, so that a
/// move cannot overwrite a session written after it started.
///
/// ```dart
/// // firebase_auth_dart_platform: one storage for every FlutterFire app.
/// final SecureAuthStorage storage = SecureAuthStorage();
/// FirebaseAuthDart.use(storageFor: (FirebaseApp app) => storage);
/// ```
class SecureAuthStorage implements AuthStorage {
  /// A storage in [storage], under [namespace].
  ///
  /// * [namespace] prefixes every key; by default [defaultNamespace]. It must
  ///   not be empty. Pass a fixed value (the application ID) when the
  ///   executable path of a desktop app changes between versions.
  /// * [storage] is the `flutter_secure_storage` instance; by default
  ///   [defaultSecureStorage].
  /// * [migrateFrom] is the storage that held the sessions before, for
  ///   example the `FileAuthStorage` at `defaultSessionFile()` of
  ///   `firebase_auth_dart_platform`.
  /// * [onMigrationIssue] receives the failed migration steps that did not
  ///   fail the operation; by default they are printed with [debugPrint].
  SecureAuthStorage({
    String? namespace,
    FlutterSecureStorage? storage,
    this.migrateFrom,
    MigrationIssueHandler? onMigrationIssue,
  }) : _namespace = namespace,
       storage = storage ?? defaultSecureStorage(),
       _onMigrationIssue = onMigrationIssue ?? _printIssue {
    if (namespace != null && namespace.isEmpty) {
      throw ArgumentError.value(namespace, 'namespace', 'must not be empty');
    }
  }

  /// The Keychain service (`kSecAttrService`) of the items on iOS and macOS
  /// in [defaultSecureStorage].
  static const String keychainService = 'firebase_auth_secure_storage';

  /// The namespace of this program when none is given:
  /// `firebase_auth_secure_storage:<app>`, where `<app>` is
  ///
  /// * macOS, Linux and Windows: the first 16 hexadecimal digits of the
  ///   SHA-256 of the absolute path of the running executable
  ///   (`Platform.resolvedExecutable`). Neither Flutter nor the plugin exposes
  ///   the bundle ID or application ID there without another plugin. Moving or
  ///   renaming the program changes it (the users sign in again), and so does
  ///   an installer that puts each version in its own directory (MSIX).
  /// * Android and iOS: `sandbox`. The operating system already keeps the
  ///   store of each app apart, and the executable path cannot serve: it is
  ///   the same for every Android app, and on iOS it changes at every update.
  /// * The web: `web` (the browser keeps each origin apart).
  ///
  /// Stable from one start to the next, never random, and the same for every
  /// instance in the program.
  static String defaultNamespace() =>
      namespaceFor(platform: _platformName(), executable: executablePath());

  /// The default namespace on [platform] (the name of a [TargetPlatform], or
  /// `web`) for the program at [executable].
  @visibleForTesting
  static String namespaceFor({required String platform, String? executable}) {
    final String app = switch (platform) {
      'macOS' || 'linux' || 'windows' =>
        sha256
            .convert(utf8.encode(executable ?? ''))
            .toString()
            .substring(0, 16),
      'web' => 'web',
      _ => 'sandbox',
    };
    return '$keychainService:$app';
  }

  /// The `flutter_secure_storage` instance used when none is given.
  ///
  /// The plugin's defaults, except on iOS and macOS, where [keychainService]
  /// is the Keychain service of the items, and macOS, where the
  /// data-protection keychain is selected explicitly
  /// (`usesDataProtectionKeychain: true`, also the plugin's default). That
  /// keychain needs the `keychain-access-groups` entitlement and so a signed
  /// app; see the README for unsigned builds. Creating it does no I/O.
  static FlutterSecureStorage defaultSecureStorage() =>
      const FlutterSecureStorage(
        iOptions: IOSOptions(accountName: keychainService),
        mOptions: MacOsOptions(
          accountName: keychainService,
          usesDataProtectionKeychain: true,
        ),
      );

  final String? _namespace;

  /// The prefix of every key in the secure store: the one given, or
  /// [defaultNamespace], worked out at first use.
  late final String namespace = _namespace ?? defaultNamespace();

  /// The secure store.
  final FlutterSecureStorage storage;

  /// Where the sessions were kept before; null when there is nothing to move.
  final AuthStorage? migrateFrom;

  final MigrationIssueHandler _onMigrationIssue;

  Future<void> _last = Future<void>.value();

  /// The key under which the session of [key] is kept in the secure store.
  String storageKeyFor(String key) => '$namespace/$key';

  @override
  Future<String?> read(String key) => _serial(() => _read(key));

  @override
  Future<void> write(String key, String? value) =>
      _serial(() => _write(key, value));

  Future<T> _serial<T>(Future<T> Function() operation) {
    final Future<T> next = _last.then((_) => operation());
    _last = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<String?> _read(String key) async {
    final String? stored = await _secure(
      'read',
      () => storage.read(key: storageKeyFor(key)),
    );
    final AuthStorage? old = migrateFrom;
    if (stored != null || old == null) {
      return stored;
    }
    return _migrate(old, key);
  }

  Future<void> _write(String key, String? value) async {
    await _secure(
      value == null ? 'delete' : 'write',
      () => storage.write(key: storageKeyFor(key), value: value),
    );
    final AuthStorage? old = migrateFrom;
    if (value == null && old != null) {
      await _deleteOld(old, key);
    }
  }

  Future<String?> _migrate(AuthStorage old, String key) async {
    final String? value;
    try {
      value = await old.read(key);
    } on Exception catch (e) {
      _onMigrationIssue(
        SecureAuthStorageMigrationIssue(
          key: key,
          step: MigrationStep.readOld,
          error: e,
        ),
      );
      return null;
    }
    if (value == null) {
      return null;
    }
    final String storageKey = storageKeyFor(key);
    await _secure('write', () => storage.write(key: storageKey, value: value));
    final String? back = await _secure(
      'read',
      () => storage.read(key: storageKey),
    );
    if (back != value) {
      Object? cleanupError;
      try {
        await _secure('delete', () => storage.delete(key: storageKey));
      } on SecureAuthStorageException catch (e) {
        cleanupError = e;
      }
      throw SecureAuthStorageMigrationException(
        key: key,
        cleanupError: cleanupError,
      );
    }
    await _deleteOld(old, key);
    return value;
  }

  Future<void> _deleteOld(AuthStorage old, String key) async {
    try {
      await old.write(key, null);
    } on Exception catch (e) {
      _onMigrationIssue(
        SecureAuthStorageMigrationIssue(
          key: key,
          step: MigrationStep.deleteOld,
          error: e,
        ),
      );
    }
  }

  static Future<T> _secure<T>(
    String operation,
    Future<T> Function() call,
  ) async {
    try {
      return await call();
    } on Exception catch (e) {
      throw SecureAuthStorageException(
        platform: _platformName(),
        operation: operation,
        cause: e,
      );
    }
  }

  static String _platformName() => kIsWeb ? 'web' : defaultTargetPlatform.name;

  static void _printIssue(SecureAuthStorageMigrationIssue issue) {
    debugPrint('firebase_auth_secure_storage_flutter: $issue');
  }
}
