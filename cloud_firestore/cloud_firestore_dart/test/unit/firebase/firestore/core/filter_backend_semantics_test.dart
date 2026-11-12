// Regression tests for the differences between the local evaluation of a
// filter and the (Standard edition) backend that the query property found
// (test/integration/firebase/firestore/property_query_test.dart). Each of
// them left a cached document in limbo forever, so that the query never got
// in sync and `get(Source.server)` did not complete.

import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

void main() {
  Document docWith(Object? value) =>
      doc('coll/doc', 1, <String, Object?>{'v': value});

  bool matches(String operator, Object? operand, Object? value) =>
      filter('v', operator, operand).matches(docWith(value));

  group('membership filters match numbers by value', () {
    test('in', () {
      expect(matches('in', <Object?>[1.0], 1), isTrue);
      expect(matches('in', <Object?>[1], 1.0), isTrue);
      expect(matches('in', <Object?>[-0.0], 0), isTrue);
      expect(matches('in', <Object?>[0], -0.0), isTrue);
      expect(matches('in', <Object?>[0.0], -0.0), isTrue);
      expect(matches('in', <Object?>[1.5], 1), isFalse);
      // Also inside arrays and maps.
      expect(
          matches('in', <Object?>[
            <Object?>[1.0, 2.0]
          ], <Object?>[
            1,
            2
          ]),
          isTrue);
      expect(
          matches('in', <Object?>[
            <String, Object?>{'x': 1.0}
          ], <String, Object?>{
            'x': 1
          }),
          isTrue);
    });

    test('not-in', () {
      expect(matches('not-in', <Object?>[1.0], 1), isFalse);
      expect(matches('not-in', <Object?>[-0.0], 0), isFalse);
      expect(matches('not-in', <Object?>[2.0], 1), isTrue);
    });

    test('array-contains', () {
      expect(matches('array-contains', 1.0, <Object?>[1, 2]), isTrue);
      expect(matches('array-contains', 1, <Object?>[1.0]), isTrue);
      expect(matches('array-contains', 0, <Object?>[-0.0]), isTrue);
      expect(matches('array-contains', 3.0, <Object?>[1, 2]), isFalse);
    });

    test('array-contains-any', () {
      expect(matches('array-contains-any', <Object?>[1.0, 'x'], <Object?>[1]),
          isTrue);
      expect(matches('array-contains-any', <Object?>[3.0, 'x'], <Object?>[1]),
          isFalse);
    });
  });

  // Null and NaN are members of a list that has them, as in the JS and
  // Android SDKs and in an Enterprise edition database. A Standard edition
  // database never matches them in these filters; that difference is pinned
  // by the query property test.
  group('null and NaN are the same as themselves', () {
    test('in and not-in', () {
      expect(matches('in', <Object?>[null], null), isTrue);
      expect(matches('in', <Object?>[double.nan], double.nan), isTrue);
      expect(matches('in', <Object?>[null, 1], 1), isTrue);
      expect(matches('in', <Object?>[null], 1), isFalse);
      expect(matches('not-in', <Object?>[1], double.nan), isTrue);
      expect(matches('not-in', <Object?>[double.nan], double.nan), isFalse);
      // Null is excluded, and a list with null matches nothing.
      expect(matches('not-in', <Object?>[1], null), isFalse);
      expect(matches('not-in', <Object?>[null], 1), isFalse);
    });

    test('array filters', () {
      expect(matches('array-contains', null, <Object?>[null]), isTrue);
      expect(
          matches('array-contains', double.nan, <Object?>[double.nan]), isTrue);
      expect(matches('array-contains', null, <Object?>[1]), isFalse);
      expect(
          matches('array-contains-any', <Object?>[null, 2], <Object?>[null, 1]),
          isTrue);
    });

    test('equality', () {
      expect(matches('==', null, null), isTrue);
      expect(matches('==', double.nan, double.nan), isTrue);
      expect(matches('!=', null, 1), isTrue);
      expect(matches('!=', double.nan, 1), isTrue);
      expect(matches('!=', double.nan, double.nan), isFalse);
      expect(matches('!=', 1, double.nan), isTrue);
      expect(matches('!=', 1, null), isFalse);
    });
  });

  group('null and NaN are not ordered in a filter', () {
    for (final String operator in <String>['<', '<=', '>', '>=']) {
      test('$operator with a number', () {
        // NaN sorts before every number, and null before everything.
        expect(matches(operator, 1, double.nan), isFalse);
        expect(matches(operator, double.nan, 1), isFalse);
        expect(matches(operator, null, 1), isFalse);
        expect(matches(operator, 1, null), isFalse);
        expect(matches(operator, null, double.nan), isFalse);
        expect(matches(operator, double.nan, null), isFalse);
      });
    }

    test('< and > never hold for them', () {
      for (final String operator in <String>['<', '>']) {
        expect(matches(operator, double.nan, double.nan), isFalse);
        expect(matches(operator, null, null), isFalse);
      }
    });

    test('<= and >= hold for null with null and NaN with NaN', () {
      for (final String operator in <String>['<=', '>=']) {
        expect(matches(operator, double.nan, double.nan), isTrue);
        expect(matches(operator, null, null), isTrue);
      }
    });

    test('other numbers compare as before', () {
      expect(matches('<', 2, 1), isTrue);
      expect(matches('<=', 1.0, 1), isTrue);
      expect(matches('>', 1, 1.5), isTrue);
      expect(matches('>=', 2, 1), isFalse);
    });
  });
}
