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
// The parts of the pipelines surface added to match firestore-pipelines.api.md
// of the JS SDK: window functions (after the JS SDK's
// test/unit/lite-api/add_window_fields.test.ts), the search stage, typed
// explain options, pipelines in a transaction and the smaller helpers.
//
// The Enterprise emulator rejects add_window_fields and search and ignores
// explain options, so these encodings are only checked here; see
// test/integration_enterprise/pipeline_surface_test.dart for what the
// emulator runs.

import 'dart:typed_data';

import 'package:cloud_firestore_dart/pipelines.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/transaction.dart'
    as core;
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/pipeline_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/datastore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/transaction.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as pb;
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:mockito/mockito.dart' show Fake;
import 'package:test/test.dart';

import 'pipeline_test_util.dart';

/// Records the pipeline requests a transaction sends.
class _RecordingClient extends Fake implements TransactionClient {
  final List<String> calls = <String>[];
  final List<proto.ExecutePipelineRequest> requests =
      <proto.ExecutePipelineRequest>[];

  @override
  Future<Uint8List> beginReadOnlyTransaction({Object? readTime}) async {
    calls.add('begin');
    return Uint8List.fromList(<int>[7]);
  }

  @override
  Future<List<proto.ExecutePipelineResponse>> executePipeline(
    proto.ExecutePipelineRequest request,
    Uint8List transaction,
  ) async {
    calls.add('pipeline in $transaction');
    requests.add(request..transaction = transaction);
    return <proto.ExecutePipelineResponse>[
      proto.ExecutePipelineResponse()
        ..results.add(proto.Document()..fields['n'] = integer(1)),
    ];
  }

  @override
  Future<void> rollback(Uint8List transaction) async {
    calls.add('rollback $transaction');
  }
}

void main() {
  Pipeline base() => source().collection('sales');

  pb.Pipeline_Stage last(Pipeline pipeline) => stagesOf(pipeline).last;

  pb.Value ordering(pb.Value expression, String direction) => mapValue(
    <String, pb.Value>{'direction': str(direction), 'expression': expression},
  );

  /// The window spec argument of the add_window_fields stage of [pipeline].
  pb.Value windowSpecArg(Pipeline pipeline) {
    final pb.Pipeline_Stage stage = last(pipeline);
    expect(stage.name, 'add_window_fields');
    expect(stage.args, hasLength(2));
    return stage.args[0];
  }

  /// The fields argument of the add_window_fields stage of [pipeline].
  pb.Value fieldsArg(Pipeline pipeline) {
    final pb.Pipeline_Stage stage = last(pipeline);
    expect(stage.name, 'add_window_fields');
    expect(stage.args, hasLength(2));
    return stage.args[1];
  }

  group('addWindowFields', () {
    test('has two arguments and no options', () {
      final pb.Pipeline_Stage stage = last(
        base().addWindowFields(
          const WindowSpec(partition: <Object>['product']),
          <Object>[countAll().as('c')],
        ),
      );
      expect(stage.name, 'add_window_fields');
      expect(stage.args, hasLength(2));
      expect(stage.options, isEmpty);
    });

    test('sends an empty window spec as an empty map', () {
      expect(
        windowSpecArg(
          base().addWindowFields(const WindowSpec(), <Object>[
            countAll().as('c'),
          ]),
        ),
        mapValue(<String, pb.Value>{}),
      );
    });

    test('sends partitions of names and expressions', () {
      expect(
        windowSpecArg(
          base().addWindowFields(
            WindowSpec(
              partition: <Object>[
                'product',
                field('region').toLower(),
                'metadata.region',
              ],
            ),
            <Object>[countAll().as('c')],
          ),
        ),
        mapValue(<String, pb.Value>{
          'partition': arrayValue(<pb.Value>[
            fieldRef('product'),
            fn('to_lower', <pb.Value>[fieldRef('region')]),
            fieldRef('metadata.region'),
          ]),
        }),
      );
    });

    test('sends partition and sort together', () {
      expect(
        windowSpecArg(
          base().addWindowFields(
            WindowSpec(
              partition: <Object>['product'],
              sort: <Ordering>[
                field('date').ascending(),
                field('price').descending(),
              ],
            ),
            <Object>[countAll().as('c')],
          ),
        ),
        mapValue(<String, pb.Value>{
          'partition': arrayValue(<pb.Value>[fieldRef('product')]),
          'sort': arrayValue(<pb.Value>[
            ordering(fieldRef('date'), 'ascending'),
            ordering(fieldRef('price'), 'descending'),
          ]),
        }),
      );
    });

    test('sends a documents frame', () {
      expect(
        windowSpecArg(
          base().addWindowFields(
            WindowSpec(
              sort: <Ordering>[field('date').ascending()],
              frame: WindowFrame.documents(preceding: 2, following: -1),
            ),
            <Object>[countAll().as('c')],
          ),
        ),
        mapValue(<String, pb.Value>{
          'sort': arrayValue(<pb.Value>[
            ordering(fieldRef('date'), 'ascending'),
          ]),
          'documents': mapValue(<String, pb.Value>{
            'preceding': integer(2),
            'following': integer(-1),
          }),
        }),
      );
    });

    test('sends the sentinels and expression bounds', () {
      expect(
        windowSpecArg(
          base().addWindowFields(
            WindowSpec(
              frame: WindowFrame.documents(
                preceding: WindowFrame.unbounded,
                following: WindowFrame.current,
              ),
            ),
            <Object>[countAll().as('c')],
          ),
        ),
        mapValue(<String, pb.Value>{
          'documents': mapValue(<String, pb.Value>{
            'preceding': str('unbounded'),
            'following': str('current'),
          }),
        }),
      );
      expect(
        windowSpecArg(
          base().addWindowFields(
            WindowSpec(
              frame: WindowFrame.documents(
                preceding: constant(3),
                following: constant(0),
              ),
            ),
            <Object>[countAll().as('c')],
          ),
        ),
        mapValue(<String, pb.Value>{
          'documents': mapValue(<String, pb.Value>{
            'preceding': integer(3),
            'following': integer(0),
          }),
        }),
      );
    });

    test('leaves out bounds that are not given', () {
      expect(
        windowSpecArg(
          base().addWindowFields(
            WindowSpec(frame: WindowFrame.documents(preceding: 1)),
            <Object>[countAll().as('c')],
          ),
        ),
        mapValue(<String, pb.Value>{
          'documents': mapValue(<String, pb.Value>{'preceding': integer(1)}),
        }),
      );
    });

    test('sends a range frame with fractional offsets and a unit', () {
      expect(
        windowSpecArg(
          base().addWindowFields(
            WindowSpec(
              sort: <Ordering>[field('salesPrice').ascending()],
              frame: WindowFrame.range(preceding: 2.5, following: 0),
            ),
            <Object>[countAll().as('c')],
          ),
        ),
        mapValue(<String, pb.Value>{
          'sort': arrayValue(<pb.Value>[
            ordering(fieldRef('salesPrice'), 'ascending'),
          ]),
          'range': mapValue(<String, pb.Value>{
            'preceding': dbl(2.5),
            'following': integer(0),
          }),
        }),
      );
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
        expect(
          windowSpecArg(
            base().addWindowFields(
              WindowSpec(
                sort: <Ordering>[field('date').ascending()],
                frame: WindowFrame.range(
                  preceding: 30,
                  following: WindowFrame.current,
                  unit: unit,
                ),
              ),
              <Object>[countAll().as('c')],
            ),
          ).mapValue.fields['range'],
          mapValue(<String, pb.Value>{
            'preceding': integer(30),
            'following': str('current'),
            'unit': str(unit),
          }),
          reason: unit,
        );
      }
    });

    test('maps every alias to its aggregate', () {
      expect(
        fieldsArg(
          base().addWindowFields(
            const WindowSpec(partition: <Object>['product']),
            <Object>[
              countAll().as('countAll'),
              field('salesPrice').count().as('count'),
              field('salesPrice').greaterThan(10).countIf().as('countIf'),
              field('salesPrice').countDistinct().as('countDistinct'),
              field('salesPrice').sum().as('sum'),
              field('salesPrice').average().as('average'),
              field('salesPrice').minimum().as('minimum'),
              field('salesPrice').maximum().as('maximum'),
              field('salesPrice').first().as('first'),
              field('salesPrice').last().as('last'),
              field('salesPrice').arrayAgg().as('arrayAgg'),
              field('salesPrice').arrayAggDistinct().as('arrayAggDistinct'),
              field('salesPrice').multiply(2).sum().as('stats.doubled'),
            ],
          ),
        ),
        mapValue(<String, pb.Value>{
          'countAll': fn('count'),
          'count': fn('count', <pb.Value>[fieldRef('salesPrice')]),
          'countIf': fn('count_if', <pb.Value>[
            fn('greater_than', <pb.Value>[fieldRef('salesPrice'), integer(10)]),
          ]),
          'countDistinct': fn('count_distinct', <pb.Value>[
            fieldRef('salesPrice'),
          ]),
          'sum': fn('sum', <pb.Value>[fieldRef('salesPrice')]),
          'average': fn('average', <pb.Value>[fieldRef('salesPrice')]),
          'minimum': fn('minimum', <pb.Value>[fieldRef('salesPrice')]),
          'maximum': fn('maximum', <pb.Value>[fieldRef('salesPrice')]),
          'first': fn('first', <pb.Value>[fieldRef('salesPrice')]),
          'last': fn('last', <pb.Value>[fieldRef('salesPrice')]),
          'arrayAgg': fn('array_agg', <pb.Value>[fieldRef('salesPrice')]),
          'arrayAggDistinct': fn('array_agg_distinct', <pb.Value>[
            fieldRef('salesPrice'),
          ]),
          'stats.doubled': fn('sum', <pb.Value>[
            fn('multiply', <pb.Value>[fieldRef('salesPrice'), integer(2)]),
          ]),
        }),
      );
    });

    test('sends rank()', () {
      expect(
        fieldsArg(
          base().addWindowFields(
            WindowSpec(sort: <Ordering>[field('salesPrice').descending()]),
            <Object>[rank().as('rank')],
          ),
        ),
        mapValue(<String, pb.Value>{'rank': fn('rank')}),
      );
    });

    test('wraps an aggregate with its own frame in over()', () {
      expect(
        fieldsArg(
          base().addWindowFields(
            WindowSpec(
              partition: <Object>['product'],
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
              field('salesPrice')
                  .sum()
                  .over(
                    WindowFrame.range(preceding: 10, following: 0, unit: 'day'),
                  )
                  .as('tenDayTotal'),
            ],
          ),
        ),
        mapValue(<String, pb.Value>{
          'runningTotal': fn('over', <pb.Value>[
            fn('sum', <pb.Value>[fieldRef('salesPrice')]),
            mapValue(<String, pb.Value>{
              'documents': mapValue(<String, pb.Value>{
                'preceding': str('unbounded'),
                'following': str('current'),
              }),
            }),
          ]),
          'movingAverage': fn('over', <pb.Value>[
            fn('average', <pb.Value>[fieldRef('salesPrice')]),
            mapValue(<String, pb.Value>{
              'documents': mapValue(<String, pb.Value>{
                'preceding': integer(1),
                'following': integer(1),
              }),
            }),
          ]),
          'tenDayTotal': fn('over', <pb.Value>[
            fn('sum', <pb.Value>[fieldRef('salesPrice')]),
            mapValue(<String, pb.Value>{
              'range': mapValue(<String, pb.Value>{
                'preceding': integer(10),
                'following': integer(0),
                'unit': str('day'),
              }),
            }),
          ]),
        }),
      );
    });

    test('supports over() on rank()', () {
      expect(
        fieldsArg(
          base().addWindowFields(
            WindowSpec(sort: <Ordering>[field('date').ascending()]),
            <Object>[
              rank()
                  .over(
                    WindowFrame.documents(
                      preceding: WindowFrame.unbounded,
                      following: WindowFrame.current,
                    ),
                  )
                  .as('r'),
            ],
          ),
        ),
        mapValue(<String, pb.Value>{
          'r': fn('over', <pb.Value>[
            fn('rank'),
            mapValue(<String, pb.Value>{
              'documents': mapValue(<String, pb.Value>{
                'preceding': str('unbounded'),
                'following': str('current'),
              }),
            }),
          ]),
        }),
      );
    });

    test('passes raw options', () {
      expect(
        last(
          base().addWindowFields(
            const WindowSpec(),
            <Object>[countAll().as('c')],
            rawOptions: <String, Object?>{'custom': 'x'},
          ),
        ).options,
        <String, pb.Value>{'custom': str('x')},
      );
    });

    test('rejects duplicate aliases, other values and no fields', () {
      expect(
        () => base().addWindowFields(const WindowSpec(), <Object>[
          field('salesPrice').sum().as('total'),
          field('salesPrice').average().as('total'),
        ]),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message,
            'message',
            contains("Duplicate alias or field 'total'"),
          ),
        ),
      );
      expect(
        () => base().addWindowFields(const WindowSpec(), <Object>[
          field('a').as('a'),
        ]),
        throwsArgumentError,
      );
      expect(
        () => base().addWindowFields(const WindowSpec(), <Object>[]),
        throwsArgumentError,
      );
    });

    test('rejects frame bounds of other types', () {
      expect(() => WindowFrame.documents(preceding: true), throwsArgumentError);
      expect(() => WindowFrame.range(unit: 3), throwsArgumentError);
    });
  });

  group('search', () {
    test('a string query is short for documentMatches', () {
      expect(
        last(base().search('waffles OR pancakes')),
        stage('search', <pb.Value>[], <String, pb.Value>{
          'query': fn('document_matches', <pb.Value>[
            str('waffles OR pancakes'),
          ]),
        }),
      );
    });

    test('sends every option under its server name', () {
      expect(
        last(
          base().search(
            documentMatches('waffles'),
            sort: <Ordering>[score().descending()],
            addFields: <Selectable>[score().as('searchScore')],
            languageCode: 'en',
            retrievalDepth: 100,
            offset: 5,
            limit: 10,
            rawOptions: <String, Object?>{'query_enhancement': 'disabled'},
          ),
        ),
        stage('search', <pb.Value>[], <String, pb.Value>{
          'query': fn('document_matches', <pb.Value>[str('waffles')]),
          'sort': arrayValue(<pb.Value>[ordering(fn('score'), 'descending')]),
          'add_fields': mapValue(<String, pb.Value>{
            'searchScore': fn('score'),
          }),
          'language_code': str('en'),
          'retrieval_depth': integer(100),
          'offset': integer(5),
          'limit': integer(10),
          'query_enhancement': str('disabled'),
        }),
      );
    });

    test('takes a geo condition', () {
      expect(
        last(
          base().search(
            field('location').geoDistance(field('home')).lessThan(1000),
          ),
        ).options['query'],
        fn('less_than', <pb.Value>[
          fn('geo_distance', <pb.Value>[
            fieldRef('location'),
            fieldRef('home'),
          ]),
          integer(1000),
        ]),
      );
    });

    test('rejects other queries and duplicate added fields', () {
      expect(() => base().search(3), throwsArgumentError);
      expect(
        () => base().search(
          'x',
          addFields: <Selectable>[score().as('s'), field('a').as('s')],
        ),
        throwsArgumentError,
      );
    });
  });

  group('explain options', () {
    Map<String, pb.Value> optionsOf(PipelineExplainOptions? explainOptions) =>
        base()
            .toExecuteRequest(encoder(), explainOptions: explainOptions)
            .structuredPipeline
            .options;

    test('are not sent by default', () {
      expect(optionsOf(null), isEmpty);
    });

    test('are sent as explain_options with mode and output_format', () {
      expect(
        optionsOf(
          const PipelineExplainOptions(
            mode: PipelineExplainMode.analyze,
            outputFormat: PipelineExplainOutputFormat.text,
          ),
        ),
        <String, pb.Value>{
          'explain_options': mapValue(<String, pb.Value>{
            'mode': str('analyze'),
            'output_format': str('text'),
          }),
        },
      );
      expect(
        optionsOf(
          const PipelineExplainOptions(mode: PipelineExplainMode.explain),
        ),
        <String, pb.Value>{
          'explain_options': mapValue(<String, pb.Value>{
            'mode': str('explain'),
          }),
        },
      );
      expect(
        optionsOf(
          const PipelineExplainOptions(mode: PipelineExplainMode.execute),
        ),
        <String, pb.Value>{
          'explain_options': mapValue(<String, pb.Value>{
            'mode': str('execute'),
          }),
        },
      );
      expect(optionsOf(const PipelineExplainOptions()), <String, pb.Value>{
        'explain_options': mapValue(<String, pb.Value>{}),
      });
    });

    test('raw options override them', () {
      expect(
        base()
            .toExecuteRequest(
              encoder(),
              explainOptions: const PipelineExplainOptions(
                mode: PipelineExplainMode.analyze,
              ),
              rawOptions: <String, Object?>{
                'explain_options': <String, Object?>{'mode': 'explain'},
              },
            )
            .structuredPipeline
            .options['explain_options'],
        mapValue(<String, pb.Value>{'mode': str('explain')}),
      );
    });
  });

  group('expressions', () {
    test('arraySum, log10 and documentMatches with an expression', () {
      expect(
        encode(field('scores').arraySum()),
        fn('sum', <pb.Value>[fieldRef('scores')]),
      );
      expect(
        encode(field('value').log10()),
        fn('log10', <pb.Value>[fieldRef('value')]),
      );
      expect(
        encode(documentMatches(field('q'))),
        fn('document_matches', <pb.Value>[fieldRef('q')]),
      );
      expect(encode(score()), fn('score'));
    });

    test('mapSet takes more key/value pairs', () {
      expect(
        encode(field('m').mapSet('a', 1, <Object?>['b', field('c')])),
        fn('map_set', <pb.Value>[
          fieldRef('m'),
          str('a'),
          integer(1),
          str('b'),
          fieldRef('c'),
        ]),
      );
      expect(
        encode(field('m').mapSet('a', 1)),
        fn('map_set', <pb.Value>[fieldRef('m'), str('a'), integer(1)]),
      );
      expect(
        () => field('m').mapSet('a', 1, <Object?>['b']),
        throwsArgumentError,
      );
    });
  });

  group('pipelineResultEqual', () {
    const String prefix = 'projects/new-project/databases/(default)/documents';

    List<PipelineResult> decode(List<proto.Document> documents) {
      return decodePipelineResponses(
        base(),
        fakeFirestore,
        encoder().serializer,
        <proto.ExecutePipelineResponse>[
          proto.ExecutePipelineResponse()..results.addAll(documents),
        ],
      ).results;
    }

    test('compares the document and the data', () {
      final List<PipelineResult> results = decode(<proto.Document>[
        proto.Document()
          ..name = '$prefix/sales/a'
          ..fields['n'] = integer(1),
        proto.Document()
          ..name = '$prefix/sales/a'
          ..fields['n'] = integer(1),
        proto.Document()
          ..name = '$prefix/sales/b'
          ..fields['n'] = integer(1),
        proto.Document()
          ..name = '$prefix/sales/a'
          ..fields['n'] = integer(2),
        proto.Document()..fields['n'] = integer(1),
        proto.Document()..fields['n'] = integer(1),
      ]);
      expect(pipelineResultEqual(results[0], results[0]), isTrue);
      expect(pipelineResultEqual(results[0], results[1]), isTrue);
      expect(pipelineResultEqual(results[0], results[2]), isFalse);
      expect(pipelineResultEqual(results[0], results[3]), isFalse);
      expect(pipelineResultEqual(results[0], results[4]), isFalse);
      expect(pipelineResultEqual(results[4], results[5]), isTrue);
    });
  });

  group('Transaction.execute', () {
    late _RecordingClient client;

    setUp(() => client = _RecordingClient());

    Transaction transaction({required bool readOnly}) =>
        TransactionInternal.create(
          core.Transaction(client, readOnly: readOnly),
          fakeFirestore,
        );

    test('runs the pipeline in the read-only transaction', () async {
      final Transaction tx = transaction(readOnly: true);
      final PipelineSnapshot first = await tx.execute(
        base().where(field('n').equal(1)),
        indexMode: PipelineIndexMode.recommended,
        explainOptions: const PipelineExplainOptions(
          mode: PipelineExplainMode.analyze,
        ),
      );
      await tx.execute(base());

      expect(first.results.single.data(), <String, Object?>{'n': 1});
      expect(client.calls, <String>[
        'begin',
        'pipeline in [7]',
        'pipeline in [7]',
      ]);
      final proto.ExecutePipelineRequest request = client.requests.first;
      expect(request.transaction, <int>[7]);
      expect(request.hasNewTransaction(), isFalse);
      expect(request.autoCommitTransaction, isFalse);
      expect(request.structuredPipeline.options.keys, <String>[
        'index_mode',
        'explain_options',
      ]);
      expect(request.structuredPipeline.pipeline.stages.last.name, 'where');
    });

    test('fails in a read-write transaction', () async {
      final Transaction tx = transaction(readOnly: false);
      await expectLater(
        tx.execute(base()),
        throwsA(
          isA<FirestoreError>().having(
            (FirestoreError e) => e.code,
            'code',
            FirestoreErrorCode.invalidArgument,
          ),
        ),
      );
      expect(client.calls, isEmpty);
    });

    test('rejects write stages before sending anything', () async {
      final Transaction tx = transaction(readOnly: true);
      for (final Pipeline pipeline in <Pipeline>[
        base().delete(),
        base().update(),
        base().insert(),
        base().upsert(),
      ]) {
        await expectLater(
          tx.execute(pipeline),
          throwsA(
            isA<FirestoreError>().having(
              (FirestoreError e) => e.code,
              'code',
              FirestoreErrorCode.invalidArgument,
            ),
          ),
        );
      }
      expect(client.calls, isEmpty);
    });

    test('rejects a pipeline of another instance', () {
      final Transaction tx = transaction(readOnly: true);
      expect(
        () => tx.execute(PipelineSource(FakeFirestore()).collection('x')),
        throwsArgumentError,
      );
    });

    test('rejects a subcollection pipeline', () {
      final Transaction tx = transaction(readOnly: true);
      expect(
        () => tx.execute(source().subcollection('reviews')),
        throwsStateError,
      );
    });
  });
}
