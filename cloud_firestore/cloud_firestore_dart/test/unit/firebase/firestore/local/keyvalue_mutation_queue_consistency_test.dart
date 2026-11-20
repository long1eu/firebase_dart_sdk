import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/mutation_queue.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/keyvalue/cache_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/keyvalue/cache_store_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/keyvalue/kv_codec.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../../../example/cache_store/memory_log/memory_log_store.dart';
import '../../../../util/test_util.dart';
import 'persistence_test_helpers.dart';

void main() {
  late MemoryLogStore store;
  late CacheStorePersistence persistence;
  late MutationQueue queue;

  setUp(() async {
    store = MemoryLogStore();
    persistence = await createKeyValuePersistence(store: store);
    queue = persistence.getMutationQueue(const User('alice'));
    await persistence.runTransaction('start', queue.start);
  });

  tearDown(() => persistence.shutdown());

  Future<void> addDanglingReference(String uid, String path) {
    return persistence.runTransaction('insert dangling reference', () async {
      // A `docMut` entry of the layout of the cache, for a batch that does not exist.
      await store.write(<CacheStoreEntry>[
        CacheStoreEntry(
          KvKeyWriter()
              .string('docMut')
              .string(uid)
              .documentKey(key(path))
              .integer(99)
              .bytes,
          Uint8List(0),
        ),
      ], <Uint8List>[]);
    });
  }

  Future<void> check() => persistence.runTransaction(
    'consistency check',
    queue.performConsistencyCheck,
  );

  test('an empty queue without references is consistent', () async {
    await check();
  });

  test(
    'an empty queue with a document_mutations row names the leaked key',
    () async {
      await addDanglingReference('alice', 'rooms/eros');
      await expectLater(
        check(),
        throwsA(
          isA<AssertionError>().having(
            (AssertionError e) => e.message,
            'message',
            allOf(contains('Document leak'), contains('rooms/eros')),
          ),
        ),
      );
    },
  );

  test('references of another user are not this queue\'s leak', () async {
    await addDanglingReference('bob', 'rooms/eros');
    await check();
  });

  test('a non-empty queue is not checked', () async {
    await persistence.runTransaction('write', () async {
      final MutationBatch batch = await queue.addMutationBatch(
        Timestamp.now(),
        <Mutation>[],
        <Mutation>[
          setMutation('rooms/a', map(<Object>['v', 1])),
        ],
      );
      expect(batch.batchId, isNonNegative);
    });
    await addDanglingReference('alice', 'rooms/eros');
    await check();
  });
}
