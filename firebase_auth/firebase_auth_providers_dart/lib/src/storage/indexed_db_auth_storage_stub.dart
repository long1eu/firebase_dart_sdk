// The parameters have the names and types of the web implementation, which uses them.
// ignore_for_file: avoid_unused_constructor_parameters

import 'dart:async';

import '../auth_storage.dart';
import 'indexed_db_types.dart';

/// An [AuthStorage] in an IndexedDB database of the origin (the JS SDK's `indexedDBLocalPersistence`). It needs a
/// browser: on the Dart VM the constructor throws an [UnsupportedError] and [isAvailable] returns false; use
/// `FileAuthStorage` there. See the documentation of the web implementation.
class IndexedDbAuthStorage implements AuthStorage {
  /// A storage in the IndexedDB database [databaseName]. Throws an [UnsupportedError] on this platform.
  IndexedDbAuthStorage({this.databaseName = defaultDatabaseName}) {
    throw UnsupportedError('IndexedDbAuthStorage needs a browser.');
  }

  /// The database used when none is given.
  static const String defaultDatabaseName = 'firebase_auth_providers_dart';

  /// The object store that holds the sessions, by key.
  static const String objectStoreName = 'sessions';

  /// The version the database is opened with.
  static const int databaseVersion = 1;

  /// The key under which [isAvailable] writes, reads back and deletes its probe value.
  static const String probeKey = '.availability-probe';

  /// The name of the IndexedDB database.
  final String databaseName;

  /// Whether IndexedDB can be used here: always false on this platform. Never throws.
  static Future<bool> isAvailable({
    String databaseName = defaultDatabaseName,
    Duration timeout = const Duration(seconds: 5),
  }) async => false;

  @override
  Future<String?> read(String key) => throw UnsupportedError('No browser');

  @override
  Future<void> write(String key, String? value) =>
      throw UnsupportedError('No browser');

  /// Closes the connection to the database.
  Future<void> close() => throw UnsupportedError('No browser');
}

/// The best persistent [AuthStorage] the browser offers: IndexedDB, else `localStorage`, else memory, decided once.
/// It needs a browser: on the Dart VM the constructor throws an [UnsupportedError]. See the documentation of the
/// web implementation.
class BestWebAuthStorage implements AuthStorage {
  /// A storage that chooses between IndexedDB, `localStorage` and memory. Throws an [UnsupportedError] on this
  /// platform.
  BestWebAuthStorage({
    String databaseName = IndexedDbAuthStorage.defaultDatabaseName,
    this.localStoragePrefix = '',
    void Function(String key, Object error)? onMigrationIssue,
    Future<bool> Function()? indexedDbAvailable,
    bool Function()? localStorageAvailable,
  }) {
    throw UnsupportedError('BestWebAuthStorage needs a browser.');
  }

  /// What goes before every key in `localStorage`.
  final String localStoragePrefix;

  /// Where the sessions are kept.
  Future<WebAuthStorageKind> get kind => throw UnsupportedError('No browser');

  @override
  Future<String?> read(String key) => throw UnsupportedError('No browser');

  @override
  Future<void> write(String key, String? value) =>
      throw UnsupportedError('No browser');
}
