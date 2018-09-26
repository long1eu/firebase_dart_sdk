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
import 'package:firebase_firestore/src/firebase/firestore/util/types.dart';
import 'package:meta/meta.dart';
import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:sqflite/sqflite.dart' as sql show Transaction;

/// A SQLite-backed instance of Persistence.
///
/// * In addition to implementations of the methods in the Persistence
/// interface, also contains helper routines that make dealing with SQLite much
/// more pleasant.
class SQLitePersistence extends Persistence {
  static const String tag = 'SQLitePersistence';

  final _OpenHelper opener;
  final LocalSerializer serializer;

  Database _db;

  @override
  bool started;

  @override
  SQLiteQueryCache queryCache;

  @override
  SQLiteRemoteDocumentCache remoteDocumentCache;

  @override
  SQLiteLruReferenceDelegate referenceDelegate;

  SQLitePersistence(this.serializer, this.opener);

  static Future<SQLitePersistence> create(
    String persistenceKey,
    DatabaseId databaseId,
    LocalSerializer serializer,
  ) async {
    final String databaseName = _databaseName(persistenceKey, databaseId);
    final _OpenHelper opener = await _OpenHelper.open(databaseName);
    final SQLitePersistence persistence = SQLitePersistence(serializer, opener);

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
  static String _databaseName(String persistenceKey, DatabaseId databaseId) {
    return Uri.encodeFull(
        'firestore.$persistenceKey.${databaseId.projectId}.${databaseId.databaseId}');
  }

  @override
  Future<void> start() async {
    Assert.hardAssert(!started, 'SQLitePersistence double-started!');
    started = true;
    await queryCache.start(_db);
    referenceDelegate.start(queryCache.highestListenSequenceNumber);
  }

  @override
  Future<void> shutdown() async {
    Assert.hardAssert(started, 'SQLitePersistence shutdown without start!');
    started = false;
    await _db.close();
    _db = null;
  }

  @override
  MutationQueue getMutationQueue(User user) {
    return SQLiteMutationQueue(this, serializer, user);
  }

  @override
  Future<void> runTransaction(
      String action, Transaction<void> operation) async {
    Log.d(tag, 'Starting transaction: $action');
    referenceDelegate.onTransactionStarted();
    await _db.transaction((sql.Transaction tx) => operation(tx),
        exclusive: true);
    referenceDelegate.onTransactionCommitted();
  }

  @override
  Future<T> runTransactionAndReturn<T>(
      String action, Transaction<T> operation) {
    Log.d(tag, 'Starting transaction: $action');
    referenceDelegate.onTransactionStarted();
    return _db.transaction((sql.Transaction tx) => operation(tx),
        exclusive: true);
  }

  /// Execute the given non-query SQL statement.
  Future<void> execute(DatabaseExecutor tx, String sql,
      [List<Object> args]) async {
    return await tx.execute(sql, args);
  }

  Future<List<Map<String, dynamic>>> query(DatabaseExecutor tx, String sql,
      [List<dynamic> args]) {
    return tx.rawQuery(sql, args);
  }
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
/// * This OpenHelper attempts to obtain exclusive access to the database and
/// attempts to do so as early as possible.
class _OpenHelper {
  final Database db;

  const _OpenHelper(this.db);

  static Future<_OpenHelper> open(String databaseName) async {
    bool configured;

    /// Ensures that onConfigure has been called. This should be called first
    /// from all methods.
    void ensureConfigured(Database db) async {
      if (!configured) {
        configured = true;
        await db.execute('PRAGMA locking_mode = EXCLUSIVE;');
      }
    }

    final Database db = await openDatabase(
      '',
      version: SQLiteSchema.version,
      onConfigure: (Database db) async {
        configured = true;
        await db.execute('PRAGMA locking_mode = EXCLUSIVE;');
      },
      onCreate: (Database db, int version) async {
        ensureConfigured(db);
        SQLiteSchema(db).runMigrations(0);
      },
      onUpgrade: (Database db, int fromVersion, int toVersion) async {
        ensureConfigured(db);
        SQLiteSchema(db).runMigrations(fromVersion);
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
      onOpen: (Database db) => ensureConfigured(db),
    );

    return _OpenHelper(db);
  }
}
