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

// Ported from the JS SDK:
// packages/firestore/test/unit/lite-api/add_window_fields.test.ts
//
// JS's `addWindowFields({partition, sort, documents | range}, ...fields)` is
// `addWindowFields(WindowSpec(partition:, sort:, frame:
// WindowFrame.documents(...) | WindowFrame.range(...)), [fields])` in Dart;
// `ascending('date')` is `field('date').ascending()`, `sum('x')` is
// `field('x').sum()`, and `.over({documents: {...}})` is
// `.over(WindowFrame.documents(...))`. Dart's `sort` is always a list.

// ignore_for_file: invalid_use_of_internal_member

import 'package:cloud_firestore_dart/pipelines.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as pb;
import 'package:test/test.dart';

import '../pipeline_test_util.dart' hide arrayValue, mapValue;

/// The proto of the (single) `add_window_fields` stage of [pipeline],
/// serialized as `execute()` does.
pb.Pipeline_Stage windowStage(Pipeline pipeline) {
  final List<pb.Pipeline_Stage> stages = <pb.Pipeline_Stage>[
    for (final pb.Pipeline_Stage stage in stagesOf(pipeline))
      if (stage.name == 'add_window_fields') stage,
  ];
  expect(stages, hasLength(1), reason: 'expected exactly one stage');
  return stages.single;
}

/// The `window_spec` argument (args[0]) of the `add_window_fields` stage.
pb.Value windowSpecArg(Pipeline pipeline) {
  final pb.Pipeline_Stage stage = windowStage(pipeline);
  expect(stage.args, hasLength(2));
  return stage.args[0];
}

/// The `fields` argument (args[1]) of the `add_window_fields` stage.
pb.Value fieldsArg(Pipeline pipeline) {
  final pb.Pipeline_Stage stage = windowStage(pipeline);
  expect(stage.args, hasLength(2));
  return stage.args[1];
}

pb.Value int_(int value) => integer(value);

pb.Value map(Map<String, pb.Value> fields) =>
    pb.Value()..mapValue = (pb.MapValue()..fields.addAll(fields));

pb.Value array(List<pb.Value> values) =>
    pb.Value()..arrayValue = (pb.ArrayValue()..values.addAll(values));

pb.Value ordering(pb.Value expression, String direction) => map(
  <String, pb.Value>{'direction': str(direction), 'expression': expression},
);

Pipeline basePipeline() => source().collection('sales');

Pipeline window(WindowSpec spec, List<Object> fields) =>
    basePipeline().addWindowFields(spec, fields);

final AliasedAggregate c = countAll().as('c');

const String noOptionsOverload =
    'Dart has one addWindowFields(WindowSpec, fields) signature; there is no '
    'options-object overload.';

const String noUndefined =
    'Dart has no undefined value: an expression cannot hold one.';

void main() {
  group('addWindowFields() serialization', () {
    group('stage shape', () {
      test('uses the add_window_fields stage name and 2 args', () {
        final pb.Pipeline_Stage stage = windowStage(
          window(const WindowSpec(partition: <Object>['product']), <Object>[c]),
        );

        expect(stage.name, 'add_window_fields');
        expect(stage.args, hasLength(2));
      });

      test('does not send any stage options', () {
        final pb.Pipeline_Stage stage = windowStage(
          window(const WindowSpec(partition: <Object>['product']), <Object>[c]),
        );

        expect(stage.options, isEmpty);
      });
    });

    group('window_spec', () {
      test('serializes an empty window spec as an empty map', () {
        expect(
          windowSpecArg(window(const WindowSpec(), <Object>[c])),
          map(<String, pb.Value>{}),
        );
      });

      test('serializes a partition of field name strings', () {
        expect(
          windowSpecArg(
            window(
              const WindowSpec(partition: <Object>['product', 'region']),
              <Object>[c],
            ),
          ),
          map(<String, pb.Value>{
            'partition': array(<pb.Value>[
              fieldRef('product'),
              fieldRef('region'),
            ]),
          }),
        );
      });

      test('serializes a partition of expressions', () {
        expect(
          windowSpecArg(
            window(
              WindowSpec(
                partition: <Object>[
                  field('product'),
                  field('region').toLower(),
                ],
              ),
              <Object>[c],
            ),
          ),
          map(<String, pb.Value>{
            'partition': array(<pb.Value>[
              fieldRef('product'),
              fn('to_lower', <pb.Value>[fieldRef('region')]),
            ]),
          }),
        );
      });

      test('serializes a nested field path partition', () {
        expect(
          windowSpecArg(
            window(
              const WindowSpec(partition: <Object>['metadata.region']),
              <Object>[c],
            ),
          ),
          map(<String, pb.Value>{
            'partition': array(<pb.Value>[fieldRef('metadata.region')]),
          }),
        );
      });

      test('serializes a single (non array) sort ordering', () {
        // Dart's sort is a list; a list of one ordering.
        expect(
          windowSpecArg(
            window(
              WindowSpec(sort: <Ordering>[field('date').ascending()]),
              <Object>[c],
            ),
          ),
          map(<String, pb.Value>{
            'sort': array(<pb.Value>[ordering(fieldRef('date'), 'ascending')]),
          }),
        );
      });

      test('serializes multiple sort orderings with mixed directions', () {
        expect(
          windowSpecArg(
            window(
              WindowSpec(
                sort: <Ordering>[
                  field('date').ascending(),
                  field('salesPrice').descending(),
                ],
              ),
              <Object>[c],
            ),
          ),
          map(<String, pb.Value>{
            'sort': array(<pb.Value>[
              ordering(fieldRef('date'), 'ascending'),
              ordering(fieldRef('salesPrice'), 'descending'),
            ]),
          }),
        );
      });

      test('serializes partition and sort together', () {
        expect(
          windowSpecArg(
            window(
              WindowSpec(
                partition: <Object>['product'],
                sort: <Ordering>[field('date').ascending()],
              ),
              <Object>[c],
            ),
          ),
          map(<String, pb.Value>{
            'partition': array(<pb.Value>[fieldRef('product')]),
            'sort': array(<pb.Value>[ordering(fieldRef('date'), 'ascending')]),
          }),
        );
      });

      test('omits an empty partition array', () {
        expect(
          windowSpecArg(
            window(
              WindowSpec(
                partition: const <Object>[],
                sort: <Ordering>[field('date').ascending()],
              ),
              <Object>[c],
            ),
          ),
          map(<String, pb.Value>{
            'sort': array(<pb.Value>[ordering(fieldRef('date'), 'ascending')]),
          }),
        );
      });

      test('omits an empty sort array', () {
        expect(
          windowSpecArg(
            window(
              const WindowSpec(
                partition: <Object>['product'],
                sort: <Ordering>[],
              ),
              <Object>[c],
            ),
          ),
          map(<String, pb.Value>{
            'partition': array(<pb.Value>[fieldRef('product')]),
          }),
        );
      });

      test('omits the frame when using default framing', () {
        final pb.Value spec = windowSpecArg(
          window(
            WindowSpec(sort: <Ordering>[field('date').ascending()]),
            <Object>[c],
          ),
        );

        expect(spec.mapValue.fields.containsKey('documents'), isFalse);
        expect(spec.mapValue.fields.containsKey('range'), isFalse);
      });
    });

    pb.Value byDate() =>
        array(<pb.Value>[ordering(fieldRef('date'), 'ascending')]);

    group('stage level documents framing', () {
      pb.Value spec(WindowFrame frame) => windowSpecArg(
        window(
          WindowSpec(sort: <Ordering>[field('date').ascending()], frame: frame),
          <Object>[c],
        ),
      );

      test('serializes numeric offsets as integers', () {
        expect(
          spec(WindowFrame.documents(preceding: 2, following: 1)),
          map(<String, pb.Value>{
            'sort': byDate(),
            'documents': map(<String, pb.Value>{
              'preceding': int_(2),
              'following': int_(1),
            }),
          }),
        );
      });

      test('serializes zero offsets', () {
        expect(
          spec(WindowFrame.documents(preceding: 0, following: 0)),
          map(<String, pb.Value>{
            'sort': byDate(),
            'documents': map(<String, pb.Value>{
              'preceding': int_(0),
              'following': int_(0),
            }),
          }),
        );
      });

      test('serializes negative offsets (look ahead windows)', () {
        expect(
          spec(WindowFrame.documents(preceding: -1, following: 2)),
          map(<String, pb.Value>{
            'sort': byDate(),
            'documents': map(<String, pb.Value>{
              'preceding': int_(-1),
              'following': int_(2),
            }),
          }),
        );
      });

      test("serializes the 'unbounded' and 'current' sentinels", () {
        expect(
          spec(
            WindowFrame.documents(
              preceding: WindowFrame.unbounded,
              following: WindowFrame.current,
            ),
          ),
          map(<String, pb.Value>{
            'sort': byDate(),
            'documents': map(<String, pb.Value>{
              'preceding': str('unbounded'),
              'following': str('current'),
            }),
          }),
        );
      });

      test('serializes an unbounded to unbounded frame', () {
        expect(
          windowSpecArg(
            window(
              WindowSpec(
                frame: WindowFrame.documents(
                  preceding: WindowFrame.unbounded,
                  following: WindowFrame.unbounded,
                ),
              ),
              <Object>[c],
            ),
          ),
          map(<String, pb.Value>{
            'documents': map(<String, pb.Value>{
              'preceding': str('unbounded'),
              'following': str('unbounded'),
            }),
          }),
        );
      });

      test('serializes constant expression bounds', () {
        expect(
          spec(
            WindowFrame.documents(
              preceding: constant(3),
              following: constant(0),
            ),
          ),
          map(<String, pb.Value>{
            'sort': byDate(),
            'documents': map(<String, pb.Value>{
              'preceding': int_(3),
              'following': int_(0),
            }),
          }),
        );
      });
    });

    group('stage level range framing', () {
      pb.Value spec(String sortField, WindowFrame frame) => windowSpecArg(
        window(
          WindowSpec(
            sort: <Ordering>[field(sortField).ascending()],
            frame: frame,
          ),
          <Object>[c],
        ),
      );

      pb.Value bySalesPrice() =>
          array(<pb.Value>[ordering(fieldRef('salesPrice'), 'ascending')]);

      test('serializes numeric range offsets', () {
        expect(
          spec('salesPrice', WindowFrame.range(preceding: 10, following: 10)),
          map(<String, pb.Value>{
            'sort': bySalesPrice(),
            'range': map(<String, pb.Value>{
              'preceding': int_(10),
              'following': int_(10),
            }),
          }),
        );
      });

      test('serializes fractional range offsets as doubles', () {
        expect(
          spec('salesPrice', WindowFrame.range(preceding: 2.5, following: 0)),
          map(<String, pb.Value>{
            'sort': bySalesPrice(),
            'range': map(<String, pb.Value>{
              'preceding': dbl(2.5),
              'following': int_(0),
            }),
          }),
        );
      });

      test("serializes a range frame with a 'day' time unit", () {
        expect(
          spec(
            'date',
            WindowFrame.range(
              preceding: 30,
              following: WindowFrame.current,
              unit: 'day',
            ),
          ),
          map(<String, pb.Value>{
            'sort': byDate(),
            'range': map(<String, pb.Value>{
              'preceding': int_(30),
              'following': str('current'),
              'unit': str('day'),
            }),
          }),
        );
      });

      for (final String unit in <String>[
        'microsecond',
        'millisecond',
        'second',
        'minute',
        'hour',
        'day',
        'week',
        'month',
        'quarter',
        'year',
      ]) {
        test("serializes the '$unit' time unit", () {
          expect(
            spec(
              'date',
              WindowFrame.range(
                preceding: 1,
                following: WindowFrame.current,
                unit: unit,
              ),
            ).mapValue.fields['range'],
            map(<String, pb.Value>{
              'preceding': int_(1),
              'following': str('current'),
              'unit': str(unit),
            }),
          );
        });
      }

      test("omits 'unit' when it is not specified", () {
        expect(
          spec(
            'salesPrice',
            WindowFrame.range(
              preceding: WindowFrame.unbounded,
              following: WindowFrame.current,
            ),
          ).mapValue.fields['range'],
          map(<String, pb.Value>{
            'preceding': str('unbounded'),
            'following': str('current'),
          }),
        );
      });
    });

    group('fields', () {
      const WindowSpec byProduct = WindowSpec(partition: <Object>['product']);

      test('maps each alias to its aggregate function', () {
        expect(
          fieldsArg(
            window(byProduct, <Object>[
              field('salesPrice').sum().as('total'),
              countAll().as('c'),
            ]),
          ),
          map(<String, pb.Value>{
            'total': fn('sum', <pb.Value>[fieldRef('salesPrice')]),
            'c': fn('count'),
          }),
        );
      });

      test('supports nested output field paths', () {
        expect(
          fieldsArg(
            window(byProduct, <Object>[
              field('salesPrice').sum().as('stats.total'),
            ]),
          ),
          map(<String, pb.Value>{
            'stats.total': fn('sum', <pb.Value>[fieldRef('salesPrice')]),
          }),
        );
      });

      test('serializes all supported aggregate function names', () {
        final Field price = field('salesPrice');
        pb.Value of(String name) =>
            fn(name, <pb.Value>[fieldRef('salesPrice')]);
        expect(
          fieldsArg(
            window(byProduct, <Object>[
              countAll().as('countAll'),
              price.count().as('count'),
              price.greaterThan(10).countIf().as('countIf'),
              price.countDistinct().as('countDistinct'),
              price.sum().as('sum'),
              price.average().as('average'),
              price.minimum().as('minimum'),
              price.maximum().as('maximum'),
              price.first().as('first'),
              price.last().as('last'),
              price.arrayAgg().as('arrayAgg'),
              price.arrayAggDistinct().as('arrayAggDistinct'),
            ]),
          ),
          map(<String, pb.Value>{
            'countAll': fn('count'),
            'count': of('count'),
            'countIf': fn('count_if', <pb.Value>[
              fn('greater_than', <pb.Value>[fieldRef('salesPrice'), int_(10)]),
            ]),
            'countDistinct': of('count_distinct'),
            'sum': of('sum'),
            'average': of('average'),
            'minimum': of('minimum'),
            'maximum': of('maximum'),
            'first': of('first'),
            'last': of('last'),
            'arrayAgg': of('array_agg'),
            'arrayAggDistinct': of('array_agg_distinct'),
          }),
        );
      });

      test('serializes aggregates over computed expressions', () {
        expect(
          fieldsArg(
            window(byProduct, <Object>[
              field('salesPrice').multiply(2).sum().as('doubled'),
            ]),
          ),
          map(<String, pb.Value>{
            'doubled': fn('sum', <pb.Value>[
              fn('multiply', <pb.Value>[fieldRef('salesPrice'), int_(2)]),
            ]),
          }),
        );
      });

      test('serializes the rank window function', () {
        expect(
          fieldsArg(
            window(
              WindowSpec(sort: <Ordering>[field('salesPrice').descending()]),
              <Object>[rank().as('rank')],
            ),
          ),
          map(<String, pb.Value>{'rank': fn('rank')}),
        );
      });

      test('rejects duplicate aliases', () {
        expect(
          () => window(byProduct, <Object>[
            field('salesPrice').sum().as('total'),
            field('salesPrice').average().as('total'),
          ]),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => '${e.message}',
              'message',
              contains("Duplicate alias or field 'total'"),
            ),
          ),
        );
      });
    });

    group('accumulator level framing (over)', () {
      final WindowSpec byDateSpec = WindowSpec(
        sort: <Ordering>[field('date').ascending()],
      );

      test("wraps an aggregate in over() with a 'documents' frame", () {
        expect(
          fieldsArg(
            window(byDateSpec, <Object>[
              field('salesPrice')
                  .average()
                  .over(WindowFrame.documents(preceding: 1, following: 1))
                  .as('movingAverage'),
            ]),
          ),
          map(<String, pb.Value>{
            'movingAverage': fn('over', <pb.Value>[
              fn('average', <pb.Value>[fieldRef('salesPrice')]),
              map(<String, pb.Value>{
                'documents': map(<String, pb.Value>{
                  'preceding': int_(1),
                  'following': int_(1),
                }),
              }),
            ]),
          }),
        );
      });

      test(
        "wraps an aggregate in over() with a 'range' frame and time unit",
        () {
          expect(
            fieldsArg(
              window(byDateSpec, <Object>[
                field('salesPrice')
                    .sum()
                    .over(
                      WindowFrame.range(
                        preceding: 10,
                        following: 0,
                        unit: 'day',
                      ),
                    )
                    .as('tenDayTotal'),
              ]),
            ),
            map(<String, pb.Value>{
              'tenDayTotal': fn('over', <pb.Value>[
                fn('sum', <pb.Value>[fieldRef('salesPrice')]),
                map(<String, pb.Value>{
                  'range': map(<String, pb.Value>{
                    'preceding': int_(10),
                    'following': int_(0),
                    'unit': str('day'),
                  }),
                }),
              ]),
            }),
          );
        },
      );

      test('supports different frames for different accumulators', () {
        expect(
          fieldsArg(
            window(
              WindowSpec(
                partition: const <Object>['product'],
                sort: <Ordering>[field('date').ascending()],
              ),
              <Object>[
                field('salesPrice')
                    .sum()
                    .over(
                      WindowFrame.documents(
                        preceding: WindowFrame.unbounded,
                        following: WindowFrame.current,
                      ),
                    )
                    .as('runningTotal'),
                field('salesPrice')
                    .average()
                    .over(WindowFrame.documents(preceding: 1, following: 1))
                    .as('movingAverage'),
              ],
            ),
          ),
          map(<String, pb.Value>{
            'runningTotal': fn('over', <pb.Value>[
              fn('sum', <pb.Value>[fieldRef('salesPrice')]),
              map(<String, pb.Value>{
                'documents': map(<String, pb.Value>{
                  'preceding': str('unbounded'),
                  'following': str('current'),
                }),
              }),
            ]),
            'movingAverage': fn('over', <pb.Value>[
              fn('average', <pb.Value>[fieldRef('salesPrice')]),
              map(<String, pb.Value>{
                'documents': map(<String, pb.Value>{
                  'preceding': int_(1),
                  'following': int_(1),
                }),
              }),
            ]),
          }),
        );
      });

      test('supports over() on a ranking window function', () {
        expect(
          fieldsArg(
            window(byDateSpec, <Object>[
              rank()
                  .over(
                    WindowFrame.documents(
                      preceding: WindowFrame.unbounded,
                      following: WindowFrame.current,
                    ),
                  )
                  .as('r'),
            ]),
          ),
          map(<String, pb.Value>{
            'r': fn('over', <pb.Value>[
              fn('rank'),
              map(<String, pb.Value>{
                'documents': map(<String, pb.Value>{
                  'preceding': str('unbounded'),
                  'following': str('current'),
                }),
              }),
            ]),
          }),
        );
      });
    });

    group('options overload', () {
      test(
        'produces the same proto as the varargs overload',
        () {},
        skip: noOptionsOverload,
      );
      test(
        'does not leak window/fields into the stage options',
        () {},
        skip: noOptionsOverload,
      );
    });

    group('user data validation', () {
      test('validates expressions in partition', () {}, skip: noUndefined);
      test('validates expressions in sort', () {}, skip: noUndefined);
      test(
        'validates expressions in documents and range frame bounds and unit',
        () {},
        skip: noUndefined,
      );
      test(
        'validates expressions in fields and over() frames',
        () {},
        skip: noUndefined,
      );
    });
  });
}
