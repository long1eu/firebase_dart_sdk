// The local pipeline executor, with the results of the Enterprise edition
// emulator for the same pipelines over the same documents (recorded by
// probing it; pipeline_executor_property_test.dart compares random
// pipelines).
//
// On the VM only: the documents hold 1.0 and -0.0, which compiled to
// JavaScript are integers, and the helpers read the environment (dart:io).
@TestOn('vm')
library;

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart'
    show DistanceMeasure, FieldValue, Int32Value;
import 'package:cloud_firestore_dart/pipelines.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart'
    as model;
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/expression_evaluator.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/pipeline_executor.dart';
import 'package:test/test.dart';

import '../../../../../util/property_pipeline.dart';
import '../../../../../util/property_pipeline_stages.dart';
import '../pipeline_test_util.dart';

final LocalPipelines local = LocalPipelines(testDatabaseId);

/// The documents of the probes: `o` tells them apart.
final Map<String, Map<String, Object?>> documents =
    <String, Map<String, Object?>>{
      'c/d01': <String, Object?>{
        'a': 1,
        'b': 'x',
        'g': 'g1',
        'arr': <Object?>[1, 2, 3],
        'm': <String, Object?>{'x': 1},
        'v': FieldValue.vector(<double>[1, 0]),
      },
      'c/d02': <String, Object?>{
        'a': 1.0,
        'b': 'y',
        'g': 'g1',
        'arr': <Object?>[],
        'm': <String, Object?>{'x': 2},
        'v': FieldValue.vector(<double>[0, 1]),
      },
      'c/d03': <String, Object?>{
        'a': null,
        'g': 'g2',
        'arr': 'notarray',
        'm': 'notmap',
        'v': FieldValue.vector(<double>[1, 1, 1]),
      },
      'c/d04': <String, Object?>{
        'a': 's',
        'g': null,
        'arr': null,
        'v': <Object?>[3.0, 4.0],
      },
      'c/d05': <String, Object?>{},
      'c/d06': <String, Object?>{
        'a': double.nan,
        'g': 'g2',
        'arr': <Object?>[null, 5],
        'v': FieldValue.vector(<double>[-1, -1]),
      },
      'c/d07': <String, Object?>{'a': -0.0, 'g': 1},
      'c/d08': <String, Object?>{'a': 0, 'g': 1.0},
      'c/d09': <String, Object?>{'a': true},
      'c/d10': <String, Object?>{
        'a': <Object?>[1],
      },
      'c/d01/sub/s1': <String, Object?>{'a': 5},
      'other/o1/sub/s2': <String, Object?>{'a': 6},
    }.map(
      (String path, Map<String, Object?> data) =>
          MapEntry<String, Map<String, Object?>>(path, <String, Object?>{
            ...data,
            if (path.split('/').length == 2) 'o': int.parse(path.substring(3)),
          }),
    );

Pipeline collection() => source().collection('c');

List<PipelineRow> run(Pipeline pipeline) => local.run(pipeline, documents);

/// The rows as plain values: the fields, and `@` with the document id when
/// the row still is a document.
List<Map<String, Object?>> rows(Pipeline pipeline) => <Map<String, Object?>>[
  for (final PipelineRow row in run(pipeline))
    <String, Object?>{
      if (row.key != null) '@': row.key!.split('/').last,
      for (final MapEntry<String, model.FieldValue> e
          in row.fields.internalValue)
        e.key: _plain(e.value),
    },
];

Object? _plain(model.FieldValue value) => switch (value) {
  model.ArrayValue() => value.internalValue.map(_plain).toList(),
  model.ObjectValue() => <String, Object?>{
    for (final MapEntry<String, model.FieldValue> e in value.internalValue)
      e.key: _plain(e.value),
  },
  _ => value.value,
};

/// The values of [name] of the rows, in order.
List<Object?> column(Pipeline pipeline, String name) => <Object?>[
  for (final Map<String, Object?> row in rows(pipeline))
    row.containsKey(name) ? row[name] : #missing,
];

final Matcher failsThePipeline = throwsA(isA<PipelineFailure>());

void main() {
  group('sources', () {
    test('a collection is its documents, not those of subcollections', () {
      expect(column(collection(), '@'), <Object?>[
        'd01', 'd02', 'd03', 'd04', 'd05', 'd06', 'd07', 'd08', 'd09', 'd10', //
      ]);
    });

    test('a collection group is every collection with the id', () {
      expect(column(source().collectionGroup('sub'), 'a'), <Object?>[5, 6]);
    });

    test('the database is every document', () {
      expect(rows(source().database()), hasLength(12));
    });

    test('documents are those that exist', () {
      expect(
        column(
          source().documents(<String>['c/d09', 'c/missing', 'c/d01']),
          'a',
        ),
        <Object?>[true, 1],
      );
    });
  });

  group('where', () {
    test('keeps the inputs for which the condition is true', () {
      expect(column(collection().where(field('a').asBoolean()), 'o'), <Object?>[
        9,
      ]);
      expect(column(collection().where(field('a').equal(1)), 'o'), <Object?>[
        1,
        2,
      ]);
    });

    test('an error fails the pipeline, also before a true in or()', () {
      expect(
        () => run(collection().where(field('a').add(1).greaterThan(0))),
        failsThePipeline,
      );
      expect(
        () => run(
          collection().where(
            field('a').add(1).greaterThan(0).or(constant(true).asBoolean()),
          ),
        ),
        failsThePipeline,
      );
    });
  });

  group('sort', () {
    test('null and missing first and equal, then the order of all values', () {
      expect(
        column(
          collection().sort(<Ordering>[
            field('a').ascending(),
            field('o').ascending(),
          ]),
          'o',
        ),
        <Object?>[3, 5, 9, 6, 7, 8, 1, 2, 4, 10],
      );
      expect(
        column(
          collection().sort(<Ordering>[
            field('a').descending(),
            field('o').ascending(),
          ]),
          'o',
        ),
        <Object?>[10, 4, 1, 2, 7, 8, 6, 9, 3, 5],
      );
      expect(
        column(
          collection().sort(<Ordering>[
            field('a').ascending(),
            field('o').descending(),
          ]),
          'o',
        ),
        <Object?>[5, 3, 9, 6, 8, 7, 2, 1, 4, 10],
      );
    });

    test('vectors after arrays, by their length first', () {
      expect(
        column(
          collection().sort(<Ordering>[
            field('v').ascending(),
            field('o').ascending(),
          ]),
          'o',
        ),
        <Object?>[5, 7, 8, 9, 10, 4, 6, 2, 1, 3],
      );
    });

    test('an error in a key fails the pipeline', () {
      expect(
        () => run(collection().sort(<Ordering>[field('a').add(1).ascending()])),
        failsThePipeline,
      );
    });

    test('limit and offset', () {
      Pipeline sorted() =>
          collection().sort(<Ordering>[field('o').ascending()]);
      expect(column(sorted().limit(3), 'o'), <Object?>[1, 2, 3]);
      expect(column(sorted().offset(8), 'o'), <Object?>[9, 10]);
      expect(column(sorted().offset(20), 'o'), isEmpty);
      expect(column(sorted().limit(0), 'o'), isEmpty);
      expect(column(sorted().offset(2).limit(3), 'o'), <Object?>[3, 4, 5]);
      expect(
        column(
          sorted().limit(3).sort(<Ordering>[field('o').descending()]),
          'o',
        ),
        <Object?>[3, 2, 1],
      );
    });
  });

  group('select, addFields, removeFields', () {
    Pipeline d01() => collection().where(field('o').equal(1));

    test('select keeps only the fields, nested by their names', () {
      expect(
        rows(d01().select(<Selectable>[field('m.x'), field('a').as('p.q')])),
        <Object?>[
          <String, Object?>{
            'm': <String, Object?>{'x': 1},
            'p': <String, Object?>{'q': 1},
          },
        ],
      );
      expect(
        rows(
          d01().select(<Selectable>[
            constant(1).as('x.y'),
            constant(2).as('x.z'),
          ]),
        ),
        <Object?>[
          <String, Object?>{
            'x': <String, Object?>{'y': 1, 'z': 2},
          },
        ],
      );
    });

    test('a field and a field inside it fail the pipeline', () {
      expect(
        () => run(
          d01().select(<Selectable>[
            constant(1).as('x'),
            constant(2).as('x.z'),
          ]),
        ),
        failsThePipeline,
      );
    });

    test('select drops the document, the stages that add keep it', () {
      final Pipeline selected = d01().select(<Selectable>[
        field('__name__').as('n'),
        field('__create_time__').isAbsent().as('c'),
      ]);
      expect(column(selected, '@'), <Object?>[#missing]);
      expect(
        column(selected.select(<Selectable>[field('__name__').as('n')]), 'n'),
        <Object?>[#missing],
      );
      expect(
        column(d01().addFields(<Selectable>[constant(1).as('x')]), '@'),
        <Object?>['d01'],
      );
    });

    test('addFields sets, replaces and removes', () {
      expect(
        rows(
          d01().addFields(<Selectable>[
            constant(9).as('a'),
            field('zz').as('b'),
            constant(null).as('g'),
            constant(8).as('m.y'),
          ]),
        ).single,
        <String, Object?>{
          '@': 'd01',
          'a': 9,
          'arr': <Object?>[1, 2, 3],
          'g': null,
          'm': <String, Object?>{'x': 1, 'y': 8},
          'o': 1,
          'v': isA<Object>(),
        },
      );
    });

    test('a nested field makes its parents maps, also for a missing value', () {
      final Pipeline d03 = collection().where(field('o').equal(3));
      expect(
        column(d03.addFields(<Selectable>[constant(9).as('m.y')]), 'm'),
        <Object?>[
          <String, Object?>{'y': 9},
        ],
      );
      expect(
        column(d03.addFields(<Selectable>[field('zz').as('m.y')]), 'm'),
        <Object?>[<String, Object?>{}],
      );
    });

    test('removeFields leaves a value that is not a map alone', () {
      expect(
        rows(
          collection().where(field('o').equal(3)).removeFields(<Object>[
            'm.x',
            'arr',
          ]),
        ).single.keys,
        unorderedEquals(<String>['@', 'a', 'g', 'm', 'o', 'v']),
      );
      expect(
        column(
          collection().where(field('o').equal(1)).removeFields(<Object>['m.x']),
          'm',
        ),
        <Object?>[<String, Object?>{}],
      );
    });

    test('an error fails the pipeline', () {
      expect(
        () => run(collection().select(<Selectable>[field('a').add(1).as('x')])),
        failsThePipeline,
      );
    });
  });

  group('distinct and aggregate', () {
    test('equal values are one group: 1 and 1.0, null and missing', () {
      final List<Object?> groups = column(
        collection().distinct(<Object>['a']),
        'a',
      );
      expect(groups, hasLength(7));
      expect(column(collection().distinct(<Object>['g']), 'g'), <Object?>[
        'g1',
        'g2',
        null,
        1,
      ]);
    });

    test('one result for no inputs without groups, none with groups', () {
      final Pipeline none = collection().where(field('a').equal(99));
      expect(
        rows(none.aggregate(<AliasedAggregate>[countAll().as('n')])),
        <Object?>[
          <String, Object?>{'n': 0},
        ],
      );
      expect(
        rows(
          none.aggregate(
            <AliasedAggregate>[countAll().as('n')],
            groups: <Object>['g'],
          ),
        ),
        isEmpty,
      );
    });

    test('groups', () {
      expect(
        rows(
          collection().aggregate(
            <AliasedAggregate>[countAll().as('n'), field('a').sum().as('s')],
            groups: <Object>['g'],
          ),
        ).map(
          (Map<String, Object?> row) => '${row['g']} ${row['n']} ${row['s']}',
        ),
        <String>['g1 2 2.0', 'g2 2 NaN', 'null 4 null', '1 2 0.0'],
      );
    });

    test('overlapping names and nested names fail the pipeline', () {
      expect(
        () => run(
          collection().aggregate(
            <AliasedAggregate>[countAll().as('g')],
            groups: <Object>['g'],
          ),
        ),
        failsThePipeline,
      );
      expect(
        () => run(collection().distinct(<Object>['m.x'])),
        failsThePipeline,
      );
      expect(
        () => run(
          collection().aggregate(<AliasedAggregate>[countAll().as('n.k')]),
        ),
        failsThePipeline,
      );
    });

    test('an error in a group or an accumulator fails the pipeline', () {
      expect(
        () => run(collection().distinct(<Object>[field('a').add(1).as('x')])),
        failsThePipeline,
      );
      expect(
        () => run(
          collection().aggregate(<AliasedAggregate>[
            field('a').add(1).sum().as('n'),
          ]),
        ),
        failsThePipeline,
      );
    });
  });

  group('unnest', () {
    test('a row per element; once for a value that is not an array; none '
        'for an empty array', () {
      expect(
        rows(
          collection().unnest(field('arr').as('e'), indexField: 'i').select(
            <Selectable>[field('o'), field('e'), field('i')],
          ),
        ).map(
          (Map<String, Object?> r) =>
              '${r['o']}:${r.containsKey('e') ? r['e'] : '-'}:${r['i']}',
        ),
        <String>[
          '1:1:0', '1:2:1', '1:3:2', '3:notarray:null', '4:null:null', //
          '5:-:null', '6:null:0', '6:5:1', '7:-:null', '8:-:null', '9:-:null',
          '10:-:null',
        ],
      );
    });

    test('keeps the document; an index named like the alias fails', () {
      expect(
        column(
          collection().where(field('o').equal(1)).unnest(field('arr').as('e')),
          '@',
        ),
        <Object?>['d01', 'd01', 'd01'],
      );
      expect(
        () => run(collection().unnest(field('arr').as('e'), indexField: 'e')),
        failsThePipeline,
      );
    });
  });

  group('union, replaceWith', () {
    test('union appends, duplicates too', () {
      final Pipeline d09 = collection().where(field('o').equal(9));
      expect(column(d09.union(d09), '@'), <Object?>['d09', 'd09']);
    });

    test('replaceWith a map, else an empty row', () {
      expect(
        rows(
          collection().replaceWith('m'),
        ).where((Map<String, Object?> r) => r.isNotEmpty),
        <Object?>[
          <String, Object?>{'x': 1},
          <String, Object?>{'x': 2},
        ],
      );
      expect(rows(collection().replaceWith('m')), hasLength(10));
    });
  });

  group('findNearest', () {
    List<Object?> distances(
      List<double> vector,
      DistanceMeasure measure, {
      int? limit,
    }) => column(
      collection().findNearest(
        'v',
        vector,
        measure,
        limit: limit,
        distanceField: 'd',
      ),
      'd',
    );

    test('vectors of the dimension of the query, nearest first', () {
      expect(distances(<double>[1, 0], DistanceMeasure.euclidean), <Object?>[
        0.0,
        1.4142135623730951,
        2.23606797749979,
      ]);
      expect(
        distances(<double>[1, 0], DistanceMeasure.cosine, limit: 2),
        <Object?>[0.0, 1.0],
      );
      expect(distances(<double>[1, 0], DistanceMeasure.dotProduct), <Object?>[
        1.0,
        0.0,
        -1.0,
      ]);
    });

    test('the cosine distance of a zero vector is NaN', () {
      final List<Object?> result = distances(<double>[
        0,
        0,
      ], DistanceMeasure.cosine);
      expect(result, hasLength(3));
      expect(result.every((Object? d) => (d! as double).isNaN), isTrue);
    });
  });

  group('not run locally', () {
    test('stages and options this executor does not know', () {
      expect(
        () => run(collection().sample(documents: 2)),
        throwsA(isA<UnsupportedExpression>()),
      );
      expect(
        () =>
            run(collection().define(<AliasedExpression>[constant(1).as('x')])),
        throwsA(isA<UnsupportedExpression>()),
      );
      expect(
        () => run(collection().limit(1, rawOptions: <String, Object?>{'x': 1})),
        throwsA(isA<UnsupportedExpression>()),
      );
      expect(
        () => run(
          collection().select(<Selectable>[
            FunctionExpression('geo_distance', <Object?>[1, 2]).as('x'),
          ]),
        ),
        throwsA(isA<UnsupportedExpression>()),
      );
    });

    test('a subquery', () {
      expect(
        () => run(
          collection().addFields(<Selectable>[
            collection()
                .aggregate(<AliasedAggregate>[countAll().as('n')])
                .toScalarExpression()
                .as('n'),
          ]),
        ),
        throwsA(isA<UnsupportedExpression>()),
      );
    });
  });

  test('Int32 values group with other numbers', () {
    final Map<String, Map<String, Object?>> numbers =
        <String, Map<String, Object?>>{
          'c/a': <String, Object?>{'x': Int32Value(2)},
          'c/b': <String, Object?>{'x': 2},
        };
    expect(
      local.run(
        collection().aggregate(
          <AliasedAggregate>[countAll().as('n')],
          groups: <Object>['x'],
        ),
        numbers,
      ),
      hasLength(1),
    );
    expect(describeValue(local.toModel(1)), 'Integer(1)');
  });
}
