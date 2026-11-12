// Copyright 2026 Google LLC
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

// Regression tests for the leftover findings of the core/local review (M3, M5, M6, M10, L1, L3, L4).

import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/empty_credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query_stream.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_settings.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_view_changes.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/index_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/database.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart';
import 'package:grpc/grpc.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../../../util/integration_test_util.dart';
import '../../../../util/local_helpers.dart';
import '../../../../util/test_util.dart';
import '../local/mock/database_mock.dart';
import '../local/persistence_test_helpers.dart';

void main() {
  test('L3: QueryStream closes after an error', () async {
    final QueryStream stream = QueryStream(Query(path('rooms/eros')));
    final List<Object> errors = <Object>[];
    final Completer<void> done = Completer<void>();
    stream.listen((_) {}, onError: errors.add, onDone: done.complete);

    stream.onError(
        exceptionFromStatus(const GrpcError.alreadyExists('test error')));

    await done.future.timeout(const Duration(seconds: 5));
    expect(errors, hasLength(1));
  });

  test('L4: View.syncedDocuments does not copy', () {
    final View view = View(Query(path('rooms')), DocumentKey.emptyKeySet);
    expect(identical(view.syncedDocuments, view.syncedDocuments), isTrue);
  });

  test('M10: MemoryCollectionParentIndex.contains reflects add', () {
    final MemoryCollectionParentIndex index = MemoryCollectionParentIndex();
    expect(index.contains(path('a/b/c')), isFalse);
    expect(index.add(path('a/b/c')), isTrue);
    expect(index.contains(path('a/b/c')), isTrue);
    expect(index.contains(path('a/b/d')), isFalse);
    expect(index.contains(path('x/y/c')), isFalse);
  });

  test('M10: a failed collection parent INSERT is not cached', () async {
    final SQLitePersistence persistence = await createSQLitePersistence();
    // Closing the database makes the INSERT throw.
    persistence.database.close();
    await expectLater(
        persistence.indexManager.addToCollectionParentIndex(path('a/b/c')),
        throwsA(anything));
    // The entry was not cached, so adding it again still attempts the write instead of silently doing nothing.
    await expectLater(
        persistence.indexManager.addToCollectionParentIndex(path('a/b/c')),
        throwsA(anything));
  });

  test('M5: view changes of a released target do not pin documents', () async {
    final LocalStoreDriver d = LocalStoreDriver(
        await createEagerGCMemoryPersistence());
    await d.start();

    final Query query = Query(path('foo'));
    final int released = await d.allocateQuery(query);
    await d.localStore.releaseTarget(released);

    // A view snapshot computed before the release arrives late.
    await d.localStore.notifyLocalViewChanges(<LocalViewChanges>[
      LocalViewChanges(
          released,
          /* fromCache= */ false,
          DocumentKey.emptyKeySet.insert(key('foo/bar')),
          DocumentKey.emptyKeySet),
    ]);

    // A new listen adds the document and then goes away: nothing references the document, so eager GC collects it.
    final int target = await d.allocateQuery(query);
    await d.applyRemoteEvent(addedRemoteEvent(
        doc('foo/bar', 2, map(<String>['a', 'b'])), <int>[target], <int>[]));
    expect(await d.localStore.readDocument(key('foo/bar')), isNotNull);
    await d.localStore.releaseTarget(target);
    expect(await d.localStore.readDocument(key('foo/bar')), isNull);

    await d.shutdown();
  });

  test('L1: SQLite query cache start tolerates NULL globals', () async {
    final SQLitePersistence persistence = await createSQLitePersistence();
    await persistence.runTransaction('null globals', () async {
      await persistence.database.execute(
          'UPDATE target_globals SET target_count = NULL, '
          'highest_listen_sequence_number = NULL');
      await persistence.queryCache.start();
    });
    expect(persistence.queryCache.targetCount, 0);
    expect(persistence.queryCache.highestListenSequenceNumber, 0);
    await persistence.shutdown();
  });

  group('M6: shutdown', () {
    Future<Firestore> open(TaskScheduler scheduler) {
      final String name =
          '${Directory.systemTemp.path}/review_left_${const Uuid().v4()}.db';
      return IntegrationTestUtil.forTests(
        DatabaseId.forDatabase('shutdown-test', DatabaseId.defaultDatabaseId),
        'shutdown-test-key',
        EmptyCredentialsProvider(),
        scheduler,
        (String p,
            {int? version,
            OnConfigure? onConfigure,
            OnCreate? onCreate,
            OnVersionChange? onUpgrade,
            OnVersionChange? onDowngrade,
            OnOpen? onOpen}) async {
          final DatabaseMock db = await DatabaseMock.create(name,
              version: version,
              onConfigure: onConfigure,
              onCreate: onCreate,
              onUpgrade: onUpgrade,
              onDowngrade: onDowngrade,
              onOpen: onOpen);
          db.renamePath = false;
          return db;
        },
        FirestoreSettings(),
      );
    }

    test('concurrent shutdown calls share one shutdown', () async {
      final TaskScheduler scheduler = TaskScheduler('');
      final Firestore firestore = await open(scheduler);
      expect(scheduler.getTask(TaskId.garbageCollection), isNotNull);

      final Future<void> first = firestore.shutdown();
      final Future<void> second = firestore.shutdown();
      await Future.wait(<Future<void>>[first, second])
          .timeout(const Duration(seconds: 10));
      expect(scheduler.getTask(TaskId.garbageCollection), isNull);
      // And a late call is still fine.
      await firestore.shutdown();
    });
  });
}
