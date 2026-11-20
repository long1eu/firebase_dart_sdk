import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/local/keyvalue/cache_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/keyvalue/cache_store_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/database.dart';
import 'package:test/test.dart';

import '../../../../../example/cache_store/memory_log/memory_log_store.dart';
import '../../../../util/test_util.dart';

/// [CacheStorePersistence] over a store that is not available for a while. The counterpart of
/// sqlite_persistence_recovery_test.dart (the `IndexedDbTransactionError` tests of the JS SDK): every error of the
/// store is a [TransientDatabaseException] of the persistence, which is recoverable.
void main() {
  late _FailingStore store;
  late CacheStorePersistence persistence;

  CacheStorePersistence create() {
    final DatabaseId databaseId = DatabaseId.forProject('projectId');
    return CacheStorePersistence(
      store,
      databaseId: databaseId,
      serializer: LocalSerializer(RemoteSerializer(databaseId)),
      lruParams: const LruGarbageCollectorParams(),
    );
  }

  setUp(() => store = _FailingStore(MemoryLogStore()));

  test('a transaction that fails transiently can be run again', () async {
    persistence = create();
    await persistence.start();

    store.failing = true;
    final Object error = await persistence
        .runTransaction('Simulated', () async {
          await persistence.remoteDocumentCache.get(key('coll/doc'));
        })
        .then<Object>((_) => 'no error', onError: (Object e) => e);
    expect(error, isA<TransientDatabaseException>());
    expect(isRecoverablePersistenceError(error), isTrue);

    store.failing = false;
    await persistence.runTransaction('check success', () async {
      await persistence.remoteDocumentCache.get(key('coll/doc'));
    });
    await persistence.shutdown();
  });

  test('a write that fails transiently is not applied', () async {
    persistence = create();
    await persistence.start();

    store.failing = true;
    final Object error = await persistence
        .runTransaction('Simulated', () async {
          await persistence.remoteDocumentCache.add(
            doc('coll/doc', 1, map(<dynamic>['a', 1])),
            version(1),
          );
        })
        .then<Object>((_) => 'no error', onError: (Object e) => e);
    expect(error, isA<TransientDatabaseException>());
    expect(isRecoverablePersistenceError(error), isTrue);

    store.failing = false;
    expect(await persistence.remoteDocumentCache.get(key('coll/doc')), isNull);
    await persistence.shutdown();
  });

  // The counterpart of review_leftovers_test.dart, "M10: a failed collection parent INSERT is not cached".
  test('a collection parent of a failed write is not cached', () async {
    persistence = create();
    await persistence.start();

    store.failing = true;
    await expectLater(
      persistence.runTransaction('Simulated', () {
        return persistence.indexManager.addToCollectionParentIndex(
          path('a/b/c'),
        );
      }),
      throwsA(isA<TransientDatabaseException>()),
    );

    // The entry was not cached, so adding it again writes it.
    store.failing = false;
    await persistence.runTransaction('add again', () {
      return persistence.indexManager.addToCollectionParentIndex(path('a/b/c'));
    });
    await persistence.shutdown();

    final CacheStorePersistence again = create();
    await again.start();
    expect(await again.indexManager.getCollectionParents('c'), <Object>[
      path('a/b'),
    ]);
    await again.shutdown();
  });

  test('blocks start() on a transient error of the store', () async {
    store.failing = true;
    persistence = create();
    await expectLater(
      persistence.start(),
      throwsA(isA<TransientDatabaseException>()),
    );
    // A persistence whose start failed is not started (it can not be shut down) and has closed its store.
    expect(persistence.started, isFalse);
    expect(store.closed, isTrue);

    // The store is free again: a new persistence starts on it.
    store.failing = false;
    persistence = create();
    await persistence.start();
    await persistence.shutdown();
  });
}

/// A [CacheStore] that throws for every read and write while [failing], as a store that is locked by another process
/// or can not be written does.
class _FailingStore implements CacheStore {
  _FailingStore(this._delegate);

  final CacheStore _delegate;
  bool failing = false;

  /// Whether the store is closed (it is when it was never opened).
  bool closed = true;

  void _check() {
    if (failing) {
      throw StateError('Simulated error');
    }
  }

  @override
  Future<void> open() async {
    await _delegate.open();
    closed = false;
  }

  @override
  Future<void> close() async {
    closed = true;
    await _delegate.close();
  }

  @override
  Future<Uint8List?> get(Uint8List key) async {
    _check();
    return _delegate.get(key);
  }

  @override
  Future<List<CacheStoreEntry>> scan(
    Uint8List start,
    Uint8List end, {
    bool reverse = false,
    int? limit,
  }) async {
    _check();
    return _delegate.scan(start, end, reverse: reverse, limit: limit);
  }

  @override
  Future<void> write(
    List<CacheStoreEntry> puts,
    List<Uint8List> deletes,
  ) async {
    _check();
    await _delegate.write(puts, deletes);
  }
}
