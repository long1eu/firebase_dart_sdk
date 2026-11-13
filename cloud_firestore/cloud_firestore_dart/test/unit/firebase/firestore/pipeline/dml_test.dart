// Copyright 2025 Google LLC
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

// Ported from the Android SDK:
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/DmlTests.kt
//
// The cases keep their Kotlin names. Kotlin's positional arguments of
// `insert`/`upsert` (collection, document id expression) and the varargs of
// `update`/`upsert`/`literals` are named parameters and lists in Dart.
// `toExecutePipelineRequest(options)` is `toExecuteRequest(encoder,
// atomic: ...)`. Android rejects invalid literal documents when it encodes
// the request; Dart (as JS) when `literals` is called, so the rejection cases
// build the pipeline inside the closure.

// ignore_for_file: prefer_single_quotes, lines_longer_than_80_chars
// ignore_for_file: invalid_use_of_internal_member

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
import 'package:fixnum/fixnum.dart';
import 'package:test/test.dart';

import 'pipeline_test_util.dart';

final Firestore db = fakeFirestore;
final Firestore otherDb = FakeFirestore(
  DatabaseId.forDatabase('otherProject', 'otherDb'),
);

CollectionReference<Map<String, Object?>> collectionOf(
  Firestore firestore,
  String path,
) => CollectionReferenceInternal.create<Map<String, Object?>>(
  ResourcePath.fromString(path),
  firestore,
);

proto.Pipeline protoOf(Pipeline pipeline) =>
    pipeline.toExecuteRequest(encoder()).structuredPipeline.pipeline;

/// The message of the [ArgumentError] [body] throws.
String argumentErrorMessage(void Function() body) {
  try {
    body();
  } on ArgumentError catch (e) {
    return '${e.message}';
  }
  fail('Expected an ArgumentError');
}

/// Why three literals cases do not apply.
const String jsLiteralsEncoding =
    'Dart follows the JS SDK (encodeLiteralValue in '
    'packages/firestore/src/lite-api/stage.ts): nested maps and lists of a '
    'literal document are always sent as map()/array() expressions. Android '
    'sends those without an expression as plain values and rejects nested '
    'arrays.';

void main() {
  test('delete stage generates delete proto', () {
    final Pipeline pipeline = source().collection('books').delete();
    final proto.Pipeline p = protoOf(pipeline);
    expect(p.stages, hasLength(2));

    final pb.Pipeline_Stage stage = p.stages[1];
    expect(stage.name, 'delete');
    expect(stage.args, isEmpty);
  });

  test('update stage generates update proto with fields', () {
    final Pipeline pipeline = source()
        .collection('books')
        .update(
          transformedFields: <Selectable>[constant('Updated').as('status')],
        );
    final proto.Pipeline p = protoOf(pipeline);
    expect(p.stages, hasLength(2));

    final pb.Pipeline_Stage stage = p.stages[1];
    expect(stage.name, 'update');
    expect(stage.args, hasLength(1));
    expect(stage.args[0].mapValue.fields['status']?.stringValue, 'Updated');
  });

  test('update stage with 0 args generates update proto with empty map', () {
    final Pipeline pipeline = source().collection('books').update();
    final proto.Pipeline p = protoOf(pipeline);
    expect(p.stages, hasLength(2));

    final pb.Pipeline_Stage stage = p.stages[1];
    expect(stage.name, 'update');
    expect(stage.args, hasLength(1));
    expect(stage.args[0].mapValue.fields, isEmpty);
  });

  test(
    'update stage with multiple varargs generates update proto with all fields',
    () {
      final Pipeline pipeline = source()
          .collection('books')
          .update(
            transformedFields: <Selectable>[
              constant('Updated').as('status'),
              field('count').add(constant(1)).as('count'),
            ],
          );
      final proto.Pipeline p = protoOf(pipeline);
      expect(p.stages, hasLength(2));

      final pb.Pipeline_Stage stage = p.stages[1];
      expect(stage.name, 'update');
      expect(stage.args, hasLength(1));
      final Map<String, pb.Value> fields = stage.args[0].mapValue.fields;
      expect(fields['status']?.stringValue, 'Updated');
      expect(fields.containsKey('count'), isTrue);
    },
  );

  test('insert stage generates insert proto with options', () {
    final Pipeline pipeline = source()
        .literals(<Map<String, Object?>>[
          <String, Object?>{'title': 'New Book'},
        ])
        .insert(collection: 'books', documentId: constant('book1'));
    final proto.Pipeline p = protoOf(pipeline);
    expect(p.stages, hasLength(2));

    final pb.Pipeline_Stage stage = p.stages[1];
    expect(stage.name, 'insert');
    expect(stage.options['collection']?.referenceValue, '/books');
    expect(stage.options['document_id']?.stringValue, 'book1');
  });

  test(
    'insert stage without documentIdExpression generates insert proto with only collection option',
    () {
      final Pipeline pipeline = source()
          .literals(<Map<String, Object?>>[
            <String, Object?>{'title': 'New Book'},
          ])
          .insert(collection: 'books');
      final proto.Pipeline p = protoOf(pipeline);
      expect(p.stages, hasLength(2));

      final pb.Pipeline_Stage stage = p.stages[1];
      expect(stage.name, 'insert');
      expect(stage.options['collection']?.referenceValue, '/books');
      expect(stage.options.containsKey('document_id'), isFalse);
    },
  );

  test(
    'insert stage without arguments generates insert proto without options',
    () {
      final Pipeline pipeline = source().collection('books').insert();
      final pb.Pipeline_Stage stage = protoOf(pipeline).stages[1];
      expect(stage.name, 'insert');
      expect(stage.args, isEmpty);
      expect(stage.options, isEmpty);
    },
  );

  test(
    'insert stage with only documentIdExpression generates insert proto without collection',
    () {
      final Pipeline pipeline = source()
          .collection('books')
          .insert(documentId: constant('book1_copy'));
      final pb.Pipeline_Stage stage = protoOf(pipeline).stages[1];
      expect(stage.name, 'insert');
      expect(stage.options.containsKey('collection'), isFalse);
      expect(stage.options['document_id']?.stringValue, 'book1_copy');
    },
  );

  test(
    'insert stage with CollectionReference generates insert proto with collection option',
    () {
      final Pipeline pipeline = source()
          .literals(<Map<String, Object?>>[
            <String, Object?>{'title': 'New Book'},
          ])
          .insert(collection: collectionOf(db, 'books'));
      final pb.Pipeline_Stage stage = protoOf(pipeline).stages[1];
      expect(stage.name, 'insert');
      expect(stage.options['collection']?.referenceValue, '/books');
      expect(stage.options.containsKey('document_id'), isFalse);
    },
  );

  test(
    'insert stage with CollectionReference and documentIdExpression generates insert proto',
    () {
      final Pipeline pipeline = source()
          .literals(<Map<String, Object?>>[
            <String, Object?>{'title': 'New Book'},
          ])
          .insert(
            collection: collectionOf(db, 'books'),
            documentId: constant('book1'),
          );
      final pb.Pipeline_Stage stage = protoOf(pipeline).stages[1];
      expect(stage.name, 'insert');
      expect(stage.options['collection']?.referenceValue, '/books');
      expect(stage.options['document_id']?.stringValue, 'book1');
    },
  );

  test(
    'insert stage rejects a CollectionReference from another Firestore instance',
    () {
      final String message = argumentErrorMessage(
        () => source()
            .collection('books')
            .insert(collection: collectionOf(otherDb, 'books')),
      );
      // Android: "Invalid CollectionReference. The Firestore instance of the
      // CollectionReference must match the Firestore instance of the
      // Pipeline." The Dart message names the databases.
      expect(message, startsWith('Invalid CollectionReference'));
    },
  );

  test(
    'target-collection upsert with CollectionReference and documentIdExpression generates upsert proto',
    () {
      final Pipeline pipeline = source()
          .literals(<Map<String, Object?>>[
            <String, Object?>{'title': 'Upserted Book'},
          ])
          .upsert(
            collection: collectionOf(db, 'books'),
            documentId: constant('book1'),
          );
      final proto.Pipeline p = protoOf(pipeline);
      expect(p.stages, hasLength(2));

      final pb.Pipeline_Stage stage = p.stages[1];
      expect(stage.name, 'upsert');
      expect(stage.args, hasLength(1));
      expect(stage.args[0].mapValue.fields, isEmpty);
      expect(stage.options['collection']?.referenceValue, '/books');
      expect(stage.options['document_id']?.stringValue, 'book1');
    },
  );

  test(
    'in-place upsert with varargs generates upsert proto without options',
    () {
      final Pipeline pipeline = source()
          .collection('books')
          .upsert(
            additionalFields: <Selectable>[
              field('count').add(constant(1)).as('count'),
            ],
          );
      final proto.Pipeline p = protoOf(pipeline);
      expect(p.stages, hasLength(2));

      final pb.Pipeline_Stage stage = p.stages[1];
      expect(stage.name, 'upsert');
      expect(stage.args, hasLength(1));
      expect(stage.options, isEmpty);
    },
  );

  test(
    'target-collection upsert with collectionPath only generates upsert proto',
    () {
      final Pipeline pipeline = source()
          .collection('books')
          .upsert(collection: 'books_backup');
      final proto.Pipeline p = protoOf(pipeline);
      expect(p.stages, hasLength(2));

      final pb.Pipeline_Stage stage = p.stages[1];
      expect(stage.name, 'upsert');
      expect(stage.args, hasLength(1));
      expect(stage.args[0].mapValue.fields, isEmpty);
      expect(stage.options['collection']?.referenceValue, '/books_backup');
      expect(stage.options.containsKey('document_id'), isFalse);
    },
  );

  test(
    'target-collection upsert with collectionPath and documentIdExpression generates upsert proto',
    () {
      final Pipeline pipeline = source()
          .literals(<Map<String, Object?>>[
            <String, Object?>{'title': 'Upserted Book'},
          ])
          .upsert(collection: 'books', documentId: constant('book1'));
      final proto.Pipeline p = protoOf(pipeline);
      expect(p.stages, hasLength(2));

      final pb.Pipeline_Stage stage = p.stages[1];
      expect(stage.name, 'upsert');
      expect(stage.args, hasLength(1));
      expect(stage.args[0].mapValue.fields, isEmpty);
      expect(stage.options['collection']?.referenceValue, '/books');
      expect(stage.options['document_id']?.stringValue, 'book1');
    },
  );

  test(
    'target-collection upsert with CollectionReference only generates upsert proto',
    () {
      final Pipeline pipeline = source()
          .collection('books')
          .upsert(collection: collectionOf(db, 'books_backup'));
      final pb.Pipeline_Stage stage = protoOf(pipeline).stages[1];
      expect(stage.name, 'upsert');
      expect(stage.options['collection']?.referenceValue, '/books_backup');
      expect(stage.options.containsKey('document_id'), isFalse);
    },
  );

  test(
    'target-collection upsert rejects a CollectionReference from another Firestore instance',
    () {
      final String message = argumentErrorMessage(
        () => source()
            .collection('books')
            .upsert(
              collection: collectionOf(otherDb, 'books'),
              documentId: constant('book1'),
            ),
      );
      // Android's message: see the insert case above.
      expect(message, startsWith('Invalid CollectionReference'));
    },
  );

  test(
    'in-place upsert with 0 args generates upsert proto without options',
    () {
      final Pipeline pipeline = source().collection('books').upsert();
      final proto.Pipeline p = protoOf(pipeline);
      expect(p.stages, hasLength(2));

      final pb.Pipeline_Stage stage = p.stages[1];
      expect(stage.name, 'upsert');
      expect(stage.args, hasLength(1));
      expect(stage.args[0].mapValue.fields, isEmpty);
      expect(stage.options, isEmpty);
    },
  );

  test(
    'in-place upsert with multiple varargs generates upsert proto without options',
    () {
      final Pipeline pipeline = source()
          .collection('books')
          .upsert(
            additionalFields: <Selectable>[
              constant('In-Place').as('status'),
              field('count').add(constant(1)).as('count'),
            ],
          );
      final proto.Pipeline p = protoOf(pipeline);
      expect(p.stages, hasLength(2));

      final pb.Pipeline_Stage stage = p.stages[1];
      expect(stage.name, 'upsert');
      expect(stage.args, hasLength(1));
      final Map<String, pb.Value> fields = stage.args[0].mapValue.fields;
      expect(fields['status']?.stringValue, 'In-Place');
      expect(fields.containsKey('count'), isTrue);
      expect(stage.options, isEmpty);
    },
  );

  test(
    'literals stage with multiple maps generates literals proto with documents',
    () {
      final Pipeline pipeline = source().literals(<Map<String, Object?>>[
        <String, Object?>{'title': 'Book 1'},
        <String, Object?>{'title': 'Book 2'},
      ]);
      final proto.Pipeline p = protoOf(pipeline);
      expect(p.stages, hasLength(1));

      final pb.Pipeline_Stage stage = p.stages[0];
      expect(stage.name, 'literals');
      expect(stage.args, hasLength(2));
      expect(stage.args[0].mapValue.fields['title']?.stringValue, 'Book 1');
      expect(stage.args[1].mapValue.fields['title']?.stringValue, 'Book 2');
    },
  );

  test(
    'literals stage with expressions and nested maps generates literals proto',
    () {
      final Pipeline pipeline = source().literals(<Map<String, Object?>>[
        <String, Object?>{
          'title': 'Book 1',
          'nested': <String, Object?>{'key': 'value'},
          'computed': constant(1).add(constant(2)),
        },
      ]);
      final proto.Pipeline p = protoOf(pipeline);
      expect(p.stages, hasLength(1));

      final pb.Pipeline_Stage stage = p.stages[0];
      expect(stage.name, 'literals');
      expect(stage.args, hasLength(1));
      final Map<String, pb.Value> fields = stage.args[0].mapValue.fields;
      expect(fields['title']?.stringValue, 'Book 1');
      expect(fields['nested']?.mapValue.fields['key']?.stringValue, 'value');
      expect(fields['computed']?.functionValue.name, 'add');
    },
    skip: jsLiteralsEncoding,
  );

  test(
    'literals stage wraps nested map containing expressions in a map expression',
    () {
      final Pipeline pipeline = source().literals(<Map<String, Object?>>[
        <String, Object?>{
          'nested': <String, Object?>{
            'sum': constant(1).add(constant(2)),
            'label': 'x',
          },
        },
      ]);
      final Map<String, pb.Value> fields = protoOf(
        pipeline,
      ).stages[0].args[0].mapValue.fields;

      final pb.Value nested = fields['nested']!;
      expect(nested.hasFunctionValue(), isTrue);
      expect(nested.functionValue.name, 'map');
      // map(key1, value1, key2, value2): keys are constants, values keep
      // their expressions.
      final List<pb.Value> args = nested.functionValue.args;
      expect(args, hasLength(4));
      final Map<String, pb.Value> entries = <String, pb.Value>{
        for (int i = 0; i < args.length; i += 2)
          args[i].stringValue: args[i + 1],
      };
      expect(entries['sum']?.functionValue.name, 'add');
      expect(entries['label']?.stringValue, 'x');
    },
  );

  test(
    'literals stage wraps list containing expressions in an array expression',
    () {
      final Pipeline pipeline = source().literals(<Map<String, Object?>>[
        <String, Object?>{
          'list': <Object?>[constant(1).add(constant(2)), 1, null],
        },
      ]);
      final pb.Value list = protoOf(
        pipeline,
      ).stages[0].args[0].mapValue.fields['list']!;

      expect(list.hasFunctionValue(), isTrue);
      expect(list.functionValue.name, 'array');
      final List<pb.Value> args = list.functionValue.args;
      expect(args, hasLength(3));
      expect(args[0].functionValue.name, 'add');
      expect(args[1].integerValue, Int64(1));
      expect(args[2].hasNullValue(), isTrue);
    },
  );

  test(
    'literals stage wraps deeply nested expressions at the top-level field',
    () {
      final Pipeline pipeline = source().literals(<Map<String, Object?>>[
        <String, Object?>{
          'outer': <String, Object?>{
            'inner': <Object?>[
              <String, Object?>{'v': constant(1)},
            ],
          },
        },
      ]);
      final pb.Value outer = protoOf(
        pipeline,
      ).stages[0].args[0].mapValue.fields['outer']!;

      expect(outer.functionValue.name, 'map');
      final pb.Value inner = outer.functionValue.args[1];
      expect(inner.functionValue.name, 'array');
      final pb.Value element = inner.functionValue.args[0];
      expect(element.functionValue.name, 'map');
      expect(element.functionValue.args[1].integerValue, Int64(1));
    },
  );

  test(
    'literals stage encodes nested values without expressions as plain values',
    () {
      final Pipeline pipeline = source().literals(<Map<String, Object?>>[
        <String, Object?>{
          'nested': <String, Object?>{'key': 'value', 'n': null},
          'list': <Object?>[1, 'a'],
        },
      ]);
      final Map<String, pb.Value> fields = protoOf(
        pipeline,
      ).stages[0].args[0].mapValue.fields;

      expect(fields['nested']!.hasMapValue(), isTrue);
      expect(fields['nested']!.mapValue.fields['key']?.stringValue, 'value');
      expect(fields['nested']!.mapValue.fields['n']?.hasNullValue(), isTrue);
      expect(fields['list']!.hasArrayValue(), isTrue);
      expect(
        fields['list']!.arrayValue.values.map(
          (pb.Value v) => v.whichValueType(),
        ),
        orderedEquals(<pb.Value_ValueType>[
          pb.Value_ValueType.integerValue,
          pb.Value_ValueType.stringValue,
        ]),
      );
    },
    skip: jsLiteralsEncoding,
  );

  test('literals without documents produces a stage with no arguments', () {
    final pb.Pipeline_Stage stage = protoOf(
      source().literals(<Map<String, Object?>>[]),
    ).stages[0];
    expect(stage.name, 'literals');
    expect(stage.args, isEmpty);
  });

  test('literals rejects empty field names at any depth', () {
    for (final Map<String, Object?> document in <Map<String, Object?>>[
      <String, Object?>{'': 1},
      <String, Object?>{
        'm': <String, Object?>{'': 2},
      },
      <String, Object?>{
        'l': <Object?>[
          <String, Object?>{'': 3},
        ],
      },
      <String, Object?>{
        'm': <String, Object?>{'sum': constant(1).add(constant(2)), '': 4},
      },
    ]) {
      final String message = argumentErrorMessage(
        () => protoOf(source().literals(<Map<String, Object?>>[document])),
      );
      expect(
        message,
        startsWith('Invalid data. Document fields must not be empty'),
      );
    }
  });

  test('literals rejects nested arrays without expressions', () {
    Pipeline pipeline() => source().literals(<Map<String, Object?>>[
      <String, Object?>{
        'l': <Object?>[
          <Object?>[1],
        ],
      },
    ]);
    expect(
      argumentErrorMessage(() => protoOf(pipeline())),
      'Invalid data. Nested arrays are not supported',
    );
  }, skip: jsLiteralsEncoding);

  test('literals rejects FieldValue sentinel in a list', () {
    Pipeline pipeline() => source().literals(<Map<String, Object?>>[
      <String, Object?>{
        'l': <Object?>[
          <String, Object?>{'ts': FieldValue.delete()},
        ],
      },
    ]);
    expect(
      argumentErrorMessage(() => protoOf(pipeline())),
      'Invalid data. FieldValue.delete() can only be used with set() and update()',
    );
  });

  test('literals rejects top-level FieldValue sentinel with field path', () {
    Pipeline pipeline() => source().literals(<Map<String, Object?>>[
      <String, Object?>{'a': 1, 'ts': FieldValue.serverTimestamp()},
    ]);
    expect(
      argumentErrorMessage(() => protoOf(pipeline())),
      'Invalid data. '
      'FieldValue.serverTimestamp() can only be used with set() and update() (found in field ts)',
    );
  });

  test('literals rejects nested FieldValue sentinel with full field path', () {
    Pipeline pipeline() => source().literals(<Map<String, Object?>>[
      <String, Object?>{
        'a': <String, Object?>{'b': FieldValue.increment(1)},
      },
    ]);
    expect(
      argumentErrorMessage(() => protoOf(pipeline())),
      'Invalid data. '
      'FieldValue.increment() can only be used with set() and update() (found in field a.b)',
    );
  });

  test(
    'literals rejects FieldValue sentinel next to a nested expression with field path',
    () {
      Pipeline pipeline() => source().literals(<Map<String, Object?>>[
        <String, Object?>{
          'a': <String, Object?>{
            'sum': constant(1).add(constant(2)),
            'd': FieldValue.delete(),
          },
        },
      ]);
      expect(
        argumentErrorMessage(() => protoOf(pipeline())),
        'Invalid data. '
        'FieldValue.delete() can only be used with set() and update() (found in field a.d)',
      );
    },
  );

  test(
    'atomic execution options configure newTransaction and autoCommitTransaction',
    () {
      final Pipeline pipeline = source()
          .literals(<Map<String, Object?>>[
            <String, Object?>{'title': 'Atomic'},
          ])
          .insert(collection: 'books', documentId: constant('book1'));
      final proto.ExecutePipelineRequest request = pipeline.toExecuteRequest(
        encoder(),
        atomic: true,
      );
      expect(request.hasNewTransaction(), isTrue);
      expect(request.newTransaction.hasReadWrite(), isTrue);
      expect(
        request.newTransaction.readWrite.concurrencyMode,
        proto.TransactionOptions_ConcurrencyMode.OPTIMISTIC,
      );
      expect(request.autoCommitTransaction, isTrue);
      expect(request.structuredPipeline.options.containsKey('atomic'), isFalse);
    },
  );

  test(
    'non-atomic execution options do not configure newTransaction or autoCommitTransaction',
    () {
      final Pipeline pipeline = source()
          .literals(<Map<String, Object?>>[
            <String, Object?>{'title': 'Non-Atomic'},
          ])
          .insert(collection: 'books', documentId: constant('book1'));

      final proto.ExecutePipelineRequest requestDisabled = pipeline
          .toExecuteRequest(encoder(), atomic: false);
      expect(requestDisabled.hasNewTransaction(), isFalse);
      expect(requestDisabled.autoCommitTransaction, isFalse);
      expect(
        requestDisabled.structuredPipeline.options.containsKey('atomic'),
        isFalse,
      );

      // Android's default ExecuteOptions and null options are both the
      // default of `atomic` here.
      final proto.ExecutePipelineRequest requestDefault = pipeline
          .toExecuteRequest(encoder());
      expect(requestDefault.hasNewTransaction(), isFalse);
      expect(requestDefault.autoCommitTransaction, isFalse);
    },
  );
}
