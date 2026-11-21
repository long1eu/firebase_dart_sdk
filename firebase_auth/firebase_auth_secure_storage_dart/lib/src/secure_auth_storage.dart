import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart'
    show AuthStorage;
import 'package:firebase_auth_secure_storage_dart/src/exceptions.dart';
import 'package:firebase_auth_secure_storage_dart/src/secret_store.dart';

/// Receives the failed migration steps that did not fail the operation.
typedef MigrationIssueHandler =
    void Function(SecureAuthStorageMigrationIssue issue);

/// An `AuthStorage` in the secure store of the system, for command line
/// tools and servers: the login keychain on macOS, the Secret Service
/// (libsecret) on Linux, files encrypted with DPAPI on Windows. See
/// [SecretStore.platform].
///
/// Each value is stored under `<namespace>/<key>` ([storageKeyFor]). The key
/// that `FirebaseUserAuth` passes already names the project (its API key),
/// so one instance can serve every app of the program. The namespace names
/// the program: the secure store is shared by every program of the user, and
/// without it two programs on this library would read and overwrite each
/// other's sessions. See [defaultNamespace] for what it is made of.
///
/// The constructor does no I/O: the namespace is worked out, and the store
/// loaded and first used, at the first [read] or [write]. A store that is
/// missing or locked fails that call with a [SecureAuthStorageException];
/// [isAvailable] asks the store before the first session is read.
///
/// With [migrateFrom], a read of a key that the secure store does not have
/// moves the session from that storage: it is read there, written to the
/// secure store, read back and compared, and only then deleted there. A
/// write of null (a sign-out) deletes the key from [migrateFrom] too, so that
/// a session the move never reached cannot come back later. Nothing is read
/// from a storage that was not passed.
///
/// Failures:
///
/// * Every exception of the store becomes a [SecureAuthStorageException]
///   that names the platform and the remedy. The value is never written
///   anywhere else instead.
/// * The store fails while a session is moved: the exception is thrown, and
///   [migrateFrom] is left as it was.
/// * The value read back differs: the copy in the store is deleted,
///   [migrateFrom] is left as it was, and a
///   [SecureAuthStorageMigrationException] is thrown.
/// * [migrateFrom] cannot be read: the read returns null (the user signs in
///   again), and `onMigrationIssue` gets [MigrationStep.readOld].
/// * [migrateFrom] cannot delete the key: the read returns the value (or the
///   sign-out completes), and `onMigrationIssue` gets
///   [MigrationStep.deleteOld]: a copy remains there.
///
/// The operations of one instance run one at a time, in order, so that a
/// move cannot overwrite a session written after it started. The calls into
/// the store are synchronous and block the isolate while the store answers.
/// No stored value is ever printed or put in an exception.
///
/// ```dart
/// final FirebaseUserAuth auth = FirebaseUserAuth(
///   apiKey: apiKey,
///   storage: SecureAuthStorage(namespace: 'com.example.tool'),
/// );
/// await auth.restore();
/// ```
class SecureAuthStorage implements AuthStorage {
  /// A storage in [store], under [namespace].
  ///
  /// * [namespace] prefixes every key; by default [defaultNamespace]. It must
  ///   not be empty. Pass a fixed value (the program's ID) for a program run
  ///   with `dart run` or `dart <file>.dart`, whose executable is the Dart
  ///   VM, and for a program whose path changes between versions.
  /// * [store] is the secure store; by default [SecretStore.platform].
  /// * [migrateFrom] is the storage that held the sessions before, for
  ///   example a `FileAuthStorage`.
  /// * [onMigrationIssue] receives the failed migration steps that did not
  ///   fail the operation; by default they are written to standard error.
  SecureAuthStorage({
    String? namespace,
    SecretStore? store,
    this.migrateFrom,
    MigrationIssueHandler? onMigrationIssue,
  }) : _namespace = namespace,
       store = store ?? SecretStore.platform(),
       _onMigrationIssue = onMigrationIssue ?? _printIssue {
    if (namespace != null && namespace.isEmpty) {
      throw ArgumentError.value(namespace, 'namespace', 'must not be empty');
    }
  }

  /// The prefix of the default namespace, and the service of the items in
  /// [SecretStore.platform]: `firebase_auth_secure_storage`.
  static const String keychainService = SecretStore.defaultService;

  /// The key of the entry [isAvailable] writes, reads back and deletes.
  static const String probeKey = '.probe';

  /// The namespace of this program when none is given:
  /// `firebase_auth_secure_storage:<app>`, where `<app>` is the first 16
  /// hexadecimal digits of the SHA-256 of the absolute path of the running
  /// executable (`Platform.resolvedExecutable`), as in the Flutter package
  /// `firebase_auth_secure_storage_flutter` on desktop.
  ///
  /// Moving or renaming the program changes it (the users sign in again).
  /// Under `dart run` or `dart <file>.dart` the executable is the Dart VM, so
  /// every such program of the user gets the same namespace: pass a fixed
  /// one there.
  static String defaultNamespace() =>
      namespaceFor(executable: Platform.resolvedExecutable);

  /// The default namespace for the program at [executable].
  ///
  /// Keep in step with `SecureAuthStorage.namespaceFor` of
  /// `firebase_auth_secure_storage_flutter` (its desktop branch); the unit
  /// test group "stored layout (pinned)" holds the expected values.
  static String namespaceFor({required String executable}) {
    final String app = sha256
        .convert(utf8.encode(executable))
        .toString()
        .substring(0, 16);
    return '$keychainService:$app';
  }

  final String? _namespace;

  /// The prefix of every key in the store: the one given, or
  /// [defaultNamespace], worked out at first use.
  late final String namespace = _namespace ?? defaultNamespace();

  /// The secure store.
  final SecretStore store;

  /// Where the sessions were kept before; null when there is nothing to move.
  final AuthStorage? migrateFrom;

  final MigrationIssueHandler _onMigrationIssue;

  Future<void> _last = Future<void>.value();

  /// The key under which the session of [key] is kept in the store.
  String storageKeyFor(String key) => '$namespace/$key';

  @override
  Future<String?> read(String key) => _serial(() => _read(key));

  @override
  Future<void> write(String key, String? value) =>
      _serial(() => _write(key, value));

  /// Whether the store can be used in this run: writes a value under
  /// [probeKey] in this namespace, reads it back and deletes it.
  ///
  /// Returns false when a step fails with a [SecureAuthStorageException]
  /// whose `isUnavailable` is true (nothing is left behind then, unless the
  /// delete itself failed). Any other failure is thrown, as is a value that
  /// reads back different (a [SecureAuthStorageException] for `read`): the
  /// store is there but misbehaves, and a fallback would hide that.
  Future<bool> isAvailable() => _serial(() async {
    try {
      await _probe();
    } on SecureAuthStorageException catch (e) {
      if (e.isUnavailable) {
        return false;
      }
      rethrow;
    }
    return true;
  });

  Future<void> _probe() async {
    final String account = storageKeyFor(probeKey);
    final String value = 'probe ${DateTime.now().microsecondsSinceEpoch}';
    // A failed write stores nothing: there is nothing to delete then.
    await _secure('write', () => store.write(account, value));
    final String? back;
    try {
      back = await _secure('read', () => store.read(account));
    } on SecureAuthStorageException {
      await _deleteProbeAfterFailure(account);
      rethrow;
    }
    await _secure('delete', () => store.delete(account));
    if (back != value) {
      throw SecureAuthStorageException(
        platform: _platformName(),
        operation: 'read',
        cause: const SecretStoreError(
          function: 'SecureAuthStorage.isAvailable',
          message: 'the probe value read back differs from the one written',
        ),
      );
    }
  }

  /// Deletes the probe entry after its read failed. That failure is what the
  /// probe reports, so a failure here is not thrown over it.
  Future<void> _deleteProbeAfterFailure(String account) async {
    try {
      await store.delete(account);
    } on Exception {
      return;
    }
  }

  Future<T> _serial<T>(Future<T> Function() operation) {
    final Future<T> next = _last.then((_) => operation());
    _last = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<String?> _read(String key) async {
    final String? stored = await _secure(
      'read',
      () => store.read(storageKeyFor(key)),
    );
    final AuthStorage? old = migrateFrom;
    if (stored != null || old == null) {
      return stored;
    }
    return _migrate(old, key);
  }

  Future<void> _write(String key, String? value) async {
    final String account = storageKeyFor(key);
    if (value == null) {
      await _secure('delete', () => store.delete(account));
    } else {
      await _secure('write', () => store.write(account, value));
    }
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
    final String moved = value;
    final String account = storageKeyFor(key);
    await _secure('write', () => store.write(account, moved));
    final String? back = await _secure('read', () => store.read(account));
    if (back != value) {
      Object? cleanupError;
      try {
        await _secure('delete', () => store.delete(account));
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

  static String _platformName() =>
      Platform.isMacOS ? 'macOS' : Platform.operatingSystem;

  static void _printIssue(SecureAuthStorageMigrationIssue issue) {
    stderr.writeln('firebase_auth_secure_storage_dart: $issue');
  }
}
