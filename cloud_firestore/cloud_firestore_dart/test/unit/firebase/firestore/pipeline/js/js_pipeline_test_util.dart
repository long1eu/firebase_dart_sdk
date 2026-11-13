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

// What the tests ported from the JS SDK's test/unit/core/pipeline/*.test.ts
// call: `db.pipeline()` (the Dart PipelineSource), `runPipeline` (as JS's
// test/util/pipelines.ts: the pipeline rewritten as core/pipeline-util.ts
// `rewriteStages` does, then run locally), `constantArray`/`constantMap`, and
// the subset of Jest's `expect` they use. The expression functions under the
// JS names, and `doc`, come from evaluation_test_util.dart.
//
// The local executor follows the Enterprise edition backend where JS's
// local evaluation differs: an expression of a stage that evaluates to an
// error fails the whole pipeline (JS drops the document from `where`).
// Tests that hit it say so.

// ignore_for_file: non_constant_identifier_names

import 'package:cloud_firestore_dart/pipelines.dart'
    show BooleanExpression, Constant, Expression, FunctionExpression, Pipeline;
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/expression_evaluator.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/pipeline_executor.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/expression.dart'
    show PipelineEncoder;
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/pipeline_source.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as pb;
import 'package:test/test.dart' as t;

import '../evaluation/evaluation_test_util.dart' hide and, or, xor;
import '../pipeline_test_util.dart' as util;

export 'package:cloud_firestore_dart/cloud_firestore_dart.dart'
    show FieldPath, GeoPoint, Timestamp;
export 'package:cloud_firestore_dart/pipelines.dart'
    show BooleanExpression, Expression, Field, Ordering, Pipeline;
export 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/pipeline_executor.dart'
    show PipelineFailure;

export '../evaluation/evaluation_test_util.dart'
    hide Subject, and, assertThat, or, xor;

final DatabaseId _databaseId = DatabaseId.forProject('project');
final PipelineEncoder _encoder = PipelineEncoder(_databaseId);
final PipelineExecutor _executor = PipelineExecutor(_databaseId);

/// JS's `newTestFirestore()`: only `pipeline()` is used.
class TestFirestore {
  PipelineSource pipeline() => util.source();
}

final TestFirestore db = TestFirestore();

const Object _none = Object();

BooleanExpression _variadic(String name, List<Object?> args) =>
    BooleanExpression(
      FunctionExpression(name, <Object?>[
        for (final Object? arg in args)
          if (!identical(arg, _none)) arg,
      ]),
    );

/// JS's `and(...conditions)`.
BooleanExpression and(
  Object? a,
  Object? b, [
  Object? c = _none,
  Object? d = _none,
  Object? e = _none,
  Object? f = _none,
  Object? g = _none,
  Object? h = _none,
  Object? i = _none,
  Object? j = _none,
  Object? k = _none,
  Object? l = _none,
]) => _variadic('and', <Object?>[a, b, c, d, e, f, g, h, i, j, k, l]);

/// JS's `or(...conditions)`.
BooleanExpression or(
  Object? a,
  Object? b, [
  Object? c = _none,
  Object? d = _none,
  Object? e = _none,
  Object? f = _none,
  Object? g = _none,
  Object? h = _none,
  Object? i = _none,
  Object? j = _none,
  Object? k = _none,
  Object? l = _none,
]) => _variadic('or', <Object?>[a, b, c, d, e, f, g, h, i, j, k, l]);

/// JS's `xor(...conditions)`.
BooleanExpression xor(
  Object? a,
  Object? b, [
  Object? c = _none,
  Object? d = _none,
  Object? e = _none,
  Object? f = _none,
  Object? g = _none,
  Object? h = _none,
  Object? i = _none,
  Object? j = _none,
  Object? k = _none,
  Object? l = _none,
]) => _variadic('xor', <Object?>[a, b, c, d, e, f, g, h, i, j, k, l]);

/// JS's `constantArray(...values)`: one constant holding the array.
Expression constantArray(List<Object?> values) => Constant(values);

/// JS's `constantMap(values)`: one constant holding the map.
Expression constantMap(Map<String, Object?> values) => Constant(values);

final pb.Value _byKey = pb.Value()
  ..mapValue = (pb.MapValue()
    ..fields['direction'] = (pb.Value()..stringValue = 'ascending')
    ..fields['expression'] = (pb.Value()..fieldReferenceValue = '__name__'));

pb.Pipeline_Stage _sortByKey() => pb.Pipeline_Stage()
  ..name = 'sort'
  ..args.add(_byKey);

bool _isKeyOrdering(pb.Value ordering) =>
    ordering.mapValue.fields['expression']?.fieldReferenceValue == '__name__';

/// The stages of [pipeline] as JS's `rewriteStages` (and Android's
/// `RealtimePipeline.rewrittenStages`) has them: `__name__` appended to every
/// sort that lacks it, a sort by `__name__` before the first limit when
/// nothing sorted yet, and a sort by `__name__` at the end when nothing
/// sorted at all.
pb.Pipeline rewriteStages(pb.Pipeline pipeline) {
  final pb.Pipeline result = pb.Pipeline();
  bool hasOrder = false;
  for (final pb.Pipeline_Stage stage in pipeline.stages) {
    if (stage.name == 'sort') {
      hasOrder = true;
      if (stage.args.any(_isKeyOrdering)) {
        result.stages.add(stage);
      } else {
        result.stages.add(stage.deepCopy()..args.add(_byKey));
      }
    } else if (stage.name == 'limit') {
      if (!hasOrder) {
        result.stages.add(_sortByKey());
        hasOrder = true;
      }
      result.stages.add(stage);
    } else {
      result.stages.add(stage);
    }
  }
  if (!hasOrder) {
    result.stages.add(_sortByKey());
  }
  return result;
}

/// JS's `runPipeline`: the documents of [input] that [pipeline] returns, in
/// its order.
///
/// Throws a [PipelineFailure] where the backend fails the pipeline.
List<TestDocument> runPipeline(Pipeline pipeline, List<TestDocument> input) {
  final Map<EvaluationInput, TestDocument> documents =
      Map<EvaluationInput, TestDocument>.identity();
  for (final TestDocument document in input) {
    documents[EvaluationInput(document.data, key: document.key)] = document;
  }
  final List<EvaluationInput> rows = _executor.execute(
    // ignore: invalid_use_of_internal_member
    rewriteStages(pipeline.toProto(_encoder)),
    documents.keys,
  );
  return <TestDocument>[
    for (final EvaluationInput row in rows) documents[row]!,
  ];
}

/// Asserts that a body fails the pipeline.
final t.Matcher failsThePipeline = t.throwsA(t.isA<PipelineFailure>());

List<String> _paths(List<TestDocument> documents) => <String>[
  for (final TestDocument document in documents)
    document.key.path.canonicalString,
];

/// The subset of Jest's `expect` the tests use.
class Expectation {
  Expectation(this.actual);

  final Object? actual;

  /// Deep equality; lists of documents compare their paths, in order (in
  /// any order for [arrayContaining]).
  void toEqual(Object? expected) {
    final Object? value = actual;
    if (value is List<TestDocument> && expected is ArrayContaining) {
      t.expect(_paths(value), t.containsAll(_paths(expected.expected)));
    } else if (value is List<TestDocument> && expected is List) {
      t.expect(
        _paths(value),
        t.orderedEquals(_paths(expected.cast<TestDocument>())),
      );
      for (int i = 0; i < value.length; i++) {
        t.expect(identical(value[i], expected[i]), t.isTrue);
      }
    } else {
      t.expect(value, expected);
    }
  }

  void toHaveLength(int length) => t.expect(actual, t.hasLength(length));

  void toBe(Object? expected) => t.expect(actual, expected);

  void toContain(Object? expected) => t.expect(actual, t.contains(expected));

  /// [actual] is a function that throws; JS's INVALID_ARGUMENT errors are
  /// [ArgumentError]s here.
  void toThrow([String? message]) => t.expect(
    actual,
    t.throwsA(
      t.isA<ArgumentError>().having(
        (ArgumentError e) => '${e.message}',
        'message',
        message == null ? t.anything : t.contains(message),
      ),
    ),
  );
}

/// Jest's `expect.arrayContaining(expected)`.
class ArrayContaining {
  ArrayContaining(this.expected);

  final List<TestDocument> expected;
}

ArrayContaining arrayContaining(List<TestDocument> expected) =>
    ArrayContaining(expected);

Expectation expectThat(Object? actual) => Expectation(actual);
