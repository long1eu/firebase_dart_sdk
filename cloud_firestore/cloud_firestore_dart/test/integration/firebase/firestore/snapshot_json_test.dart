// Copyright 2025 Google LLC
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

// Port of the JS SDK integration tests of toJSON(), fromJSON() and onSnapshotResume() (test/integration/api/
// database.test.ts): a snapshot is serialized, read back by another instance (with an empty cache), and listened to
// from there.

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/internal.dart';
import 'package:test/test.dart';

import '../../../util/integration_test_util.dart';

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/snapshot_json';

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  /// Waits until an element of [events] matches [test] and returns it.
  Future<T> waitFor<T>(List<T> events, bool Function(T event) test) async {
    for (int i = 0; i < 200; i++) {
      for (final T event in events) {
        if (test(event)) {
          return event;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    fail('No matching event in $events');
  }

  /// The JSON object as another process would receive it.
  Map<String, Object?> transfer(Map<String, Object?> json) =>
      jsonDecode(jsonEncode(json)) as Map<String, Object?>;

  test('DocumentSnapshot fromJson in another instance', () async {
    final DocumentReference<Map<String, Object?>> docRef =
        (await IntegrationTestUtil.testDocumentWithData(<String, Object?>{
      'a': 1,
      'nested': <String, Object?>{'b': 'c'}
    }))
            .withoutConverter();
    final DocumentSnapshot<Map<String, Object?>> snapshot = await docRef.get();
    final Map<String, Object?> json = transfer(snapshot.toJson());

    final Firestore other = await IntegrationTestUtil.testFirestore();
    final DocumentSnapshot<Map<String, Object?>> fromJson =
        DocumentSnapshot<Map<String, Object?>>.fromJson(other, json);
    expect(fromJson.exists, isTrue);
    expect(fromJson.reference.path, docRef.path);
    expect(fromJson.data, snapshot.data);
  });

  test('DocumentSnapshot events for a snapshot created by a bundle', () async {
    final DocumentReference<Map<String, Object?>> docRef =
        (await IntegrationTestUtil.testDocumentWithData(
                <String, Object?>{'a': 1}))
            .withoutConverter();
    final Map<String, Object?> json = transfer((await docRef.get()).toJson());

    final Firestore other = await IntegrationTestUtil.testFirestore();
    final List<DocumentSnapshot<Map<String, Object?>>> events =
        <DocumentSnapshot<Map<String, Object?>>>[];
    final StreamSubscription<DocumentSnapshot<Map<String, Object?>>> sub = other
        .documentSnapshotsFromJson<Map<String, Object?>>(json)
        .listen(events.add);

    final DocumentSnapshot<Map<String, Object?>> first = await waitFor(
        events, (DocumentSnapshot<Map<String, Object?>> s) => true);
    expect(first.exists, isTrue);
    expect(first.data, <String, Object?>{'a': 1});

    await docRef.set(<String, Object?>{'a': 2});
    final DocumentSnapshot<Map<String, Object?>> updated = await waitFor(
        events,
        (DocumentSnapshot<Map<String, Object?>> s) =>
            s.data?['a'] == 2 && !s.metadata.isFromCache);
    expect(updated.exists, isTrue);
    await sub.cancel();
  });

  test('DocumentSnapshot of a missing document resumes on the document',
      () async {
    final DocumentReference<Map<String, Object?>> docRef =
        (await IntegrationTestUtil.testDocument()).withoutConverter();
    final DocumentSnapshot<Map<String, Object?>> snapshot = await docRef.get();
    expect(snapshot.exists, isFalse);
    final Map<String, Object?> json = transfer(snapshot.toJson());

    final Firestore other = await IntegrationTestUtil.testFirestore();
    expect(DocumentSnapshot<Map<String, Object?>>.fromJson(other, json).exists,
        isFalse);
    final List<DocumentSnapshot<Map<String, Object?>>> events =
        <DocumentSnapshot<Map<String, Object?>>>[];
    final StreamSubscription<DocumentSnapshot<Map<String, Object?>>> sub = other
        .documentSnapshotsFromJson<Map<String, Object?>>(json)
        .listen(events.add);
    await waitFor(events,
        (DocumentSnapshot<Map<String, Object?>> s) => !s.metadata.isFromCache);

    await docRef.set(<String, Object?>{'a': 1});
    await waitFor(events,
        (DocumentSnapshot<Map<String, Object?>> s) => s.data?['a'] == 1);
    await sub.cancel();
  });

  test(
      'QuerySnapshot resumes from a serialized snapshot and receives later '
      'changes', () async {
    final CollectionReference<Map<String, Object?>> collection =
        await _collectionWithDocs(<String, Map<String, Object?>>{
      'a': <String, Object?>{'foo': 1},
      'b': <String, Object?>{'bar': 2},
    });
    final Query<Map<String, Object?>> query =
        collection.orderByField(FieldPath.documentIdField);
    final QuerySnapshot<Map<String, Object?>> snapshot = await query.get();
    expect(snapshot.metadata.isFromCache, isFalse);
    final Map<String, Object?> json = transfer(snapshot.toJson());

    // A change made after the snapshot was taken, before listening resumes.
    await collection.document('c').set(<String, Object?>{'baz': 3});

    final List<String> sent = <String>[];
    final InternalLogLevel level = Log.level;
    Log.level = InternalLogLevel.d;
    late final Firestore other;
    final List<QuerySnapshot<Map<String, Object?>>> events =
        <QuerySnapshot<Map<String, Object?>>>[];
    late final StreamSubscription<QuerySnapshot<Map<String, Object?>>> sub;
    try {
      await runZoned(() async {
        other = await IntegrationTestUtil.testFirestore();
        Log.level = InternalLogLevel.d;

        final QuerySnapshot<Map<String, Object?>> fromJson =
            QuerySnapshot<Map<String, Object?>>.fromJson(other, json);
        expect(
            fromJson.docs
                .map((QueryDocumentSnapshot<Map<String, Object?>> d) => d.data),
            <Map<String, Object?>>[
              <String, Object?>{'foo': 1},
              <String, Object?>{'bar': 2},
            ]);
        expect(fromJson.query.query, query.query);

        sub = other
            .querySnapshotsFromJson<Map<String, Object?>>(json)
            .listen(events.add);

        // The first event is raised from the bundle loaded into the cache.
        final QuerySnapshot<Map<String, Object?>> first = await waitFor(
            events, (QuerySnapshot<Map<String, Object?>> s) => true);
        expect(first.metadata.isFromCache, isTrue);
        expect(first.docs.map((QueryDocumentSnapshot<Object?> d) => d.id),
            <String>['a', 'b']);

        // Then the backend sends what changed since the read time of the snapshot.
        final QuerySnapshot<Map<String, Object?>> synced = await waitFor(events,
            (QuerySnapshot<Map<String, Object?>> s) => !s.metadata.isFromCache);
        expect(synced.docs.map((QueryDocumentSnapshot<Object?> d) => d.id),
            <String>['a', 'b', 'c']);
      }, zoneSpecification: ZoneSpecification(
          print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
        if (line.contains('Stream sending') && line.contains('addTarget')) {
          sent.add(line);
        }
      }));
    } finally {
      Log.level = level;
    }

    // The listen of the named query was resumed from the read time of the snapshot (the bundle has no resume token).
    final List<String> queryListens = sent
        .where((String line) => line.contains(collection.id))
        .toList(growable: false);
    expect(queryListens, isNotEmpty);
    expect(queryListens.first, contains('readTime'));
    expect(queryListens.first, isNot(contains('resumeToken')));

    // Later changes are received.
    await collection.document('a').update(<String, Object?>{'foo': 5});
    final QuerySnapshot<Map<String, Object?>> updated = await waitFor(
        events,
        (QuerySnapshot<Map<String, Object?>> s) =>
            s.docs.first.data['foo'] == 5);
    expect(updated.docs.map((QueryDocumentSnapshot<Object?> d) => d.id),
        <String>['a', 'b', 'c']);
    await sub.cancel();
  });

  test('QuerySnapshot events with a converter', () async {
    final CollectionReference<Map<String, Object?>> collection =
        await _collectionWithDocs(<String, Map<String, Object?>>{
      'a': <String, Object?>{'n': 1},
      'b': <String, Object?>{'n': 2},
    });
    final FirestoreDataConverter<int> converter =
        FirestoreDataConverter<int>.from(
      fromFirestore: (DocumentSnapshot<Map<String, Object?>> snapshot,
              SnapshotOptions? options) =>
          snapshot.data!['n']! as int,
      toFirestore: (int value, SetOptions? options) =>
          <String, Object?>{'n': value},
    );
    final Map<String, Object?> json = transfer(
        (await collection.orderBy('n').withConverter(converter).get())
            .toJson());

    final Firestore other = await IntegrationTestUtil.testFirestore();
    expect(
        QuerySnapshot<int>.fromJson(other, json, converter: converter)
            .docs
            .map((QueryDocumentSnapshot<int> d) => d.data),
        <int>[1, 2]);

    final List<QuerySnapshot<int>> events = <QuerySnapshot<int>>[];
    final StreamSubscription<QuerySnapshot<int>> sub = other
        .querySnapshotsFromJson<int>(json, converter: converter)
        .listen(events.add);
    final QuerySnapshot<int> first =
        await waitFor(events, (QuerySnapshot<int> s) => true);
    expect(
        first.docs.map((QueryDocumentSnapshot<int> d) => d.data), <int>[1, 2]);
    await sub.cancel();
  });

  test('QuerySnapshot error events for an invalid bundle', () async {
    final Firestore db = await IntegrationTestUtil.testFirestore();
    final Map<String, Object?> json = <String, Object?>{
      'bundle': 'BadData',
      'bundleName': 'bundleName',
      'bundleSource': 'QuerySnapshot',
    };
    final Completer<Object> error = Completer<Object>();
    final StreamSubscription<QuerySnapshot<Map<String, Object?>>> sub = db
        .querySnapshotsFromJson<Map<String, Object?>>(json)
        .listen((_) => fail('Unexpected event'), onError: error.complete);
    expect(await error.future, isNotNull);
    await sub.cancel();
  });

  test('DocumentSnapshot error events for an invalid bundle', () async {
    final Firestore db = await IntegrationTestUtil.testFirestore();
    final Map<String, Object?> json = <String, Object?>{
      'bundle': 'BadData',
      'bundleName': 'coll/doc',
      'bundleSource': 'DocumentSnapshot',
    };
    final Completer<Object> error = Completer<Object>();
    final StreamSubscription<DocumentSnapshot<Map<String, Object?>>> sub = db
        .documentSnapshotsFromJson<Map<String, Object?>>(json)
        .listen((_) => fail('Unexpected event'), onError: error.complete);
    expect(await error.future, isNotNull);
    await sub.cancel();
  });

  test('resume rejects JSON of the other snapshot type', () async {
    final Firestore db = await IntegrationTestUtil.testFirestore();
    final Map<String, Object?> json = <String, Object?>{
      'bundle': 'BadData',
      'bundleName': 'coll/doc',
      'bundleSource': 'DocumentSnapshot',
    };
    expect(() => db.querySnapshotsFromJson<Map<String, Object?>>(json),
        throwsA(isA<FirestoreError>()));
    expect(
        () => db.documentSnapshotsFromJson<Map<String, Object?>>(<String,
            Object?>{'bundle': 'x', 'bundleSource': 'DocumentSnapshot'}),
        throwsA(isA<FirestoreError>()));
  });
}

Future<CollectionReference<Map<String, Object?>>> _collectionWithDocs(
    Map<String, Map<String, Object?>> docs) async {
  final CollectionReference<dynamic> collection =
      await IntegrationTestUtil.testCollectionWithDocs(docs);
  return collection.withoutConverter();
}
