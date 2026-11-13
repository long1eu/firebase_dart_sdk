// File created by
// Lung Razvan <long1eu>
// on 21/09/2018

library sqlite_persistence;

import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/bound.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/listent_sequence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/order_by.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/target.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/index/firestore_index_value_writer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/index/index_byte_encoder.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/index/index_entry.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/encoded_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_delegate.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/bundle_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/globals_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/document_overlay_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/index_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/mutation_queue.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/overlay_migration_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/query_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/reference_delegate.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/remote_document_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/stats_collector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_context.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/reference_set.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_bundle_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_globals_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_database_files.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_document_overlay_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_overlay_migration_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/stored_proto.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/no_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/target_index_matcher.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/unknown_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/database.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/logic_utils.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/types.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/admin/v1/index.dart'
    as admin;
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:collection/collection.dart';
import 'package:firebase_app_dart/internal.dart';
import 'package:meta/meta.dart';
import 'package:protobuf/protobuf.dart';
import 'package:semaphore/semaphore.dart';

part 'sqlite_client_metadata.dart';
part 'sqlite_index_manager.dart';
part 'sqlite_lru_reference_delegate.dart';
part 'sqlite_mutation_queue.dart';
part 'sqlite_query_cache.dart';
part 'sqlite_remote_document_cache.dart';
part 'sqlite_schema.dart';

/// A SQLite-backed instance of Persistence.
///
/// In addition to implementations of the methods in the Persistence interface, also contains helper
/// routines that make dealing with SQLite much more pleasant.
class SQLitePersistence extends Persistence {
  SQLitePersistence._(
    this.serializer,
    this.openDatabase,
    this.databaseName,
    StatsCollector statsCollector,
    String clientId,
    Clock clock,
    PrimaryLeaseMode leaseMode,
  ) : _statsCollector = statsCollector,
      // One lock per database (not one for the whole process): instances on different databases never wait on
      // each other, while two handles on the same file are serialized.
      _semaphore = GlobalSemaphore('persistence:$databaseName') {
    indexManager = SqliteIndexManager(this);
    clientMetadata = SQLiteClientMetadata._(this, clientId, clock, leaseMode);
  }

  /// The metadata of this client in the cache and its primary lease.
  late final SQLiteClientMetadata clientMetadata;

  /// Whether this client holds the primary lease of the cache (see [SQLiteClientMetadata]).
  bool get isPrimary => clientMetadata.isPrimary;

  /// The epoch of the cache when this client opened it. `clearPersistence` of another client that finds clients
  /// alive empties the cache in place and increments the epoch instead of deleting the file.
  int? _epoch;

  /// Set when the cache was cleared by another client: every transaction fails from then on.
  bool _clearedByOtherClient = false;

  /// Called (once) when this client notices that another client cleared the cache. The client terminates.
  void Function()? databaseClearedListener;

  /// The persistences of this isolate that have a database file open, by path. A client that clears a cache in place
  /// tells the others of its isolate at once (as IndexedDB tells the other connections of a deleted database with a
  /// `versionchange` event); clients in other isolates or processes notice the new epoch at their next transaction or
  /// metadata refresh.
  static final Map<String, Set<SQLitePersistence>> _openInIsolate =
      <String, Set<SQLitePersistence>>{};

  /// Marks the cache as cleared by another client and calls [databaseClearedListener] (once).
  void _onClearedByOtherClient() {
    if (_clearedByOtherClient) {
      return;
    }
    _clearedByOtherClient = true;
    Log.w(
      tag,
      'The persistent cache "$databaseName" was cleared by another client: this client terminates.',
    );
    final void Function()? listener = databaseClearedListener;
    if (listener != null) {
      scheduleMicrotask(listener);
    }
  }

  static const String tag = 'SQLitePersistence';

  /// Whether this is compiled for a browser.
  static const bool _isWeb = bool.fromEnvironment('dart.library.js_interop');

  final OpenDatabase openDatabase;
  final String databaseName;
  final LocalSerializer serializer;
  final StatsCollector _statsCollector;
  final Semaphore _semaphore;

  /// The lock of the database file once it is open, taken after [_semaphore]. Two persistences with different names
  /// can have the same file open in one isolate (an opener decides the file). One of them can hold the write lock of
  /// SQLite across an `await`; without this lock the other one would then wait for it in a synchronous call, which
  /// blocks the isolate, and with it the first one, until the busy timeout.
  Semaphore? _fileSemaphore;

  Future<void> _lock() async {
    await _semaphore.acquire();
    final Semaphore? file = _fileSemaphore;
    if (file != null) {
      await file.acquire();
    }
  }

  void _unlock() {
    _fileSemaphore?.release();
    _semaphore.release();
  }

  late Database _db;

  /// The path of the database file, known once [start] opened it. Kept after
  /// [shutdown] so that [clearPersistence] can delete it.
  String? _databasePath;

  /// How the database that was opened deletes its storage, when it does that
  /// itself (see [ClearableDatabase]).
  Future<void> Function()? _clearStorage;

  /// How long a statement waits for the lock of another connection (another isolate or process that has the same
  /// database file open) before it fails with `SQLITE_BUSY`.
  static const Duration busyTimeout = Duration(seconds: 10);

  /// `PRAGMA data_version` as it was when the state this client keeps in memory was last read. SQLite changes the
  /// value when another connection commits, and never for a commit of this connection.
  int? _dataVersion;

  /// The mutation queues and index managers that were handed out and keep state of the database in memory.
  final List<WeakReference<SQLiteMutationQueue>> _mutationQueues =
      <WeakReference<SQLiteMutationQueue>>[];
  final List<WeakReference<SqliteIndexManager>> _indexManagers =
      <WeakReference<SqliteIndexManager>>[];

  /// The number of times the in-memory state was read again because another connection had changed the database.
  @visibleForTesting
  int foreignCommitsSeen = 0;

  @override
  bool started = false;

  @override
  late SQLiteQueryCache queryCache;

  @override
  late final BundleCache bundleCache = SQLiteBundleCache(this, serializer);

  @override
  late final GlobalsCache globalsCache = SQLiteGlobalsCache(this);

  @override
  late SqliteIndexManager indexManager;

  @override
  late SQLiteRemoteDocumentCache remoteDocumentCache;

  @override
  late SQLiteLruReferenceDelegate referenceDelegate;

  Future<int> get byteSize async {
    final int pageSize = await getPageSize();
    final int pageCount = await getPageCount();
    return pageCount * pageSize;
  }

  /// Gets the page size of the database. Typically 4096.
  ///
  /// @see https://www.sqlite.org/pragma.html#pragma_page_size
  Future<int> getPageSize() async {
    return (await _db.query('PRAGMA page_size'))[0].values.first;
  }

  /// Gets the number of pages in the database file. Multiplying this with the
  /// page size yields the approximate size of the database on disk (including
  /// the WAL, if relevant).
  ///
  /// @see https://www.sqlite.org/pragma.html#pragma_page_count.
  Future<int> getPageCount() async {
    return (await _db.query('PRAGMA page_count'))[0].values.first;
  }

  static Future<SQLitePersistence> create(
    String persistenceKey,
    DatabaseId databaseId,
    LocalSerializer serializer,
    OpenDatabase openDatabase,
    LruGarbageCollectorParams params, [
    StatsCollector statsCollector = StatsCollector.noOp,
  ]) async {
    return createWithLease(
      persistenceKey,
      databaseId,
      serializer,
      openDatabase,
      params,
      statsCollector: statsCollector,
    );
  }

  /// [create] with the parameters of the primary lease: the id of this client (a new random one by default), the
  /// clock of the lease and how a lease held by another client is treated.
  static Future<SQLitePersistence> createWithLease(
    String persistenceKey,
    DatabaseId databaseId,
    LocalSerializer serializer,
    OpenDatabase openDatabase,
    LruGarbageCollectorParams params, {
    StatsCollector statsCollector = StatsCollector.noOp,
    String? clientId,
    Clock? clock,
    PrimaryLeaseMode leaseMode = PrimaryLeaseMode.forceOwnership,
  }) async {
    final String databaseName = sDatabaseName(persistenceKey, databaseId);

    final SQLitePersistence persistence = SQLitePersistence._(
      serializer,
      openDatabase,
      databaseName,
      statsCollector,
      clientId ?? autoId(),
      clock ?? _systemClock,
      leaseMode,
    );

    final SQLiteQueryCache queryCache = SQLiteQueryCache(
      persistence,
      serializer,
    );
    final SQLiteRemoteDocumentCache remoteDocumentCache =
        SQLiteRemoteDocumentCache(persistence, serializer, statsCollector);
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
    await _lock();
    try {
      Log.d(tag, 'Starting SQLite persistance');
      hardAssert(!started, 'SQLitePersistence double-started!');
      _db = await _openDb(databaseName, openDatabase);
      _databasePath = _db.path;
      (_openInIsolate[_db.path] ??= <SQLitePersistence>{}).add(this);
      try {
        await _startOpened();
      } catch (_) {
        // Nothing else would close the handle: [shutdown] requires a started persistence.
        started = false;
        try {
          _db.close();
        } catch (e) {
          Log.w(tag, 'Closing the database after a failed start failed: $e');
        }
        rethrow;
      }
    } finally {
      _unlock();
    }
  }

  /// The part of [start] after the database is open. The caller holds [_semaphore].
  Future<void> _startOpened() async {
    // A persistence that is started again already holds the lock of its file (from [_lock]): the semaphores are
    // not reentrant, taking it twice would wait forever.
    final Semaphore file = GlobalSemaphore('sqlite-file:${_db.path}');
    if (!identical(file, _fileSemaphore)) {
      await file.acquire();
      _fileSemaphore?.release();
      _fileSemaphore = file;
    }
    final Database db = _db;
    _clearStorage = db is ClearableDatabase ? db.clearStorage : null;
    // Read before the state: a commit of another connection in between is then seen by the next transaction.
    _dataVersion = await _readDataVersion();
    await queryCache.start();
    _epoch = await _metadataTransaction(
      _ensureEpoch,
      checkForeignCommits: false,
    );
    started = true;
    referenceDelegate.start(queryCache.highestListenSequenceNumber);
    await _metadataTransaction(() => clientMetadata._update(atStart: true));
  }

  /// The epoch of the cache, or null when its row is missing, repeated or does not hold an integer (a damaged file, or
  /// rows written by something else than this SDK, which may also have created the table without its constraints). A
  /// running client treats null as a changed epoch: it terminates as after a clear by another client.
  Future<int?> _readEpoch() async {
    final List<Map<String, dynamic>> rows = await _db.query(
      'SELECT epoch FROM persistence_epoch WHERE id = 0',
    );
    final Object? epoch = rows.length == 1 ? rows.single['epoch'] : null;
    return epoch is int ? epoch : null;
  }

  /// Reads the epoch when this client starts, and repairs a missing or malformed row first: a new client starts on
  /// such a file instead of failing. The caller runs it in a transaction.
  Future<int> _ensureEpoch() async {
    await _db.execute(
      'INSERT OR IGNORE INTO persistence_epoch (id, epoch) VALUES (0, 0)',
    );
    final int? epoch = await _readEpoch();
    if (epoch != null) {
      return epoch;
    }
    Log.w(tag, 'Replacing the malformed epoch of the cache "$databaseName".');
    // Delete and insert: a table without its constraints may hold the row more than once.
    await _db.execute('DELETE FROM persistence_epoch WHERE id = 0');
    await _db.execute(
      'INSERT INTO persistence_epoch (id, epoch) VALUES (0, 0)',
    );
    return 0;
  }

  /// A transaction for the client metadata: no listen sequence number is used up. The caller holds [_semaphore].
  Future<T> _metadataTransaction<T>(
    Future<T> Function() operation, {
    bool checkForeignCommits = true,
  }) async {
    bool began = false;
    try {
      await _db.execute('BEGIN IMMEDIATE;');
      began = true;
      if (checkForeignCommits) {
        await _refreshAfterForeignCommit();
      }
      final T result = await operation();
      await _db.execute('COMMIT;');
      began = false;
      return result;
    } catch (_) {
      if (began) {
        try {
          await _db.execute('ROLLBACK;');
        } catch (e) {
          Log.w(tag, 'Rollback of the client metadata transaction failed: $e');
        }
      }
      rethrow;
    }
  }

  /// Writes the metadata of this client, refreshes, takes or releases the primary lease, and lets the primary remove
  /// the clients that are gone. The client runs this every [SQLiteClientMetadata.refreshInterval], and when its
  /// network is enabled or disabled.
  ///
  /// A failure of the database (another connection holding the lock for longer than [busyTimeout]) is logged and
  /// leaves the state as it was, as in the JS SDK; a [FirestoreError] (the cache was cleared or migrated by another
  /// client) is thrown.
  Future<void> refreshClientMetadata() async {
    await _lock();
    try {
      if (!started) {
        return;
      }
      await _metadataTransaction(() async {
        await clientMetadata._update();
        await clientMetadata._maybeGarbageCollect();
      });
    } on FirestoreError {
      rethrow;
    } catch (e) {
      Log.w(tag, 'Refreshing the client metadata failed: $e');
    } finally {
      _unlock();
    }
  }

  /// Records whether the network of this client is enabled and refreshes the metadata: a client without network
  /// gives the lease to one with network.
  Future<void> setNetworkEnabled(bool enabled) async {
    if (clientMetadata.networkEnabled != enabled) {
      clientMetadata.networkEnabled = enabled;
      await refreshClientMetadata();
    }
  }

  /// Registers [listener] for the changes of [isPrimary] and calls it with the current state. It is not called once
  /// this persistence is shut down.
  @override
  void setPrimaryStateListener(PrimaryStateListener listener) {
    clientMetadata.primaryStateListener = (bool isPrimary) {
      if (started) {
        listener(isPrimary);
      }
    };
    listener(isPrimary);
  }

  /// The ids of the clients of this cache that refreshed their metadata within
  /// [SQLiteClientMetadata.maxClientAgeMs], this one included.
  @override
  Future<List<String>> getActiveClients() async {
    await _lock();
    try {
      return await _metadataTransaction(clientMetadata._activeClients);
    } finally {
      _unlock();
    }
  }

  @override
  Future<void> shutdown() async {
    await _lock();
    try {
      Log.d(tag, 'Shutingdown SQLite persistance');
      hardAssert(started, 'SQLitePersistence shutdown without start!');

      started = false;
      _openInIsolate[_db.path]?.remove(this);
      // Release the lease now, so that another client takes over at its next refresh instead of when the lease
      // expires.
      try {
        await _metadataTransaction(
          clientMetadata._remove,
          checkForeignCommits: false,
        );
      } catch (e) {
        Log.w(tag, 'Could not release the primary lease: $e');
      }
      _db.close();
    } finally {
      _unlock();
    }
  }

  @visibleForTesting
  Database get database => _db;

  @override
  IndexManager getIndexManager(User user) {
    final SqliteIndexManager manager = SqliteIndexManager(
      this,
      serializer,
      user,
    );
    _track(_indexManagers, manager);
    return manager;
  }

  void _track<T extends Object>(List<WeakReference<T>> list, T value) {
    list
      ..removeWhere((WeakReference<T> reference) => reference.target == null)
      ..add(WeakReference<T>(value));
  }

  Future<int> _readDataVersion() async {
    return (await _db.query('PRAGMA data_version')).first.values.first as int;
  }

  /// Reads the state that this client keeps in memory again when another connection changed the database since it
  /// was read. Called at the start of every transaction, when this connection already holds the write lock: what is
  /// read here stays true until the transaction ends.
  ///
  /// PORTING NOTE: the Android SDK opens the database in exclusive locking mode and can cache this state for as long
  /// as it runs. The port cannot (see [_openDb]), and two clients on one file happen: the isolate before a hot
  /// restart, a background isolate, a second process. Without this they hand out the same target and batch ids and
  /// overwrite each other's metadata rows with what they remembered.
  Future<void> _refreshAfterForeignCommit() async {
    if (_clearedByOtherClient) {
      throw _clearedError();
    }
    final int dataVersion = await _readDataVersion();
    if (dataVersion == _dataVersion) {
      return;
    }

    final int schemaVersion =
        (await _db.query('PRAGMA user_version')).first.values.first as int;
    if (schemaVersion != SQLiteSchema.version) {
      throw FirestoreError(
        'The persistent cache was opened by a different version of the SDK while this client was using it '
        '(its schema version is now $schemaVersion, this client uses ${SQLiteSchema.version}). Terminate this '
        'instance; a new instance migrates the cache when it starts.',
        FirestoreErrorCode.failedPrecondition,
      );
    }

    if (await _readEpoch() != _epoch) {
      _onClearedByOtherClient();
      throw _clearedError();
    }

    await queryCache.start();
    referenceDelegate.listenSequence.advanceTo(
      queryCache.highestListenSequenceNumber,
    );
    for (final WeakReference<SQLiteMutationQueue> reference
        in _mutationQueues) {
      await reference.target?._refresh();
    }
    for (final WeakReference<SqliteIndexManager> reference in _indexManagers) {
      await reference.target?._refresh();
    }
    _dataVersion = dataVersion;
    foreignCommitsSeen++;
  }

  FirestoreError _clearedError() => FirestoreError(
    'The persistent cache was cleared by another client (Firestore.clearPersistence) while this client was using it.',
    FirestoreErrorCode.failedPrecondition,
  );

  /// Deletes the database file and its journal, WAL and shared memory side
  /// files, or lets the database delete its own storage when it is a
  /// [ClearableDatabase]. Only valid after [shutdown]; does nothing when the
  /// database was never opened.
  ///
  /// PORTING NOTE: Android derives the path from [databaseName] with
  /// `Context.getDatabasePath`. Here the file is chosen by the [OpenDatabase]
  /// callback, so the file of the database that was opened is deleted.
  Future<void> clearPersistence() async {
    await _lock();
    try {
      hardAssert(!started, 'SQLitePersistence cleared while running!');
      final String? path = _databasePath;
      final Future<void> Function()? clearStorage = _clearStorage;
      if (clearStorage != null) {
        try {
          await clearStorage();
        } on FirestoreError {
          rethrow;
        } catch (e) {
          throw FirestoreError(
            'Failed to clear persistence: $e',
            FirestoreErrorCode.unknown,
            e,
          );
        }
      } else if (path != null) {
        if (!await _clearInPlaceIfOthersAreAlive()) {
          deleteSqliteDatabaseFiles(path);
        }
      }
    } finally {
      _unlock();
    }
  }

  /// Empties the cache in place and increments its epoch when other clients have it open: deleting the file under
  /// them would leave them working on a file that is gone (or, on some platforms, fail). The other clients notice the
  /// new epoch at their next transaction or metadata refresh and terminate. Returns false, and changes nothing, when
  /// no other client refreshed its metadata within [SQLiteClientMetadata.maxClientAgeMs]: the file is deleted then.
  Future<bool> _clearInPlaceIfOthersAreAlive() async {
    final Database db = await _openDb(databaseName, openDatabase);
    bool cleared = false;
    try {
      // Applications clear the cache for privacy (on sign-out): the deleted rows must not stay readable in the free
      // pages of the file. secure_delete overwrites them with zeros; it is a setting of this connection, which is
      // closed afterwards. A query: the pragma returns a row.
      await db.query('PRAGMA secure_delete = ON');
      await db.execute('BEGIN EXCLUSIVE;');
      try {
        final int now = clientMetadata._clock();
        final int others =
            (await db.query(
                  // A row from the future is not a live client (as for the garbage collection of the primary).
                  'SELECT COUNT(*) AS c FROM clients WHERE client_id != ? AND update_time_ms >= ? '
                  'AND update_time_ms <= ?',
                  <Object?>[
                    clientMetadata.clientId,
                    now - SQLiteClientMetadata.maxClientAgeMs,
                    now,
                  ],
                )).single['c']
                as int;
        if (others == 0) {
          await db.execute('COMMIT;');
          return false;
        }

        Log.w(
          tag,
          'clearPersistence: $others other client(s) have the cache "$databaseName" open. The cache is emptied in '
          'place; they terminate when they notice.',
        );
        final List<Map<String, dynamic>> tables = await db.query(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        );
        for (final Map<String, dynamic> table in tables) {
          final String name = table['name'] as String;
          if (name == 'persistence_epoch' ||
              (name.startsWith('sqlite_') && name != 'sqlite_sequence')) {
            continue;
          }
          // The name comes from the file, which another process may have written: quoted as an identifier, never
          // run as SQL.
          await db.execute('DELETE FROM "${name.replaceAll('"', '""')}"');
        }
        // The one row that a new cache has.
        await SQLiteSchema(db)._ensureTargetGlobal();
        await db.execute('UPDATE target_globals SET target_count = 0');
        // An epoch that is missing or not an integer becomes 1: the other clients notice a change either way.
        await db.execute(
          'INSERT OR REPLACE INTO persistence_epoch (id, epoch) VALUES (0, '
          "(SELECT CASE WHEN typeof(epoch) = 'integer' THEN epoch + 1 ELSE 1 END "
          'FROM persistence_epoch WHERE id = 0))',
        );
        await db.execute('COMMIT;');
        cleared = true;
        final String? path = _databasePath;
        for (final SQLitePersistence other
            in _openInIsolate[path]?.toList() ?? const <SQLitePersistence>[]) {
          if (!identical(other, this)) {
            other._onClearedByOtherClient();
          }
        }
      } catch (_) {
        try {
          await db.execute('ROLLBACK;');
        } catch (e) {
          Log.w(tag, 'Rollback of clearPersistence failed: $e');
        }
        rethrow;
      }
      // In WAL mode the old pages are still in the log (and the zeroed ones only in the log): copy the log into the
      // file and empty it. Other clients reading at this moment can keep the checkpoint from completing; it is then
      // logged, and finishes with a later checkpoint. Does nothing with a rollback journal. VACUUM is not used: it
      // rewrites the whole file while the other clients have it open, and secure_delete already zeroes the pages.
      try {
        final List<Map<String, dynamic>> result = await db.query(
          'PRAGMA wal_checkpoint(TRUNCATE)',
        );
        if (result.isNotEmpty && result.first.values.first != 0) {
          Log.w(
            tag,
            'clearPersistence: the write-ahead log of "$databaseName" could not be emptied now.',
          );
        }
      } catch (e) {
        Log.w(tag, 'clearPersistence: checkpoint failed: $e');
      }
      return cleared;
    } finally {
      db.close();
    }
  }

  @override
  MutationQueue getMutationQueue(User user) {
    final SQLiteMutationQueue queue = SQLiteMutationQueue(
      this,
      serializer,
      _statsCollector,
      user,
    );
    _track(_mutationQueues, queue);
    return queue;
  }

  @override
  OverlayMigrationManager get overlayMigrationManager =>
      SQLiteOverlayMigrationManager(this);

  @override
  DocumentOverlayCache getDocumentOverlayCache(User user) {
    return SQLiteDocumentOverlayCache(this, serializer, user);
  }

  @override
  Future<void> runTransaction(
    String action,
    Transaction<void> operation,
  ) async {
    return runTransactionAndReturn(action, operation);
  }

  @override
  Future<T> runTransactionAndReturn<T>(
    String action,
    Transaction<T> operation,
  ) {
    return _runTransaction(action, operation, primary: false);
  }

  /// Verifies (or takes) the primary lease inside the transaction before [operation] and extends it afterwards, see
  /// [Persistence.runPrimaryTransaction].
  @override
  Future<T> runPrimaryTransaction<T>(String action, Transaction<T> operation) {
    return _runTransaction(action, operation, primary: true);
  }

  Future<T> _runTransaction<T>(
    String action,
    Transaction<T> operation, {
    required bool primary,
  }) async {
    beforeTransaction?.call(action);
    await _lock();
    Log.d(tag, 'Starting transaction: $action');

    bool began = false;
    try {
      // IMMEDIATE takes the write lock now. A deferred transaction takes it at its first write, and that fails at
      // once, whatever the busy timeout, when another connection wrote since this transaction first read.
      await _db.execute('BEGIN IMMEDIATE;');
      began = true;
      await _refreshAfterForeignCommit();
      if (primary) {
        // Before the listen sequence number is taken: a client that is not primary uses none.
        await clientMetadata._verifyPrimaryLease(action);
      }
      referenceDelegate.onTransactionStarted();
      final T result = await operation();
      if (primary) {
        // After the operation, so that a long operation leaves a lease with a recent timestamp (as in the JS SDK).
        await clientMetadata._extendPrimaryLease();
      }
      await _db.execute('COMMIT;');
      began = false;
      await referenceDelegate.onTransactionCommitted();
      return result;
    } catch (_) {
      referenceDelegate.onTransactionRolledBack();
      if (began) {
        try {
          await _db.execute('ROLLBACK;');
        } catch (e) {
          Log.w(tag, 'Rollback of transaction "$action" failed: $e');
        }
      }
      rethrow;
    } finally {
      _unlock();
    }
  }

  /// Execute the given non-query SQL statement.
  Future<void> execute(String statement, [List<Object?>? args]) {
    return _db.execute(statement, args);
  }

  Future<List<Map<String, dynamic>>> query(
    String statement, [
    List<Object?>? args,
  ]) {
    return _db.query(statement, args);
  }

  Future<int> delete(String statement, [List<Object?>? args]) {
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
  /// Switches a database in SQLite's default rollback-journal mode (`delete`) to write-ahead logging, which SQLite
  /// recommends for concurrent access (https://www.sqlite.org/wal.html). With a rollback journal a reader needs the
  /// file free of writers and a writer needs it free of readers; the busy handler only polls, so with several
  /// clients (isolates, processes) that keep writing, a connection can wait out the whole [busyTimeout] without ever
  /// finding the file free and fail with `database is locked`. Measured: 16 isolates opening a new cache at once next
  /// to a coverage run, `PRAGMA user_version` failed after 10.5 s. In WAL mode readers and the writer do not block
  /// each other; only writers wait for each other, for the length of one transaction.
  ///
  /// The mode is stored in the file, so it is switched once. A journal mode that the opener chose (anything but
  /// `delete`, or `wal` already) is kept, and a file system without the shared memory WAL needs answers with the mode
  /// it keeps. Not on the web: there one tab at a time has the database (a Web Lock guards it), and the crash safety
  /// of the example openers is built on the rollback journal.
  ///
  /// The switch needs the file to itself for a moment. When other connections are opening the same file at once
  /// (several isolates or processes) it can fail with `database is locked` (SQLITE_BUSY or SQLITE_LOCKED) without
  /// waiting for the busy timeout; it is then tried again [_walSwitchRetries] times, a little later each time, and
  /// given up at debug level: the file keeps working in its current mode, and the next open that finds it in
  /// `delete` mode switches it. Any other failure is logged as a warning.
  static Future<void> _useWriteAheadLog(Database db) async {
    if (_isWeb) {
      return;
    }
    for (int attempt = 0; ; attempt++) {
      try {
        final List<Map<String, dynamic>> current = await db.query(
          'PRAGMA journal_mode',
        );
        // Also when another connection switched the file in the meantime.
        if (current.isEmpty ||
            '${current.first.values.first}'.toLowerCase() != 'delete') {
          return;
        }
        final List<Map<String, dynamic>> result = await db.query(
          'PRAGMA journal_mode = WAL',
        );
        final String mode = result.isEmpty
            ? ''
            : '${result.first.values.first}'.toLowerCase();
        if (mode != 'wal') {
          Log.d(tag, 'The database stays in journal mode "$mode".');
        }
        return;
      } catch (e) {
        if (!_isBusyOrLocked(e)) {
          Log.w(
            tag,
            'Could not switch the database to write-ahead logging: $e',
          );
          return;
        }
        if (attempt == _walSwitchRetries) {
          Log.d(
            tag,
            'The database is busy; it stays in its journal mode until the next open: $e',
          );
          return;
        }
        await Future<void>.delayed(_walSwitchRetryDelay * (attempt + 1));
      }
    }
  }

  /// How often a switch to write-ahead logging that found the database busy is tried again.
  static const int _walSwitchRetries = 5;

  /// The wait before the first retry; it grows by this much with each one (at most 1.5 s in all, well within
  /// [busyTimeout]).
  static const Duration _walSwitchRetryDelay = Duration(milliseconds: 100);

  /// Whether [error] of a [Database] is SQLite's SQLITE_BUSY (5) or SQLITE_LOCKED (6). The binding is the app's, so
  /// the error is recognized by its text (and the one of its cause, for a [TransientDatabaseException]).
  static bool _isBusyOrLocked(Object error) {
    final String text = <Object?>[
      error,
      if (error is TransientDatabaseException) error.cause,
    ].join(' ');
    return RegExp(
      r'database (table )?is locked|SQLITE_(BUSY|LOCKED)|Exception\((5|6)\)',
    ).hasMatch(text);
  }

  /// Unlike the Android SDK this does NOT take exclusive access to the database (`PRAGMA locking_mode = EXCLUSIVE`),
  /// because that makes a second open of the file fail after a Flutter hot restart (the old handle stays open).
  static Future<Database> _openDb(
    String databaseName,
    OpenDatabase openDatabase,
  ) async {
    bool configured = false;

    /// Ensures that onConfigure has been called. This should be called first from all methods.
    Future<void> ensureConfigured(Database db) async {
      if (!configured) {
        configured = true;
        // Intentionally no `PRAGMA locking_mode = EXCLUSIVE`: it breaks flutter hot restart.
        //
        // Wait for the lock of another connection instead of failing at once. The pragma returns a row, so it is
        // sent as a query: some bindings refuse rows from `execute`.
        try {
          await db.query('PRAGMA busy_timeout = ${busyTimeout.inMilliseconds}');
        } catch (e) {
          Log.w(tag, 'Could not set the busy timeout of the database: $e');
        }
        await _useWriteAheadLog(db);
      }
    }

    /// Brings the schema to [SQLiteSchema.version] while no other connection can read or write.
    ///
    /// Two clients that open an old (or new) file at the same moment are both told to migrate it by their openers.
    /// The second one waits here, finds the version the first one stored and does nothing. The version is read and
    /// stored inside the transaction for that reason; the opener stores it again afterwards.
    Future<void> migrate(Database db) async {
      await ensureConfigured(db);
      bool began = false;
      try {
        await db.execute('BEGIN EXCLUSIVE;');
        began = true;
      } catch (e) {
        // An opener may run the callbacks inside a transaction of its own (example/sqlite_database_web.dart does).
        if (!'$e'.contains('within a transaction')) {
          rethrow;
        }
      }
      try {
        final int stored =
            (await db.query('PRAGMA user_version')).first.values.first as int;
        if (stored < SQLiteSchema.version) {
          await SQLiteSchema(db).runMigrations(stored);
          await db.execute('PRAGMA user_version = ${SQLiteSchema.version}');
        }
        if (began) {
          await db.execute('COMMIT;');
        }
      } catch (_) {
        if (began) {
          try {
            await db.execute('ROLLBACK;');
          } catch (e) {
            Log.w(tag, 'Rollback of the schema migration failed: $e');
          }
        }
        rethrow;
      }
    }

    final Database db = await openDatabase(
      databaseName,
      version: SQLiteSchema.version,
      onConfigure: ensureConfigured,
      onCreate: (Database db, int version) => migrate(db),
      onUpgrade: (Database db, int fromVersion, int toVersion) => migrate(db),
      onDowngrade: (Database db, int fromVersion, int toVersion) async {
        await ensureConfigured(db);

        // For now, we can safely do nothing.
        //
        // PORTING NOTE: a client of a newer SDK that still has this file open notices the lowered version at its next
        // transaction and fails (see [_refreshAfterForeignCommit]); this client goes on.
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
  LongQuery(
    this._db,
    this._head,
    List<Object?>? argsHead,
    List<Object?> argsIter,
    this._tail,
  ) : _argsIter = argsIter,
      _argsHead = argsHead ?? <Object?>[],
      _subqueriesPerformed = 0;

  final SQLitePersistence _db;

  // The non-changing beginning of each subquery.
  final String _head;

  // The non-changing end of each subquery.
  final String _tail;

  // Arguments that will be prepended in each subquery before the main argument list.
  final List<Object?> _argsHead;

  int _subqueriesPerformed;

  final List<Object?> _argsIter;

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

    final List<Object?> subqueryArgs = List<Object?>.from(_argsHead);
    final StringBuffer placeholdersBuilder = StringBuffer();

    for (
      int i = 0;
      j < _argsIter.length && i < _limit - _argsHead.length;
      i++
    ) {
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
