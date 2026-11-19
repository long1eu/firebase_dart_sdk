// A queue written with `mergeUnsentWrites` off is merged when the next instance on the same cache has it on, before
// anything is sent, and the backend ends with the same documents as without the merge.

import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/internal_access.dart';
import 'package:firebase_app_dart/internal.dart' show InternalLogLevel;
import 'package:test/test.dart';

import '../../../unit/firebase/firestore/local/mock/database_mock.dart';
import '../../../util/integration_test_util.dart';

void main() {
  tearDown(() => IntegrationTestUtil.tearDown());

  Settings settings({required bool merge}) =>
      IntegrationTestUtil.newTestSettings().copyWith(
        cacheSettings: PersistentCacheSettings(mergeUnsentWrites: merge),
      );

  /// Queues edits of 20 documents with the setting off, then opens the cache again with [mergeAtStart] and sends them.
  Future<(Map<String, Object?>, int)> run({required bool mergeAtStart}) async {
    final String path =
        'integration/merge_queued_${mergeAtStart}_${DateTime.now().microsecondsSinceEpoch}';
    final String collectionPath =
        'merge_queued_${DateTime.now().microsecondsSinceEpoch}';
    Future<FirebaseFirestore> open({required bool merge}) =>
        IntegrationTestUtil.testFirestoreInstance(
          IntegrationTestUtil.provider.projectId,
          InternalLogLevel.w,
          settings(merge: merge),
          path,
          fixedDbName: '$path.db',
        );
    addTearDown(() => DatabaseMock.deleteDatabaseFiles('$path.db'));
    FirebaseFirestore firestore = await open(merge: false);
    await firestore.disableNetwork();
    CollectionReference collection = firestore.collection(collectionPath);
    for (int edit = 0; edit < 50; edit++) {
      for (int i = 0; i < 20; i++) {
        final DocumentReference ref = collection.doc('doc$i');
        unawaited(
          (edit == 0
                  ? ref.set(<String, Object?>{'title': 'new', 'edits': 0})
                  : ref.update(<String, Object?>{
                      'title': 'edit $edit',
                      'field${edit % 7}': edit,
                      'edits': edit,
                      'tags': FieldValue.arrayUnion(<Object?>[edit % 5]),
                      'updatedAt': FieldValue.serverTimestamp(),
                    }))
              .catchError((Object _) {}),
        );
      }
    }
    await collection.limit(1).get(const GetOptions(source: Source.cache));
    expect(await firestore.getPendingWriteCount(), 1000);
    await firestore.terminate();

    firestore = await open(merge: mergeAtStart);
    // The cache is the one of the first instance. Nothing is sent before the merge ends, and after it at most the
    // writes that do not merge are left: here the first set of each document and one merged update.
    await firestore.client.queuedWritesMerged;
    expect(
      await firestore.getPendingWriteCount(),
      mergeAtStart ? lessThanOrEqualTo(40) : greaterThan(900),
    );
    // The instance starts with the network on: the merge must come before the first write is sent.
    await firestore.waitForPendingWrites();
    collection = firestore.collection(collectionPath);
    final QuerySnapshot snapshot = await collection.get(
      const GetOptions(source: Source.server),
    );
    final AggregateQuerySnapshot versions = await collection.count().get();
    expect(versions.count, 20);
    return (
      <String, Object?>{
        for (final QueryDocumentSnapshot doc in snapshot.docs)
          doc.id: (Map<String, Object?>.of(
            doc.data(),
          )..remove('updatedAt')).toString(),
      },
      snapshot.docs
          .where((QueryDocumentSnapshot doc) => doc['updatedAt'] is Timestamp)
          .length,
    );
  }

  test(
    'a queue of an earlier session is merged before it is sent',
    () async {
      final Stopwatch watch = Stopwatch()..start();
      final (Map<String, Object?> merged, int mergedTimes) = await run(
        mergeAtStart: true,
      );
      final Duration withMerge = watch.elapsed;
      watch.reset();
      final (Map<String, Object?> separate, int separateTimes) = await run(
        mergeAtStart: false,
      );
      printOnFailure('with the merge $withMerge, without ${watch.elapsed}');
      expect(merged, separate);
      expect(mergedTimes, 20);
      expect(separateTimes, 20);
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
