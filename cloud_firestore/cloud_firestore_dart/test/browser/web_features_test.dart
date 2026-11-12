// A broader smoke set for the web: the features that go through different
// parts of the client, each once, in a real browser against the emulator.
//
//   dart test -p chrome -c dart2wasm test/browser

@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:test/test.dart';

import 'browser_test_util.dart';

typedef Json = Map<String, Object?>;

class City {
  const City(this.name, this.population);

  factory City.fromMap(Json map) =>
      City(map['name']! as String, map['population']! as int);

  final String name;
  final int population;

  Json toMap() => <String, Object?>{'name': name, 'population': population};
}

final FirestoreDataConverter<City> cityConverter =
    FirestoreDataConverter<City>.from(
  fromFirestore: (DocumentSnapshot<Json> snapshot, SnapshotOptions? options) =>
      City.fromMap(snapshot.data!),
  toFirestore: (City city, SetOptions? options) => city.toMap(),
);

/// A bundle with two documents of `coll-1` and a named query, as in the
/// integration test of bundles.
List<int> createBundle(String collection) {
  int utf8Length(String s) => utf8.encode(s).length;
  const String db = 'projects/$projectId/databases/(default)';
  final List<String> elements = <String>[
    '{"namedQuery":{"name":"limit","readTime":{"seconds":1000,"nanos":9999},'
        '"bundledQuery":{"parent":"$db/documents",'
        '"structuredQuery":{"from":[{"collectionId":"$collection"}],"orderBy":'
        '[{"field":{"fieldPath":"bar"},"direction":"DESCENDING"},{"field":'
        '{"fieldPath":"__name__"},"direction":"DESCENDING"}],"limit":'
        '{"value":1}},"limitType":"FIRST"}}}',
    '{"documentMetadata":{"name":"$db/documents/$collection/a","readTime":'
        '{"seconds":1000,"nanos":9999},"exists":true}}',
    '{"document":{"name":"$db/documents/$collection/a",'
        '"createTime":{"seconds":1,"nanos":9},"updateTime":{"seconds":1,'
        '"nanos":9},"fields":{"k":{"stringValue":"a"},"bar":'
        '{"integerValue":1}}}}',
    '{"documentMetadata":{"name":"$db/documents/$collection/b","readTime":'
        '{"seconds":1000,"nanos":9999},"exists":true}}',
    '{"document":{"name":"$db/documents/$collection/b",'
        '"createTime":{"seconds":1,"nanos":9},"updateTime":{"seconds":1,'
        '"nanos":9},"fields":{"k":{"stringValue":"\u{1F60A}"},"bar":'
        '{"integerValue":2}}}}',
  ];
  final String body =
      elements.map((String element) => '${utf8Length(element)}$element').join();
  final String metadata =
      '{"metadata":{"id":"test-bundle","createTime":{"seconds":1001,"nanos":9999},'
      '"version":1,"totalDocuments":2,"totalBytes":${utf8Length(body)}}}';
  return utf8.encode('${utf8Length(metadata)}$metadata$body');
}

void main() {
  test('a listener with metadata changes sees the write being acknowledged',
      () async {
    final Firestore firestore = await newClient();
    final DocumentReference<Json> doc =
        firestore.collection(newCollectionName()).doc('a');
    final EventLog<DocumentSnapshot<Json>> log =
        EventLog<DocumentSnapshot<Json>>(
            doc.getSnapshots(MetadataChanges.include));

    await log.waitFor((DocumentSnapshot<Json> s) => !s.exists);
    final Future<void> written = doc.set(<String, Object?>{'a': 1});

    final DocumentSnapshot<Json> pending = await log.waitFor(
        (DocumentSnapshot<Json> s) => s.exists && s.metadata.hasPendingWrites);
    expect(pending.data, <String, Object?>{'a': 1});
    final DocumentSnapshot<Json> acknowledged = await log.waitFor(
        (DocumentSnapshot<Json> s) =>
            s.exists &&
            !s.metadata.hasPendingWrites &&
            !s.metadata.isFromCache);
    expect(acknowledged.data, <String, Object?>{'a': 1});
    await written;
  });

  test('a write batch is applied as a whole', () async {
    final Firestore firestore = await newClient();
    final CollectionReference<Json> collection =
        firestore.collection(newCollectionName());
    await collection.doc('update').set(<String, Object?>{'n': 1});
    await collection.doc('delete').set(<String, Object?>{'n': 1});

    final WriteBatch batch = firestore.batch()
      ..set(collection.doc('new'), <String, Object?>{'n': 3})
      ..update(collection.doc('update'), <String, Object?>{'n': 2})
      ..delete(collection.doc('delete'));
    await batch.commit();

    final Firestore other = await newClient();
    final QuerySnapshot<Json> snapshot =
        await other.collection(collection.id).get(Source.server);
    expect(<String, Object?>{
      for (final QueryDocumentSnapshot<Json> d in snapshot.docs) d.id: d.data
    }, <String, Object?>{
      'new': <String, Object?>{'n': 3},
      'update': <String, Object?>{'n': 2},
    });
  });

  test('loads a bundle with a named query into the cache', () async {
    final Firestore firestore = await newClient();
    final String collection = newCollectionName();

    final LoadBundleTask task = firestore.loadBundle(createBundle(collection));
    final List<LoadBundleTaskProgress> progress = <LoadBundleTaskProgress>[];
    final Future<void> streamed = task.stream.forEach(progress.add);
    final LoadBundleTaskProgress result = await task.future;
    await streamed;
    expect(result.taskState, LoadBundleTaskState.success);
    expect(result.documentsLoaded, 2);
    expect(progress.last.taskState, LoadBundleTaskState.success);

    // The documents only exist in the bundle, so they come from the cache.
    final QuerySnapshot<Json> cached =
        await firestore.collection(collection).get(Source.cache);
    expect(
        cached.docs.map((QueryDocumentSnapshot<Json> d) => d.data).toList(),
        <Json>[
          <String, Object?>{'bar': 1, 'k': 'a'},
          <String, Object?>{'bar': 2, 'k': '\u{1F60A}'},
        ]);

    final Query<Json>? named = await firestore.getNamedQuery('limit');
    expect(named, isNotNull);
    expect(
        (await named!.get(Source.cache))
            .docs
            .map((QueryDocumentSnapshot<Json> d) => d.data)
            .toList(),
        <Json>[
          <String, Object?>{'bar': 2, 'k': '\u{1F60A}'}
        ]);
    expect(await firestore.getNamedQuery('does-not-exist'), isNull);
  });

  test('a snapshot goes through JSON and is resumed in another client',
      () async {
    final Firestore firestore = await newClient();
    final DocumentReference<Json> doc =
        firestore.collection(newCollectionName()).doc('a');
    await doc.set(<String, Object?>{'a': 1});
    // Through text, as it would travel between a server and a page.
    final Json json =
        jsonDecode(jsonEncode((await doc.get(Source.server)).toJson())) as Json;

    final Firestore other = await newClient();
    expect(DocumentSnapshot<Json>.fromJson(other, json).data,
        <String, Object?>{'a': 1});

    final EventLog<DocumentSnapshot<Json>> log =
        EventLog<DocumentSnapshot<Json>>(
            other.documentSnapshotsFromJson<Json>(json));
    final DocumentSnapshot<Json> first =
        await log.waitFor((DocumentSnapshot<Json> s) => true);
    expect(first.data, <String, Object?>{'a': 1});

    await doc.set(<String, Object?>{'a': 2});
    final DocumentSnapshot<Json> updated = await log.waitFor(
        (DocumentSnapshot<Json> s) =>
            s.data?['a'] == 2 && !s.metadata.isFromCache);
    expect(updated.exists, isTrue);
  });

  test('finds the nearest vectors', () async {
    final Firestore firestore = await newClient();
    final CollectionReference<Json> collection =
        firestore.collection(newCollectionName());
    await collection.doc('a').set(<String, Object?>{
      'embedding': FieldValue.vector(<double>[1.0, 1.0])
    });
    await collection.doc('b').set(<String, Object?>{
      'embedding': FieldValue.vector(<double>[2.0, 2.0])
    });
    await collection.doc('c').set(<String, Object?>{
      'embedding': FieldValue.vector(<double>[9.0, 9.0])
    });

    final VectorQuerySnapshot snapshot = await collection
        .findNearest(
            'embedding', <double>[0.0, 0.0], 2, DistanceMeasure.euclidean,
            distanceResultField: 'distance')
        .get();
    expect(snapshot.docs.map((DocumentSnapshot<Object?> d) => d.id).toList(),
        <String>['a', 'b']);
    final Json nearest = snapshot.docs.first.data! as Json;
    expect(nearest['embedding'], isA<VectorValue>());
    expect(nearest['distance'], closeTo(1.4142, 0.001));
  });

  test('filters with the named arguments of where', () async {
    final Firestore firestore = await newClient();
    final CollectionReference<Json> collection =
        firestore.collection(newCollectionName());
    final Map<String, Json> docs = <String, Json>{
      'a': <String, Object?>{
        'n': 1,
        'tags': <String>['x'],
        'city': 'SF',
        'gone': null
      },
      'b': <String, Object?>{
        'n': 2,
        'tags': <String>['x', 'y'],
        'city': 'LA'
      },
      'c': <String, Object?>{
        'n': 3,
        'tags': <String>['z'],
        'city': 'NY'
      },
    };
    for (final MapEntry<String, Json> entry in docs.entries) {
      await collection.doc(entry.key).set(entry.value);
    }

    Future<List<String>> ids(Query<Json> query) async =>
        (await query.get(Source.server))
            .docs
            .map((QueryDocumentSnapshot<Json> d) => d.id)
            .toList();

    expect(await ids(collection.where('n', isGreaterThanOrEqualTo: 2)),
        <String>['b', 'c']);
    expect(await ids(collection.where('n', isEqualTo: 1)), <String>['a']);
    expect(
        await ids(collection.where('n', isNotEqualTo: 2)), <String>['a', 'c']);
    expect(await ids(collection.where('tags', arrayContains: 'x')),
        <String>['a', 'b']);
    expect(
        await ids(
            collection.where('tags', arrayContainsAny: <String>['y', 'z'])),
        <String>['b', 'c']);
    expect(await ids(collection.where('city', whereIn: <String>['SF', 'NY'])),
        <String>['a', 'c']);
    expect(await ids(collection.where('city', whereNotIn: <String>['SF'])),
        <String>['b', 'c']);
    expect(await ids(collection.where('gone', isNull: true)), <String>['a']);
    expect(
        await ids(collection
            .where('n', isGreaterThan: 1)
            .orderBy('n', Direction.descending)
            .limit(1)),
        <String>['c']);
  });

  test('reads and writes through a converter', () async {
    final Firestore firestore = await newClient();
    final CollectionReference<City> cities = firestore
        .collection(newCollectionName())
        .withConverter<City>(cityConverter);
    await cities.doc('sf').set(const City('San Francisco', 870000));
    await cities.doc('la').set(const City('Los Angeles', 3900000));

    final DocumentSnapshot<City> sf = await cities.doc('sf').get(Source.server);
    expect(sf.data!.name, 'San Francisco');

    final QuerySnapshot<City> big = await cities
        .where('population', isGreaterThan: 1000000)
        .get(Source.server);
    expect(big.docs.single.data.name, 'Los Angeles');

    // Without the converter the same documents are plain maps.
    expect(
        (await firestore.collection(cities.id).doc('sf').get(Source.server))
            .data,
        <String, Object?>{'name': 'San Francisco', 'population': 870000});
  });

  test('waitForPendingWrites completes once the writes are acknowledged',
      () async {
    final Firestore firestore = await newClient();
    final DocumentReference<Json> doc =
        firestore.collection(newCollectionName()).doc('a');

    await firestore.disableNetwork();
    bool acknowledged = false;
    unawaited(
        doc.set(<String, Object?>{'a': 1}).then((_) => acknowledged = true));
    bool waited = false;
    final Future<void> waiting =
        firestore.waitForPendingWrites().then((_) => waited = true);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(acknowledged, isFalse);
    expect(waited, isFalse);

    await firestore.enableNetwork();
    await waiting.timeout(const Duration(seconds: 20));
    expect(waited, isTrue);

    final Firestore other = await newClient();
    expect((await other.doc(doc.path).get(Source.server)).data,
        <String, Object?>{'a': 1});
  });

  test('terminate ends the client; clearPersistence has nothing to delete',
      () async {
    final Firestore firestore = await newClient();
    final DocumentReference<Json> doc =
        firestore.collection(newCollectionName()).doc('a');
    await doc.set(<String, Object?>{'a': 1});

    // While the client runs clearing is refused.
    await expectLater(
        firestore.clearPersistence(),
        throwsA(isA<FirestoreError>().having((FirestoreError e) => e.code,
            'code', FirestoreErrorCode.failedPrecondition)));

    await firestore.terminate();
    // The cache was in memory, so this is a no-op, but it must not fail for
    // the lack of a file system.
    await firestore.clearPersistence();

    await expectLater(doc.get(), throwsA(anything));

    // The write reached the backend before the client ended.
    final Firestore other = await newClient();
    expect((await other.doc(doc.path).get(Source.server)).data,
        <String, Object?>{'a': 1});
  });
}
