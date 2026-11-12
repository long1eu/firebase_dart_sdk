// Tests of the FlutterFire-style `Query.where(field, isEqualTo: ...)` sugar.

import 'package:cloud_firestore_dart/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/filter.dart'
    show Filter;
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_data_converter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/set_options.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/user_data_converter.dart';
import 'package:test/test.dart';

import '../../../util/test_util.dart' as util;
import 'test_util.dart' as unit;

class _TestFirestore extends unit.FirebaseFirestoreMock {
  @override
  DatabaseId get databaseId => DatabaseId.forProject('project');

  @override
  UserDataConverter get dataConverter => UserDataConverter(databaseId);
}

String _fromFirestore(
        DocumentSnapshot<Map<String, Object?>> snapshot, Object? _) =>
    snapshot.id;

Map<String, Object?> _toFirestore(String value, SetOptions? _) =>
    <String, Object?>{'value': value};

void main() {
  final Firestore db = _TestFirestore();
  Query<Map<String, Object?>> collection() =>
      Query<Map<String, Object?>>(util.query('collection'), db);

  test('each named argument builds the same query as the where* method', () {
    final Query<Map<String, Object?>> q = collection();
    expect(q.where('a', isEqualTo: 1), q.whereEqualTo('a', 1));
    expect(q.where('a', isNotEqualTo: 1), q.whereNotEqualTo('a', 1));
    expect(q.where('a', isLessThan: 1), q.whereLessThan('a', 1));
    expect(
        q.where('a', isLessThanOrEqualTo: 1), q.whereLessThanOrEqualTo('a', 1));
    expect(q.where('a', isGreaterThan: 1), q.whereGreaterThan('a', 1));
    expect(q.where('a', isGreaterThanOrEqualTo: 1),
        q.whereGreaterThanOrEqualTo('a', 1));
    expect(q.where('a', arrayContains: 1), q.whereArrayContains('a', 1));
    expect(q.where('a', arrayContainsAny: <int>[1, 2]),
        q.whereArrayContainsAny('a', <Object?>[1, 2]));
    expect(q.where('a', whereIn: <int>[1, 2]), q.whereIn('a', <Object?>[1, 2]));
    expect(q.where('a', whereNotIn: <int>[1, 2]),
        q.whereNotIn('a', <Object?>[1, 2]));
    expect(q.where('a', isNull: true), q.whereEqualTo('a', null));
    expect(q.where('a', isNull: false), q.whereNotEqualTo('a', null));
  });

  test('iterables that are not lists are accepted', () {
    final Query<Map<String, Object?>> q = collection();
    expect(q.where('a', whereIn: <int>{1, 2}), q.whereIn('a', <Object?>[1, 2]));
    expect(q.where('a', arrayContainsAny: <int>[1, 2].map((int i) => i)),
        q.whereArrayContainsAny('a', <Object?>[1, 2]));
  });

  test('several named arguments are combined with AND', () {
    final Query<Map<String, Object?>> q = collection();
    expect(q.where('age', isGreaterThanOrEqualTo: 18, isLessThan: 65),
        q.whereLessThan('age', 65).whereGreaterThanOrEqualTo('age', 18));
    expect(q.where('age', isGreaterThanOrEqualTo: 18, isLessThan: 65),
        isNot(q.whereGreaterThanOrEqualTo('age', 18)),
        reason: 'both filters must be present');
  });

  test('the field can be a dotted string or a FieldPath', () {
    final Query<Map<String, Object?>> q = collection();
    expect(q.where('a.b', isEqualTo: 1),
        q.whereEqualToField(FieldPath.of(<String>['a', 'b']), 1));
    expect(q.where(FieldPath.of(<String>['a.b']), isEqualTo: 1),
        q.whereEqualToField(FieldPath.of(<String>['a.b']), 1));
    expect(q.where(FieldPath.of(<String>['a.b']), isEqualTo: 1),
        isNot(q.where('a.b', isEqualTo: 1)));
  });

  test('a Filter is still accepted', () {
    final Query<Map<String, Object?>> q = collection();
    expect(q.where(Filter.equalTo('a', 1)), q.whereEqualTo('a', 1));
    expect(q.where(Filter.and(<Filter>[])), same(q));
    final Filter or =
        Filter.or(<Filter>[Filter.equalTo('a', 1), Filter.greaterThan('b', 2)]);
    expect(q.where(or), q.where(or));
    expect(q.where(or), isNot(q));
  });

  test('keeps the type and the converter of the query', () {
    const FirestoreDataConverter<String> converter =
        FirestoreDataConverter<String>.from(
            fromFirestore: _fromFirestore, toFirestore: _toFirestore);
    final Query<String> typed = collection().withConverter<String>(converter);
    final Query<String> filtered = typed.where('a', isEqualTo: 1);
    expect(filtered.converter, same(converter));
    expect(filtered, typed.whereEqualTo('a', 1));
    final Query<String> filteredByFilter = typed.where(Filter.equalTo('a', 1));
    expect(filteredByFilter, filtered);
  });

  test('rejects invalid arguments', () {
    final Query<Map<String, Object?>> q = collection();
    Matcher throwsArgument(String message) =>
        throwsA(isA<ArgumentError>().having(
            (ArgumentError e) => e.message.toString(),
            'message',
            contains(message)));

    expect(() => q.where('a'), throwsArgument('at least one non-null'));
    expect(() => q.where('a', isEqualTo: null),
        throwsArgument('Use isNull to compare with null'));
    expect(() => q.where(Filter.equalTo('a', 1), isEqualTo: 1),
        throwsArgument('cannot be combined with a Filter'));
    expect(() => q.where(Filter.equalTo('a', 1), isNull: false),
        throwsArgument('cannot be combined with a Filter'));
    expect(() => q.where(42, isEqualTo: 1),
        throwsArgument('expects a Filter, a String field or a FieldPath'));
    // The usual query validation still applies.
    expect(() => q.where('a', whereIn: <int>[]), throwsA(isA<ArgumentError>()));
    expect(() => q.where('a', whereIn: <int>[1], whereNotIn: <int>[2]),
        throwsA(isA<ArgumentError>()));
  });
}
