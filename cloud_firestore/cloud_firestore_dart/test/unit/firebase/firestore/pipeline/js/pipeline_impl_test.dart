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
// packages/firestore/test/unit/api/pipeline_impl.test.ts
//
// JS executes the pipeline against a fake datastore and inspects the
// request. Dart builds the same request with
// `Pipeline.toExecuteRequest(encoder, ...)`, which is what `execute()` sends.
// JS's option objects (`insert({collection, documentIdExpression})`, ...)
// and varargs are named parameters and lists in Dart; a JS stage `options`
// of `undefined` or `{}` is an empty map in the proto.
//
// Cases whose inputs and checks Android's DmlTests.kt has too are skipped
// with that reason (they run in ../dml_test.dart).

// ignore_for_file: invalid_use_of_internal_member, lines_longer_than_80_chars

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart'
    show CollectionReference, FieldValue;
import 'package:cloud_firestore_dart/pipelines.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/collection_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as pb;
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:test/test.dart';

import '../pipeline_test_util.dart';

String sameAsAndroid(String name) =>
    "The same case as Android's DmlTests.kt '$name', ported in dml_test.dart.";

proto.ExecutePipelineRequest request(
  Pipeline pipeline, {
  bool atomic = false,
}) => pipeline.toExecuteRequest(encoder(), atomic: atomic);

pb.Pipeline_Stage stageAt(Pipeline pipeline, int index) =>
    request(pipeline).structuredPipeline.pipeline.stages[index];

pb.Value mapOf(Map<String, pb.Value> fields) => mapValue(fields);

CollectionReference<Map<String, Object?>> collectionOf(
  Firestore firestore,
  String path,
) => CollectionReferenceInternal.create<Map<String, Object?>>(
  ResourcePath.fromString(path),
  firestore,
);

pb.Pipeline_Stage collectionFoo() =>
    stage('collection', <pb.Value>[ref('/foo')]);

/// The message of the [ArgumentError] [body] throws.
String argumentErrorMessage(void Function() body) {
  try {
    body();
  } on ArgumentError catch (e) {
    return '${e.message}';
  }
  fail('Expected an ArgumentError');
}

void main() {
  final Firestore firestore = fakeFirestore;

  group('execute(Pipeline|PipelineOptions)', () {
    test(
      'returns execution time with empty results',
      () {},
      skip:
          'Ported in ../pipeline_result_test.dart ("returns the execution time '
          'with empty results"), which decodes the response as execute() does.',
    );

    test('serializes the pipeline', () {
      final proto.ExecutePipelineRequest req = request(
        source().collection('foo'),
      );
      expect(req.database, 'projects/new-project/databases/(default)');
      expect(req.structuredPipeline.options, isEmpty);
      expect(req.structuredPipeline.pipeline.stages, <pb.Pipeline_Stage>[
        collectionFoo(),
      ]);
    });

    test('serializes the pipeline options', () {
      final proto.ExecutePipelineRequest req = source()
          .collection('foo')
          .toExecuteRequest(
            encoder(),
            indexMode: PipelineIndexMode.recommended,
          );
      expect(req.database, 'projects/new-project/databases/(default)');
      expect(req.structuredPipeline.options, <String, pb.Value>{
        'index_mode': str('recommended'),
      });
      expect(req.structuredPipeline.pipeline.stages, <pb.Pipeline_Stage>[
        collectionFoo(),
      ]);
    });

    test('serializes the pipeline raw options', () {
      final proto.ExecutePipelineRequest req = source()
          .collection('foo')
          .toExecuteRequest(
            encoder(),
            rawOptions: <String, Object?>{'foo': 'bar'},
          );
      expect(req.database, 'projects/new-project/databases/(default)');
      expect(req.structuredPipeline.options, <String, pb.Value>{
        'foo': str('bar'),
      });
      expect(req.structuredPipeline.pipeline.stages, <pb.Pipeline_Stage>[
        collectionFoo(),
      ]);
    });
  });

  group('stage serialization', () {
    group('search stage', () {
      test('serializes the pipeline', () {
        final proto.ExecutePipelineRequest req = request(
          source()
              .collection('foo')
              .search(
                'foo',
                sort: <Ordering>[field('foo').ascending()],
                addFields: <Selectable>[constant(true).as('bar')],
              ),
        );
        expect(req.structuredPipeline.options, isEmpty);
        expect(req.structuredPipeline.pipeline.stages, <pb.Pipeline_Stage>[
          collectionFoo(),
          stage('search', <pb.Value>[], <String, pb.Value>{
            'query': fn('document_matches', <pb.Value>[str('foo')]),
            'sort': arrayValue(<pb.Value>[
              mapOf(<String, pb.Value>{
                'direction': str('ascending'),
                'expression': fieldRef('foo'),
              }),
            ]),
            'add_fields': mapOf(<String, pb.Value>{'bar': boolean(true)}),
          }),
        ]);
      });

      test(
        'defaults to atomic=false when atomic option is omitted or false',
        () {},
        skip: sameAsAndroid(
          'non-atomic execution options do not configure newTransaction or '
          'autoCommitTransaction',
        ),
      );

      test(
        'serializes autoCommitTransaction on ProtoExecutePipelineRequest when atomic is true',
        () {},
        skip: sameAsAndroid(
          'atomic execution options configure newTransaction and '
          'autoCommitTransaction',
        ),
      );
    });

    group('insert and upsert stages', () {
      test(
        'serializes default insert stage',
        () {},
        skip: sameAsAndroid(
          'insert stage without arguments generates insert proto without '
          'options',
        ),
      );

      test(
        'serializes insert stage with collection path and document ID field',
        () {
          expect(
            stageAt(
              source()
                  .collection('foo')
                  .insert(collection: 'customers', documentId: 'idField'),
              1,
            ),
            stage('insert', <pb.Value>[], <String, pb.Value>{
              'collection': ref('/customers'),
              'document_id': fieldRef('idField'),
            }),
          );
        },
      );

      test(
        'serializes insert stage with CollectionReference and document ID expressions',
        () {
          final CollectionReference<Map<String, Object?>> targetColRef =
              collectionOf(firestore, 'customers/c1/orders');
          expect(
            stageAt(
              source()
                  .collection('foo')
                  .insert(
                    collection: targetColRef,
                    documentId: constant('fixedId'),
                  ),
              1,
            ),
            stage('insert', <pb.Value>[], <String, pb.Value>{
              'collection': ref('/customers/c1/orders'),
              'document_id': str('fixedId'),
            }),
          );

          // Verify with field expression.
          expect(
            stageAt(
              source().collection('foo').insert(documentId: field('otherId')),
              1,
            ).options['document_id'],
            fieldRef('otherId'),
          );
        },
      );

      test('serializes insert stage with rawOptions', () {
        expect(
          stageAt(
            source()
                .collection('foo')
                .insert(
                  collection: 'customers',
                  rawOptions: <String, Object?>{'custom_opt': 'val'},
                ),
            1,
          ),
          stage('insert', <pb.Value>[], <String, pb.Value>{
            'collection': ref('/customers'),
            'custom_opt': str('val'),
          }),
        );
      });

      test('serializes upsert stage with additionalFields and options', () {
        expect(
          stageAt(
            source()
                .collection('foo')
                .upsert(
                  additionalFields: <Selectable>[constant('Alice').as('name')],
                  collection: 'customers',
                  documentId: 'idField',
                ),
            1,
          ),
          stage(
            'upsert',
            <pb.Value>[
              mapOf(<String, pb.Value>{'name': str('Alice')}),
            ],
            <String, pb.Value>{
              'collection': ref('/customers'),
              'document_id': fieldRef('idField'),
            },
          ),
        );
      });

      test(
        'serializes upsert stage with multiple additional fields in options',
        () {},
        skip: sameAsAndroid(
          'in-place upsert with multiple varargs generates upsert proto '
          'without options',
        ),
      );

      test('serializes upsert stage with rawOptions', () {
        final pb.Pipeline_Stage upsertStage = stageAt(
          source()
              .collection('foo')
              .upsert(
                additionalFields: <Selectable>[constant(true).as('active')],
                rawOptions: <String, Object?>{'custom_opt': 'val'},
              ),
          1,
        );
        expect(upsertStage.name, 'upsert');
        expect(upsertStage.options, <String, pb.Value>{
          'custom_opt': str('val'),
        });
        expect(upsertStage.args[0].mapValue.fields, <String, pb.Value>{
          'active': boolean(true),
        });
      });

      test(
        'serializes default upsert stage without arguments',
        () {},
        skip: sameAsAndroid(
          'in-place upsert with 0 args generates upsert proto without options',
        ),
      );

      test('serializes upsert stage with options only', () {
        final pb.Pipeline_Stage upsertStage = stageAt(
          source()
              .collection('foo')
              .upsert(collection: 'users', documentId: field('id')),
          1,
        );
        expect(upsertStage.name, 'upsert');
        expect(upsertStage.options, <String, pb.Value>{
          'collection': ref('/users'),
          'document_id': fieldRef('id'),
        });
        expect(upsertStage.args, <pb.Value>[mapOf(<String, pb.Value>{})]);
      });

      test(
        'serializes upsert stage with single variadic expression',
        () {},
        skip: sameAsAndroid(
          'in-place upsert with varargs generates upsert proto without options',
        ),
      );

      test(
        'serializes upsert stage with multiple variadic expressions',
        () {},
        skip: sameAsAndroid(
          'in-place upsert with multiple varargs generates upsert proto '
          'without options',
        ),
      );

      test('throws on empty collection path in insert and upsert stages', () {
        // JS: "Function insert() cannot be called with an empty collection
        // path." The Dart message says the same in its own words.
        expect(
          argumentErrorMessage(
            () => source().collection('foo').insert(collection: ''),
          ),
          'insert() needs a non-empty path.',
        );
        expect(
          argumentErrorMessage(
            () => source().collection('foo').upsert(collection: ''),
          ),
          'upsert() needs a non-empty path.',
        );
      });

      test(
        'throws on CollectionReference from a different database in insert and upsert stages',
        () {
          final Firestore otherFirestore = FakeFirestore(
            DatabaseId.forDatabase('project2', '(default)'),
          );
          final CollectionReference<Map<String, Object?>> otherCollection =
              collectionOf(otherFirestore, 'bar');
          expect(
            argumentErrorMessage(
              () => source()
                  .collection('foo')
                  .insert(collection: otherCollection),
            ),
            contains('Invalid CollectionReference'),
          );
          expect(
            argumentErrorMessage(
              () => source()
                  .collection('foo')
                  .upsert(collection: otherCollection),
            ),
            contains('Invalid CollectionReference'),
          );

          // A CollectionReference from the same database is accepted.
          final CollectionReference<Map<String, Object?>> sameCollection =
              collectionOf(firestore, 'bar');
          expect(() {
            source().collection('foo').insert(collection: sameCollection);
            source().collection('foo').upsert(collection: sameCollection);
          }, returnsNormally);
        },
      );
    });

    group('delete stage', () {
      test(
        'serializes default delete stage',
        () {},
        skip: sameAsAndroid('delete stage generates delete proto'),
      );

      test('serializes delete stage with rawOptions', () {
        expect(
          stageAt(
            source()
                .collection('foo')
                .delete(rawOptions: <String, Object?>{'custom_opt': 'val'}),
            1,
          ),
          stage('delete', <pb.Value>[], <String, pb.Value>{
            'custom_opt': str('val'),
          }),
        );
      });
    });

    group('update stage', () {
      test(
        'serializes default update stage without transforms',
        () {},
        skip: sameAsAndroid(
          'update stage with 0 args generates update proto with empty map',
        ),
      );

      test(
        'serializes update stage with vararg transform expression',
        () {},
        skip: sameAsAndroid('update stage generates update proto with fields'),
      );

      test(
        'serializes update stage with multiple vararg transform expressions',
        () {},
        skip: sameAsAndroid(
          'update stage with multiple varargs generates update proto with all '
          'fields',
        ),
      );

      test('serializes update stage with UpdateStageOptions', () {
        final pb.Pipeline_Stage updateStage = stageAt(
          source()
              .collection('foo')
              .update(
                transformedFields: <Selectable>[
                  constant(true).as('is_top_scorer'),
                ],
                rawOptions: <String, Object?>{'custom_opt': 'val'},
              ),
          1,
        );
        expect(updateStage.name, 'update');
        expect(updateStage.options, <String, pb.Value>{
          'custom_opt': str('val'),
        });
        expect(updateStage.args[0].mapValue.fields, <String, pb.Value>{
          'is_top_scorer': boolean(true),
        });
      });
    });

    group('literals stage', () {
      test(
        'serializes literals stage with array overload',
        () {},
        skip: sameAsAndroid(
          'literals stage with multiple maps generates literals proto with '
          'documents',
        ),
      );

      test(
        'serializes literals stage when a document has a documents array field',
        () {
          expect(
            stageAt(
              source().literals(<Map<String, Object?>>[
                <String, Object?>{
                  'documents': <Object?>['a', 'b'],
                  'title': 'Folder',
                },
              ]),
              0,
            ),
            stage('literals', <pb.Value>[
              mapOf(<String, pb.Value>{
                'documents': fn('array', <pb.Value>[str('a'), str('b')]),
                'title': str('Folder'),
              }),
            ]),
          );
        },
      );

      test(
        'serializes literals stage with options overload and rawOptions',
        () {
          expect(
            stageAt(
              source().literals(
                <Map<String, Object?>>[
                  <String, Object?>{'item': 'apple', 'count': 10},
                ],
                rawOptions: <String, Object?>{'custom_opt': 'val'},
              ),
              0,
            ),
            stage(
              'literals',
              <pb.Value>[
                mapOf(<String, pb.Value>{
                  'item': str('apple'),
                  'count': integer(10),
                }),
              ],
              <String, pb.Value>{'custom_opt': str('val')},
            ),
          );
        },
      );

      test(
        'serializes literals stage with expressions in top-level, nested maps, and arrays',
        () {
          final pb.Pipeline_Stage literalsStage = stageAt(
            source().literals(<Map<String, Object?>>[
              <String, Object?>{
                'base': 10,
                'calc': constant(10).multiply(constant(2)),
                'nested': <String, Object?>{
                  'val': constant('hello'),
                  'sum': constant(1).add(constant(2)),
                },
                'arr': <Object?>[1, constant(3).add(constant(4))],
              },
            ]),
            0,
          );
          expect(literalsStage.name, 'literals');
          expect(literalsStage.args, <pb.Value>[
            mapOf(<String, pb.Value>{
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
          ]);
        },
      );

      test(
        'omits undefined literal fields when ignoreUndefinedProperties is set',
        () {},
        skip: 'Dart has no undefined and no ignoreUndefinedProperties setting.',
      );

      group('rejects FieldValue sentinels in literals()', () {
        // JS: "Function literals() called with invalid data. X() can only be
        // used with update() and set() (found in field F)". Dart words it as
        // set() does: "Invalid data. FieldValue.X() can only be used with
        // set() and update() (found in field F)".
        void rejects(Map<String, Object?> doc, String sentinel, String? path) {
          expect(
            argumentErrorMessage(
              () => source().literals(<Map<String, Object?>>[doc]),
            ),
            'Invalid data. $sentinel() can only be used with set() and '
            'update()${path == null ? '' : ' (found in field $path)'}',
          );
        }

        test(
          'top-level serverTimestamp()',
          () {},
          skip: sameAsAndroid(
            'literals rejects top-level FieldValue sentinel with field path',
          ),
        );

        test('increment()', () {
          rejects(
            <String, Object?>{'n': FieldValue.increment(1)},
            'FieldValue.increment',
            'n',
          );
        });

        test('arrayUnion()', () {
          rejects(
            <String, Object?>{
              'arr': FieldValue.arrayUnion(<Object?>['x']),
            },
            'FieldValue.arrayUnion',
            'arr',
          );
        });

        test('deleteField()', () {
          rejects(
            <String, Object?>{'gone': FieldValue.delete()},
            'FieldValue.delete',
            'gone',
          );
        });

        test('nested in a map', () {
          rejects(
            <String, Object?>{
              'a': <String, Object?>{'b': FieldValue.serverTimestamp()},
            },
            'FieldValue.serverTimestamp',
            'a.b',
          );
        });

        test('inside an array', () {
          // JS names the array field ("found in field arr"); Dart, as
          // Android (UserData.ParseContext), has no path inside arrays.
          rejects(
            <String, Object?>{
              'arr': <Object?>[1, FieldValue.serverTimestamp()],
            },
            'FieldValue.serverTimestamp',
            null,
          );
        });
      });

      group('rejects undefined in literals() by default', () {
        const String noUndefined = 'Dart has no undefined value.';
        test('top-level undefined', () {}, skip: noUndefined);
        test('nested undefined', () {}, skip: noUndefined);
        test('undefined inside an array', () {}, skip: noUndefined);
      });

      test(
        'rejects non-array or invalid options object in literals()',
        () {},
        skip:
            'literals() takes a List<Map<String, Object?>> in Dart; a map '
            'instead does not compile.',
      );
    });
  });
}
