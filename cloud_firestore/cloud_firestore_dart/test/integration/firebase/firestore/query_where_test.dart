// Emulator tests of the FlutterFire-style `Query.where(field, isEqualTo: ...)`
// sugar: the named arguments must select the same documents on the backend
// and in the local cache as the filters they stand for.

import 'package:cloud_firestore_dart/src/firebase/firestore/collection_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_data_converter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/set_options.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/source.dart';
import 'package:test/test.dart';

import '../../../util/integration_test_util.dart';

const testFirestore = IntegrationTestUtil.testFirestore;
const testCollectionWithDocs = IntegrationTestUtil.testCollectionWithDocs;

String _nameFromFirestore(
        DocumentSnapshot<Map<String, Object?>> snapshot, Object? _) =>
    snapshot.data!['name']! as String;

Map<String, Object?> _nameToFirestore(String value, SetOptions? _) =>
    <String, Object?>{'name': value};

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/query_where';

  setUp(() => testFirestore());

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  final Map<String, Map<String, Object?>> people =
      <String, Map<String, Object?>>{
    'ana': <String, Object?>{
      'name': 'Ana',
      'age': 17,
      'tags': <String>['a', 'b'],
      'nick': null
    },
    'bob': <String, Object?>{
      'name': 'Bob',
      'age': 30,
      'tags': <String>['b'],
      'nick': 'bobby'
    },
    'cat': <String, Object?>{
      'name': 'Cat',
      'age': 65,
      'tags': <String>['c'],
      'nick': 'kit'
    },
    'dan': <String, Object?>{'name': 'Dan', 'age': 41, 'tags': <String>[]},
  };

  /// The sorted ids [query] returns from the backend, after checking that
  /// the cache returns the same ones.
  Future<List<String>> ids(Query<Object?> query) async {
    List<String> sorted(QuerySnapshot<Object?> snapshot) =>
        snapshot.docs.map((DocumentSnapshot<Object?> doc) => doc.id).toList()
          ..sort();
    final List<String> server = sorted(await query.get(Source.server));
    expect(sorted(await query.get(Source.cache)), server, reason: 'cache');
    return server;
  }

  test('named arguments filter on the backend and in the cache', () async {
    final CollectionReference c = await testCollectionWithDocs(people);

    expect(await ids(c.where('age', isEqualTo: 30)), <String>['bob']);
    expect(await ids(c.where('age', isNotEqualTo: 30)),
        <String>['ana', 'cat', 'dan']);
    expect(await ids(c.where('age', isLessThan: 30)), <String>['ana']);
    expect(await ids(c.where('age', isLessThanOrEqualTo: 30)),
        <String>['ana', 'bob']);
    expect(await ids(c.where('age', isGreaterThan: 41)), <String>['cat']);
    expect(await ids(c.where('age', isGreaterThanOrEqualTo: 41)),
        <String>['cat', 'dan']);
    expect(
        await ids(c.where('tags', arrayContains: 'b')), <String>['ana', 'bob']);
    expect(await ids(c.where('tags', arrayContainsAny: <String>['a', 'c'])),
        <String>['ana', 'cat']);
    expect(await ids(c.where('age', whereIn: <int>{17, 65, 99})),
        <String>['ana', 'cat']);
    expect(await ids(c.where('age', whereNotIn: <int>[17, 65])),
        <String>['bob', 'dan']);
    expect(await ids(c.where('nick', isNull: true)), <String>['ana']);
    expect(await ids(c.where('nick', isNull: false)), <String>['bob', 'cat']);
  });

  test('several named arguments, FieldPath fields and Filters', () async {
    final CollectionReference c = await testCollectionWithDocs(people);

    expect(
        await ids(c.where('age', isGreaterThanOrEqualTo: 18, isLessThan: 65)),
        <String>['bob', 'dan']);
    expect(
        await ids(c
            .where('age', isGreaterThan: 17)
            .where('tags', arrayContains: 'b')),
        <String>['bob']);
    expect(
        await ids(c
            .where(FieldPath.documentIdField, whereIn: <String>['ana', 'dan'])),
        <String>['ana', 'dan']);
    expect(await ids(c.where(FieldPath.of(<String>['name']), isEqualTo: 'Cat')),
        <String>['cat']);
    // The Filter form keeps working and can be mixed with the sugar.
    expect(
        await ids(c
            .where(Filter.or(<Filter>[
              Filter.equalTo('name', 'Ana'),
              Filter.equalTo('name', 'Bob'),
              Filter.equalTo('name', 'Cat'),
            ]))
            .where('age', isGreaterThan: 17)),
        <String>['bob', 'cat']);
  });

  test('works on a query with a converter', () async {
    final CollectionReference c = await testCollectionWithDocs(people);
    final Query<String> names = c.withConverter<String>(
        const FirestoreDataConverter<String>.from(
            fromFirestore: _nameFromFirestore, toFirestore: _nameToFirestore));

    final QuerySnapshot<String> snapshot =
        await names.where('age', isGreaterThan: 30).get(Source.server);
    expect(
        snapshot.docs.map((DocumentSnapshot<String> d) => d.data).toList()
          ..sort(),
        <String>['Cat', 'Dan']);
  });
}
