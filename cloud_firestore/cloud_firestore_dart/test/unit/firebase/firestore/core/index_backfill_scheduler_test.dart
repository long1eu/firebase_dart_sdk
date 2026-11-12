import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart'
    show DocumentSnapshot, MemoryCacheSettings, QuerySnapshot, Source;
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/empty_credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart'
    as core;
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_settings.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/index_backfiller.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/memory/memory_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/index_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/database.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../../../util/index_helpers.dart';
import '../../../../util/integration_test_util.dart';
import '../../../../util/test_util.dart' show filter, key, path;
import '../local/mock/database_mock.dart';

/// A client on an unreachable host: writes stay pending, queries are served from the cache.
Future<Firestore> open(FirestoreSettings settings, TaskScheduler scheduler,
    {MockCredentialsProvider? credentials}) {
  final String dbPath =
      '${Directory.systemTemp.path}/index_backfill_${const Uuid().v4()}.db';
  addTearDown(() => DatabaseMock.deleteDatabaseFiles(dbPath));
  return IntegrationTestUtil.forTests(
    DatabaseId.forDatabase('index-test', DatabaseId.defaultDatabaseId),
    'index-test-key',
    credentials ?? EmptyCredentialsProvider(),
    scheduler,
    (String p,
        {int? version,
        OnConfigure? onConfigure,
        OnCreate? onCreate,
        OnVersionChange? onUpgrade,
        OnVersionChange? onDowngrade,
        OnOpen? onOpen}) async {
      final DatabaseMock db = await DatabaseMock.create(dbPath,
          version: version,
          onConfigure: onConfigure,
          onCreate: onCreate,
          onUpgrade: onUpgrade,
          onDowngrade: onDowngrade,
          onOpen: onOpen);
      db.renamePath = false;
      return db;
    },
    settings,
  );
}

final FirestoreSettings offline =
    FirestoreSettings().withEmulator('127.0.0.1', 1);

/// Runs the scheduled backfill now and waits until it rescheduled itself (which it does when the run is over).
Future<void> runBackfill(TaskScheduler scheduler) async {
  final TimerTask? before = scheduler.getTask(TaskId.indexBackfill);
  expect(before, isNotNull);
  scheduler.runUntil(TaskId.indexBackfill);
  for (int i = 0; i < 200; i++) {
    final TimerTask? task = scheduler.getTask(TaskId.indexBackfill);
    if (task != null && !identical(task, before)) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('The index backfill did not reschedule itself');
}

void main() {
  test('the index backfill is scheduled with SQLite persistence', () async {
    final TaskScheduler scheduler = TaskScheduler('');
    final Firestore firestore = await open(offline, scheduler);
    expect(scheduler.getTask(TaskId.indexBackfill), isNotNull);
    await firestore.terminate();
    expect(scheduler.getTask(TaskId.indexBackfill), isNull);
  });

  test('the index backfill is not scheduled with memory persistence', () async {
    final TaskScheduler scheduler = TaskScheduler('');
    final Firestore firestore = await open(
        offline.copyWith(cacheSettings: const MemoryCacheSettings()),
        scheduler);
    expect(scheduler.getTask(TaskId.indexBackfill), isNull);
    await firestore.terminate();
  });

  test(
      'a scheduled run fills the configured indexes and the next one is scheduled',
      () async {
    final TaskScheduler scheduler = TaskScheduler('');
    final Firestore firestore = await open(offline, scheduler);
    addTearDown(firestore.terminate);
    final LocalStore localStore = firestore.client.localStore;

    await localStore.configureFieldIndexes(<FieldIndex>[
      fieldIndex('coll', fieldsAndKinds: <Object>['a', SegmentKind.ascending])
    ]);
    firestore.doc('coll/one').set(<String, Object?>{'a': 1}).ignore();
    firestore.doc('coll/two').set(<String, Object?>{'a': 2}).ignore();
    firestore.doc('coll/other').set(<String, Object?>{'b': 2}).ignore();
    // The writes are in the local store once a cache read sees them.
    final DocumentSnapshot<Map<String, Object?>> written =
        await firestore.doc('coll/other').get(Source.cache);
    expect(written.exists, isTrue);

    final IndexManager indexManager = localStore.indexManagerForCurrentUser;
    final core.Query query =
        core.Query(path('coll')).filter(filter('a', '>=', 1));
    expect(await indexManager.getDocumentsMatchingTarget(query.toTarget()),
        isEmpty);
    expect(indexManager.getFieldIndexes('coll').single.indexState,
        FieldIndex.initialState);

    await runBackfill(scheduler);

    expect(await indexManager.getDocumentsMatchingTarget(query.toTarget()),
        <DocumentKey>[key('coll/one'), key('coll/two')]);
    final IndexState state =
        indexManager.getFieldIndexes('coll').single.indexState;
    expect(state.sequenceNumber, 1);
    // Three pending writes were processed.
    expect(state.offset.largestBatchId, greaterThanOrEqualTo(1));

    // The public API returns the same documents, now through the index.
    final QuerySnapshot<Map<String, Object?>> snapshot = await firestore
        .collection('coll')
        .whereGreaterThanOrEqualTo('a', 1)
        .get(Source.cache);
    expect(snapshot.docs.map((DocumentSnapshot<Object?> d) => d.id).toList(),
        <String>['one', 'two']);

    // A document written after the backfill is found before the next run.
    firestore.doc('coll/three').set(<String, Object?>{'a': 3}).ignore();
    final QuerySnapshot<Map<String, Object?>> withNew = await firestore
        .collection('coll')
        .whereGreaterThanOrEqualTo('a', 1)
        .get(Source.cache);
    expect(withNew.docs.map((DocumentSnapshot<Object?> d) => d.id).toList(),
        <String>['one', 'two', 'three']);

    await runBackfill(scheduler);
    expect(await indexManager.getDocumentsMatchingTarget(query.toTarget()),
        <DocumentKey>[key('coll/one'), key('coll/two'), key('coll/three')]);
  });

  test('a run with nothing to do reschedules itself', () async {
    final TaskScheduler scheduler = TaskScheduler('');
    final Firestore firestore = await open(offline, scheduler);
    addTearDown(firestore.terminate);

    // No index is configured.
    await runBackfill(scheduler);
    await runBackfill(scheduler);
    expect(scheduler.getTask(TaskId.indexBackfill), isNotNull);
  });

  test('a run that fails does not stop the schedule, stop() does', () async {
    final TaskScheduler scheduler = TaskScheduler('');
    final MemoryPersistence persistence =
        MemoryPersistence.createEagerGcMemoryPersistence();
    int runs = 0;
    final IndexBackfillerScheduler backfillScheduler = IndexBackfillerScheduler(
      IndexBackfiller.forTesting(persistence, () => persistence.indexManager,
          () => throw StateError('not used')),
      scheduler,
      run: (Future<int> Function() backfill) async {
        runs++;
        throw StateError('the database is closed');
      },
    )..start();

    await runBackfill(scheduler);
    await runBackfill(scheduler);
    expect(runs, 2);

    backfillScheduler.stop();
    expect(scheduler.getTask(TaskId.indexBackfill), isNull);
  });

  test('index state and entries follow the user', () async {
    final TaskScheduler scheduler = TaskScheduler('');
    final MockCredentialsProvider credentials = MockCredentialsProvider();
    final Firestore firestore =
        await open(offline, scheduler, credentials: credentials);
    addTearDown(firestore.terminate);
    final LocalStore localStore = firestore.client.localStore;

    await localStore.configureFieldIndexes(<FieldIndex>[
      fieldIndex('coll', fieldsAndKinds: <Object>['a', SegmentKind.ascending])
    ]);
    firestore.doc('coll/anonymous').set(<String, Object?>{'a': 1}).ignore();
    await firestore.doc('coll/anonymous').get(Source.cache);
    await runBackfill(scheduler);

    final IndexManager anonymousManager = localStore.indexManagerForCurrentUser;
    final core.Query query =
        core.Query(path('coll')).filter(filter('a', '>=', 1));
    expect(await anonymousManager.getDocumentsMatchingTarget(query.toTarget()),
        <DocumentKey>[key('coll/anonymous')]);

    credentials.changeUserTo(const User('alice'));
    // The user change is applied asynchronously, on the queue of the client.
    for (int i = 0;
        i < 200 &&
            identical(localStore.indexManagerForCurrentUser, anonymousManager);
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    QuerySnapshot<Map<String, Object?>> snapshot = await firestore
        .collection('coll')
        .whereGreaterThanOrEqualTo('a', 1)
        .get(Source.cache);
    // The pending write of the other user is not visible to alice.
    expect(snapshot.docs, isEmpty);

    final IndexManager aliceManager = localStore.indexManagerForCurrentUser;
    expect(identical(aliceManager, anonymousManager), isFalse);
    // The index is configured for every user, alice has not backfilled it yet.
    expect(aliceManager.getFieldIndexes('coll').single.indexState,
        FieldIndex.initialState);
    expect(await aliceManager.getDocumentsMatchingTarget(query.toTarget()),
        isEmpty);

    firestore.doc('coll/alice').set(<String, Object?>{'a': 5}).ignore();
    await firestore.doc('coll/alice').get(Source.cache);
    await runBackfill(scheduler);
    expect(await aliceManager.getDocumentsMatchingTarget(query.toTarget()),
        <DocumentKey>[key('coll/alice')]);

    snapshot = await firestore
        .collection('coll')
        .whereGreaterThanOrEqualTo('a', 1)
        .get(Source.cache);
    expect(snapshot.docs.map((DocumentSnapshot<Object?> d) => d.id).toList(),
        <String>['alice']);
  });
}
