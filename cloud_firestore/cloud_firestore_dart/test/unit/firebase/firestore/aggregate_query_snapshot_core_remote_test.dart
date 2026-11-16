// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'package:cloud_firestore_dart/src/firebase/firestore/aggregate_field.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/aggregate_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/aggregate_query_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:test/test.dart';

import '../../../util/test_util.dart' as util;
import 'test_util.dart' as unit;

/// Ported from upstream AggregateQuerySnapshotTest and AggregateQueryTest
/// (current `main`), extended to the sum / average fields of the port.
void main() {
  AggregateQuery countQuery(String path) => AggregateQueryInternal.create(
      unit.query(path), <AggregateField>[AggregateField.count()]);

  Map<String, FieldValue> data(Map<String, Object?> raw) => raw.map(
      (String k, Object? v) => MapEntry<String, FieldValue>(k, util.wrap(v)));

  group('AggregateQuerySnapshot', () {
    test('createWithCountShouldReturnInstanceWithTheGivenQueryAndCount', () {
      final AggregateQuery query = countQuery('foo');
      final AggregateQuerySnapshot snapshot =
          AggregateQuerySnapshotInternal.create(query, data(<String, Object?>{'count': 42}));

      expect(snapshot.query, same(query));
      expect(snapshot.count, 42);
    });

    test('equality and hashCode consider query and data', () {
      final AggregateQuery query = countQuery('foo');
      final AggregateQuerySnapshot a =
          AggregateQuerySnapshotInternal.create(query, data(<String, Object?>{'count': 1}));
      final AggregateQuerySnapshot b = AggregateQuerySnapshotInternal.create(
          countQuery('foo'), data(<String, Object?>{'count': 1}));
      final AggregateQuerySnapshot otherCount =
          AggregateQuerySnapshotInternal.create(query, data(<String, Object?>{'count': 2}));
      final AggregateQuerySnapshot otherQuery = AggregateQuerySnapshotInternal.create(
          countQuery('bar'), data(<String, Object?>{'count': 1}));

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(otherCount));
      expect(a, isNot(otherQuery));
    });

    test('data is copied defensively', () {
      final Map<String, FieldValue> raw = data(<String, Object?>{'count': 1});
      final AggregateQuerySnapshot snapshot =
          AggregateQuerySnapshotInternal.create(countQuery('foo'), raw);
      raw['count'] = util.wrap(5);
      expect(snapshot.count, 1);
    });

    test('count is null when the count alias is null', () {
      final AggregateQuerySnapshot snapshot = AggregateQuerySnapshotInternal.create(
          countQuery('foo'), data(<String, Object?>{'count': null}));
      expect(snapshot.count, isNull);
    });

    test('reading a field that was not requested fails', () {
      final AggregateQuerySnapshot snapshot = AggregateQuerySnapshotInternal.create(
          countQuery('foo'), data(<String, Object?>{'count': 1}));
      expect(() => snapshot.get(AggregateField.sum('a')), throwsArgumentError);
      expect(() => (snapshot.get(AggregateField.average('a')) as num?)?.toInt(),
          throwsArgumentError);
    });

    test('sum and average values are read as int, double or null', () {
      final AggregateQuerySnapshot snapshot = AggregateQuerySnapshotInternal.create(
        countQuery('foo'),
        data(<String, Object?>{
          'sum_a': 5,
          'average_a': 2.5,
          'sum_b': null,
          'average_b': 3.7,
          'sum_c': 3,
        }),
      );
      expect((snapshot.get(AggregateField.sum('a')) as num?)?.toInt(), 5);
      expect((snapshot.get(AggregateField.sum('a')) as num?)?.toDouble(), 5.0);
      expect((snapshot.get(AggregateField.average('a')) as num?)?.toDouble(), 2.5);
      expect(snapshot.get(AggregateField.sum('b')), isNull);
      expect((snapshot.get(AggregateField.sum('b')) as num?)?.toInt(), isNull);
      expect((snapshot.get(AggregateField.sum('b')) as num?)?.toDouble(), isNull);
      // Doubles are truncated when read as int.
      expect((snapshot.get(AggregateField.average('b')) as num?)?.toInt(), 3);
      expect((snapshot.get(AggregateField.sum('c')) as num?)?.toDouble(), 3.0);
    });

    test('non numeric values cannot be read as numbers', () {
      final AggregateQuerySnapshot snapshot = AggregateQuerySnapshotInternal.create(
          countQuery('foo'), data(<String, Object?>{'sum_a': 'text'}));
      expect(() => snapshot.getSum('a'), throwsStateError);
    });

    test('NaN and infinity are kept by getAverage', () {
      final AggregateQuerySnapshot snapshot = AggregateQuerySnapshotInternal.create(
        countQuery('foo'),
        data(<String, Object?>{
          'average_nan': double.nan,
          'average_inf': double.infinity,
        }),
      );
      expect(snapshot.getAverage('nan'), isNaN);
      expect(snapshot.getAverage('inf'), double.infinity);
    });
  });

  group('AggregateQuery', () {
    test('equality and hashCode consider query and fields', () {
      final AggregateQuery a = AggregateQueryInternal.create(unit.query('foo'),
          <AggregateField>[AggregateField.count(), AggregateField.sum('x')]);
      final AggregateQuery b = AggregateQueryInternal.create(unit.query('foo'),
          <AggregateField>[AggregateField.count(), AggregateField.sum('x')]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
          a,
          isNot(AggregateQueryInternal.create(
              unit.query('foo'), <AggregateField>[AggregateField.count()])));
      expect(
          a,
          isNot(AggregateQueryInternal.create(unit.query('bar'), <AggregateField>[
            AggregateField.count(),
            AggregateField.sum('x')
          ])));
      // Order of the aggregations is significant.
      expect(
          a,
          isNot(AggregateQueryInternal.create(unit.query('foo'), <AggregateField>[
            AggregateField.sum('x'),
            AggregateField.count()
          ])));
    });

    test('the list of fields is unmodifiable', () {
      final AggregateQuery q = countQuery('foo');
      expect(() => q.aggregateFields.add(AggregateField.sum('x')),
          throwsUnsupportedError);
    });

    test('the Query.aggregate helper wraps the query and the fields', () {
      final AggregateQuery q =
          unit.query('foo').aggregate(<AggregateField>[AggregateField.count()]);
      expect(q.query, unit.query('foo'));
      expect(q.aggregateFields, <AggregateField>[AggregateField.count()]);
    });
  });

  group('AggregateField', () {
    test('aliases', () {
      expect(AggregateField.count().alias, 'count');
      expect(AggregateField.sum('a.b').alias, 'sum_a.b');
      expect(AggregateField.average('a').alias, 'average_a');
    });

    test('equality', () {
      expect(AggregateField.count(), AggregateField.count());
      expect(AggregateField.count().hashCode, AggregateField.count().hashCode);
      expect(AggregateField.sum('a'), AggregateField.sum('a'));
      expect(
          AggregateField.sum('a').hashCode, AggregateField.sum('a').hashCode);
      expect(AggregateField.sum('a'), isNot(AggregateField.sum('b')));
      expect(AggregateField.sum('a'), isNot(AggregateField.average('a')));
      expect(AggregateField.sum('a'), isNot(AggregateField.count()));
      expect(AggregateField.count(), isNot(AggregateField.sum('a')));
    });

    test('field path variants match the string variants', () {
      expect(AggregateField.sum(FieldPath.fromString('a.b')),
          AggregateField.sum('a.b'));
      expect(AggregateField.average(FieldPath.fromString('a.b')),
          AggregateField.average('a.b'));
    });

    test('toString', () {
      expect(AggregateField.count().toString(), 'count()');
      expect(AggregateField.sum('a').toString(), 'sum(a)');
    });
  });
}
