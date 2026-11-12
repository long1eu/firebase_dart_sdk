// Copyright 2026 Google LLC
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
// createFromAggregateQuery and createFromVectorQuery: the stages that follow
// the converted query (query_to_pipeline_test.dart covers the query itself).

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as pb;
import 'package:test/test.dart';

import '../../../../util/test_util.dart' as util;
import 'pipeline_test_util.dart';

void main() {
  Query<Object?> query() => Query<Object?>(util.query('coll'), fakeFirestore);

  // collection, where(exists(__name__)), sort(__name__)
  const int queryStages = 3;

  group('createFromAggregateQuery', () {
    test('count', () {
      final List<pb.Pipeline_Stage> stages =
          stagesOf(source().createFromAggregateQuery(query().count()));
      expect(stages, hasLength(queryStages + 1));
      expect(stages.first, stage('collection', <pb.Value>[ref('/coll')]));
      expect(
          stages.last,
          stage('aggregate', <pb.Value>[
            mapValue(<String, pb.Value>{'count': fn('count')}),
            mapValue(<String, pb.Value>{}),
          ]));
    });

    test('several fields use the names of the classic result', () {
      final List<pb.Pipeline_Stage> stages = stagesOf(
          source().createFromAggregateQuery(query().aggregate(<AggregateField>[
        AggregateField.count(),
        AggregateField.sum('total'),
        AggregateField.averageField(FieldPath.of(<String>['a', 'b.c'])),
      ])));
      expect(
          stages.last,
          stage('aggregate', <pb.Value>[
            mapValue(<String, pb.Value>{
              'count': fn('count'),
              'sum_total': fn('sum', <pb.Value>[fieldRef('total')]),
              r'`average_a.\`b.c\``':
                  fn('average', <pb.Value>[fieldRef('a.`b.c`')]),
            }),
            mapValue(<String, pb.Value>{}),
          ]));
    });

    test('aliases are kept', () {
      final List<pb.Pipeline_Stage> stages = stagesOf(source()
          .createFromAggregateQuery(
              query().aggregateWithAliases(<String, AggregateField>{
        'orders': AggregateField.count(),
        'revenue': AggregateField.sum('total'),
      })));
      expect(
          stages.last,
          stage('aggregate', <pb.Value>[
            mapValue(<String, pb.Value>{
              'orders': fn('count'),
              'revenue': fn('sum', <pb.Value>[fieldRef('total')]),
            }),
            mapValue(<String, pb.Value>{}),
          ]));
    });

    test('rejects a query of another database', () {
      final FakeFirestore other = FakeFirestore(util.dbId('other'));
      expect(
          () => source().createFromAggregateQuery(
              Query<Object?>(util.query('coll'), other).count()),
          throwsArgumentError);
    });
  });

  group('createFromVectorQuery', () {
    final pb.Value vector = mapValue(<String, pb.Value>{
      '__type__': str('__vector__'),
      'value': arrayValue(<pb.Value>[dbl(1), dbl(2)]),
    });

    test('findNearest with a limit', () {
      final List<pb.Pipeline_Stage> stages = stagesOf(source()
          .createFromVectorQuery(query().findNearest(
              'embedding', <double>[1, 2], 5, DistanceMeasure.cosine)));
      expect(stages, hasLength(queryStages + 1));
      expect(
          stages.last,
          stage(
              'find_nearest',
              <pb.Value>[fieldRef('embedding'), vector, str('cosine')],
              <String, pb.Value>{'limit': integer(5)}));
    });

    test('distanceResultField', () {
      final List<pb.Pipeline_Stage> stages = stagesOf(source()
          .createFromVectorQuery(query().findNearest(
              'embedding', <double>[1, 2], 5, DistanceMeasure.euclidean,
              distanceResultField: 'distance')));
      expect(stages.last.options, <String, pb.Value>{
        'limit': integer(5),
        'distance_field': fieldRef('distance'),
      });
    });

    test('distanceThreshold filters on the distance', () {
      final List<pb.Pipeline_Stage> stages = stagesOf(source()
          .createFromVectorQuery(query().findNearest(
              'embedding', <double>[1, 2], 5, DistanceMeasure.euclidean,
              distanceResultField: 'distance', distanceThreshold: 0.5)));
      expect(stages, hasLength(queryStages + 2));
      expect(
          stages.last,
          stage('where', <pb.Value>[
            fn('less_than_or_equal', <pb.Value>[
              fn('euclidean_distance',
                  <pb.Value>[fieldRef('embedding'), vector]),
              dbl(0.5)
            ])
          ]));
    });

    test('the threshold of a dot product is a lower bound', () {
      pb.Value condition(DistanceMeasure measure) =>
          stagesOf(source().createFromVectorQuery(query().findNearest(
                  'embedding', <double>[1, 2], 5, measure,
                  distanceThreshold: 0.5)))
              .last
              .args
              .single;

      expect(
          condition(DistanceMeasure.dotProduct),
          fn('greater_than_or_equal', <pb.Value>[
            fn('dot_product', <pb.Value>[fieldRef('embedding'), vector]),
            dbl(0.5)
          ]));
      expect(
          condition(DistanceMeasure.cosine),
          fn('less_than_or_equal', <pb.Value>[
            fn('cosine_distance', <pb.Value>[fieldRef('embedding'), vector]),
            dbl(0.5)
          ]));
    });
  });
}
