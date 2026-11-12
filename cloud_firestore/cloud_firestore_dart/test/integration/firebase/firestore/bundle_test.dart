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

import 'package:cloud_firestore_dart/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_settings.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local_cache_settings.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/load_bundle_task.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/load_bundle_task_progress.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/source.dart';
import 'package:test/test.dart';

import '../../../util/integration_test_util.dart';

// NOTE: Loading a real bundle against the emulator is untested: this file is the port of the Android BundleTest
// (androidTest) and was written without being run. The Android tests of limitToLast() named queries are not ported:
// the port's core Query has no limitToLast() yet.
void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/bundle';

  // Elements 1.. of the bundle; the metadata element is generated from them.
  const List<String> bundleTemplates = <String>[
    '{"namedQuery":{"name":"limit","readTime":{"seconds":1000,"nanos":9999},'
        '"bundledQuery":{"parent":"projects/{projectId}/databases/(default)/documents",'
        '"structuredQuery":{"from":[{"collectionId":"coll-1"}],"orderBy":'
        '[{"field":{"fieldPath":"bar"},"direction":"DESCENDING"},{"field":'
        '{"fieldPath":"__name__"},"direction":"DESCENDING"}],"limit":'
        '{"value":1}},"limitType":"FIRST"}}}',
    '{"documentMetadata":{"name":'
        '"projects/{projectId}/databases/(default)/documents/coll-1/a","readTime":'
        '{"seconds":1000,"nanos":9999},"exists":true}}',
    '{"document":{"name":"projects/{projectId}/databases/(default)/documents/coll-1/a",'
        '"createTime":{"seconds":1,"nanos":9},"updateTime":{"seconds":1,'
        '"nanos":9},"fields":{"k":{"stringValue":"a"},"bar":'
        '{"integerValue":1}}}}',
    '{"documentMetadata":{"name":'
        '"projects/{projectId}/databases/(default)/documents/coll-1/b","readTime":'
        '{"seconds":1000,"nanos":9999},"exists":true}}',
    '{"document":{"name":"projects/{projectId}/databases/(default)/documents/coll-1/b",'
        '"createTime":{"seconds":1,"nanos":9},"updateTime":{"seconds":1,'
        '"nanos":9},"fields":{"k":{"stringValue":"\u{1F60A}"},"bar":'
        '{"integerValue":2}}}}',
  ];

  late Firestore db;

  setUp(() async {
    db = await IntegrationTestUtil.testFirestore();
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  int utf8Length(String s) => utf8.encode(s).length;

  /// Returns a valid bundle by replacing the project id in [bundleTemplates] (also recalculates the length
  /// prefixes and the metadata).
  List<int> createBundle([String? projectId]) {
    final String project = projectId ?? db.databaseId.projectId;
    final StringBuffer bundle = StringBuffer();
    for (final String template in bundleTemplates) {
      final String element = template.replaceAll('{projectId}', project);
      bundle
        ..write(utf8Length(element))
        ..write(element);
    }
    final String elements = bundle.toString();

    final String metadata =
        '{"metadata":{"id":"test-bundle","createTime":{"seconds":1001,"nanos":9999},'
        '"version":1,"totalDocuments":2,"totalBytes":${utf8Length(elements)}}}';
    return utf8.encode('${utf8Length(metadata)}$metadata$elements');
  }

  Future<List<Map<String, Object?>>> cachedValues(Query query) async {
    final QuerySnapshot snapshot = await query.get(Source.cache);
    return snapshot.docs
        .map((DocumentSnapshot d) => d.data as Map<String, Object?>)
        .toList();
  }

  Future<void> verifyQueryResults() async {
    // Read from cache. These documents do not exist in the backend, so they can only be read from cache.
    expect(await cachedValues(db.collection('coll-1')), <Map<String, Object?>>[
      <String, Object?>{'bar': 1, 'k': 'a'},
      <String, Object?>{'bar': 2, 'k': '\u{1F60A}'},
    ]);

    final Query? limitQuery = await db.getNamedQuery('limit');
    expect(limitQuery, isNotNull);
    expect(await cachedValues(limitQuery!), <Map<String, Object?>>[
      <String, Object?>{'bar': 2, 'k': '\u{1F60A}'},
    ]);

    expect(await db.getNamedQuery('does-not-exist'), isNull);
  }

  void verifySuccessProgress(LoadBundleTaskProgress progress) {
    expect(progress.taskState, LoadBundleTaskState.success);
    expect(progress.bytesLoaded, progress.totalBytes);
    expect(progress.documentsLoaded, progress.totalDocuments);
  }

  test('testLoadDocumentsWithProgressUpdates', () async {
    final List<LoadBundleTaskProgress> progressEvents =
        <LoadBundleTaskProgress>[];

    final LoadBundleTask bundleTask = db.loadBundle(createBundle());
    final Future<void> done = bundleTask.stream.forEach(progressEvents.add);
    final LoadBundleTaskProgress result = await bundleTask.future;
    await done;

    expect(progressEvents.length, 4);
    for (int i = 0; i < 3; i++) {
      expect(progressEvents[i].taskState, LoadBundleTaskState.running);
      expect(progressEvents[i].documentsLoaded, i);
      expect(progressEvents[i].bytesLoaded,
          lessThanOrEqualTo(progressEvents[i].totalBytes));
    }
    verifySuccessProgress(progressEvents[3]);
    expect(progressEvents[3], result);

    await verifyQueryResults();
  });

  test('testLoadFromAStreamInSmallChunks', () async {
    final List<int> bundle = createBundle();
    final Stream<List<int>> chunks = Stream<List<int>>.fromIterable(<List<int>>[
      for (int i = 0; i < bundle.length; i += 37)
        bundle.sublist(i, i + 37 > bundle.length ? bundle.length : i + 37)
    ]);

    final LoadBundleTaskProgress result =
        await db.loadBundleStream(chunks).future;
    verifySuccessProgress(result);

    await verifyQueryResults();
  });

  test('testLoadForASecondTimeSkips', () async {
    final List<int> bundle = createBundle();
    await db.loadBundle(bundle).future;

    final List<LoadBundleTaskProgress> progressEvents =
        <LoadBundleTaskProgress>[];
    final LoadBundleTask secondLoad = db.loadBundle(bundle);
    final Future<void> done = secondLoad.stream.forEach(progressEvents.add);
    await secondLoad.future;
    await done;

    // No loading actually happened in the second loadBundle call, only the success progress is recorded.
    expect(progressEvents.length, 1);
    verifySuccessProgress(progressEvents.single);

    await verifyQueryResults();
  });

  test('testLoadWithDocumentsThatAreAlreadyPulledFromBackend', () async {
    await db.document('coll-1/a').set(<String, Object?>{'bar': 'newValueA'});
    await db.document('coll-1/b').set(<String, Object?>{'bar': 'newValueB'});

    final LoadBundleTaskProgress result =
        await db.loadBundle(createBundle()).future;
    verifySuccessProgress(result);

    // The test bundle is holding ancient documents, so the cache keeps the documents from the backend.
    expect(await cachedValues(db.collection('coll-1')), <Map<String, Object?>>[
      <String, Object?>{'bar': 'newValueA'},
      <String, Object?>{'bar': 'newValueB'},
    ]);
  });

  test('testLoadWithDocumentsFromOtherProjectFails', () async {
    final List<LoadBundleTaskProgress> progressEvents =
        <LoadBundleTaskProgress>[];
    final LoadBundleTask bundleTask =
        db.loadBundle(createBundle('other-project'));
    final Future<void> done = bundleTask.stream.forEach(progressEvents.add);

    await expectLater(
        bundleTask.future,
        throwsA(isA<FirestoreError>().having((FirestoreError e) => e.code,
            'code', FirestoreErrorCode.invalidArgument)));
    await done;

    expect(progressEvents.length, 2);
    expect(progressEvents[0].taskState, LoadBundleTaskState.running);
    expect(progressEvents[0].documentsLoaded, 0);
    expect(progressEvents[1].taskState, LoadBundleTaskState.error);
    expect(progressEvents[1].bytesLoaded, 0);
    expect(progressEvents[1].documentsLoaded, 0);

    // Firestore still functions, despite having loaded a problematic bundle.
    await db.collection('coll-1').get(Source.cache);
  });
  test('testLoadedDocumentsShouldNotBeGarbageCollectedRightAway', () async {
    // Only meaningful with memory persistence (SQLite only ever deletes lazily): use a memory cache with eager GC.
    final FirestoreSettings base = IntegrationTestUtil.newTestSettings();
    db = await IntegrationTestUtil.testFirestore(FirestoreSettings(
      host: base.host,
      port: base.port,
      sslEnabled: base.sslEnabled,
      cacheSettings: MemoryCacheSettings(),
    ));

    final LoadBundleTaskProgress result =
        await db.loadBundle(createBundle()).future;
    verifySuccessProgress(result);

    // Read a different collection. This triggers GC.
    await db.collection('coll-other').get(Source.cache);

    // The loaded documents must still be in the cache: with eager GC they would be collected if the "umbrella" target
    // of the bundle did not hold their keys (see LocalStore).
    await verifyQueryResults();
  });
}
