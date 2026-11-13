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
// Phase 2 of the Pipelines preview: write stages and atomic execution,
// subqueries and variables, lambda functions, explain. The write stage cases
// port the JS SDK's test/unit/api/pipeline_impl.test.ts.

import 'package:cloud_firestore_dart/pipelines.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/collection_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/pipeline_result.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as pb;
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:test/test.dart';

import 'pipeline_test_util.dart';

void main() {
  Pipeline base() => source().collection('books');

  pb.Pipeline_Stage last(Pipeline pipeline) => stagesOf(pipeline).last;

  final Field a = field('a');
  final pb.Value fa = fieldRef('a');

  pb.Value variableRef(String name) =>
      pb.Value()..variableReferenceValue = name;

  group('atomic execution', () {
    test('is off by default', () {
      final proto.ExecutePipelineRequest request =
          base().delete().toExecuteRequest(encoder());
      expect(request.hasNewTransaction(), isFalse);
      expect(request.autoCommitTransaction, isFalse);
      expect(
          base().toExecuteRequest(encoder(), atomic: false).hasNewTransaction(),
          isFalse);
    });

    test('starts an optimistic read-write transaction that auto commits', () {
      final proto.ExecutePipelineRequest request =
          base().delete().toExecuteRequest(encoder(), atomic: true);
      expect(request.autoCommitTransaction, isTrue);
      expect(request.newTransaction.hasReadWrite(), isTrue);
      expect(request.newTransaction.readWrite.concurrencyMode,
          proto.TransactionOptions_ConcurrencyMode.OPTIMISTIC);
      // `atomic` is not a pipeline option.
      expect(request.structuredPipeline.options, isEmpty);
    });
  });

  group('write stages', () {
    test('delete', () {
      expect(last(base().delete()), stage('delete'));
      expect(
          last(base().delete(rawOptions: <String, Object?>{'custom': 'x'})),
          stage(
              'delete', <pb.Value>[], <String, pb.Value>{'custom': str('x')}));
    });

    test('update without transforms sends an empty map', () {
      expect(last(base().update()),
          stage('update', <pb.Value>[mapValue(<String, pb.Value>{})]));
    });

    test('update with transforms', () {
      expect(
          last(base().update(transformedFields: <Selectable>[
            a.add(1).as('a'),
            constant('x').as('b'),
          ])),
          stage('update', <pb.Value>[
            mapValue(<String, pb.Value>{
              'a': fn('add', <pb.Value>[fa, integer(1)]),
              'b': str('x'),
            })
          ]));
      expect(
          () => base().update(transformedFields: <Selectable>[
                a.add(1).as('x'),
                a.add(2).as('x'),
              ]),
          throwsArgumentError);
    });

    test('insert without arguments', () {
      expect(last(base().insert()), stage('insert'));
    });

    test('insert with a collection path and a document id field', () {
      expect(
          last(base().insert(collection: 'archive', documentId: 'id')),
          stage('insert', <pb.Value>[], <String, pb.Value>{
            'collection': ref('/archive'),
            'document_id': fieldRef('id'),
          }));
    });

    test('insert with a CollectionReference and a document id expression', () {
      expect(
          last(base().insert(
              collection: CollectionReferenceInternal.create<Map<String, Object?>>(
                  ResourcePath.fromString('a/b/c'), fakeFirestore),
              documentId: field('title').toLower())),
          stage('insert', <pb.Value>[], <String, pb.Value>{
            'collection': ref('/a/b/c'),
            'document_id': fn('to_lower', <pb.Value>[fieldRef('title')]),
          }));
    });

    test('insert with raw options', () {
      expect(
          last(base().insert(
              collection: 'archive',
              rawOptions: <String, Object?>{'custom': 1})),
          stage('insert', <pb.Value>[], <String, pb.Value>{
            'collection': ref('/archive'),
            'custom': integer(1),
          }));
    });

    test('upsert without arguments sends an empty map', () {
      expect(last(base().upsert()),
          stage('upsert', <pb.Value>[mapValue(<String, pb.Value>{})]));
    });

    test('upsert with additional fields and a target', () {
      expect(
          last(base().upsert(
            additionalFields: <Selectable>[
              constant(true).as('archived'),
              a.add(1).as('a'),
            ],
            collection: 'archive',
            documentId: field('id'),
          )),
          stage('upsert', <pb.Value>[
            mapValue(<String, pb.Value>{
              'archived': boolean(true),
              'a': fn('add', <pb.Value>[fa, integer(1)]),
            })
          ], <String, pb.Value>{
            'collection': ref('/archive'),
            'document_id': fieldRef('id'),
          }));
    });

    test('insert and upsert reject invalid collections', () {
      expect(() => base().insert(collection: ''), throwsArgumentError);
      expect(() => base().upsert(collection: ''), throwsArgumentError);
      expect(() => base().insert(collection: 'a/b'), throwsArgumentError);
      expect(() => base().insert(collection: 1), throwsArgumentError);

      final Firestore other =
          FakeFirestore(DatabaseId.forDatabase('other-project', '(default)'));
      final CollectionReference<Map<String, Object?>> foreign =
          CollectionReferenceInternal.create<Map<String, Object?>>(
              ResourcePath.fromString('a'), other);
      expect(() => base().insert(collection: foreign), throwsArgumentError);
      expect(() => base().upsert(collection: foreign), throwsArgumentError);
    });
  });

  group('variables and subqueries', () {
    test('define', () {
      expect(
          last(base().define(<AliasedExpression>[
            a.add(1).as('x'),
            currentDocument().as('doc'),
          ])),
          stage('let', <pb.Value>[
            mapValue(<String, pb.Value>{
              'x': fn('add', <pb.Value>[fa, integer(1)]),
              'doc': fn('current_document'),
            })
          ]));
      expect(() => base().define(<AliasedExpression>[]), throwsArgumentError);
    });

    test('variable, currentDocument and getField', () {
      expect(encode(variable('x')), variableRef('x'));
      expect(encode(variable('x').add(1)),
          fn('add', <pb.Value>[variableRef('x'), integer(1)]));
      expect(encode(variable('doc').getField('title')),
          fn('get_field', <pb.Value>[variableRef('doc'), str('title')]));
      expect(encode(currentDocument().getField(field('key'))),
          fn('get_field', <pb.Value>[fn('current_document'), fieldRef('key')]));
    });

    final pb.Value subquery = pb.Value()
      ..pipelineValue = (pb.Pipeline()
        ..stages.addAll(<pb.Pipeline_Stage>[
          stage('subcollection', <pb.Value>[str('reviews')]),
          stage('limit', <pb.Value>[integer(1)]),
        ]));

    test('subcollection', () {
      expect(stagesOf(source().subcollection('reviews')), <pb.Pipeline_Stage>[
        stage('subcollection', <pb.Value>[str('reviews')])
      ]);
      expect(stagesOf(source().subcollection('reviews/r1/replies')).single.args,
          <pb.Value>[str('reviews/r1/replies')]);
      expect(() => source().subcollection(''), throwsArgumentError);
      expect(() => source().subcollection('a/b'), throwsArgumentError);
    });

    test('a subcollection pipeline cannot be executed directly', () {
      expect(source().subcollection('reviews').limit(1).execute(),
          throwsStateError);
    });

    test('toArrayExpression and toScalarExpression', () {
      final Pipeline sub = source().subcollection('reviews').limit(1);
      expect(
          encode(sub.toArrayExpression()), fn('array', <pb.Value>[subquery]));
      expect(
          encode(sub.toScalarExpression()), fn('scalar', <pb.Value>[subquery]));
    });

    test('a subquery inside a stage', () {
      final Pipeline sub = source().subcollection('reviews').limit(1);
      expect(
          last(base()
              .addFields(<Selectable>[sub.toArrayExpression().as('reviews')])),
          stage('add_fields', <pb.Value>[
            mapValue(<String, pb.Value>{
              'reviews': fn('array', <pb.Value>[subquery]),
            })
          ]));
    });
  });

  group('lambda functions', () {
    test('arrayFilter', () {
      expect(
          encode(a.arrayFilter((Expression e) => e.greaterThan(1))),
          fn('array_filter', <pb.Value>[
            fa,
            str('element'),
            fn('greater_than', <pb.Value>[variableRef('element'), integer(1)]),
          ]));
      expect(
          encode(a.arrayFilter((Expression e) => e.getField('ok').asBoolean(),
              alias: 'item')),
          fn('array_filter', <pb.Value>[
            fa,
            str('item'),
            fn('get_field', <pb.Value>[variableRef('item'), str('ok')]),
          ]));
    });

    test('arrayTransform', () {
      expect(
          encode(a.arrayTransform((Expression e) => e.multiply(2))),
          fn('array_transform', <pb.Value>[
            fa,
            str('element'),
            fn('multiply', <pb.Value>[variableRef('element'), integer(2)]),
          ]));
      // A result that is not an expression is a constant.
      expect(encode(a.arrayTransform((Expression e) => 0, alias: 'x')),
          fn('array_transform', <pb.Value>[fa, str('x'), integer(0)]));
    });

    test('arrayTransformWithIndex', () {
      expect(
          encode(a.arrayTransformWithIndex(
              (Expression e, Expression i) => e.add(i))),
          fn('array_transform', <pb.Value>[
            fa,
            str('element'),
            str('index'),
            fn('add', <pb.Value>[variableRef('element'), variableRef('index')]),
          ]));
      expect(
          encode(a.arrayTransformWithIndex((Expression e, Expression i) => i,
              elementAlias: 'v', indexAlias: 'k')),
          fn('array_transform',
              <pb.Value>[fa, str('v'), str('k'), variableRef('k')]));
    });

    test('nested lambdas use their own aliases', () {
      expect(
          encode(a.arrayTransform(
              (Expression row) => row.arrayFilter(
                  (Expression cell) => cell.greaterThan(row.arrayLength()),
                  alias: 'cell'),
              alias: 'row')),
          fn('array_transform', <pb.Value>[
            fa,
            str('row'),
            fn('array_filter', <pb.Value>[
              variableRef('row'),
              str('cell'),
              fn('greater_than', <pb.Value>[
                variableRef('cell'),
                fn('array_length', <pb.Value>[variableRef('row')]),
              ]),
            ]),
          ]));
    });
  });

  test('switchOn, nor and array extremes', () {
    final BooleanExpression c1 = field('x').exists();
    final BooleanExpression c2 = field('y').exists();
    final pb.Value p1 = fn('exists', <pb.Value>[fieldRef('x')]);
    final pb.Value p2 = fn('exists', <pb.Value>[fieldRef('y')]);

    expect(encode(switchOn(c1, 'one')),
        fn('switch_on', <pb.Value>[p1, str('one')]));
    expect(encode(switchOn(c1, 'one', <Object?>[c2, a, 'default'])),
        fn('switch_on', <pb.Value>[p1, str('one'), p2, fa, str('default')]));
    expect(encode(nor(c1, c2)), fn('nor', <pb.Value>[p1, p2]));
    expect(encode(c1.nor(c2, <BooleanExpression>[c1])),
        fn('nor', <pb.Value>[p1, p2, p1]));
    expect(encode(a.arrayMaximum()), fn('maximum', <pb.Value>[fa]));
    expect(encode(a.arrayMinimum()), fn('minimum', <pb.Value>[fa]));
    expect(encode(a.arrayMaximumN(2)),
        fn('maximum_n', <pb.Value>[fa, integer(2)]));
    expect(encode(a.arrayMinimumN(field('n'))),
        fn('minimum_n', <pb.Value>[fa, fieldRef('n')]));
  });

  group('explain', () {
    test('options are sent with rawOptions', () {
      expect(
          base()
              .toExecuteRequest(encoder(), rawOptions: <String, Object?>{
                'explain_options': <String, Object?>{'mode': 'analyze'}
              })
              .structuredPipeline
              .options,
          <String, pb.Value>{
            'explain_options':
                mapValue(<String, pb.Value>{'mode': str('analyze')}),
          });
    });

    PipelineSnapshot decode(List<proto.ExecutePipelineResponse> responses) {
      return decodePipelineResponses(
          base(), fakeFirestore, encoder().serializer, responses);
    }

    test('stats are null when the server sends none', () {
      expect(
          decode(<proto.ExecutePipelineResponse>[
            proto.ExecutePipelineResponse()
          ]).explainStats,
          isNull);
    });

    test('text stats of the last response are decoded', () {
      final PipelineSnapshot snapshot = decode(<proto.ExecutePipelineResponse>[
        proto.ExecutePipelineResponse()
          ..results.add(proto.Document()..fields['n'] = integer(1)),
        proto.ExecutePipelineResponse()
          ..explainStats = (proto.ExplainStats()
            ..data = proto.Any.pack(proto.StringValue()..value = 'the plan')),
      ]);
      expect(snapshot.results, hasLength(1));
      expect(snapshot.explainStats!.typeUrl,
          'type.googleapis.com/google.protobuf.StringValue');
      expect(snapshot.explainStats!.text, 'the plan');
    });

    test('stats of another type are kept raw', () {
      final PipelineExplainStats stats = decode(<proto.ExecutePipelineResponse>[
        proto.ExecutePipelineResponse()
          ..explainStats = (proto.ExplainStats()
            ..data = (proto.Any()
              ..typeUrl = 'type.googleapis.com/some.Other'
              ..value = <int>[1, 2, 3])),
      ]).explainStats!;
      expect(stats.text, isNull);
      expect(stats.value, <int>[1, 2, 3]);
    });
  });
}
