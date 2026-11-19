// Copyright 2017 Google LLC (behaviour ported from `indexeddb_persistence.ts` and `simple_db.ts` of firebase-js-sdk)
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/// The IndexedDB engine: a [Persistence] on the JS SDK's IndexedDB schema, version 18. Web only (see
/// `indexeddb_persistence_platform.dart`).
///
/// # Transactions
///
/// Every persistence transaction is one IndexedDB transaction over all the stores, `readwrite` (the JS SDK does the
/// same; the persistence serializes its transactions anyway). An IndexedDB transaction commits on its own as soon as
/// control returns to the event loop with no request of it pending. The futures of this engine complete in the
/// `success` event of their request, and Dart runs the code after an `await` of a completed future as a microtask,
/// before the event loop goes on: a transaction stays active as long as the operation only awaits requests of the
/// transaction and other futures that complete without a new task (docs/spikes/indexeddb_cache.md, point 4).
///
/// The rule for every operation run inside [Persistence.runTransaction]: it awaits nothing else. No timer
/// (`Future.delayed`, `Timer`, `Future(() {})`), no I/O other than requests of this persistence, no isolate, no
/// network. A request made after the transaction committed fails with `TransactionInactiveError`; the writes before
/// it are committed, the ones after are not. That is not a rollback, so it is not retried: the engine fails the
/// transaction with an [IndexedDbTransactionInactiveError] that names the transaction and the request, logs it as an
/// error and refuses every later transaction (the client has to be restarted). The same happens when the IndexedDB
/// transaction completed before the operation returned (it awaited something that let the event loop run).
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_metadata.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/named_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/bound.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/listent_sequence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/target.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/index/index_entry.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/index/js_index_value_writer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/indexeddb/indexeddb_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/indexeddb/indexeddb_schema.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/indexeddb/indexeddb_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/indexeddb/web/idb.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_delegate.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/bundle_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/document_overlay_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/globals_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/index_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/mutation_queue.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/overlay_migration_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/query_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/reference_delegate.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/remote_document_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_context.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/reference_set.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_collections.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/overlay.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/target_index_matcher.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/database.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/logic_utils.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/types.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:collection/collection.dart';
import 'package:firebase_app_dart/internal.dart';
import 'package:semaphore/semaphore.dart';
import 'package:web/web.dart' as web;

part 'indexeddb_caches_web.dart';
part 'indexeddb_index_manager_web.dart';
part 'indexeddb_mutation_queue_web.dart';
part 'indexeddb_query_cache_web.dart';
part 'indexeddb_remote_document_cache_web.dart';
part 'indexeddb_transaction_web.dart';

/// Whether this platform has IndexedDB: only the web.
const bool indexedDbPersistenceSupported = true;

/// Creates the IndexedDB persistence of the app [persistenceKey] (its name) and [databaseId]. It is opened by
/// [Persistence.start].
IndexedDbPersistence createIndexedDbPersistence({
  required String persistenceKey,
  required DatabaseId databaseId,
  required LocalSerializer serializer,
  required LruGarbageCollectorParams lruParams,
}) {
  return WebIndexedDbPersistence(
    persistenceKey: persistenceKey,
    databaseId: databaseId,
    serializer: serializer,
    lruParams: lruParams,
  );
}

/// The message of the error every transaction fails with while another client holds the primary lease and this
/// client may not share the database (`PRIMARY_LEASE_EXCLUSIVE_ERROR_MSG` of the JS SDK).
const String _exclusiveErrorMessage =
    'Another tab (of this app, with this SDK or the JS SDK) holds the IndexedDB cache of this app: only one tab at a '
    'time may use it. Close the other tab, or use a memory cache in this one.';

/// See [IndexedDbPersistence].
class WebIndexedDbPersistence extends IndexedDbPersistence {
  WebIndexedDbPersistence({
    required String persistenceKey,
    required DatabaseId databaseId,
    required LocalSerializer serializer,
    required LruGarbageCollectorParams lruParams,
    String? clientId,
  }) : storagePrefix = indexedDbStoragePrefix(persistenceKey, databaseId),
       databaseName = indexedDbDatabaseName(persistenceKey, databaseId),
       clientId = clientId ?? autoId(),
       serializer = IndexedDbSerializer(serializer),
       _semaphore = GlobalSemaphore(
         'indexeddb:${indexedDbDatabaseName(persistenceKey, databaseId)}',
       ) {
    queryCache = IndexedDbQueryCache._(this);
    remoteDocumentCache = IndexedDbRemoteDocumentCache._(this);
    referenceDelegate = IndexedDbReferenceDelegate._(this, lruParams);
    indexManager = IndexedDbIndexManager._(this, null);
    globalsCache = IndexedDbGlobalsCache._(this);
  }

  static const String tag = 'IndexedDbPersistence';

  /// The prefix of the database name and of the LocalStorage keys of the JS SDK.
  final String storagePrefix;

  @override
  final String databaseName;

  @override
  final String clientId;

  final IndexedDbSerializer serializer;

  final Semaphore _semaphore;

  web.IDBDatabase? _db;

  /// The key of the zone value that holds the transaction of the operation running inside [runTransaction]. A zone
  /// value, not a field: code outside the operation (another asynchronous flow of the client) that uses a cache
  /// meanwhile must not make requests on the operation's transaction.
  final Object _zoneKey = Object();

  /// Set when a transaction failed for good (see [IndexedDbTransactionInactiveError]), or the database was deleted by
  /// another client: every later transaction fails with it.
  Object? _fatalError;

  /// Whether the state kept in memory (the target metadata, the indexes) has to be read again: a transaction rolled
  /// back.
  bool _reloadState = false;

  @override
  bool started = false;

  @override
  bool isPrimary = false;

  bool _networkEnabled = true;

  PrimaryStateListener? _primaryStateListener;

  JSFunction? _pageHideHandler;
  JSFunction? _pageShowHandler;

  /// When this client last removed the rows of inactive clients (`maybeGarbageCollectMultiClientState`).
  int _lastClientGarbageCollectionMs = 0;

  @override
  late final IndexedDbQueryCache queryCache;

  @override
  late final IndexedDbRemoteDocumentCache remoteDocumentCache;

  @override
  late final IndexedDbReferenceDelegate referenceDelegate;

  @override
  late final IndexedDbIndexManager indexManager;

  @override
  LruGarbageCollector get garbageCollector =>
      referenceDelegate.garbageCollector;

  @override
  late final IndexedDbGlobalsCache globalsCache;

  @override
  late final IndexedDbBundleCache bundleCache = IndexedDbBundleCache._(this);

  @override
  OverlayMigrationManager get overlayMigrationManager =>
      // A database of version 18 has its overlays: the JS SDK built them in its version 14 migration, and a new one
      // starts with them.
      const NoOpOverlayMigrationManager();

  @override
  MutationQueue getMutationQueue(User user) =>
      IndexedDbMutationQueue._(this, user);

  @override
  DocumentOverlayCache getDocumentOverlayCache(User user) =>
      IndexedDbDocumentOverlayCache._(this, user);

  final Map<String, IndexedDbIndexManager> _indexManagers =
      <String, IndexedDbIndexManager>{};

  /// One index manager per user: the index states and entries are per user (`uid`), the configuration and the
  /// collection parents are shared.
  @override
  IndexManager getIndexManager(User user) => _indexManagers.putIfAbsent(
    user.uid ?? '',
    () => IndexedDbIndexManager._(this, user),
  );

  /// The transaction of the operation that is running in this zone, or a new read-only transaction for a use outside
  /// of [runTransaction].
  ///
  /// PORTING NOTE: the local store of this port reads some caches outside a persistence transaction (`executeQuery`,
  /// `readDocument`, `getNextMutationBatch`, `getHighestUnacknowledgedBatchId`, `getRemoteDocumentKeys`, which the
  /// Android and JS SDKs run in transactions); SQLite runs those statements in transactions of their own
  /// (autocommit). Here each such cache call gets a read-only IndexedDB transaction of its own, which commits by
  /// itself once its requests are done; IndexedDB runs it after the read-write transactions created before it.
  _IdbTransaction get _current {
    final Object? transaction = Zone.current[_zoneKey];
    if (transaction is _IdbTransaction) {
      return transaction;
    }
    _throwIfFailed();
    return _begin('A read outside of a persistence transaction', 'readonly');
  }

  /// Runs [operation] with [transaction] as the transaction of its zone (see [_current]).
  Future<R> _inTransaction<R>(
    _IdbTransaction transaction,
    Future<R> Function() operation,
  ) => runZoned(operation, zoneValues: <Object, Object>{_zoneKey: transaction});

  static int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  // Opening

  @override
  Future<void> start() async {
    await _semaphore.acquire();
    try {
      hardAssert(!started, 'IndexedDbPersistence double-started!');
      Log.d(tag, 'Opening $databaseName');
      final web.IDBDatabase db = _db = await _open();
      db.onversionchange = ((web.IDBVersionChangeEvent event) {
        _onVersionChange(event.newVersion);
      }).toJS;
      final _IdbTransaction transaction = _begin(
        'Start the IndexedDB persistence',
      );
      try {
        await _claim(transaction);
        await _inTransaction(transaction, queryCache._load);
        await transaction.commit();
      } catch (_) {
        transaction.abort();
        db.close();
        _db = null;
        rethrow;
      }
      referenceDelegate._start(queryCache.highestListenSequenceNumber);
      isPrimary = true;
      started = true;
      _attachPageHandlers();
    } finally {
      _semaphore.release();
    }
  }

  /// Opens the database at [indexedDbSchemaVersion], creating it when there is none. A database of another version is
  /// refused: an older one would need the JS SDK's migrations, a newer one was written by a JS SDK this SDK does not
  /// know.
  Future<web.IDBDatabase> _open() {
    final web.IDBOpenDBRequest request = web.window.indexedDB.open(
      databaseName,
      indexedDbSchemaVersion,
    );
    final Completer<web.IDBDatabase> completer = Completer<web.IDBDatabase>();
    int? refusedVersion;
    request.onupgradeneeded = ((web.IDBVersionChangeEvent event) {
      final web.IDBTransaction upgrade = request.transaction!;
      if (event.oldVersion == 0) {
        _createSchema(request.result! as web.IDBDatabase, upgrade);
      } else {
        refusedVersion = event.oldVersion;
        upgrade.abort();
      }
    }).toJS;
    request.onblocked = ((web.Event _) {
      Log.w(
        tag,
        'Opening $databaseName waits for another connection to close it.',
      );
    }).toJS;
    request.onsuccess = ((web.Event _) {
      completer.complete(request.result! as web.IDBDatabase);
    }).toJS;
    request.onerror = ((web.Event event) {
      event.preventDefault();
      final web.DOMException? error = request.error;
      final int? version = refusedVersion;
      if (version != null) {
        completer.completeError(
          FirestoreException(
            message:
                'The IndexedDB cache $databaseName has schema version $version, written by an older JS SDK: '
                'IndexedDbCacheSettings only open version $indexedDbSchemaVersion. Open the app once with a '
                'current JS SDK (it migrates the database), or clear the cache with clearPersistence().',
            errorCode: FirestoreErrorCode.failedPrecondition,
          ),
        );
      } else if (error?.name == 'VersionError') {
        completer.completeError(
          FirestoreException(
            message:
                'The IndexedDB cache $databaseName has a schema version newer than $indexedDbSchemaVersion, written '
                'by a newer JS SDK: IndexedDbCacheSettings only open version $indexedDbSchemaVersion. Clear the cache '
                'with clearPersistence() to start over.',
            errorCode: FirestoreErrorCode.failedPrecondition,
          ),
        );
      } else {
        completer.completeError(
          FirestoreException(
            message:
                'Opening the IndexedDB cache $databaseName failed: ${idbDescribe(error)}',
            errorCode: FirestoreErrorCode.unavailable,
          ),
        );
      }
    }).toJS;
    return completer.future;
  }

  /// Creates the stores and indexes of version 18 in a new database, and the rows a new database of the JS SDK has
  /// (`createOrUpgrade` from version 0 of `indexeddb_schema_converter.ts`: the target metadata of version 3 and the
  /// document cache metadata of version 6). The stores that later versions dropped (`remoteDocuments`,
  /// `remoteDocumentChanges`) are not created.
  static void _createSchema(web.IDBDatabase db, web.IDBTransaction upgrade) {
    web.IDBObjectStoreParameters keyPath(Object path, {bool auto = false}) =>
        web.IDBObjectStoreParameters(
          keyPath: idbKey(path),
          autoIncrement: auto,
        );
    void index(
      web.IDBObjectStore store,
      String name,
      Object path, {
      bool unique = false,
    }) {
      store.createIndex(
        name,
        idbKey(path),
        web.IDBIndexParameters(unique: unique),
      );
    }

    // Version 1.
    db.createObjectStore(DbStores.owner);
    db.createObjectStore(
      DbStores.mutationQueues,
      keyPath(DbStores.mutationQueuesKeyPath),
    );
    index(
      db.createObjectStore(
        DbStores.mutations,
        keyPath(DbStores.mutationsKeyPath, auto: true),
      ),
      DbStores.mutationsUserIndex,
      DbStores.mutationsUserIndexPath,
      unique: true,
    );
    db.createObjectStore(DbStores.documentMutations);
    index(
      db.createObjectStore(
        DbStores.targetDocuments,
        keyPath(DbStores.targetDocumentsKeyPath),
      ),
      DbStores.targetDocumentsDocumentIndex,
      DbStores.targetDocumentsDocumentIndexPath,
      unique: true,
    );
    index(
      db.createObjectStore(DbStores.targets, keyPath(DbStores.targetsKeyPath)),
      DbStores.targetsQueryIndex,
      DbStores.targetsQueryIndexPath,
      unique: true,
    );
    db.createObjectStore(DbStores.targetGlobal);
    // Version 4.
    db.createObjectStore(
      DbStores.clientMetadata,
      keyPath(DbStores.clientMetadataKeyPath),
    );
    // Version 6.
    db.createObjectStore(DbStores.remoteDocumentGlobal);
    // Version 8.
    db.createObjectStore(
      DbStores.collectionParents,
      keyPath(DbStores.collectionParentsKeyPath),
    );
    // Version 11.
    db.createObjectStore(DbStores.bundles, keyPath(DbStores.bundlesKeyPath));
    db.createObjectStore(
      DbStores.namedQueries,
      keyPath(DbStores.namedQueriesKeyPath),
    );
    // Version 12.
    final web.IDBObjectStore overlays = db.createObjectStore(
      DbStores.documentOverlays,
      keyPath(DbStores.documentOverlaysKeyPath),
    );
    index(
      overlays,
      DbStores.documentOverlaysCollectionPathIndex,
      DbStores.documentOverlaysCollectionPathIndexPath,
    );
    index(
      overlays,
      DbStores.documentOverlaysCollectionGroupIndex,
      DbStores.documentOverlaysCollectionGroupIndexPath,
    );
    // Version 13.
    final web.IDBObjectStore remoteDocuments = db.createObjectStore(
      DbStores.remoteDocuments,
      keyPath(DbStores.remoteDocumentsKeyPath),
    );
    index(
      remoteDocuments,
      DbStores.remoteDocumentsDocumentKeyIndex,
      DbStores.remoteDocumentsDocumentKeyIndexPath,
    );
    index(
      remoteDocuments,
      DbStores.remoteDocumentsCollectionGroupIndex,
      DbStores.remoteDocumentsCollectionGroupIndexPath,
    );
    // Version 15.
    index(
      db.createObjectStore(
        DbStores.indexConfiguration,
        keyPath(DbStores.indexConfigurationKeyPath, auto: true),
      ),
      DbStores.indexConfigurationCollectionGroupIndex,
      DbStores.indexConfigurationCollectionGroupIndexPath,
    );
    index(
      db.createObjectStore(
        DbStores.indexState,
        keyPath(DbStores.indexStateKeyPath),
      ),
      DbStores.indexStateSequenceNumberIndex,
      DbStores.indexStateSequenceNumberIndexPath,
    );
    index(
      db.createObjectStore(
        DbStores.indexEntries,
        keyPath(DbStores.indexEntriesKeyPath),
      ),
      DbStores.indexEntriesDocumentKeyIndex,
      DbStores.indexEntriesDocumentKeyIndexPath,
    );
    // Version 17.
    db.createObjectStore(DbStores.globals, keyPath(DbStores.globalsKeyPath));

    // The rows of a new database (`writeEmptyTargetGlobalEntry`, `addDocumentGlobal`). The open request succeeds once
    // the upgrade transaction committed them.
    upgrade
        .objectStore(DbStores.targetGlobal)
        .put(
          idbToJs(
            IndexedDbQueryCache._metadataRow(0, 0, SnapshotVersion.none, 0),
          ),
          DbStores.targetGlobalKey.toJS,
        );
    upgrade
        .objectStore(DbStores.remoteDocumentGlobal)
        .put(
          idbToJs(<String, Object?>{'byteSize': 0}),
          DbStores.remoteDocumentGlobalKey.toJS,
        );
  }

  /// Another connection wants to delete or upgrade the database: let it (this connection would block it), and stop.
  void _onVersionChange(int? newVersion) {
    Log.w(
      tag,
      newVersion == null
          ? 'The IndexedDB cache $databaseName was deleted by another client (clearPersistence): this client stops.'
          : 'Another client upgrades the IndexedDB cache $databaseName to version $newVersion: this client stops.',
    );
    _fatalError ??= FirestoreException(
      message:
          'The IndexedDB cache $databaseName was deleted or upgraded by another client while this client was using it.',
      errorCode: FirestoreErrorCode.failedPrecondition,
    );
    _db?.close();
    final void Function()? listener = databaseClearedListener;
    databaseClearedListener = null;
    if (listener != null) {
      scheduleMicrotask(listener);
    }
  }

  // Transactions

  _IdbTransaction _begin(String action, [String mode = 'readwrite']) {
    final web.IDBDatabase? db = _db;
    if (db == null) {
      throw FirestoreException(
        message: 'The IndexedDB cache $databaseName is closed.',
        errorCode: FirestoreErrorCode.failedPrecondition,
      );
    }
    return _IdbTransaction(
      this,
      action,
      db.transaction(
        <JSString>[for (final String store in DbStores.all) store.toJS].toJS,
        mode,
      ),
    );
  }

  void _throwIfFailed() {
    final Object? fatal = _fatalError;
    if (fatal is Error) {
      throw fatal;
    } else if (fatal != null) {
      throw fatal as Exception;
    }
  }

  /// Fails every later transaction with [error].
  void _fail(IndexedDbTransactionInactiveError error) {
    if (_fatalError == null) {
      _fatalError = error;
      Log.e(tag, '$error');
    }
  }

  @override
  Future<void> runTransaction(String action, Transaction<void> operation) =>
      _runTransaction(action, operation, primary: false);

  @override
  Future<T> runTransactionAndReturn<T>(
    String action,
    Transaction<T> operation,
  ) => _runTransaction(action, operation, primary: false);

  @override
  Future<T> runPrimaryTransaction<T>(String action, Transaction<T> operation) =>
      _runTransaction(action, operation, primary: true);

  Future<T> _runTransaction<T>(
    String action,
    Transaction<T> operation, {
    required bool primary,
  }) async {
    beforeTransaction?.call(action);
    await _semaphore.acquire();
    try {
      _throwIfFailed();
      Log.d(tag, 'Starting transaction: $action');
      final _IdbTransaction transaction = _begin(action);
      try {
        if (_reloadState) {
          await _inTransaction(transaction, _reload);
          _reloadState = false;
        }
        await _verifyOwner(transaction);
        referenceDelegate.onTransactionStarted();
        final T result = await _inTransaction(transaction, operation);
        if (primary) {
          // After the operation, so that a long operation leaves a lease with a recent timestamp (as in the JS SDK).
          await _putLease(transaction);
        }
        transaction.checkNotFinished('the end of the operation');
        await transaction.commit();
        await referenceDelegate.onTransactionCommitted();
        return result;
      } catch (error) {
        referenceDelegate.onTransactionRolledBack();
        transaction.abort();
        _reloadState = true;
        if (error is IndexedDbTransactionInactiveError) {
          _fail(error);
        }
        rethrow;
      }
    } finally {
      _semaphore.release();
    }
  }

  /// Reads the state kept in memory again (the target metadata, the indexes and index states), after a transaction
  /// rolled back: it may have changed that state before it failed.
  Future<void> _reload() async {
    await queryCache._load();
    for (final IndexedDbIndexManager manager in _indexManagers.values) {
      if (manager._started) {
        await manager.start();
      }
    }
  }

  /// A transaction for the client metadata and the lease: no listen sequence number is used up.
  Future<T> _runMetadataTransaction<T>(
    String action,
    Future<T> Function(_IdbTransaction transaction) operation,
  ) async {
    await _semaphore.acquire();
    try {
      _throwIfFailed();
      final _IdbTransaction transaction = _begin(action);
      try {
        final T result = await operation(transaction);
        transaction.checkNotFinished('the end of the operation');
        await transaction.commit();
        return result;
      } catch (error) {
        transaction.abort();
        if (error is IndexedDbTransactionInactiveError) {
          _fail(error);
        }
        rethrow;
      }
    } finally {
      _semaphore.release();
    }
  }

  // The primary lease and the client metadata (single tab).

  bool _isZombied(Object? clientId) {
    if (clientId is! String) {
      return false;
    }
    try {
      return web.window.localStorage.getItem(
            indexedDbZombieKey(storagePrefix, clientId),
          ) !=
          null;
    } catch (_) {
      return false;
    }
  }

  void _setZombied(bool zombied) {
    try {
      final String key = indexedDbZombieKey(storagePrefix, clientId);
      if (zombied) {
        web.window.localStorage.setItem(key, '${_nowMs()}');
      } else {
        web.window.localStorage.removeItem(key);
      }
    } catch (e) {
      Log.d(tag, 'LocalStorage is not available: $e');
    }
  }

  /// The row of `owner`, or null when there is none.
  Future<Map<String, Object?>?> _readOwner(_IdbTransaction transaction) async {
    final Object? owner = idbToDart(
      await transaction.request(
        'get the primary lease',
        () => transaction.store(DbStores.owner).get(DbStores.ownerKey.toJS),
      ),
    );
    return owner is Map ? owner.cast<String, Object?>() : null;
  }

  /// Whether [owner] is a lease of another client that is valid (`currentLeaseIsValid` of the JS SDK): refreshed less
  /// than 5 s ago by a client that did not mark itself as closed in LocalStorage.
  bool _isOtherLiveLease(Map<String, Object?>? owner) =>
      owner != null &&
      owner['ownerId'] != clientId &&
      indexedDbIsWithinAge(
        owner['leaseTimestampMs'],
        indexedDbPrimaryLeaseMs,
        _nowMs(),
      ) &&
      !_isZombied(owner['ownerId']);

  Future<void> _putLease(_IdbTransaction transaction) async {
    await transaction.request(
      'put the primary lease',
      () => transaction
          .store(DbStores.owner)
          .put(
            idbToJs(<String, Object?>{
              'ownerId': clientId,
              // A single tab: a JS tab that finds this lease does not share the database (it fails with its
              // PRIMARY_LEASE_EXCLUSIVE_ERROR_MSG, or falls back to a memory cache).
              'allowTabSynchronization': false,
              'leaseTimestampMs': _nowMs(),
            }),
            DbStores.ownerKey.toJS,
          ),
    );
  }

  Future<void> _putClientMetadata(_IdbTransaction transaction) async {
    final bool inForeground = _inForeground;
    await transaction.request(
      'put the client metadata',
      () => transaction
          .store(DbStores.clientMetadata)
          .put(
            idbToJs(<String, Object?>{
              'clientId': clientId,
              'updateTimeMs': _nowMs(),
              'networkEnabled': _networkEnabled,
              'inForeground': inForeground,
            }),
          ),
    );
  }

  /// Checks that no other client uses the database, then takes the lease and writes this client's row, in one
  /// transaction (so two tabs that start at once can not both pass). As a JS tab with `persistentSingleTabManager`
  /// starts (`start` and `canActAsPrimary` of `indexeddb_persistence.ts`): it fails while another client holds a valid
  /// lease, whatever that client allows, and, when this tab is hidden or offline, while another client that refreshed
  /// its row less than 5 s ago is better placed to take the lease (in the foreground, or online).
  Future<void> _claim(_IdbTransaction transaction) async {
    final Map<String, Object?>? owner = await _readOwner(transaction);
    if (_isOtherLiveLease(owner)) {
      final bool multiTab = owner!['allowTabSynchronization'] == true;
      throw FirestoreException(
        message:
            '$_exclusiveErrorMessage (The primary lease of $databaseName is held by client ${owner['ownerId']}'
            '${multiTab ? ', a JS SDK tab with persistentMultipleTabManager' : ''}; it was refreshed less than '
            '${indexedDbPrimaryLeaseMs ~/ 1000} s ago.)',
        errorCode: FirestoreErrorCode.failedPrecondition,
      );
    }
    final int now = _nowMs();
    final List<Map<String, Object?>> clients = await _readClients(transaction);
    final bool inForeground = _inForeground;
    if (!(_networkEnabled && inForeground)) {
      for (final Map<String, Object?> other in clients) {
        final Object? id = other['clientId'];
        if (id == clientId ||
            !indexedDbIsWithinAge(
              other['updateTimeMs'],
              indexedDbPrimaryLeaseMs,
              now,
            ) ||
            _isZombied(id)) {
          continue;
        }
        final bool otherNetwork = other['networkEnabled'] == true;
        final bool otherForeground = other['inForeground'] == true;
        if ((!_networkEnabled && otherNetwork) ||
            (!inForeground &&
                otherForeground &&
                _networkEnabled == otherNetwork)) {
          throw FirestoreException(
            message:
                '$_exclusiveErrorMessage (Client $id of $databaseName is active and better placed to hold the '
                'primary lease: this tab is ${inForeground ? 'offline' : 'in the background'}.)',
            errorCode: FirestoreErrorCode.failedPrecondition,
          );
        }
      }
    }
    await _putClientMetadata(transaction);
    await _putLease(transaction);
    await _removeClients(transaction, _inactiveClients(clients, now));
    _lastClientGarbageCollectionMs = now;
  }

  bool get _inForeground {
    try {
      return web.document.visibilityState == 'visible';
    } catch (_) {
      // Not in a window (a worker): count as in the foreground.
      return true;
    }
  }

  Future<List<Map<String, Object?>>> _readClients(
    _IdbTransaction transaction,
  ) async {
    final List<Object?> rows =
        idbToDart(
              await transaction.request(
                'get all client metadata',
                () => transaction.store(DbStores.clientMetadata).getAll(),
              ),
            )!
            as List<Object?>;
    return <Map<String, Object?>>[
      for (final Object? row in rows)
        if (row is Map && row['clientId'] is String)
          row.cast<String, Object?>(),
    ];
  }

  /// The ids of the other clients that are no longer active (`filterActiveClients` with `MAX_CLIENT_AGE_MS`): their
  /// row is older than 30 minutes, or they marked themselves as closed.
  List<String> _inactiveClients(List<Map<String, Object?>> clients, int now) =>
      <String>[
        for (final Map<String, Object?> client in clients)
          if (client['clientId'] != clientId &&
              (!indexedDbIsWithinAge(
                    client['updateTimeMs'],
                    indexedDbMaxClientAgeMs,
                    now,
                  ) ||
                  _isZombied(client['clientId'])))
            client['clientId']! as String,
      ];

  /// Removes the rows of the inactive clients [ids] and their zombie marks (`maybeGarbageCollectMultiClientState`).
  Future<void> _removeClients(
    _IdbTransaction transaction,
    List<String> ids,
  ) async {
    await Future.wait(<Future<void>>[
      for (final String id in ids)
        transaction.request(
          'delete the metadata of client $id',
          () => transaction.store(DbStores.clientMetadata).delete(id.toJS),
        ),
    ]);
    for (final String id in ids) {
      try {
        web.window.localStorage.removeItem(
          indexedDbZombieKey(storagePrefix, id),
        );
      } catch (_) {
        // LocalStorage is not available.
      }
    }
  }

  /// Before an operation and before a refresh: this client must still be the owner of the lease it took at start.
  ///
  /// The lease of a tab in the background can lapse (the browser slows its timers down), and another client (a JS tab,
  /// or another tab of this SDK) may then have taken it and used the database. The JS SDK's single tab checks the
  /// lease the same way (`verifyAllowTabSynchronization`, `verifyPrimaryLease`). This client keeps state of the cache
  /// in memory (the target metadata, the indexes, the local store's targets), which the other client may have made
  /// stale, so it does not go on: it fails for good and terminates ([databaseClearedListener]), and a new instance
  /// starts over from the database. Nothing is written in the transaction that finds out.
  Future<void> _verifyOwner(_IdbTransaction transaction) async {
    final Map<String, Object?>? owner = await _readOwner(transaction);
    if (owner != null && owner['ownerId'] == clientId) {
      return;
    }
    final String holder = owner == null
        ? 'another client held it and released it'
        : _isOtherLiveLease(owner)
        ? 'client ${owner['ownerId']} holds it'
        : 'client ${owner['ownerId']} took it';
    final FirestoreException error = FirestoreException(
      message:
          '$_exclusiveErrorMessage (This client lost the primary lease of $databaseName: $holder. The other client may '
          'have changed the cache, so this instance stops; a new instance reads the cache again.)',
      errorCode: FirestoreErrorCode.failedPrecondition,
    );
    Log.e(tag, error.message);
    _fatalError ??= error;
    _setPrimary(false);
    final void Function()? listener = databaseClearedListener;
    databaseClearedListener = null;
    if (listener != null) {
      scheduleMicrotask(listener);
    }
    throw error;
  }

  void _setPrimary(bool primary) {
    if (isPrimary == primary) {
      return;
    }
    isPrimary = primary;
    _primaryStateListener?.call(primary);
  }

  @override
  void setPrimaryStateListener(PrimaryStateListener listener) {
    _primaryStateListener = (bool isPrimary) {
      if (started) {
        listener(isPrimary);
      }
    };
    listener(isPrimary);
  }

  @override
  Future<List<String>> getActiveClients() async {
    return _runMetadataTransaction<List<String>>('Get the active clients', (
      _IdbTransaction transaction,
    ) async {
      final int now = _nowMs();
      final List<Object?> clients =
          idbToDart(
                await transaction.request(
                  'get all client metadata',
                  () => transaction.store(DbStores.clientMetadata).getAll(),
                ),
              )!
              as List<Object?>;
      return <String>[
        for (final Object? client in clients)
          if (client is Map &&
              indexedDbIsWithinAge(
                client['updateTimeMs'],
                indexedDbMaxClientAgeMs,
                now,
              ) &&
              !_isZombied(client['clientId']))
            client['clientId']! as String,
      ];
    });
  }

  /// Refreshes this client's row and the lease (`updateClientMetadataAndTryBecomePrimary`), after checking that this
  /// client still owns the lease ([_verifyOwner]): a lease that lapsed while the tab was in the background is taken
  /// again when nobody else took it. Removes the rows of clients that are no longer active every 30 minutes.
  @override
  Future<void> refreshClientMetadata() async {
    if (!started) {
      return;
    }
    try {
      await _runMetadataTransaction<void>(
        'Update the client metadata and the primary lease',
        (_IdbTransaction transaction) async {
          await _verifyOwner(transaction);
          await _putClientMetadata(transaction);
          await _putLease(transaction);
          final int now = _nowMs();
          if (!indexedDbIsWithinAge(
            _lastClientGarbageCollectionMs,
            indexedDbMaxClientAgeMs,
            now,
          )) {
            _lastClientGarbageCollectionMs = now;
            await _removeClients(
              transaction,
              _inactiveClients(await _readClients(transaction), now),
            );
          }
        },
      );
    } on FirestoreException {
      rethrow;
    } on IndexedDbTransactionInactiveError {
      rethrow;
    } catch (e) {
      // As the JS SDK: proceed with the current state; the next transaction verifies the lease.
      Log.w(tag, 'Refreshing the client metadata failed: $e');
    }
  }

  @override
  Future<void> setNetworkEnabled(bool enabled) async {
    if (_networkEnabled != enabled) {
      _networkEnabled = enabled;
      await refreshClientMetadata();
    }
  }

  /// The JS SDK marks a client as closed in LocalStorage when its page is hidden for good (`pagehide`), so that the
  /// next page can take the lease at once; a page that comes back from the back/forward cache is alive again.
  void _attachPageHandlers() {
    try {
      final JSFunction hide = _pageHideHandler = ((web.Event _) {
        _setZombied(true);
      }).toJS;
      final JSFunction show = _pageShowHandler =
          ((web.PageTransitionEvent event) {
            if (event.persisted) {
              _setZombied(false);
            }
          }).toJS;
      web.window.addEventListener('pagehide', hide);
      web.window.addEventListener('pageshow', show);
    } catch (e) {
      Log.d(tag, 'No page events (not in a window): $e');
    }
  }

  void _detachPageHandlers() {
    try {
      final JSFunction? hide = _pageHideHandler;
      final JSFunction? show = _pageShowHandler;
      if (hide != null) {
        web.window.removeEventListener('pagehide', hide);
      }
      if (show != null) {
        web.window.removeEventListener('pageshow', show);
      }
    } catch (_) {
      // Not in a window.
    }
    _pageHideHandler = null;
    _pageShowHandler = null;
  }

  // Closing

  @override
  Future<void> shutdown() async {
    hardAssert(started, 'IndexedDbPersistence shutdown without start!');
    started = false;
    _detachPageHandlers();
    // As the JS SDK: marked as closed first, so that another tab may take over even if the release below does not
    // finish; the mark goes once the rows are gone.
    _setZombied(true);
    if (_fatalError == null) {
      try {
        await _runMetadataTransaction<void>('Shut down', (
          _IdbTransaction transaction,
        ) async {
          final Object? owner = idbToDart(
            await transaction.request(
              'get the primary lease',
              () =>
                  transaction.store(DbStores.owner).get(DbStores.ownerKey.toJS),
            ),
          );
          if (owner is Map && owner['ownerId'] == clientId) {
            await transaction.request(
              'release the primary lease',
              () => transaction
                  .store(DbStores.owner)
                  .delete(DbStores.ownerKey.toJS),
            );
          }
          await transaction.request(
            'delete the client metadata',
            () => transaction
                .store(DbStores.clientMetadata)
                .delete(clientId.toJS),
          );
        });
        _setZombied(false);
      } catch (e) {
        Log.w(tag, 'Could not release the primary lease: $e');
      }
    }
    await _semaphore.acquire();
    try {
      _db?.close();
      _db = null;
    } finally {
      _semaphore.release();
    }
  }

  @override
  Future<void> clearPersistence() async {
    hardAssert(!started, 'IndexedDbPersistence cleared while running!');
    try {
      await idbRequest(web.window.indexedDB.deleteDatabase(databaseName));
    } catch (e) {
      throw FirestoreException(
        message: 'Failed to clear persistence: $e',
        errorCode: FirestoreErrorCode.unknown,
        cause: e,
      );
    }
  }
}
