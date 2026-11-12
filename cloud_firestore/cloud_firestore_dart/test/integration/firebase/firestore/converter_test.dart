import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart'
    show autoId;
import 'package:test/test.dart';

import '../../../util/integration_test_util.dart';

class City {
  const City(this.name, this.population, [this.updated]);

  factory City.fromMap(Map<String, Object?> map) =>
      City(map['name']! as String, map['population']! as int, map['updated']);

  final String name;
  final int population;
  final Object? updated;

  Map<String, Object?> toMap() => <String, Object?>{
        'name': name,
        'population': population,
        if (updated != null) 'updated': updated,
      };
}

final FirestoreDataConverter<City> cityConverter =
    FirestoreDataConverter<City>.from(
  fromFirestore: (DocumentSnapshot<Map<String, Object?>> snapshot,
          SnapshotOptions? options) =>
      City.fromMap(snapshot
          .getData(options?.serverTimestamps ?? ServerTimestampBehavior.none)!),
  toFirestore: (City city, SetOptions? options) => city.toMap(),
);

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/converter_test';
  late Firestore firestore;

  setUp(() async {
    firestore = await IntegrationTestUtil.testFirestore();
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  CollectionReference<City> cities() => firestore
      .collection('cities${autoId()}')
      .withConverter<City>(cityConverter);

  test('set and get round trip through the converter', () async {
    final DocumentReference<City> ref = cities().doc('sf');
    await ref.set(const City('San Francisco', 870000));

    final DocumentSnapshot<City> snapshot = await ref.get();
    expect(snapshot.exists, isTrue);
    final City city = snapshot.data!;
    expect(city.name, 'San Francisco');
    expect(city.population, 870000);

    // Stored data is the raw map.
    final DocumentSnapshot<Map<String, Object?>> raw =
        await ref.withoutConverter().get();
    expect(raw.data, <String, Object?>{
      'name': 'San Francisco',
      'population': 870000,
    });
  });

  test('missing document yields null data', () async {
    final DocumentSnapshot<City> snapshot = await cities().doc('nope').get();
    expect(snapshot.exists, isFalse);
    expect(snapshot.data, isNull);
  });

  test('add returns a typed reference', () async {
    final CollectionReference<City> col = cities();
    final DocumentReference<City> ref =
        await col.add(const City('Los Angeles', 4000000));
    final City city = (await ref.get()).data!;
    expect(city.name, 'Los Angeles');
  });

  test('queries return typed snapshots, refinements keep the converter',
      () async {
    final CollectionReference<City> col = cities();
    await col.doc('a').set(const City('A', 1));
    await col.doc('b').set(const City('B', 2));
    await col.doc('c').set(const City('C', 3));

    final Query<City> query =
        col.whereGreaterThan('population', 1).orderBy('population');
    final QuerySnapshot<City> snapshot = await query.get();
    expect(snapshot.docs.map((QueryDocumentSnapshot<City> d) => d.data.name),
        <String>['B', 'C']);
    expect(snapshot.docs.first.ref.converter, same(cityConverter));

    final QuerySnapshot<Map<String, Object?>> rawSnapshot =
        await query.withoutConverter().get();
    expect(rawSnapshot.docs.first.data['name'], 'B');

    // Query.withConverter on a raw query.
    final QuerySnapshot<City> viaQuery = await firestore
        .collection(col.id)
        .orderBy('population')
        .limit(1)
        .withConverter<City>(cityConverter)
        .get();
    expect(viaQuery.docs.single.data.name, 'A');
  });

  test('snapshots stream and docChanges are typed', () async {
    final CollectionReference<City> col = cities();
    await col.doc('a').set(const City('A', 1));

    final QuerySnapshot<City> first = await col.snapshots.first;
    expect(first.docChanges.single.document.data.name, 'A');

    final DocumentSnapshot<City> docSnap = await col.doc('a').snapshots.first;
    expect(docSnap.data!.population, 1);
  });

  test('merge set passes SetOptions to toFirestore', () async {
    final List<SetOptions?> seen = <SetOptions?>[];
    final FirestoreDataConverter<City> recording =
        FirestoreDataConverter<City>.from(
      fromFirestore:
          (DocumentSnapshot<Map<String, Object?>> s, SnapshotOptions? o) =>
              City.fromMap(s.data!),
      toFirestore: (City c, SetOptions? o) {
        seen.add(o);
        return <String, Object?>{'population': c.population};
      },
    );
    final DocumentReference<Map<String, Object?>> raw =
        firestore.collection('cities${autoId()}').doc('x');
    await raw.set(<String, Object?>{'name': 'X', 'population': 1});
    await raw
        .withConverter<City>(recording)
        .set(const City('ignored', 9), SetOptions.mergeAllFields);
    expect(seen.single, same(SetOptions.mergeAllFields));
    expect((await raw.get()).data,
        <String, Object?>{'name': 'X', 'population': 9});
  });

  test('update takes a raw field map', () async {
    final DocumentReference<City> ref = cities().doc('u');
    await ref.set(const City('U', 1));
    await ref.update(<String, Object?>{'population': 5});
    expect((await ref.get()).data!.population, 5);
  });

  test('server timestamps go through SnapshotOptions', () async {
    final DocumentReference<City> ref = cities().doc('t');
    await ref.set(City('T', 1, FieldValue.serverTimestamp()));
    final City city = (await ref.get()).data!;
    expect(city.updated, isA<Timestamp>());
  });

  test('WriteBatch and Transaction use the converter', () async {
    final CollectionReference<City> col = cities();
    final DocumentReference<City> b = col.doc('b');
    final DocumentReference<City> t = col.doc('t');

    await (firestore.batch()..set(b, const City('B', 2))).commit();
    expect((await b.get()).data!.name, 'B');

    final String name =
        await firestore.runTransaction<String>((Transaction transaction) async {
      final DocumentSnapshot<City> snap = await transaction.get(b);
      // The port requires every document read to also be written.
      transaction
        ..set(b, snap.data!)
        ..set(t, City('${snap.data!.name}!', 3));
      return snap.data!.name;
    });
    expect(name, 'B');
    expect((await t.get()).data!.name, 'B!');
  });

  test('converter identity participates in equality', () {
    final CollectionReference<City> a = cities();
    expect(a.withoutConverter().doc('z'), isNot(a.doc('z')));
    expect(a.doc('z').withoutConverter().withConverter<City>(cityConverter),
        a.doc('z'));
  });
}
