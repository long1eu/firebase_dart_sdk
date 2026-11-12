// Regression test for a difference between the client and the backend that
// the mutation property found
// (test/integration/firebase/firestore/property_mutation_test.dart):
// arrayUnion and arrayRemove compare numbers by value.

import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/array_transform_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

void main() {
  List<FieldValue> values(List<Object?> list) => list.map(wrap).toList();

  FieldValue union(List<Object?> current, List<Object?> elements) =>
      ArrayTransformOperationUnion(values(elements)).apply(wrap(current));

  FieldValue remove(List<Object?> current, List<Object?> elements) =>
      ArrayTransformOperationRemove(values(elements)).apply(wrap(current));

  test('arrayUnion does not add a number that is there with another type', () {
    expect(union(<Object?>[1], <Object?>[1.0]), wrap(<Object?>[1]));
    expect(union(<Object?>[1.0], <Object?>[1]), wrap(<Object?>[1.0]));
    expect(union(<Object?>[0], <Object?>[-0.0]), wrap(<Object?>[0]));
    expect(union(<Object?>[], <Object?>[1.0, 1]), wrap(<Object?>[1.0]));
    expect(union(<Object?>[1], <Object?>[1.5]), wrap(<Object?>[1, 1.5]));
    expect(
        union(<Object?>[
          <String, Object?>{'k': 1}
        ], <Object?>[
          <String, Object?>{'k': 1.0}
        ]),
        wrap(<Object?>[
          <String, Object?>{'k': 1}
        ]));
  });

  test('arrayUnion adds null and NaN once', () {
    expect(union(<Object?>[null], <Object?>[null]), wrap(<Object?>[null]));
    expect(union(<Object?>[double.nan], <Object?>[double.nan]),
        wrap(<Object?>[double.nan]));
  });

  test('arrayRemove removes a number whatever its type', () {
    expect(remove(<Object?>[1, 2, 1.0], <Object?>[1.0]), wrap(<Object?>[2]));
    expect(remove(<Object?>[0.0, -0.0, 0], <Object?>[0]), wrap(<Object?>[]));
    expect(remove(<Object?>[1, 'a', null], <Object?>[null, 'a']),
        wrap(<Object?>[1]));
    expect(remove(<Object?>[1.5], <Object?>[1]), wrap(<Object?>[1.5]));
  });
}
