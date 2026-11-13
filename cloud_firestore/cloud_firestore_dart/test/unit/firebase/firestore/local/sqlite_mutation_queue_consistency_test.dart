import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/encoded_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/mutation_queue.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/reference_set.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';
import 'persistence_test_helpers.dart';

void main() {
  late SQLitePersistence persistence;
  late MutationQueue queue;

  setUp(() async {
    persistence = await createSQLitePersistence();
    persistence.referenceDelegate.inMemoryPins = ReferenceSet();
    queue = persistence.getMutationQueue(const User('alice'));
    await persistence.runTransaction('start', queue.start);
  });

  tearDown(() => persistence.shutdown());

  Future<void> addDanglingReference(String uid, String path) {
    return persistence.runTransaction('insert dangling reference', () async {
      await persistence.database.execute(
        'INSERT INTO document_mutations (uid, path, batch_id) VALUES (?, ?, ?)',
        <Object>[uid, EncodedPath.encode(key(path).path), 99],
      );
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
