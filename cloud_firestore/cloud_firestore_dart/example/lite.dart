// Firestore Lite (experimental): the client without a local cache and without
// listeners. Every call is one request to the backend and one response.
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/lite.dart
//
// This file imports `lite.dart` and not `cloud_firestore_dart.dart` (nor
// common.dart, which does): a program that only imports the lite library
// does not contain the sync engine, the local store or the SQLite layer.

import 'dart:io';

import 'package:cloud_firestore_dart/lite.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

class City {
  const City(this.name, this.population);

  final String name;
  final int population;
}

final FirestoreDataConverter<City> cityConverter =
    FirestoreDataConverter<City>.from(
      fromFirestore: (QueryDocumentSnapshot<Map<String, Object?>> snapshot) =>
          City(
            snapshot.data['name']! as String,
            snapshot.data['population']! as int,
          ),
      toFirestore: (City city, SetOptions? options) => <String, Object?>{
        'name': city.name,
        'population': city.population,
      },
    );

Future<void> main() async {
  final String emulator =
      Platform.environment['FIRESTORE_EMULATOR_HOST'] ?? '127.0.0.1:8080';
  final int colon = emulator.lastIndexOf(':');

  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'demo-key',
      applicationId: '1:1234567890:dart:example',
      // A `demo-` project id keeps the emulator from talking to a real project.
      projectId: 'demo-example',
    ),
  );
  // Synchronous: there is no cache to open. Nothing is sent until the first
  // call.
  final Firestore firestore = Firestore.instanceFor(
    app: app,
    settings: FirestoreSettings().withEmulator(
      emulator.substring(0, colon),
      int.parse(emulator.substring(colon + 1)),
    ),
  );

  // A collection that is new on every run.
  final CollectionReference<Map<String, Object?>> cities = firestore.collection(
    'examples/${DateTime.now().microsecondsSinceEpoch}/cities',
  );

  // Writes complete when the backend has applied them.
  await cities.doc('SF').set({'name': 'San Francisco', 'population': 808000});
  await cities.doc('SF').update({'visits': FieldValue.increment(1)});

  final WriteBatch batch = firestore.batch()
    ..set(cities.doc('LA'), {'name': 'Los Angeles', 'population': 3820000})
    ..set(cities.doc('NYC'), {'name': 'New York', 'population': 8260000})
    ..set(cities.doc('SEA'), {'name': 'Seattle', 'population': 755000});
  await batch.commit();

  // Reads always come from the backend: there is no metadata and no Source.
  final DocumentSnapshot<Map<String, Object?>> sf = await cities
      .doc('SF')
      .get();
  print('SF: ${sf.data}');

  // Queries: the same builder as the main library.
  final QuerySnapshot<Map<String, Object?>> big = await cities
      .where('population', isGreaterThan: 800000)
      .orderBy('population', Direction.descending)
      .get();
  print('big: ${big.docs.map((doc) => doc.id).toList()}');

  // limitToLast: the flipped query is sent and the result reversed.
  final QuerySnapshot<Map<String, Object?>> largest = await cities
      .orderBy('population')
      .limitToLast(2)
      .get();
  print('two largest: ${largest.docs.map((doc) => doc.id).toList()}');

  // Pages with a cursor.
  final Query<Map<String, Object?>> byName = cities.orderBy('name').limit(2);
  final QuerySnapshot<Map<String, Object?>> first = await byName.get();
  final QuerySnapshot<Map<String, Object?>> second = await byName
      .startAfterDocument(first.docs.last)
      .get();
  print(
    'pages: ${first.docs.map((doc) => doc.id).toList()} '
    '${second.docs.map((doc) => doc.id).toList()}',
  );

  // Aggregations run on the server.
  final AggregateQuerySnapshot totals = await cities.aggregateWithAliases({
    'cities': AggregateField.count(),
    'people': AggregateField.sum('population'),
  }).get();
  print('totals: ${totals.data()}');

  // Converters.
  final QuerySnapshot<City> typed = await cities
      .withConverter(cityConverter)
      .orderBy('name')
      .limit(1)
      .get();
  print('first by name: ${typed.docs.single.data.name}');

  // A transaction: reads first, then writes. It is run again when a document
  // it read changed before the commit.
  final int population = await firestore.runTransaction<int>((
    Transaction transaction,
  ) async {
    final DocumentSnapshot<Map<String, Object?>> seattle = await transaction
        .get(cities.doc('SEA'));
    final int next = (seattle.get('population')! as int) + 1;
    transaction.update(cities.doc('SEA'), {'population': next});
    return next;
  });
  print('Seattle: $population');

  await cities.doc('NYC').delete();
  print('NYC exists: ${(await cities.doc('NYC').get()).exists}');

  // Terminate the instance: on native platforms the open gRPC channel keeps
  // the process alive otherwise.
  await firestore.terminate();
  try {
    await cities.doc('SF').get();
  } on FirestoreError catch (e) {
    print(
      'after terminate: ${e.code == FirestoreErrorCode.failedPrecondition}',
    );
  }
}
