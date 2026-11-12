// Copyright 2022 Google LLC
//
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
import 'package:cloud_firestore_dart/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/field_path.dart'
    as api;
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/aggregation_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as proto_v1;
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:fixnum/fixnum.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

void main() {
  late RemoteSerializer serializer;

  setUp(() => serializer = RemoteSerializer(DatabaseId.forDatabase('p', 'd')));

  proto.StructuredAggregationQuery encode(
      Query q, List<AggregateField> fields, Map<String, String> aliases) {
    return serializer.encodeStructuredAggregationQuery(
        serializer.encodeAggregateQueryTarget(q), fields, aliases);
  }

  group('AggregateField', () {
    test('aliases', () {
      expect(AggregateField.count().alias, 'count');
      expect(AggregateField.sum('a.b').alias, 'sum_a.b');
      expect(AggregateField.average('a').alias, 'average_a');
      expect(AggregateField.sum('a').fieldPath, 'a');
      expect(AggregateField.count().fieldPath, '');
    });

    test('equality', () {
      expect(AggregateField.count(), AggregateField.count());
      expect(AggregateField.sum('a'), AggregateField.sum('a'));
      expect(AggregateField.sum('a'),
          AggregateField.sumField(api.FieldPath.of(<String>['a'])));
      expect(AggregateField.sum('a'), isNot(AggregateField.sum('b')));
      expect(AggregateField.sum('a'), isNot(AggregateField.average('a')));
      expect(AggregateField.count(), isNot(AggregateField.sum('a')));
      expect(
          AggregateField.sum('a').hashCode, AggregateField.sum('a').hashCode);
    });
  });

  group('encodeStructuredAggregationQuery', () {
    test('count', () {
      final Map<String, String> aliases = <String, String>{};
      final proto.StructuredAggregationQuery result = encode(
          query('coll'), <AggregateField>[AggregateField.count()], aliases);

      expect(aliases, <String, String>{'aggregate_1': 'count'});
      expect(result.aggregations, hasLength(1));
      expect(result.aggregations[0].alias, 'aggregate_1');
      expect(result.aggregations[0].hasCount(), isTrue);
      expect(result.structuredQuery.from[0].collectionId, 'coll');
    });

    test('sum and average with nested and special field paths', () {
      final Map<String, String> aliases = <String, String>{};
      final proto.StructuredAggregationQuery result = encode(
          query('coll'),
          <AggregateField>[
            AggregateField.sum('a.b'),
            AggregateField.average('c'),
            AggregateField.sumField(api.FieldPath.of(<String>['d.e', 'f g'])),
          ],
          aliases);

      expect(aliases, <String, String>{
        'aggregate_1': 'sum_a.b',
        'aggregate_2': 'average_c',
        'aggregate_3': 'sum_`d.e`.`f g`',
      });
      expect(result.aggregations[0].hasSum(), isTrue);
      expect(result.aggregations[0].sum.field_1.fieldPath, 'a.b');
      expect(result.aggregations[1].hasAvg(), isTrue);
      expect(result.aggregations[1].avg.field_1.fieldPath, 'c');
      expect(result.aggregations[2].sum.field_1.fieldPath, '`d.e`.`f g`');
    });

    test('deduplicates identical aggregations', () {
      final Map<String, String> aliases = <String, String>{};
      final proto.StructuredAggregationQuery result = encode(
          query('coll'),
          <AggregateField>[
            AggregateField.count(),
            AggregateField.sum('a'),
            AggregateField.count(),
            AggregateField.sum('a'),
            AggregateField.average('a'),
          ],
          aliases);

      expect(result.aggregations, hasLength(3));
      expect(aliases, <String, String>{
        'aggregate_1': 'count',
        'aggregate_2': 'sum_a',
        'aggregate_3': 'average_a',
      });
    });

    test('sends filters, explicit orderBy and limit but no implicit order', () {
      final Query q = query('coll')
          .filter(filter('a', '==', 1))
          .orderBy(orderBy('b', 'desc'))
          .limit(5);
      final proto.StructuredAggregationQuery result = encode(
          q, <AggregateField>[AggregateField.count()], <String, String>{});

      expect(result.structuredQuery.hasWhere(), isTrue);
      expect(result.structuredQuery.orderBy, hasLength(1));
      expect(result.structuredQuery.orderBy[0].field_1.fieldPath, 'b');
      expect(result.structuredQuery.limit.value, 5);
    });

    test('composite filters and multiple inequalities are sent as filters', () {
      final Query q = query('coll')
          .filter(orFilters(<Filter>[
            filter('a', '>', 1),
            andFilters(<Filter>[filter('b', '==', 2), filter('c', '<', 3)]),
          ]))
          .filter(filter('d', '!=', 4));
      final proto.StructuredAggregationQuery result = encode(
          q, <AggregateField>[AggregateField.count()], <String, String>{});

      final proto.StructuredQuery_Filter where = result.structuredQuery.where;
      expect(where.hasCompositeFilter(), isTrue);
      expect(where.compositeFilter.op,
          proto.StructuredQuery_CompositeFilter_Operator.AND);
      expect(where.compositeFilter.filters, hasLength(2));
      expect(where.compositeFilter.filters[0].compositeFilter.op,
          proto.StructuredQuery_CompositeFilter_Operator.OR);
      // The implicit orderBy of the inequality fields is not sent.
      expect(result.structuredQuery.orderBy, isEmpty);
    });

    test('a query without explicit order sends no order', () {
      final proto.StructuredAggregationQuery result = encode(
          query('coll').filter(filter('a', '>', 1)),
          <AggregateField>[AggregateField.count()],
          <String, String>{});
      expect(result.structuredQuery.orderBy, isEmpty);
    });

    test('does not modify the listen target encoding', () {
      final Query q = query('coll').orderBy(orderBy('b'));
      serializer.encodeAggregateQueryTarget(q);
      expect(serializer.encodeQueryTarget(q.toTarget()).structuredQuery.orderBy,
          hasLength(2));
    });
  });

  group('decodeAggregationResult', () {
    test('maps aliases and decodes int, double and null', () {
      final Map<String, FieldValue> result = serializer.decodeAggregationResult(
        <String, proto_v1.Value>{
          'aggregate_1': proto_v1.Value()..integerValue = Int64(42),
          'aggregate_2': proto_v1.Value()..doubleValue = 1.5,
          'aggregate_3': proto_v1.Value()
            ..nullValue = proto.NullValue.NULL_VALUE,
        },
        <String, String>{
          'aggregate_1': 'count',
          'aggregate_2': 'sum_a',
          'aggregate_3': 'average_a',
        },
      );
      expect(result['count']!.value, 42);
      expect(result['sum_a']!.value, 1.5);
      expect(result['average_a']!.value, isNull);
    });

    test('fails for unknown server aliases', () {
      expect(
          () => serializer.decodeAggregationResult(<String, proto_v1.Value>{
                'x': proto_v1.Value()..integerValue = Int64(1)
              }, <String, String>{}),
          throwsA(anything));
    });
  });
}
