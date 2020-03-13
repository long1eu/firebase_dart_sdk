// File created by
// Lung Razvan <long1eu>
// on 21/09/2018

import 'dart:async';

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/mutation_queue.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistence.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/sqlite_lru_reference_delegate.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/sqlite_mutation_queue.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/sqlite_query_cache.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/sqlite_remote_document_cache.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/sqlite_schema.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/database.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/types.dart';
import 'package:meta/meta.dart';

/// A SQLite-backed instance of Persistence.
///
/// In addition to implementations of the methods in the Persistence interface, also contains helper
/// routines that make dealing with SQLite much more pleasant.
class SQLitePersistence extends Persistence {
  SQLitePersistence._(this.serializer, this.openDatabase, this.databaseName);

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

  int get byteSize => _db.file.lengthSync();

  static Future<SQLitePersistence> create(
      String persistenceKey,
      DatabaseId databaseId,
      LocalSerializer serializer,
      OpenDatabase openDatabase,
      LruGarbageCollectorParams params) async {
    final String databaseName = sDatabaseName(persistenceKey, databaseId);

    final SQLitePersistence persistence =
        SQLitePersistence._(serializer, openDatabase, databaseName);

    final SQLiteQueryCache queryCache =
        SQLiteQueryCache(persistence, serializer);
    final SQLiteRemoteDocumentCache remoteDocumentCache =
        SQLiteRemoteDocumentCache(persistence, serializer);
    final SQLiteLruReferenceDelegate referenceDelegate =
        SQLiteLruReferenceDelegate(persistence, params);

    return persistence
      ..queryCache = queryCache
      ..remoteDocumentCache = remoteDocumentCache
      ..referenceDelegate = referenceDelegate;
  }

  /// Creates the database name that is used to identify the database to be used with a Firestore instance. Note that
  /// this needs to stay stable across releases. The database is uniquely identified by a persistence key - usually the
  /// Firebase app name - and a DatabaseId (project and database).
  ///
  /// Format is [firestore.{persistence-key}.{project-id}.{database-id}].
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
    hardAssert(!started, 'SQLitePersistence double-started!');
    _db = await _openDb(databaseName, openDatabase);
    await queryCache.start();
    started = true;
    referenceDelegate.start(queryCache.highestListenSequenceNumber);
  }

  @override
  Future<void> shutdown() async {
    Log.d(tag, 'Shutingdown SQLite persistance');
    hardAssert(started, 'SQLitePersistence shutdown without start!');

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

  /// Configures database connections just the way we like them, delegating to SQLiteSchema to actually do the work of
  /// migration.
  ///
  /// The order of events when opening a new connection is as follows:
  ///   * New connection
  ///   * onConfigure
  ///   * onCreate / onUpgrade (optional; if version already matches these aren't called)
  ///   * onOpen
  ///
  /// This attempts to obtain exclusive access to the database and attempts to do so as early as possible.
  static Future<Database> _openDb(
      String databaseName, OpenDatabase openDatabase) async {
    bool configured;

    /// Ensures that onConfigure has been called. This should be called first from all methods.
    FutureOr<void> ensureConfigured(Database db) async {
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
        // The only case that's possible at this point would be to downgrade from version 1 (present
        // in our first released version) to 0 (uninstalled). Nobody would want us to just wipe the
        // data so instead we just keep it around in the hope that they'll upgrade again :-).
        //
        // Note that if you uninstall a Firestore-based app, the database goes away completely. The
        // downgrade-then-upgrade case can only happen in very limited circumstances.
        //
        // We'll have to revisit this once we ship a migration past version 1, but this will
        // definitely be good enough for our initial launch.
      },
      onOpen: (Database db) async => ensureConfigured(db),
    );

    return db;
  }
}

/// Encapsulates a query whose parameter list is so long that it might exceed SQLite limit.
///
/// SQLite limits maximum number of host parameters to 999 (see https://www.sqlite.org/limits.html). This class wraps
/// most of the messy details of splitting a large query into several smaller ones.
///
/// The class is configured to contain a "template" for each subquery:
///   * head -- the beginning of the query, will be the same for each subquery
///   * tail -- the end of the query, also the same for each subquery
///
/// Then the host parameters will be inserted in-between head and tail; if there are too many arguments for a single
/// query, several subqueries will be issued. Each subquery which will have the following form:
///
/// [head][an auto-generated comma-separated list of '?' placeholders][_tail]
///
/// To use this class, keep calling [performNextSubquery], which will issue the next subquery, as long as
/// [hasMoreSubqueries] returns true. Note that if the parameter list is empty, not even a single query will be issued.
///
/// For example, imagine for demonstration purposes that the limit were 2, and the [LongQuery] was created like this:
///
/// ```dart
///   final List<String> args = <String>['foo', 'bar', 'baz', 'spam', 'eggs'];
///   final LongQuery longQuery = LongQuery(
///     db,
///     'SELECT name WHERE id in (',
///     args,
///     ')',
///   );
/// ```
///
/// Assuming limit of 2, this query will issue three subqueries:
///
/// ```dart
///   await longQuery.performNextSubquery(); // SELECT name WHERE id in (?, ?) [foo, bar]
///   await longQuery.performNextSubquery(); // SELECT name WHERE id in (?, ?) [baz, spam]
///   await longQuery.performNextSubquery(); // SELECT name WHERE id in (?) [eggs]
/// ```
class LongQuery {
  /// Creates a new [LongQuery] with parameters that describe a template for creating each subquery.
  ///
  /// If [argsHead] is provided, it should contain the parameters that will be reissued in each subquery, i.e.
  /// subqueries take the form:
  ///
  /// [_head][_argsHead][an auto-generated comma-separated list of '?' placeholders][_tail]
  LongQuery(this._db, this._head, List<dynamic> argsHead,
      List<dynamic> argsIter, this._tail)
      : _argsIter = argsIter,
        _argsHead = argsHead ?? <dynamic>[],
        _subqueriesPerformed = 0;

  final SQLitePersistence _db;

  // The non-changing beginning of each subquery.
  final String _head;

  // The non-changing end of each subquery.
  final String _tail;

  // Arguments that will be prepended in each subquery before the main argument list.
  final List<Object> _argsHead;

  int _subqueriesPerformed;

  final List<Object> _argsIter;

  // Limit for the number of host parameters beyond which a query will be split into several subqueries. Deliberately
  // set way below 999 as a safety measure because this class doesn't attempt to check for placeholders in the query
  // [head]; if it only relied on the number of placeholders it itself generates, in that situation it would still
  // exceed the SQLite limit.
  static const int _limit = 900;

  int j = 0;

  /// Whether [performNextSubquery] can be called.
  bool get hasMoreSubqueries => j < _argsIter.length;

  /// Performs the next subquery
  Future<List<Map<String, dynamic>>> performNextSubquery() async {
    ++_subqueriesPerformed;

    final List<Object> subqueryArgs = List<Object>.from(_argsHead);
    final StringBuffer placeholdersBuilder = StringBuffer();

    for (int i = 0;
        j < _argsIter.length && i < _limit - _argsHead.length;
        i++) {
      if (i > 0) {
        placeholdersBuilder.write(', ');
      }
      placeholdersBuilder.write('?');

      subqueryArgs.add(_argsIter[j]);
      j++;
    }

    return _db.query('$_head$placeholdersBuilder$_tail', subqueryArgs);
  }

  /// How many subqueries were performed.
  int get subqueriesPerformed => _subqueriesPerformed;
}
