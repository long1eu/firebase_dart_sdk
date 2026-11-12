// Copyright 2021 Google LLC
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

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore_vm/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/bundle/bundle_reader.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/bundle/bundle_serializer.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/bundle/bundled_query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/bundle/named_query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/online_state.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/sync_engine.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/load_bundle_task.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/load_bundle_task_progress.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/no_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/remote_store.dart';
import 'package:grpc/grpc.dart';
import 'package:mockito/mockito.dart' show Fake;
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../../../util/test_util.dart';
import '../local/persistence_test_helpers.dart';
import 'test_bundle_builder.dart';

class _FakeRemoteStore extends Fake implements RemoteStore {
  @override
  Future<void> listen(QueryData queryData) async {}
}

class _RecordingCallback implements SyncEngineCallback {
  final List<ViewSnapshot> snapshots = <ViewSnapshot>[];

  @override
  Future<void> onViewSnapshots(List<ViewSnapshot> snapshotList) async {
    snapshots.addAll(snapshotList);
  }

  @override
  void onError(Query query, GrpcError error) {}

  @override
  void handleOnlineStateChange(OnlineState onlineState) {}
}

/// Loads bundles through the [SyncEngine] into a [LocalStore], with the memory and the SQLite persistence.
///
/// The Android SDK covers this in the spec tests (`bundle_spec_test.json`) and in the emulator tests, which are not
/// available here.
void main() {
  // The persistences of the test helpers use this project.
  final DatabaseId databaseId = DatabaseId.forProject('projectId');
  final BundleSerializer serializer =
      BundleSerializer(RemoteSerializer(databaseId));

  final Map<String, Future<Persistence> Function()> persistences =
      <String, Future<Persistence> Function()>{
    'memory': createEagerGCMemoryPersistence,
    'sqlite': () => createSQLitePersistence(
        'firebase/firestore/bundle/bundle_load_test-${const Uuid().v4()}.db'),
  };

  persistences.forEach((String name, Future<Persistence> Function() create) {
    group(name, () {
      late Persistence persistence;
      late LocalStore localStore;
      late SyncEngine syncEngine;
      late _RecordingCallback callback;

      setUp(() async {
        persistence = await create();
        localStore = LocalStore(persistence, User.unauthenticated);
        await localStore.start();
        syncEngine =
            SyncEngine(localStore, _FakeRemoteStore(), User.unauthenticated);
        callback = _RecordingCallback();
        syncEngine.syncEngineListener = callback;
      });

      tearDown(() => persistence.shutdown());

      String bundleWithQueryAndDocuments({int createTimeMicros = 6000000}) {
        final TestBundleBuilder builder = TestBundleBuilder(databaseId)
          ..addNamedQuery('coll-query', 5000000, BundledQueryLimitType.first,
              '', <String, dynamic>{
            'from': <Object?>[
              <String, dynamic>{'collectionId': 'coll'}
            ],
            'orderBy': <Object?>[
              <String, dynamic>{
                'field': <String, dynamic>{'fieldPath': '__name__'}
              }
            ],
          })
          ..addDocumentMetadata(
              'coll/doc1', 5600000, true, <String>['coll-query'])
          ..addDocument('coll/doc1', 1200000, 5600000, <String, dynamic>{
            'foo': <String, dynamic>{'stringValue': 'value1'},
          })
          ..addDocumentMetadata(
              'coll/deleted', 5600001, false, <String>['coll-query']);
        return builder.build('bundle-1', createTimeMicros, 1);
      }

      Future<LoadBundleTask> load(String bundle, {int? chunkSize}) async {
        final List<int> bytes = utf8.encode(bundle);
        final Stream<List<int>> stream = chunkSize == null
            ? Stream<List<int>>.value(bytes)
            : Stream<List<int>>.fromIterable(<List<int>>[
                for (int i = 0; i < bytes.length; i += chunkSize)
                  bytes.sublist(
                      i,
                      i + chunkSize > bytes.length
                          ? bytes.length
                          : i + chunkSize)
              ]);
        final LoadBundleTask task = LoadBundleTask();
        await syncEngine.loadBundle(BundleReader(serializer, stream), task);
        return task;
      }

      test('loads documents and named queries into the local store', () async {
        final String bundle = bundleWithQueryAndDocuments();
        final LoadBundleTask task = await load(bundle, chunkSize: 100);

        expect(task.isComplete, isTrue);
        expect(task.isSuccessful, isTrue);
        final LoadBundleTaskProgress result = await task.future;
        expect(result.taskState, LoadBundleTaskState.success);
        expect(result.documentsLoaded, 2);
        expect(result.totalDocuments, 2);
        expect(result.bytesLoaded, result.totalBytes);

        expect(await localStore.readDocument(key('coll/doc1')),
            doc('coll/doc1', 5600000, <String, Object?>{'foo': 'value1'}));
        final MaybeDocument? deleted =
            await localStore.readDocument(key('coll/deleted'));
        expect(deleted, isA<NoDocument>());

        final NamedQuery? namedQuery =
            await localStore.getNamedQuery('coll-query');
        expect(namedQuery, isNotNull);
        expect(namedQuery!.readTime, version(5000000));

        // The named query is allocated as a target that resumes from its read time, and holds the documents.
        final Query query = namedQuery.bundledQuery.query;
        final QueryData queryData = await localStore.allocateTarget(query.toTarget());
        expect(queryData.snapshotVersion, version(5000000));
        expect(queryData.resumeToken, isEmpty);
        expect(
            await localStore.getRemoteDocumentKeys(queryData.targetId),
            // The keys come from the document metadata, deleted documents included.
            keySet(<DocumentKey>[key('coll/doc1'), key('coll/deleted')]));
      });

      test('reports the progress while loading', () async {
        final LoadBundleTask task = LoadBundleTask();
        final List<LoadBundleTaskProgress> progress =
            <LoadBundleTaskProgress>[];
        final Future<void> done = task.stream.forEach(progress.add);

        final String bundle = bundleWithQueryAndDocuments();
        await syncEngine.loadBundle(
            BundleReader.fromBytes(serializer, utf8.encode(bundle)), task);
        await done;

        expect(
            progress.map((LoadBundleTaskProgress p) => p.taskState).toList(),
            <LoadBundleTaskState>[
              LoadBundleTaskState.running, // initial
              LoadBundleTaskState.running, // coll/doc1
              LoadBundleTaskState.running, // coll/deleted
              LoadBundleTaskState.success,
            ]);
        expect(
            progress
                .map((LoadBundleTaskProgress p) => p.documentsLoaded)
                .toList(),
            <int>[0, 1, 2, 2]);
        expect(progress.last.bytesLoaded, progress.last.totalBytes);
        expect(task.snapshot, progress.last);
      });

      test('raises snapshots for the queries that are listened to', () async {
        await syncEngine.listen(query('coll'));
        callback.snapshots.clear();

        await load(bundleWithQueryAndDocuments());

        expect(callback.snapshots, hasLength(1));
        expect(callback.snapshots.single.documents.map((d) => d.key).toList(),
            <DocumentKey>[key('coll/doc1')]);
      });

      test('skips a bundle that was already loaded', () async {
        final LoadBundleTask first = await load(bundleWithQueryAndDocuments());
        expect(first.isSuccessful, isTrue);

        // Same id and the same (or older) create time.
        final LoadBundleTask task = LoadBundleTask();
        final List<LoadBundleTaskProgress> progress =
            <LoadBundleTaskProgress>[];
        final Future<void> done = task.stream.forEach(progress.add);
        await syncEngine.loadBundle(
            BundleReader.fromBytes(
                serializer, utf8.encode(bundleWithQueryAndDocuments())),
            task);
        await done;

        expect(progress, hasLength(1));
        expect(progress.single.taskState, LoadBundleTaskState.success);
        expect(progress.single.documentsLoaded, 2);
      });

      test('loads a bundle with a newer create time again', () async {
        await load(bundleWithQueryAndDocuments());

        final TestBundleBuilder builder = TestBundleBuilder(databaseId)
          ..addDocumentMetadata('coll/doc1', 7000000, true)
          ..addDocument('coll/doc1', 1200000, 7000000, <String, dynamic>{
            'foo': <String, dynamic>{'stringValue': 'value2'},
          });
        final LoadBundleTask task =
            await load(builder.build('bundle-1', 7000000, 1));

        expect(task.isSuccessful, isTrue);
        expect(await localStore.readDocument(key('coll/doc1')),
            doc('coll/doc1', 7000000, <String, Object?>{'foo': 'value2'}));
      });

      test('fails with invalid argument for a corrupt bundle', () async {
        final String bundle = bundleWithQueryAndDocuments();
        // Cut the bundle in the middle of the last element.
        final LoadBundleTask task =
            await load(bundle.substring(0, bundle.length - 20));

        expect(task.isComplete, isTrue);
        expect(task.isSuccessful, isFalse);
        expect(task.snapshot.taskState, LoadBundleTaskState.error);
        expect(task.exception, isA<FirestoreError>());
        expect((task.exception! as FirestoreError).code,
            FirestoreErrorCode.invalidArgument);
        await expectLater(task.future, throwsA(isA<FirestoreError>()));

        // Nothing was applied: the bundle is not marked as loaded and its documents are not in the cache.
        expect(await localStore.readDocument(key('coll/doc1')), isNull);
        final LoadBundleTask retry = await load(bundleWithQueryAndDocuments());
        expect(retry.isSuccessful, isTrue);
      });

      test('fails when the number of documents does not match the metadata',
          () async {
        final TestBundleBuilder builder = TestBundleBuilder(databaseId)
          ..addDocumentMetadata('coll/doc1', 5600000, true)
          ..addDocument('coll/doc1', 1200000, 5600000, <String, dynamic>{});
        final String bundle = builder.build('bundle-1', 6000000, 1);
        // Claim two documents in the metadata.
        final String broken =
            bundle.replaceFirst('"totalDocuments":1', '"totalDocuments":2');
        final LoadBundleTask task = await load(broken);

        expect(task.snapshot.taskState, LoadBundleTaskState.error);
        await expectLater(task.future, throwsA(isA<FirestoreError>()));
      });
    });
  });
}
