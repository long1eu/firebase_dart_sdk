// Copyright 2024 Google LLC
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

import 'package:cloud_firestore_dart/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart'
    as core;
import 'package:cloud_firestore_dart/src/firebase/firestore/distance_measure.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/vector_query_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/vector_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/vector_value.dart';
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:test/test.dart';

import '../../../util/core_helpers.dart';
import '../../../util/test_util.dart' as util;
import 'test_util.dart';

void main() {
  final RemoteSerializer serializer =
      RemoteSerializer(DatabaseId.forDatabase('p', 'd'));

  group('Query.findNearest validation', () {
    test('accepts a VectorValue or a List<double>', () {
      final VectorQuery a = query('coll').findNearest(vectorField: 'v', queryVector: VectorValue(<double>[1.0]), limit: 5, distanceMeasure: DistanceMeasure.cosine);
      final VectorQuery b = query('coll').findNearest(vectorField: 'v', queryVector: <double>[1.0], limit: 5, distanceMeasure: DistanceMeasure.cosine);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.limit, 5);
      expect(a.distanceMeasure, DistanceMeasure.cosine);
    });

    test('rejects other vector types', () {
      expect(
          () => query('coll').findNearest(vectorField: 'v', queryVector: <int>[1, 2], limit: 5, distanceMeasure: DistanceMeasure.cosine),
          throwsArgumentError);
    });

    test('limit must be between 1 and 1000', () {
      for (final int limit in <int>[0, -1, 1001]) {
        expect(
            () => query('coll').findNearest(vectorField: 'v', queryVector: <double>[1.0], limit: limit, distanceMeasure: DistanceMeasure.cosine),
            throwsArgumentError,
            reason: 'limit $limit');
      }
      query('coll').findNearest(vectorField: 'v', queryVector: <double>[1.0], limit: 1, distanceMeasure: DistanceMeasure.cosine);
      query('coll').findNearest(vectorField: 'v', queryVector: <double>[1.0], limit: 1000, distanceMeasure: DistanceMeasure.cosine);
    });

    test('query vector must be non-empty and at most 2048 dimensions', () {
      expect(
          () => query('coll').findNearest(vectorField: 'v', queryVector: <double>[], limit: 5, distanceMeasure: DistanceMeasure.euclidean),
          throwsArgumentError);
      expect(
          () => query('coll').findNearest(vectorField: 'v', queryVector: List<double>.filled(2049, 1.0), limit: 5, distanceMeasure: DistanceMeasure.euclidean),
          throwsArgumentError);
      query('coll').findNearest(vectorField: 'v', queryVector: List<double>.filled(2048, 1.0), limit: 5, distanceMeasure: DistanceMeasure.euclidean);
    });

    test('distance result field and threshold are validated', () {
      expect(
          () => query('coll').findNearest(vectorField: 'v', queryVector: <double>[1.0], limit: 5, distanceMeasure: DistanceMeasure.euclidean, distanceResultField: ''),
          throwsArgumentError);
      expect(
          () => query('coll').findNearest(vectorField: 'v', queryVector: <double>[1.0], limit: 5, distanceMeasure: DistanceMeasure.euclidean, distanceThreshold: double.nan),
          throwsArgumentError);
    });
  });

  group('encodeVectorQueryTarget', () {
    test('encodes all find_nearest options', () {
      final VectorQuery vq =
          QueryInternal.create(util.query('coll').filter(util.filter('a', '==', 1)), firestore).findNearest(vectorField: FieldPath(<String>['x', 'y']), queryVector: <double>[1.0, 2.0], limit: 7, distanceMeasure: DistanceMeasure.dotProduct, distanceResultField: 'dist', distanceThreshold: 0.5);
      final proto.Target_QueryTarget target =
          serializer.encodeVectorQueryTarget(vq.query.query, vq);
      final proto.StructuredQuery_FindNearest fn =
          target.structuredQuery.findNearest;
      expect(fn.vectorField.fieldPath, 'x.y');
      expect(fn.distanceMeasure,
          proto.StructuredQuery_FindNearest_DistanceMeasure.DOT_PRODUCT);
      expect(fn.limit.value, 7);
      expect(fn.distanceResultField, 'dist');
      expect(fn.distanceThreshold.value, 0.5);
      expect(fn.queryVector.mapValue.fields['__type__']!.stringValue,
          '__vector__');
      expect(
          fn.queryVector.mapValue.fields['value']!.arrayValue.values
              .map((v) => v.doubleValue),
          <double>[1.0, 2.0]);
      // The base query's filters are kept.
      expect(target.structuredQuery.hasWhere(), isTrue);
    });

    test('keeps OR filters of the base query', () {
      final VectorQuery vq = QueryInternal.create(
              util.query('coll').filter(util.orFilters(<Filter>[
                util.filter('a', '==', 1),
                util.filter('b', '>', 2),
              ])),
              firestore).findNearest(vectorField: 'v', queryVector: <double>[1.0], limit: 3, distanceMeasure: DistanceMeasure.euclidean);
      final proto.Target_QueryTarget target =
          serializer.encodeVectorQueryTarget(vq.query.query, vq);
      expect(target.structuredQuery.where.compositeFilter.op,
          proto.StructuredQuery_CompositeFilter_Operator.OR);
      expect(target.structuredQuery.where.compositeFilter.filters, hasLength(2));
      // Implicit orderings (here b, __name__) are not sent.
      expect(target.structuredQuery.orderBy, isEmpty);
      expect(target.structuredQuery.hasFindNearest(), isTrue);
    });

    test('sends the explicit orderings and drops the implicit ones', () {
      final VectorQuery vq = QueryInternal.create(
        util
            .query('coll')
            .filter(util.filter('b', '>', 1))
            .orderBy(util.orderBy('a', 'desc')),
        firestore,
      ).findNearest(vectorField: 'v', queryVector: <double>[1.0], limit: 3, distanceMeasure: DistanceMeasure.euclidean);
      final proto.StructuredQuery sq = serializer
          .encodeVectorQueryTarget(vq.query.query, vq)
          .structuredQuery;
      // The listen target would also order by b and __name__ (descending).
      expect(sq.orderBy, hasLength(1));
      expect(sq.orderBy.single.field_1.fieldPath, 'a');
      expect(
        sq.orderBy.single.direction,
        proto.StructuredQuery_Direction.DESCENDING,
      );
    });

    test('encodes the base query as its aggregate target', () {
      final core.Query base = util
          .query('coll')
          .filter(util.filter('b', '>', 1)).orderBy(util.orderBy('a'))
          .limitToLast(4)
          .startAt(bound(true, <Object>[1]))
          .endAt(bound(false, <Object>[9]));
      final VectorQuery vq = QueryInternal.create(
        base,
        firestore,
      ).findNearest(vectorField: 'v', queryVector: <double>[1.0], limit: 3, distanceMeasure: DistanceMeasure.euclidean);
      final proto.StructuredQuery sq =
          serializer
              .encodeVectorQueryTarget(vq.query.query, vq)
              .structuredQuery
              .deepCopy()
            ..clearFindNearest();
      expect(
        sq,
        serializer.encodeQueryTarget(base.toAggregateTarget()).structuredQuery,
      );
      // limitToLast flips the explicit ordering and swaps the cursors, as for
      // aggregations.
      expect(
        sq.orderBy.single.direction,
        proto.StructuredQuery_Direction.DESCENDING,
      );
      expect(sq.startAt.values.single.integerValue.toInt(), 9);
      expect(sq.endAt.values.single.integerValue.toInt(), 1);
    });

    test('omits optional fields and implicit orderings', () {
      final VectorQuery vq = query('coll').findNearest(vectorField: 'v', queryVector: <double>[1.0], limit: 3, distanceMeasure: DistanceMeasure.euclidean);
      final proto.StructuredQuery sq = serializer
          .encodeVectorQueryTarget(vq.query.query, vq)
          .structuredQuery;
      expect(sq.findNearest.distanceMeasure,
          proto.StructuredQuery_FindNearest_DistanceMeasure.EUCLIDEAN);
      expect(sq.findNearest.hasDistanceThreshold(), isFalse);
      expect(sq.findNearest.distanceResultField, isEmpty);
      expect(sq.orderBy, isEmpty);
    });
  });
}
