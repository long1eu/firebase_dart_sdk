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
// Stage lists for classic queries, after the JS SDK's core/pipeline-util.ts
// (toPipelineStages) and its query_to_pipeline tests.

import 'package:cloud_firestore_dart/src/firebase/firestore/core/bound.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart'
    as core;
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/query_to_pipeline.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as pb;
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart' as util;
import 'pipeline_test_util.dart';

List<pb.Pipeline_Stage> convert(core.Query query) =>
    stagesOf(queryToPipeline(fakeFirestore, query));

pb.Value exists(String field) => fn('exists', <pb.Value>[fieldRef(field)]);

pb.Value and(List<pb.Value> args) => fn('and', args);

pb.Value or(List<pb.Value> args) => fn('or', args);

pb.Value ordering(String field, [String direction = 'ascending']) {
  return mapValue(<String, pb.Value>{
    'direction': str(direction),
    'expression': fieldRef(field),
  });
}

pb.Value cmp(String name, String field, pb.Value value) =>
    fn(name, <pb.Value>[fieldRef(field), value]);

Bound bound(List<Object?> values, {required bool inclusive}) {
  return Bound(
      position: values.map<FieldValue>(util.wrap).toList(),
      inclusive: inclusive);
}

void main() {
  final pb.Pipeline_Stage keyExists =
      stage('where', <pb.Value>[exists('__name__')]);
  final pb.Pipeline_Stage keySort =
      stage('sort', <pb.Value>[ordering('__name__')]);

  test('collection query', () {
    expect(convert(util.query('coll')), <pb.Pipeline_Stage>[
      stage('collection', <pb.Value>[ref('/coll')]),
      keyExists,
      keySort,
    ]);
  });

  test('collection group query', () {
    expect(convert(core.Query(util.path(''), collectionGroup: 'coll')).first,
        stage('collection_group', <pb.Value>[ref(''), str('coll')]));
  });

  test('document query', () {
    expect(convert(util.query('coll/doc')).first,
        stage('documents', <pb.Value>[ref('/coll/doc')]));
  });

  pb.Value notNull(String field) =>
      cmp('not_equal', field, pb.Value()..nullValue = pb.Value().nullValue);

  pb.Value ifArray(String field, pb.Value condition) =>
      fn('conditional', <pb.Value>[
        fn('is_type', <pb.Value>[fieldRef(field), str('array')]),
        condition,
        boolean(false)
      ]);

  test('comparison filters also require the field to exist', () {
    const Map<String, String> operators = <String, String>{
      '<': 'less_than',
      '<=': 'less_than_or_equal',
      '>': 'greater_than',
      '>=': 'greater_than_or_equal',
      '==': 'equal',
    };
    for (final MapEntry<String, String> entry in operators.entries) {
      final String operator = entry.key;
      final String name = entry.value;
      final List<pb.Pipeline_Stage> stages =
          convert(util.query('coll').filter(util.filter('a', operator, 1)));
      expect(
          stages[1],
          stage('where', <pb.Value>[
            and(<pb.Value>[exists('a'), cmp(name, 'a', integer(1))])
          ]),
          reason: operator);
    }
  });

  test('not-equal filters do not match null', () {
    expect(
        convert(util.query('coll').filter(util.filter('a', '!=', 1)))[1],
        stage('where', <pb.Value>[
          and(<pb.Value>[cmp('not_equal', 'a', integer(1)), notNull('a')])
        ]));
    // `!= null` is the "is not null" filter itself.
    expect(convert(util.query('coll').filter(util.filter('a', '!=', null)))[1],
        stage('where', <pb.Value>[notNull('a')]));
    expect(
        convert(util
            .query('coll')
            .filter(util.filter('a', 'not-in', <int>[1, 2])))[1],
        stage('where', <pb.Value>[
          and(<pb.Value>[
            cmp('not_equal_any', 'a',
                arrayValue(<pb.Value>[integer(1), integer(2)])),
            notNull('a'),
          ])
        ]));
    expect(
        convert(
            util.query('coll').filter(util.filter('a', 'not-in', <int>[1])))[1],
        stage('where', <pb.Value>[
          and(<pb.Value>[cmp('not_equal', 'a', integer(1)), notNull('a')])
        ]));
  });

  test('in filters', () {
    expect(
        convert(
            util.query('coll').filter(util.filter('a', 'in', <int>[1, 2])))[1],
        stage('where', <pb.Value>[
          and(<pb.Value>[
            exists('a'),
            cmp('equal_any', 'a',
                arrayValue(<pb.Value>[integer(1), integer(2)]))
          ])
        ]));
    expect(
        convert(util.query('coll').filter(util.filter('a', 'in', <int>[1])))[1],
        stage('where', <pb.Value>[
          and(<pb.Value>[exists('a'), cmp('equal', 'a', integer(1))])
        ]));
  });

  test('array filters only look at arrays', () {
    expect(
        convert(util
            .query('coll')
            .filter(util.filter('a', 'array-contains', 1)))[1],
        stage('where', <pb.Value>[
          and(<pb.Value>[
            exists('a'),
            ifArray('a', cmp('array_contains', 'a', integer(1))),
          ])
        ]));
    expect(
        convert(util
            .query('coll')
            .filter(util.filter('a', 'array-contains-any', <int>[1, 2])))[1],
        stage('where', <pb.Value>[
          and(<pb.Value>[
            exists('a'),
            ifArray(
                'a',
                cmp('array_contains_any', 'a',
                    arrayValue(<pb.Value>[integer(1), integer(2)]))),
          ])
        ]));
  });

  test('composite filters', () {
    final core.Query query = util.query('coll').filter(util.orFilters(<Filter>[
          util.filter('a', '==', 1),
          util.andFilters(<Filter>[
            util.filter('b', '!=', 2),
            util.filter('c', '!=', 3),
          ]),
        ]));
    expect(
        convert(query)[1],
        stage('where', <pb.Value>[
          or(<pb.Value>[
            and(<pb.Value>[exists('a'), cmp('equal', 'a', integer(1))]),
            and(<pb.Value>[
              and(<pb.Value>[cmp('not_equal', 'b', integer(2)), notNull('b')]),
              and(<pb.Value>[cmp('not_equal', 'c', integer(3)), notNull('c')]),
            ]),
          ])
        ]));
  });

  test('every filter becomes its own where stage', () {
    final List<pb.Pipeline_Stage> stages = convert(util
        .query('coll')
        .filter(util.filter('a', '!=', 1))
        .filter(util.filter('b', '!=', 2)));
    expect(stages.map((pb.Pipeline_Stage s) => s.name),
        <String>['collection', 'where', 'where', 'where', 'sort']);
  });

  test('orderings include the implicit ones and require the fields', () {
    final List<pb.Pipeline_Stage> stages = convert(util
        .query('coll')
        .filter(util.filter('b', '>', 1))
        .orderBy(util.orderBy('a', 'desc')));
    expect(stages.sublist(2), <pb.Pipeline_Stage>[
      stage('where', <pb.Value>[
        and(<pb.Value>[exists('a'), exists('b'), exists('__name__')])
      ]),
      stage('sort', <pb.Value>[
        ordering('a', 'descending'),
        ordering('b', 'descending'),
        ordering('__name__', 'descending'),
      ]),
    ]);
  });

  test('limit', () {
    expect(convert(util.query('coll').limitToFirst(5)), <pb.Pipeline_Stage>[
      stage('collection', <pb.Value>[ref('/coll')]),
      keyExists,
      keySort,
      stage('limit', <pb.Value>[integer(5)]),
    ]);
  });

  test('limitToLast sorts in reverse, limits and sorts again', () {
    final List<pb.Pipeline_Stage> stages =
        convert(util.query('coll').orderBy(util.orderBy('a')).limitToLast(2));
    expect(stages.sublist(2), <pb.Pipeline_Stage>[
      stage('sort', <pb.Value>[
        ordering('a', 'descending'),
        ordering('__name__', 'descending'),
      ]),
      stage('limit', <pb.Value>[integer(2)]),
      stage('sort', <pb.Value>[ordering('a'), ordering('__name__')]),
    ]);
  });

  test('limitToLast needs an explicit ordering', () {
    expect(() => convert(util.query('coll').limitToLast(2)), throwsStateError);
  });

  group('cursors', () {
    core.Query base([String direction = 'asc']) =>
        util.query('coll').orderBy(util.orderBy('a', direction));

    pb.Pipeline_Stage cursorStage(core.Query query) => convert(query)[3];

    test('startAt is inclusive', () {
      expect(
          cursorStage(base().startAt(bound(<Object?>[1], inclusive: true))),
          stage('where', <pb.Value>[
            or(<pb.Value>[
              cmp('greater_than', 'a', integer(1)),
              cmp('equal', 'a', integer(1)),
            ])
          ]));
    });

    test('startAfter is exclusive', () {
      expect(cursorStage(base().startAt(bound(<Object?>[1], inclusive: false))),
          stage('where', <pb.Value>[cmp('greater_than', 'a', integer(1))]));
    });

    test('endBefore is exclusive', () {
      expect(cursorStage(base().endAt(bound(<Object?>[1], inclusive: false))),
          stage('where', <pb.Value>[cmp('less_than', 'a', integer(1))]));
    });

    test('endAt is inclusive', () {
      expect(
          cursorStage(base().endAt(bound(<Object?>[1], inclusive: true))),
          stage('where', <pb.Value>[
            or(<pb.Value>[
              cmp('less_than', 'a', integer(1)),
              cmp('equal', 'a', integer(1)),
            ])
          ]));
    });

    test('descending orderings flip the comparison', () {
      expect(
          cursorStage(
              base('desc').startAt(bound(<Object?>[1], inclusive: false))),
          stage('where', <pb.Value>[cmp('less_than', 'a', integer(1))]));
      expect(
          cursorStage(
              base('desc').endAt(bound(<Object?>[1], inclusive: false))),
          stage('where', <pb.Value>[cmp('greater_than', 'a', integer(1))]));
    });

    test('cursors over several fields compare lexicographically', () {
      final core.Query query = base()
          .orderBy(util.orderBy('b', 'desc'))
          .startAt(bound(<Object?>[1, 2], inclusive: false));
      expect(
          cursorStage(query),
          stage('where', <pb.Value>[
            or(<pb.Value>[
              cmp('greater_than', 'a', integer(1)),
              and(<pb.Value>[
                cmp('equal', 'a', integer(1)),
                cmp('less_than', 'b', integer(2)),
              ]),
            ])
          ]));
    });

    test('cursors come after the sort and before the limit', () {
      final List<pb.Pipeline_Stage> stages = convert(base()
          .startAt(bound(<Object?>[1], inclusive: true))
          .endAt(bound(<Object?>[5], inclusive: false))
          .limitToFirst(3));
      expect(stages.map((pb.Pipeline_Stage s) => s.name), <String>[
        'collection',
        'where',
        'sort',
        'where',
        'where',
        'limit',
      ]);
    });

    test('limitToLast applies the cursors between the reversed sort and limit',
        () {
      final List<pb.Pipeline_Stage> stages = convert(
          base().startAt(bound(<Object?>[1], inclusive: true)).limitToLast(3));
      expect(stages.map((pb.Pipeline_Stage s) => s.name),
          <String>['collection', 'where', 'sort', 'where', 'limit', 'sort']);
      expect(
          stages[3],
          stage('where', <pb.Value>[
            or(<pb.Value>[
              cmp('greater_than', 'a', integer(1)),
              cmp('equal', 'a', integer(1)),
            ])
          ]));
    });
  });

  test('createFrom rejects a query of another database', () {
    final Firestore other = FakeFirestore(util.dbId('other'));
    expect(() => source().createFrom(QueryInternal.create<Object?>(util.query('coll'), other)),
        throwsArgumentError);
    expect(
        stagesOf(source()
                .createFrom(QueryInternal.create<Object?>(util.query('coll'), fakeFirestore)))
            .first,
        stage('collection', <pb.Value>[ref('/coll')]));
  });
}
