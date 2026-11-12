// Typed data converters: read and write your own model class instead of maps.
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/converters.dart

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import 'common.dart';

class City {
  const City(this.name, this.population);

  factory City.fromMap(Map<String, Object?> map) =>
      City(map['name']! as String, map['population']! as int);

  final String name;
  final int population;

  Map<String, Object?> toMap() => <String, Object?>{
    'name': name,
    'population': population,
  };

  @override
  String toString() => 'City($name, $population)';
}

/// A converter can also be a subclass of [FirestoreDataConverter].
class CityConverter extends FirestoreDataConverter<City> {
  const CityConverter();

  @override
  City fromFirestore(
    DocumentSnapshot<Map<String, Object?>> snapshot,
    SnapshotOptions? options,
  ) => City.fromMap(snapshot.data!);

  @override
  Map<String, Object?> toFirestore(City value, SetOptions? options) =>
      value.toMap();
}

Future<void> main() async {
  final Firestore firestore = await connect();

  // From two functions...
  final FirestoreDataConverter<City> converter =
      FirestoreDataConverter<City>.from(
        fromFirestore: (snapshot, options) => City.fromMap(snapshot.data!),
        toFirestore: (city, options) => city.toMap(),
      );

  final CollectionReference<City> cities = firestore
      .collection(scratch('cities'))
      .withConverter<City>(converter);

  await cities.doc('sf').set(const City('San Francisco', 870000));
  await cities.doc('la').set(const City('Los Angeles', 3900000));

  final DocumentSnapshot<City> sf = await cities.doc('sf').get();
  print('document: ${sf.data}');

  // Queries keep the converter: filters still name the stored fields.
  final QuerySnapshot<City> big = await cities
      .where('population', isGreaterThan: 1000000)
      .get();
  print('query: ${<City>[for (final doc in big.docs) doc.data]}');

  // `update` always takes raw field values.
  await cities.doc('sf').update(<String, Object?>{'population': 880000});

  // ...or from a class; and back to maps with withoutConverter().
  final DocumentReference<City> typed = firestore
      .doc(cities.doc('sf').path)
      .withConverter<City>(const CityConverter());
  print('class converter: ${(await typed.get()).data}');
  final DocumentSnapshot<Map<String, Object?>> raw = await typed
      .withoutConverter()
      .get();
  print('raw: ${raw.data}');

  await firestore.terminate();
}
