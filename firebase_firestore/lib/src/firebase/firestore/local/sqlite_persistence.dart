// File created by
// Lung Razvan <long1eu>
// on 21/09/2018

import 'dart:async';

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_firestore/src/firebase/firestore/auth/user.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/local_serializer.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/mutation_queue.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/persistence.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/sqlite_lru_reference_delegate.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/sqlite_mutation_queue.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/sqlite_query_cache.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/sqlite_remote_document_cache.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/sqlite_schema.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/database_id.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/database.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/types.dart';
import 'package:meta/meta.dart';

/// A SQLite-backed instance of Persistence.
///
/// * In addition to implementations of the methods in the Persistence
/// interface, also contains helper routines that make dealing with SQLite much
/// more pleasant.
class SQLitePersistence extends Persistence {
  static const String tag = 'SQLitePersistence';

  final OpenDatabase openDatabase;
  final String databaseName;
  final LocalSerializer serializer;

  Database _db;

  @override
  bool started = false;

  @override
  SQLiteQueryCache queryCache;

  @override
  SQLiteRemoteDocumentCache remoteDocumentCache;

  @override
  SQLiteLruReferenceDelegate referenceDelegate;

  SQLitePersistence._(this.serializer, this.openDatabase, this.databaseName);

  static Future<SQLitePersistence> create(
      String persistenceKey,
      DatabaseId databaseId,
      LocalSerializer serializer,
      OpenDatabase openDatabase) async {
    final String databaseName = sDatabaseName(persistenceKey, databaseId);

    final SQLitePersistence persistence =
        SQLitePersistence._(serializer, openDatabase, databaseName);

    final SQLiteQueryCache queryCache =
        SQLiteQueryCache(persistence, serializer);
    final SQLiteRemoteDocumentCache remoteDocumentCache =
        SQLiteRemoteDocumentCache(persistence, serializer);
    final SQLiteLruReferenceDelegate referenceDelegate =
        SQLiteLruReferenceDelegate(persistence);

    return persistence
      ..queryCache = queryCache
      ..remoteDocumentCache = remoteDocumentCache
      ..referenceDelegate = referenceDelegate;
  }

  /// Creates the database name that is used to identify the database to be used
  /// with a Firestore instance. Note that this needs to stay stable across
  /// releases. The database is uniquely identified by a persistence key -
  /// usually the Firebase app name - and a DatabaseId (project and database).
  ///
  /// * Format is [firestore.{persistence-key}.{project-id}.{database-id}].
  @visibleForTesting
  static String sDatabaseName(String persistenceKey, DatabaseId databaseId) {
    return 'firestore.'
        '${Uri.encodeQueryComponent(persistenceKey)}.'
        '${Uri.encodeQueryComponent(databaseId.projectId)}.'
        '${Uri.encodeQueryComponent(databaseId.databaseId)}';
  }

  @override
  Future<void> start() async {
    Log.d(tag, 'Starting SQLite persistance');
    Assert.hardAssert(!started, 'SQLitePersistence double-started!');
    _db = await _openDb(databaseName, openDatabase);
    await queryCache.start();
    started = true;
    referenceDelegate.start(queryCache.highestListenSequenceNumber);
  }

  @override
  Future<void> shutdown() async {
    Log.d(tag, 'Shutingdown SQLite persistance');
    Assert.hardAssert(started, 'SQLitePersistence shutdown without start!');

    started = false;
    _db.close();
    _db = null;
  }

  @visibleForTesting
  Database get database => _db;

  @override
  MutationQueue getMutationQueue(User user) {
    return SQLiteMutationQueue(this, serializer, user);
  }

  @override
  Future<void> runTransaction(
      String action, Transaction<void> operation) async {
    Log.d(tag, 'Starting transaction: $action');
    try {
      referenceDelegate.onTransactionStarted();
      await _db.execute('BEGIN;');
      await operation();
      await _db.execute('COMMIT;');
      await referenceDelegate.onTransactionCommitted();
    } catch (e) {
      await _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  @override
  Future<T> runTransactionAndReturn<T>(
      String action, Transaction<T> operation) async {
    Log.d(tag, 'Starting transaction: $action');

    try {
      referenceDelegate.onTransactionStarted();
      await _db.execute('BEGIN;');
      final T result = await operation();
      await _db.execute('COMMIT;');
      await referenceDelegate.onTransactionCommitted();
      return result;
    } catch (e) {
      await _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  /// Execute the given non-query SQL statement.
  Future<void> execute(String statement, [List<Object> args]) {
    return _db.execute(statement, args);
  }

  Future<List<Map<String, dynamic>>> query(String statement,
      [List<dynamic> args]) {
    return _db.query(statement, args);
  }

  Future<int> delete(String statement, [List<dynamic> args]) {
    return _db.delete(statement, args);
  }

  /// Configures database connections just the way we like them, delegating to
  /// SQLiteSchema to actually do the work of migration.
  ///
  /// * The order of events when opening a new connection is as follows:
  ///
  /// <ol>
  /// <li>New connection
  /// <li>onConfigure
  /// <li>onCreate / onUpgrade (optional; if version already matches these aren't
  /// called)
  /// <li>onOpen
  /// </ol>
  ///
  /// * This attempts to obtain exclusive access to the database and attempts to
  /// do so as early as possible.
  static Future<Database> _openDb(
      String databaseName, OpenDatabase openDatabase) async {
    bool configured;

    /// Ensures that onConfigure has been called. This should be called first
    /// from all methods.
    void ensureConfigured(Database db) async {
      if (!configured) {
        configured = true;
        await db.query('PRAGMA locking_mode = EXCLUSIVE;');
      }
    }

    final Database db = await openDatabase(
      databaseName,
      version: SQLiteSchema.version,
      onConfigure: (Database db) async {
        configured = true;
        await db.query('PRAGMA locking_mode = EXCLUSIVE;');
      },
      onCreate: (Database db, int version) async {
        ensureConfigured(db);
        await SQLiteSchema(db).runMigrations(0);
      },
      onUpgrade: (Database db, int fromVersion, int toVersion) async {
        ensureConfigured(db);
        await SQLiteSchema(db).runMigrations(fromVersion);
      },
      onDowngrade: (Database db, int fromVersion, int toVersion) async {
        ensureConfigured(db);

        // For now, we can safely do nothing.
        //
        // The only case that's possible at this point would be to downgrade
        // from version 1 (present in our first released version) to 0
        // (uninstalled). Nobody would want us to just wipe the data so instead
        // we just keep it around in the hope that they'll upgrade again :-).
        //
        // Note that if you uninstall a Firestore-based app, the database goes
        // away completely. The downgrade-then-upgrade case can only happen in
        // very limited circumstances.
        //
        // We'll have to revisit this once we ship a migration past version 1,
        // but this will definitely be good enough for our initial launch.
      },
      onOpen: (Database db) async => ensureConfigured(db),
    );

    return db;
  }
}
