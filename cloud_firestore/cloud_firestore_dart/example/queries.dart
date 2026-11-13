// Queries: filters with named arguments, `Filter.or`, ordering, `limitToLast`
// and cursors.
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/queries.dart

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import 'common.dart';

List<String> ids(QuerySnapshot<Map<String, Object?>> snapshot) => <String>[
  for (final doc in snapshot.docs) doc.id,
];

Future<void> main() async {
  final Firestore firestore = connect();
  final CollectionReference<Map<String, Object?>> cities = firestore.collection(
    scratch('cities'),
  );

  // A batch writes all the documents in one request.
  final WriteBatch batch = firestore.batch();
  <String, Map<String, Object?>>{
    'lisbon': {
      'country': 'PT',
      'population': 545000,
      'tags': ['capital'],
    },
    'milan': {
      'country': 'IT',
      'population': 1370000,
      'tags': ['fashion'],
    },
    'paris': {
      'country': 'FR',
      'population': 2100000,
      'tags': ['capital'],
    },
    'porto': {
      'country': 'PT',
      'population': 232000,
      'tags': ['port'],
    },
    'rome': {
      'country': 'IT',
      'population': 2800000,
      'tags': ['capital'],
    },
  }.forEach((String id, Map<String, Object?> data) {
    batch.set(cities.doc(id), data);
  });
  await batch.commit();

  // Named arguments on a field; all of them have to match.
  print('IT: ${ids(await cities.where('country', isEqualTo: 'IT').get())}');
  print(
    '500k..2.5m: ${ids(await cities.where('population', isGreaterThan: 500000, isLessThan: 2500000).get())}',
  );
  print(
    'PT or FR: ${ids(await cities.where('country', whereIn: <String>['PT', 'FR']).get())}',
  );
  print(
    'capitals: ${ids(await cities.where('tags', arrayContains: 'capital').get())}',
  );

  // The same filters exist as methods named like in the Android SDK.
  print('not IT: ${ids(await cities.whereNotEqualTo('country', 'IT').get())}');

  // OR queries are built with Filter.or / Filter.and.
  final Query<Map<String, Object?>> either = cities.where(
    Filter.or(<Filter>[
      Filter.equalTo('country', 'PT'),
      Filter.and(<Filter>[
        Filter.equalTo('country', 'IT'),
        Filter.greaterThan('population', 2000000),
      ]),
    ]),
  );
  print('PT, or IT above 2m: ${ids(await either.get())}');

  // Ordering and limits. limitToLast returns the last documents of the
  // ordering, still in ascending order.
  final Query<Map<String, Object?>> byPopulation = cities.orderBy('population');
  print('2 smallest: ${ids(await byPopulation.limit(2).get())}');
  print('2 largest: ${ids(await byPopulation.limitToLast(2).get())}');
  print(
    'descending: ${ids(await cities.orderBy('population', Direction.descending).limit(2).get())}',
  );

  // Cursors: by field values, or by a document snapshot (the usual way to
  // page through a result).
  print(
    'from 1m: ${ids(await byPopulation.startAt(<Object?>[1000000]).get())}',
  );
  final QuerySnapshot<Map<String, Object?>> firstPage = await byPopulation
      .limit(2)
      .get();
  final QuerySnapshot<Map<String, Object?>> secondPage = await byPopulation
      .startAfterDocument(firstPage.docs.last)
      .limit(2)
      .get();
  print('page 1: ${ids(firstPage)}, page 2: ${ids(secondPage)}');

  // The document id is a field too.
  print(
    'ids up to m: ${ids(await cities.where(FieldPath.documentIdField, isLessThan: cities.doc('m')).get())}',
  );

  await firestore.terminate();
}
