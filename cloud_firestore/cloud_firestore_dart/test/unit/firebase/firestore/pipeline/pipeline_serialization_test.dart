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
// Ports the phase 1 parts of the JS SDK's test/unit/api/pipeline_impl.test.ts
// (request and stage serialization) and adds one case per stage.

import 'package:cloud_firestore_dart/pipelines.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/collection_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/distance_measure.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/vector_value.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as pb;
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:test/test.dart';

import 'pipeline_test_util.dart';

void main() {
  group('execute request', () {
    test('serializes the pipeline', () {
      final proto.ExecutePipelineRequest request =
          source().collection('foo').toExecuteRequest(encoder());

      expect(request.database, 'projects/new-project/databases/(default)');
      expect(request.structuredPipeline.options, isEmpty);
      expect(request.structuredPipeline.pipeline.stages, <pb.Pipeline_Stage>[
        stage('collection', <pb.Value>[ref('/foo')]),
      ]);
      expect(request.hasNewTransaction(), isFalse);
      expect(request.autoCommitTransaction, isFalse);
    });

    test('serializes the pipeline options', () {
      final proto.ExecutePipelineRequest request = source()
          .collection('foo')
          .toExecuteRequest(encoder(),
              indexMode: PipelineIndexMode.recommended);

      expect(request.structuredPipeline.options,
          <String, pb.Value>{'index_mode': str('recommended')});
      expect(request.structuredPipeline.pipeline.stages, <pb.Pipeline_Stage>[
        stage('collection', <pb.Value>[ref('/foo')]),
      ]);
    });

    test('serializes the pipeline raw options', () {
      final proto.ExecutePipelineRequest request = source()
          .collection('foo')
          .toExecuteRequest(encoder(),
              rawOptions: <String, Object?>{'foo': 'bar'});

      expect(request.structuredPipeline.options,
          <String, pb.Value>{'foo': str('bar')});
    });

    test('raw options override known options', () {
      final proto.ExecutePipelineRequest request = source()
          .collection('foo')
          .toExecuteRequest(encoder(),
              indexMode: PipelineIndexMode.recommended,
              rawOptions: <String, Object?>{'index_mode': 'other'});

      expect(request.structuredPipeline.options,
          <String, pb.Value>{'index_mode': str('other')});
    });
  });

  group('sources', () {
    test('collection', () {
      expect(stagesOf(source().collection('foo')), <pb.Pipeline_Stage>[
        stage('collection', <pb.Value>[ref('/foo')])
      ]);
      expect(stagesOf(source().collection('/foo/bar/baz')), <pb.Pipeline_Stage>[
        stage('collection', <pb.Value>[ref('/foo/bar/baz')])
      ]);
      expect(
          stagesOf(source().collection(
              CollectionReferenceInternal.create<Map<String, Object?>>(
                  ResourcePath.fromString('a/b/c'), fakeFirestore))),
          <pb.Pipeline_Stage>[
            stage('collection', <pb.Value>[ref('/a/b/c')])
          ]);
    });

    test('collection with options', () {
      expect(
          stagesOf(source().collection('foo',
              forceIndex: 'idx', rawOptions: <String, Object?>{'x': 1})),
          <pb.Pipeline_Stage>[
            stage('collection', <pb.Value>[ref('/foo')],
                <String, pb.Value>{'force_index': str('idx'), 'x': integer(1)})
          ]);
    });

    test('collection rejects invalid arguments', () {
      expect(() => source().collection(''), throwsArgumentError);
      expect(() => source().collection('a/b'), throwsArgumentError);
      expect(() => source().collection('a//b'), throwsArgumentError);
      expect(() => source().collection(42), throwsArgumentError);
    });

    test('rejects references of another database', () {
      final Firestore other =
          FakeFirestore(DatabaseId.forDatabase('other-project', '(default)'));
      expect(
          () => source().collection(CollectionReferenceInternal.create<Map<String, Object?>>(
              ResourcePath.fromString('a'), other)),
          throwsA(isA<ArgumentError>().having((ArgumentError e) => e.message,
              'message', contains('does not match the project ID'))));
      expect(
          () => source().documents(<Object>[
                DocumentReferenceInternal.create<Map<String, Object?>>(
                    DocumentKey.fromPathString('a/b'), other)
              ]),
          throwsArgumentError);
    });

    test('collectionGroup', () {
      expect(stagesOf(source().collectionGroup('books')), <pb.Pipeline_Stage>[
        stage('collection_group', <pb.Value>[ref(''), str('books')])
      ]);
      expect(() => source().collectionGroup(''), throwsArgumentError);
      expect(() => source().collectionGroup('a/b'), throwsArgumentError);
    });

    test('database', () {
      expect(stagesOf(source().database()),
          <pb.Pipeline_Stage>[stage('database')]);
    });

    test('documents', () {
      expect(
          stagesOf(source().documents(<Object>[
            'a/b',
            '/c/d',
            DocumentReferenceInternal.create<Map<String, Object?>>(
                DocumentKey.fromPathString('e/f'), fakeFirestore),
          ])),
          <pb.Pipeline_Stage>[
            stage(
                'documents', <pb.Value>[ref('/a/b'), ref('/c/d'), ref('/e/f')])
          ]);
      expect(() => source().documents(<Object>[]), throwsArgumentError);
      expect(() => source().documents(<Object>['a']), throwsArgumentError);
    });

    test('literals', () {
      expect(
          stagesOf(source().literals(<Map<String, Object?>>[
            <String, Object?>{'name': 'Alice', 'age': 30},
            <String, Object?>{'name': 'Bob', 'age': 25},
          ])),
          <pb.Pipeline_Stage>[
            stage('literals', <pb.Value>[
              mapValue(
                  <String, pb.Value>{'name': str('Alice'), 'age': integer(30)}),
              mapValue(
                  <String, pb.Value>{'name': str('Bob'), 'age': integer(25)}),
            ])
          ]);
    });

    test('literals with a list field', () {
      expect(
          stagesOf(source().literals(<Map<String, Object?>>[
            <String, Object?>{
              'documents': <String>['a', 'b'],
              'title': 'Folder'
            },
          ])),
          <pb.Pipeline_Stage>[
            stage('literals', <pb.Value>[
              mapValue(<String, pb.Value>{
                'documents': fn('array', <pb.Value>[str('a'), str('b')]),
                'title': str('Folder'),
              }),
            ])
          ]);
    });

    test('literals with raw options', () {
      expect(
          stagesOf(source().literals(<Map<String, Object?>>[
            <String, Object?>{'item': 'apple', 'count': 10},
          ], rawOptions: <String, Object?>{
            'custom_opt': 'val'
          })),
          <pb.Pipeline_Stage>[
            stage('literals', <pb.Value>[
              mapValue(<String, pb.Value>{
                'item': str('apple'),
                'count': integer(10)
              }),
            ], <String, pb.Value>{
              'custom_opt': str('val')
            })
          ]);
    });

    test('literals with expressions at the top level, in maps and in lists',
        () {
      expect(
          stagesOf(source().literals(<Map<String, Object?>>[
            <String, Object?>{
              'base': 10,
              'calc': constant(10).multiply(constant(2)),
              'nested': <String, Object?>{
                'val': constant('hello'),
                'sum': constant(1).add(constant(2)),
              },
              'arr': <Object?>[1, constant(3).add(constant(4))],
            },
          ])),
          <pb.Pipeline_Stage>[
            stage('literals', <pb.Value>[
              mapValue(<String, pb.Value>{
                'base': integer(10),
                'calc': fn('multiply', <pb.Value>[integer(10), integer(2)]),
                'nested': fn('map', <pb.Value>[
                  str('val'),
                  str('hello'),
                  str('sum'),
                  fn('add', <pb.Value>[integer(1), integer(2)]),
                ]),
                'arr': fn('array', <pb.Value>[
                  integer(1),
                  fn('add', <pb.Value>[integer(3), integer(4)]),
                ]),
              }),
            ])
          ]);
    });
  });

  group('stages', () {
    Pipeline base() => source().collection('books');

    pb.Pipeline_Stage last(Pipeline pipeline) => stagesOf(pipeline).last;

    test('a pipeline is immutable', () {
      final Pipeline a = base();
      final Pipeline b = a.limit(1);
      expect(stagesOf(a), hasLength(1));
      expect(stagesOf(b), hasLength(2));
    });

    test('where', () {
      expect(
          last(base().where(field('state').equal('MD'))),
          stage('where', <pb.Value>[
            fn('equal', <pb.Value>[fieldRef('state'), str('MD')])
          ]));
    });

    test('select', () {
      expect(
          last(base().select(<Object>[
            'title',
            field('author.name'),
            field('title').toUpper().as('upper'),
          ])),
          stage('select', <pb.Value>[
            mapValue(<String, pb.Value>{
              'title': fieldRef('title'),
              'author.name': fieldRef('author.name'),
              'upper': fn('to_upper', <pb.Value>[fieldRef('title')]),
            })
          ]));
    });

    test('select rejects duplicates, empty lists and unsupported values', () {
      expect(
          () => base().select(<Object>['a', field('a')]),
          throwsA(isA<ArgumentError>().having((ArgumentError e) => e.message,
              'message', contains("Duplicate alias or field 'a'"))));
      expect(() => base().select(<Object>[]), throwsArgumentError);
      expect(() => base().select(<Object>[1]), throwsArgumentError);
      expect(() => base().select(<Object>[field('a').add(1)]),
          throwsArgumentError);
    });

    test('addFields', () {
      expect(
          last(base()
              .addFields(<Selectable>[field('a').add(field('b')).as('sum')])),
          stage('add_fields', <pb.Value>[
            mapValue(<String, pb.Value>{
              'sum': fn('add', <pb.Value>[fieldRef('a'), fieldRef('b')])
            })
          ]));
    });

    test('removeFields', () {
      expect(last(base().removeFields(<Object>['a', field('b.c')])),
          stage('remove_fields', <pb.Value>[fieldRef('a'), fieldRef('b.c')]));
      expect(() => base().removeFields(<Object>[]), throwsArgumentError);
    });

    test('sort', () {
      expect(
          last(base().sort(<Ordering>[
            field('rating').descending(),
            field('title').ascending(),
          ])),
          stage('sort', <pb.Value>[
            mapValue(<String, pb.Value>{
              'direction': str('descending'),
              'expression': fieldRef('rating'),
            }),
            mapValue(<String, pb.Value>{
              'direction': str('ascending'),
              'expression': fieldRef('title'),
            }),
          ]));
      expect(() => base().sort(<Ordering>[]), throwsArgumentError);
    });

    test('limit and offset', () {
      expect(last(base().limit(10)), stage('limit', <pb.Value>[integer(10)]));
      expect(last(base().offset(5)), stage('offset', <pb.Value>[integer(5)]));
      expect(() => base().limit(-1), throwsArgumentError);
      expect(() => base().offset(-1), throwsArgumentError);
    });

    test('aggregate without groups', () {
      expect(
          last(base().aggregate(<AliasedAggregate>[
            countAll().as('n'),
            field('rating').average().as('avg'),
          ])),
          stage('aggregate', <pb.Value>[
            mapValue(<String, pb.Value>{
              'n': fn('count'),
              'avg': fn('average', <pb.Value>[fieldRef('rating')]),
            }),
            mapValue(<String, pb.Value>{}),
          ]));
    });

    test('aggregate with groups', () {
      expect(
          last(base().aggregate(
            <AliasedAggregate>[field('rating').sum().as('total')],
            groups: <Object>['genre', field('year').mod(10).as('decade')],
          )),
          stage('aggregate', <pb.Value>[
            mapValue(<String, pb.Value>{
              'total': fn('sum', <pb.Value>[fieldRef('rating')]),
            }),
            mapValue(<String, pb.Value>{
              'genre': fieldRef('genre'),
              'decade': fn('mod', <pb.Value>[fieldRef('year'), integer(10)]),
            }),
          ]));
    });

    test('aggregate rejects duplicate aliases and empty accumulators', () {
      expect(
          () => base().aggregate(<AliasedAggregate>[
                countAll().as('n'),
                field('a').sum().as('n'),
              ]),
          throwsArgumentError);
      expect(() => base().aggregate(<AliasedAggregate>[]), throwsArgumentError);
    });

    test('distinct', () {
      expect(
          last(base().distinct(<Object>['genre'])),
          stage('distinct', <pb.Value>[
            mapValue(<String, pb.Value>{'genre': fieldRef('genre')})
          ]));
    });

    test('findNearest', () {
      final pb.Value vector = mapValue(<String, pb.Value>{
        '__type__': str('__vector__'),
        'value': arrayValue(<pb.Value>[dbl(1), dbl(2)]),
      });
      expect(
          last(base().findNearest(
              'embedding', <double>[1, 2], DistanceMeasure.euclidean)),
          stage('find_nearest',
              <pb.Value>[fieldRef('embedding'), vector, str('euclidean')]));
      expect(
          last(base().findNearest(field('embedding'),
              VectorValue(<double>[1, 2]), DistanceMeasure.dotProduct,
              limit: 3, distanceField: 'distance')),
          stage('find_nearest', <pb.Value>[
            fieldRef('embedding'),
            vector,
            str('dot_product')
          ], <String, pb.Value>{
            'limit': integer(3),
            'distance_field': fieldRef('distance'),
          }));
      expect(
          last(base().findNearest(
                  'embedding', field('other'), DistanceMeasure.cosine))
              .args,
          <pb.Value>[fieldRef('embedding'), fieldRef('other'), str('cosine')]);
      expect(() => base().findNearest('e', <int>[1], DistanceMeasure.cosine),
          throwsArgumentError);
      expect(
          () => base()
              .findNearest('e', <double>[1], DistanceMeasure.cosine, limit: 0),
          throwsArgumentError);
    });

    test('sample', () {
      expect(last(base().sample(documents: 10)),
          stage('sample', <pb.Value>[integer(10), str('documents')]));
      expect(last(base().sample(percentage: 0.5)),
          stage('sample', <pb.Value>[dbl(0.5), str('percent')]));
      expect(() => base().sample(), throwsArgumentError);
      expect(() => base().sample(documents: 1, percentage: 0.5),
          throwsArgumentError);
    });

    test('union', () {
      final Pipeline other = source().collection('other').limit(1);
      expect(
          last(base().union(other)),
          stage('union', <pb.Value>[
            pb.Value()
              ..pipelineValue = (pb.Pipeline()
                ..stages.addAll(<pb.Pipeline_Stage>[
                  stage('collection', <pb.Value>[ref('/other')]),
                  stage('limit', <pb.Value>[integer(1)]),
                ]))
          ]));
    });

    test('unnest', () {
      expect(last(base().unnest(field('tags').as('tag'))),
          stage('unnest', <pb.Value>[fieldRef('tags'), fieldRef('tag')]));
      expect(
          last(base().unnest(field('tags').as('tag'), indexField: 'i')),
          stage('unnest', <pb.Value>[fieldRef('tags'), fieldRef('tag')],
              <String, pb.Value>{'index_field': fieldRef('i')}));
    });

    test('replaceWith', () {
      expect(
          last(base().replaceWith('address')),
          stage('replace_with',
              <pb.Value>[fieldRef('address'), str('full_replace')]));
      expect(
          last(base().replaceWith(field('a').mapGet('b'))),
          stage('replace_with', <pb.Value>[
            fn('map_get', <pb.Value>[fieldRef('a'), str('b')]),
            str('full_replace')
          ]));
      expect(() => base().replaceWith(1), throwsArgumentError);
    });

    test('rawStage', () {
      expect(
          last(base().rawStage('custom_stage', <Object?>[
            field('a'),
            3,
            <String, Object?>{'x': field('b'), 'y': 1},
          ], options: <String, Object?>{
            'opt': true,
            'expr': field('c'),
          })),
          stage('custom_stage', <pb.Value>[
            fieldRef('a'),
            integer(3),
            mapValue(<String, pb.Value>{'x': fieldRef('b'), 'y': integer(1)}),
          ], <String, pb.Value>{
            'opt': boolean(true),
            'expr': fieldRef('c'),
          }));
    });

    test('stage raw options', () {
      expect(
          last(base().where(field('a').exists(),
              rawOptions: <String, Object?>{'hint': 'x'})),
          stage('where', <pb.Value>[
            fn('exists', <pb.Value>[fieldRef('a')])
          ], <String, pb.Value>{
            'hint': str('x')
          }));
    });
  });
}
