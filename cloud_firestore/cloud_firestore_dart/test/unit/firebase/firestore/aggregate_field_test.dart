// Ported from the JS SDK's test/unit/api/aggregate.test.ts. JS's
// aggregateFieldEqual(a, b) is `a == b` here.

import 'package:cloud_firestore_dart/src/firebase/firestore/aggregate_field.dart';
import 'package:test/test.dart';

void main() {
  group('aggregateFieldEqual', () {
    test('equates two equal aggregate fields', () {
      expect(AggregateField.count() == AggregateField.count(), isTrue);
      expect(AggregateField.sum('foo') == AggregateField.sum('foo'), isTrue);
      expect(
        AggregateField.average('bar') == AggregateField.average('bar'),
        isTrue,
      );
      expect(
        AggregateField.sum('foo.bar') == AggregateField.sum('foo.bar'),
        isTrue,
      );
      expect(
        AggregateField.average('bar.baz') == AggregateField.average('bar.baz'),
        isTrue,
      );
    });

    test('differentiates two different aggregate fields', () {
      expect(AggregateField.sum('foo') == AggregateField.sum('bar'), isFalse);
      expect(
        AggregateField.average('foo') == AggregateField.average('bar'),
        isFalse,
      );
      expect(
        AggregateField.average('foo') == AggregateField.sum('foo'),
        isFalse,
      );
      expect(
        AggregateField.sum('foo') == AggregateField.average('foo'),
        isFalse,
      );
    });
  });
}
