// The targets of a persistent cache are found again after a restart, also for
// queries whose canonical id contains a timestamp or a document reference.
// The canonical id is the key of the stored target: a client that does not
// find the target listens from scratch and downloads the results again,
// instead of resuming with the stored resume token.

import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/target.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart'
    show FirestoreInternal;
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query.dart'
    show QueryInternal;
import 'package:firebase_app_dart/internal.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../../unit/firebase/firestore/local/mock/database_mock.dart';
import '../../../util/integration_test_util.dart';

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/target_reuse';

  tearDown(() => IntegrationTestUtil.tearDown());

  test('a restarted client reuses the targets of queries with timestamp and '
      'reference filters', () async {
    final String dbName = 'integration/target_reuse/${const Uuid().v4()}.db';
    DatabaseMock.deleteDatabaseFiles(dbName);
    addTearDown(() => DatabaseMock.deleteDatabaseFiles(dbName));
    final String name = 'target-reuse-${const Uuid().v4()}';

    Future<Firestore> open() => IntegrationTestUtil.testFirestoreInstance(
      IntegrationTestUtil.provider.projectId,
      InternalLogLevel.w,
      IntegrationTestUtil.newTestSettings(),
      IntegrationTestUtil.currentDatabasePath,
      fixedDbName: dbName,
    );

    Map<String, Query<Map<String, Object?>>> queries(Firestore db) {
      final CollectionReference<Map<String, Object?>> rooms = db.collection(
        name,
      );
      return <String, Query<Map<String, Object?>>>{
        'timestamp': rooms.where(
          'at',
          isLessThanOrEqualTo: const Timestamp(60, 3000),
        ),
        'reference': rooms.where('owner', isEqualTo: db.doc('users/eros')),
        'both': rooms
            .where('owner', isEqualTo: db.doc('users/eros'))
            .where('at', isGreaterThan: const Timestamp(10, 0))
            .orderBy('at', Direction.descending)
            .limit(5),
      };
    }

    const Map<String, List<String>> expectedDocs = <String, List<String>>{
      'timestamp': <String>['a', 'b'],
      'reference': <String>['a', 'c'],
      'both': <String>['c', 'a'],
    };

    Future<QuerySnapshot<Map<String, Object?>>> firstSynced(
      Query<Map<String, Object?>> query,
    ) => query
        .getSnapshots(MetadataChanges.include)
        .firstWhere(
          (QuerySnapshot<Map<String, Object?>> s) => !s.metadata.isFromCache,
        )
        .timeout(const Duration(seconds: 20));

    List<String> ids(QuerySnapshot<Map<String, Object?>> snapshot) => snapshot
        .docs
        .map((QueryDocumentSnapshot<Map<String, Object?>> d) => d.id)
        .toList();

    Future<QueryData?> stored(Firestore db, Query<Object?> query) =>
        db.client.localStore.getQueryData(query.query.toTarget());

    // First run: write the documents and listen to the queries.
    Firestore db = await open();
    await db.collection(name).doc('a').set(<String, Object?>{
      'at': const Timestamp(20, 0),
      'owner': db.doc('users/eros'),
    });
    await db.collection(name).doc('b').set(<String, Object?>{
      'at': const Timestamp(60, 3000),
      'owner': db.doc('users/hades'),
    });
    await db.collection(name).doc('c').set(<String, Object?>{
      'at': const Timestamp(61, 0),
      'owner': db.doc('users/eros'),
    });

    final Map<String, QueryData> before = <String, QueryData>{};
    final Map<String, Target> targets = <String, Target>{};
    for (final MapEntry<String, Query<Map<String, Object?>>> entry in queries(
      db,
    ).entries) {
      expect(
        ids(await firstSynced(entry.value)),
        expectedDocs[entry.key],
        reason: entry.key,
      );
      // Let the resume token of the target reach the cache.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final QueryData queryData = (await stored(db, entry.value))!;
      expect(queryData.resumeToken, isNotEmpty, reason: entry.key);
      before[entry.key] = queryData;
      targets[entry.key] = entry.value.query.toTarget();
    }
    // The ids are the ones of the JS SDK, without any toString output.
    expect(
      targets['timestamp']!.canonicalId,
      '$name|f:at<=time(60,3000)|ob:atasc,__name__asc',
    );
    expect(
      targets['reference']!.canonicalId,
      '$name|f:owner==users/eros|ob:__name__asc',
    );
    expect(
      targets['both']!.canonicalId,
      '$name|f:owner==users/eros,at>time(10,0)|ob:atdesc,__name__desc|l:5',
    );
    await db.terminate();

    // Second run, with the same cache.
    db = await open();
    for (final MapEntry<String, Query<Map<String, Object?>>> entry in queries(
      db,
    ).entries) {
      // The stored target is found by its canonical id, with its resume token.
      final QueryData? found = await stored(db, entry.value);
      expect(found, isNotNull, reason: entry.key);
      expect(found!.targetId, before[entry.key]!.targetId, reason: entry.key);
      expect(found.resumeToken, isNotEmpty, reason: entry.key);
      expect(
        found.snapshotVersion,
        before[entry.key]!.snapshotVersion,
        reason: entry.key,
      );

      // The first snapshot comes from the cache with the documents of the
      // target, before the backend answered.
      final Completer<QuerySnapshot<Map<String, Object?>>> first =
          Completer<QuerySnapshot<Map<String, Object?>>>();
      final Completer<QuerySnapshot<Map<String, Object?>>> synced =
          Completer<QuerySnapshot<Map<String, Object?>>>();
      final StreamSubscription<QuerySnapshot<Map<String, Object?>>> sub = entry
          .value
          .getSnapshots(MetadataChanges.include)
          .listen((QuerySnapshot<Map<String, Object?>> snapshot) {
            if (!first.isCompleted) {
              first.complete(snapshot);
            }
            if (!snapshot.metadata.isFromCache && !synced.isCompleted) {
              synced.complete(snapshot);
            }
          });
      final QuerySnapshot<Map<String, Object?>> cached = await first.future
          .timeout(const Duration(seconds: 20));
      expect(cached.metadata.isFromCache, isTrue, reason: entry.key);
      expect(ids(cached), expectedDocs[entry.key], reason: entry.key);
      expect(
        ids(await synced.future.timeout(const Duration(seconds: 20))),
        expectedDocs[entry.key],
        reason: entry.key,
      );
      await sub.cancel();

      // Listening did not allocate another target for the query.
      final QueryData after = (await stored(db, entry.value))!;
      expect(after.targetId, before[entry.key]!.targetId, reason: entry.key);
    }

    // The cache still has exactly the three targets.
    final List<int> targetIds = <int>[];
    await db.client.persistence.runTransaction('count targets', () async {
      await db.client.persistence.queryCache.forEachTarget(
        (QueryData queryData) => targetIds.add(queryData.targetId),
      );
    });
    expect(
      targetIds.toSet(),
      before.values.map((QueryData q) => q.targetId).toSet(),
    );
    await db.terminate();
  });
}
