/// The persistence of the key-value cache: every cache of the SDK laid out in one ordered key-value store
/// ([CacheStore]), in the spirit of the LevelDB persistence of the iOS SDK.
///
/// The layout, one table per key prefix (the keys are written with [KvKeyWriter]; a table name is the first string of
/// a key):
///
/// | table          | key after the table name                    | value                                           |
/// |----------------|---------------------------------------------|-------------------------------------------------|
/// | `meta`         | name (`version`, `database`)                | the schema version, the database id             |
/// | `doc`          | document key                                | read time, document type, `MaybeDocument` proto |
/// | `docRead`      | collection, read time, document id          | (empty) the documents of a collection by read time |
/// | `collParent`   | collection id, parent path                  | (empty) the collection parent index              |
/// | `mutQueue`     | uid                                         | the last stream token                           |
/// | `mut`          | uid, batch id                               | `WriteBatch` proto                              |
/// | `docMut`       | uid, document key, batch id                 | (empty) the batches that change a document       |
/// | `overlay`      | uid, document key                           | largest batch id, `Write` proto                 |
/// | `overlayBatch` | uid, batch id, document key                 | (empty)                                         |
/// | `overlayColl`  | uid, collection, batch id, document id      | (empty)                                         |
/// | `overlayGroup` | uid, collection group, batch id, document key | (empty)                                       |
/// | `target`       | target id                                   | `Target` proto                                  |
/// | `targetCanon`  | canonical id, target id                     | (empty)                                         |
/// | `targetDoc`    | target id, document key                     | (empty)                                         |
/// | `docTarget`    | document key, target id                     | (empty); for target id 0 the sequence number    |
/// | `targetGlobal` | (nothing)                                   | highest target id and sequence number, last remote snapshot version, target count |
/// | `bundle`       | bundle id                                   | schema version, create time, documents, bytes   |
/// | `namedQuery`   | name                                        | read time, `BundledQuery` proto                 |
/// | `global`       | name                                        | the value (session token, merge marks, the byte size of the documents) |
///
/// and the tables of the persistent cache indexes, see [_KvIndexManager].
///
/// Only one client uses a store at a time: it is always the primary client.
// ignore_for_file: library_private_types_in_public_api
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_metadata.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundled_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/named_query.dart';
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
import 'package:cloud_firestore_dart/src/firebase/firestore/local/keyvalue/cache_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/keyvalue/key_value_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/keyvalue/kv_codec.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_delegate.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/bundle_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/document_overlay_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/globals_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/index_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/mutation_queue.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/overlay_migration_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/query_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/reference_delegate.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/remote_document_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/stats_collector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_context.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/reference_set.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/stored_proto.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/overlay.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/no_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/target_index_matcher.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/unknown_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/logic_utils.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/types.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/admin/v1/index.dart'
    as admin;
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:collection/collection.dart';
import 'package:firebase_app_dart/internal.dart';
import 'package:semaphore/semaphore.dart';

part 'kv_bundle_and_globals.dart';
part 'kv_index_manager.dart';
part 'kv_mutation_queue.dart';
part 'kv_overlay_cache.dart';
part 'kv_query_cache.dart';
part 'kv_reference_delegate.dart';
part 'kv_remote_document_cache.dart';

/// The version of the layout this SDK writes. A store with another version is not opened.
const int kvSchemaVersion = 1;

/// The tables of the layout (see the library comment).
abstract final class _Table {
  static const String meta = 'meta';
  static const String doc = 'doc';
  static const String docRead = 'docRead';
  static const String collParent = 'collParent';
  static const String mutQueue = 'mutQueue';
  static const String mut = 'mut';
  static const String docMut = 'docMut';
  static const String overlay = 'overlay';
  static const String overlayBatch = 'overlayBatch';
  static const String overlayColl = 'overlayColl';
  static const String overlayGroup = 'overlayGroup';
  static const String target = 'target';
  static const String targetCanon = 'targetCanon';
  static const String targetDoc = 'targetDoc';
  static const String docTarget = 'docTarget';
  static const String targetGlobal = 'targetGlobal';
  static const String bundle = 'bundle';
  static const String namedQuery = 'namedQuery';
  static const String global = 'global';
  static const String indexConfig = 'indexConfig';
  static const String indexState = 'indexState';
  static const String indexEntry = 'indexEntry';
  static const String docIndexEntry = 'docIndexEntry';
}

/// A writer that starts with the name of [table].
KvKeyWriter _key(String table) => KvKeyWriter().string(table);

final Uint8List _empty = Uint8List(0);

/// The persistence of a key-value cache over a [CacheStore].
class CacheStorePersistence extends KeyValuePersistence {
  CacheStorePersistence(
    this.store, {
    required this.databaseId,
    required this.serializer,
    required LruGarbageCollectorParams lruParams,
    StatsCollector statsCollector = StatsCollector.noOp,
  }) : _statsCollector = statsCollector {
    queryCache = _KvQueryCache(this);
    remoteDocumentCache = _KvRemoteDocumentCache(this);
    indexManager = _KvIndexManager(this);
    referenceDelegate = _KvReferenceDelegate(this, lruParams);
    bundleCache = _KvBundleCache(this);
    globalsCache = _KvGlobalsCache(this);
  }

  /// Creates the persistence, for the settings of the entry library.
  static KeyValuePersistenceFactory factoryFor(CacheStore store) =>
      ({
        required DatabaseId databaseId,
        required LocalSerializer serializer,
        required LruGarbageCollectorParams lruParams,
      }) => CacheStorePersistence(
        store,
        databaseId: databaseId,
        serializer: serializer,
        lruParams: lruParams,
      );

  static const String tag = 'CacheStorePersistence';

  /// The stores that a started persistence uses: a store belongs to one instance at a time.
  static final Set<CacheStore> _storesInUse = Set<CacheStore>.identity();

  final CacheStore store;
  final DatabaseId databaseId;
  final LocalSerializer serializer;
  final StatsCollector _statsCollector;
  final Semaphore _semaphore = LocalSemaphore(1);

  @override
  late final _KvQueryCache queryCache;

  @override
  late final _KvRemoteDocumentCache remoteDocumentCache;

  @override
  late final _KvIndexManager indexManager;

  @override
  late final _KvReferenceDelegate referenceDelegate;

  @override
  late final BundleCache bundleCache;

  @override
  late final GlobalsCache globalsCache;

  @override
  LruGarbageCollector get garbageCollector =>
      referenceDelegate.garbageCollector;

  /// The mutation queues handed out, by uid: their state is read again after a transaction rolled back.
  final Map<String, _KvMutationQueue> _mutationQueues =
      <String, _KvMutationQueue>{};

  @override
  bool started = false;

  /// The transaction that runs, if any.
  CacheStoreTransaction? _current;

  /// Whether a transaction rolled back, so that the state kept in memory between transactions (the target globals,
  /// the next batch id, the byte size of the documents) is read again before the next one.
  bool _stale = false;

  /// The transaction that runs. Every read and write of the caches goes through it. Outside of a transaction (which
  /// the [Persistence] contract does not allow, but tests do), each read or write is a transaction of its own, as a
  /// statement outside of a transaction is in SQLite.
  CacheStoreTransaction get _tx => _current ?? _AutoCommit(store);

  @override
  Future<void> start() async {
    await _semaphore.acquire();
    try {
      hardAssert(!started, 'CacheStorePersistence double-started!');
      if (!_storesInUse.add(store)) {
        throw FirestoreException(
          message:
              'This CacheStore is the cache of another Firestore instance that is running. A store holds the cache of '
              'one instance at a time: terminate the other instance first, or give this one its own store.',
          errorCode: FirestoreErrorCode.failedPrecondition,
        );
      }
      try {
        await store.open();
        try {
          await _inTransaction(() async {
            await _checkSchema();
            await _loadState();
          });
        } catch (_) {
          await store.close();
          rethrow;
        }
      } catch (_) {
        _storesInUse.remove(store);
        rethrow;
      }
      started = true;
      referenceDelegate.start(queryCache.highestListenSequenceNumber);
    } finally {
      _semaphore.release();
    }
  }

  /// Writes the version and the database of a new store, and checks those of a store written before.
  Future<void> _checkSchema() async {
    final Uint8List versionKey = _key(_Table.meta).string('version').bytes;
    final Uint8List databaseKey = _key(_Table.meta).string('database').bytes;
    final String database = '${databaseId.projectId}/${databaseId.databaseId}';
    final Uint8List? version = await _tx.get(versionKey);
    if (version == null) {
      final List<CacheStoreEntry> any = await _tx.scan(
        Uint8List(0),
        Uint8List.fromList(<int>[0xff, 0xff, 0xff, 0xff]),
        limit: 1,
      );
      if (any.isNotEmpty) {
        throw FirestoreException(
          message:
              'The CacheStore holds data that the key-value cache did not write (no schema version). Give the cache '
              'an empty store.',
          errorCode: FirestoreErrorCode.failedPrecondition,
        );
      }
      await _tx.put(versionKey, KvKeyWriter().integer(kvSchemaVersion).bytes);
      await _tx.put(databaseKey, utf8.encode(database));
      return;
    }
    final int stored = KvKeyReader(version).integer();
    if (stored != kvSchemaVersion) {
      throw FirestoreException(
        message:
            'The CacheStore holds a cache of schema version $stored, this SDK reads version $kvSchemaVersion. '
            'Clear the store (FirebaseFirestore.clearPersistence) or use the SDK that wrote it.',
        errorCode: FirestoreErrorCode.failedPrecondition,
      );
    }
    final Uint8List? storedDatabase = await _tx.get(databaseKey);
    if (storedDatabase != null && utf8.decode(storedDatabase) != database) {
      throw FirestoreException(
        message:
            'The CacheStore holds the cache of the database ${utf8.decode(storedDatabase)}, not of $database. '
            'Give each database its own store.',
        errorCode: FirestoreErrorCode.failedPrecondition,
      );
    }
  }

  /// Reads the state kept in memory between transactions.
  Future<void> _loadState() async {
    await queryCache._start();
    await remoteDocumentCache._loadByteSize();
    for (final _KvMutationQueue queue in _mutationQueues.values) {
      await queue._load();
    }
    for (final _KvIndexManager manager in _startedIndexManagers.toList()) {
      await manager.start();
    }
    _stale = false;
  }

  @override
  Future<void> shutdown() async {
    await _semaphore.acquire();
    try {
      hardAssert(started, 'CacheStorePersistence shutdown without start');
      started = false;
      try {
        await store.close();
      } finally {
        _storesInUse.remove(store);
      }
    } finally {
      _semaphore.release();
    }
  }

  @override
  Future<void> clearPersistence() async {
    await _semaphore.acquire();
    try {
      hardAssert(!started, 'clearPersistence on a running cache');
      if (!_storesInUse.add(store)) {
        throw FirestoreException(
          message:
              'The CacheStore is the cache of another Firestore instance that is running: not cleared.',
          errorCode: FirestoreErrorCode.failedPrecondition,
        );
      }
      try {
        await store.open();
        try {
          await store.transaction((CacheStoreTransaction tx) async {
            final Uint8List end = Uint8List.fromList(<int>[
              0xff,
              0xff,
              0xff,
              0xff,
            ]);
            while (true) {
              final List<CacheStoreEntry> entries = await tx.scan(
                Uint8List(0),
                end,
                limit: 1000,
              );
              for (final CacheStoreEntry entry in entries) {
                await tx.delete(entry.key);
              }
              if (entries.length < 1000) {
                break;
              }
            }
          });
        } finally {
          await store.close();
        }
      } finally {
        _storesInUse.remove(store);
      }
    } finally {
      _semaphore.release();
    }
  }

  @override
  MutationQueue getMutationQueue(User user) {
    final String uid = user.uid ?? '';
    return _mutationQueues.putIfAbsent(uid, () => _KvMutationQueue(this, uid));
  }

  @override
  OverlayMigrationManager get overlayMigrationManager =>
      const NoOpOverlayMigrationManager();

  @override
  DocumentOverlayCache getDocumentOverlayCache(User user) =>
      _KvDocumentOverlayCache(this, user.isAuthenticated ? user.uid! : '');

  /// The index managers of users that were started: their field indexes are read again after a rollback.
  final Set<_KvIndexManager> _startedIndexManagers = <_KvIndexManager>{};

  @override
  IndexManager getIndexManager(User user) =>
      _KvIndexManager(this, user.uid ?? '');

  @override
  Future<void> runTransaction(String action, Transaction<void> operation) =>
      runTransactionAndReturn(action, operation);

  @override
  Future<T> runTransactionAndReturn<T>(
    String action,
    Transaction<T> operation,
  ) async {
    beforeTransaction?.call(action);
    await _semaphore.acquire();
    try {
      hardAssert(started, 'The key-value cache is not started');
      if (_stale) {
        await _inTransaction(_loadState);
      }
      Log.d(tag, 'Starting transaction: $action');
      bool inProgress = false;
      try {
        final T result = await _inTransaction(() async {
          referenceDelegate.onTransactionStarted();
          inProgress = true;
          return operation();
        });
        inProgress = false;
        indexManager._onCommitted();
        await referenceDelegate.onTransactionCommitted();
        return result;
      } catch (_) {
        if (inProgress) {
          referenceDelegate.onTransactionRolledBack();
        }
        indexManager._onRolledBack();
        _stale = true;
        rethrow;
      }
    } finally {
      _semaphore.release();
    }
  }

  /// Runs [body] in a transaction of the store, with [_tx] set to it.
  Future<T> _inTransaction<T>(Future<T> Function() body) {
    return store.transaction<T>((CacheStoreTransaction tx) async {
      _current = tx;
      try {
        return await body();
      } finally {
        _current = null;
      }
    });
  }

  // Helpers of the caches.

  /// Calls [onPage] with the entries of the keys starting with [prefix] (from [from] when given), in key order, in
  /// pages of [pageSize]. Stops when [onPage] returns false.
  Future<void> _scanPrefix(
    Uint8List prefix,
    FutureOr<bool> Function(List<CacheStoreEntry> page) onPage, {
    Uint8List? from,
    int pageSize = 1000,
  }) async {
    final Uint8List end = prefixEnd(prefix);
    Uint8List start = from ?? prefix;
    while (true) {
      final List<CacheStoreEntry> page = await _tx.scan(
        start,
        end,
        limit: pageSize,
      );
      if (page.isEmpty) {
        return;
      }
      if (!await onPage(page) || page.length < pageSize) {
        return;
      }
      start = keySuccessor(page.last.key);
    }
  }

  /// The entries of the keys starting with [prefix], all of them.
  Future<List<CacheStoreEntry>> _scanAll(Uint8List prefix) async {
    final List<CacheStoreEntry> result = <CacheStoreEntry>[];
    await _scanPrefix(prefix, (List<CacheStoreEntry> page) {
      result.addAll(page);
      return true;
    });
    return result;
  }

  /// Whether a key starts with [prefix].
  Future<bool> _hasPrefix(Uint8List prefix) async =>
      (await _tx.scan(prefix, prefixEnd(prefix), limit: 1)).isNotEmpty;

  /// The uids that have a mutation queue.
  Future<List<String>> _queueUids() async {
    final Uint8List prefix = _key(_Table.mutQueue).bytes;
    return <String>[
      for (final CacheStoreEntry entry in await _scanAll(prefix))
        (KvKeyReader(entry.key)..string()).string(),
    ];
  }

  /// Whether a mutation queue of any user changes [key].
  Future<bool> _mutationQueuesContainKey(DocumentKey key) async {
    for (final String uid in await _queueUids()) {
      if (await _hasPrefix(
        _key(_Table.docMut).string(uid).documentKey(key).bytes,
      )) {
        return true;
      }
    }
    return false;
  }
}

/// The value of a read time (seconds, then nanoseconds).
KvKeyWriter _writeVersion(KvKeyWriter writer, SnapshotVersion version) => writer
    .integer(version.timestamp.seconds)
    .integer(version.timestamp.nanoseconds);

SnapshotVersion _readVersion(KvKeyReader reader) {
  final int seconds = reader.integer();
  final int nanos = reader.integer();
  return SnapshotVersion(Timestamp(seconds, nanos));
}

/// Runs each read or write in a transaction of its own.
class _AutoCommit implements CacheStoreTransaction {
  _AutoCommit(this._store);

  final CacheStore _store;

  @override
  Future<Uint8List?> get(Uint8List key) => _store.transaction(
    (CacheStoreTransaction tx) => tx.get(key),
    readOnly: true,
  );

  @override
  Future<void> put(Uint8List key, Uint8List value) =>
      _store.transaction((CacheStoreTransaction tx) => tx.put(key, value));

  @override
  Future<void> delete(Uint8List key) =>
      _store.transaction((CacheStoreTransaction tx) => tx.delete(key));

  @override
  Future<List<CacheStoreEntry>> scan(
    Uint8List start,
    Uint8List end, {
    bool reverse = false,
    int? limit,
  }) => _store.transaction(
    (CacheStoreTransaction tx) =>
        tx.scan(start, end, reverse: reverse, limit: limit),
    readOnly: true,
  );
}
