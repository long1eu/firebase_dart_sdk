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

// What the tests ported from Android's pipeline/*Tests.kt call: a stand-in
// for `RealtimePipelineSource`/`RealtimePipeline` (only `where`, `sort` and
// `limit`, as upstream), `runPipeline`, and the subset of Truth they use on
// lists of documents. The expression functions under their Kotlin names, and
// `doc`, come from evaluation_test_util.dart.
//
// `runPipeline` runs the local PipelineExecutor over the pipeline as
// Android's `RealtimePipeline.rewrittenStages` rewrites it: a sort by
// `__name__` before the first limit when nothing sorted yet, `__name__`
// appended to every sort that does not have it, and a sort by `__name__` at
// the end when nothing sorted at all.
//
// Where the executor differs from Android by design: an expression of a
// stage that evaluates to an error fails the whole pipeline (as the
// Enterprise edition backend does); Android's realtime evaluation drops the
// document from `where` and sorts the error like null. Tests that hit it
// assert `failsThePipeline` and say so.

// ignore_for_file: non_constant_identifier_names

import 'package:cloud_firestore_dart/pipelines.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/expression_evaluator.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/pipeline_executor.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/expression.dart'
    show PipelineEncoder;
import 'package:test/test.dart' as t;

import '../evaluation/evaluation_test_util.dart';
import '../pipeline_test_util.dart' show source;

export 'package:cloud_firestore_dart/cloud_firestore_dart.dart'
    show FieldPath, GeoPoint, Timestamp;
export 'package:cloud_firestore_dart/pipelines.dart'
    show BooleanExpression, Expression, Field, Ordering;
export 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/pipeline_executor.dart'
    show PipelineFailure;

export '../evaluation/evaluation_test_util.dart' hide assertThat, Subject;

final DatabaseId _databaseId = DatabaseId.forProject('project');
final PipelineEncoder _encoder = PipelineEncoder(_databaseId);
final PipelineExecutor _executor = PipelineExecutor(_databaseId);

/// Android's `RealtimePipelineSource(db)`.
class RealtimePipelineSource {
  RealtimePipeline collection(String path) =>
      RealtimePipeline._(() => source().collection(path), const <_Step>[]);

  RealtimePipeline collectionGroup(String collectionId) => RealtimePipeline._(
    () => source().collectionGroup(collectionId),
    const <_Step>[],
  );
}

sealed class _Step {
  const _Step();
}

class _Where extends _Step {
  const _Where(this.condition);

  final BooleanExpression condition;
}

class _Sort extends _Step {
  const _Sort(this.orderings);

  final List<Ordering> orderings;
}

class _Limit extends _Step {
  const _Limit(this.limit);

  final int limit;
}

/// Android's `RealtimePipeline`: `where`, `sort` and `limit`.
class RealtimePipeline {
  RealtimePipeline._(this._source, this._steps);

  final Pipeline Function() _source;
  final List<_Step> _steps;

  RealtimePipeline _with(_Step step) =>
      RealtimePipeline._(_source, <_Step>[..._steps, step]);

  RealtimePipeline where(BooleanExpression condition) =>
      _with(_Where(condition));

  RealtimePipeline sort(List<Ordering> orderings) => _with(_Sort(orderings));

  RealtimePipeline limit(int limit) => _with(_Limit(limit));

  static bool _isKey(Ordering ordering) {
    final Expression expression = ordering.expression;
    return expression is Field && expression.path.isKeyField;
  }

  static final Ordering _byKey = Field.of(Field.documentIdName).ascending();

  /// The pipeline as Android's `rewrittenStages` has it.
  Pipeline toPipeline() {
    Pipeline pipeline = _source();
    bool hasOrder = false;
    for (final _Step step in _steps) {
      switch (step) {
        case _Where():
          pipeline = pipeline.where(step.condition);
        case _Limit():
          if (!hasOrder) {
            hasOrder = true;
            pipeline = pipeline.sort(<Ordering>[_byKey]);
          }
          pipeline = pipeline.limit(step.limit);
        case _Sort():
          hasOrder = true;
          pipeline = pipeline.sort(<Ordering>[
            ...step.orderings,
            if (!step.orderings.any(_isKey)) _byKey,
          ]);
      }
    }
    if (!hasOrder) {
      pipeline = pipeline.sort(<Ordering>[_byKey]);
    }
    return pipeline;
  }
}

/// Android's `runPipeline`: the documents of [input] that [pipeline] returns,
/// in its order.
///
/// Throws a [PipelineFailure] where the backend fails the pipeline.
List<TestDocument> runPipeline(
  RealtimePipeline pipeline,
  List<TestDocument> input,
) {
  final Map<EvaluationInput, TestDocument> documents =
      Map<EvaluationInput, TestDocument>.identity();
  for (final TestDocument document in input) {
    documents[EvaluationInput(document.data, key: document.key)] = document;
  }
  // ignore: invalid_use_of_internal_member
  final List<EvaluationInput> rows = _executor.execute(
    // ignore: invalid_use_of_internal_member
    pipeline.toPipeline().toProto(_encoder),
    documents.keys,
  );
  return <TestDocument>[
    for (final EvaluationInput row in rows) documents[row]!,
  ];
}

/// Asserts that [body] fails the pipeline.
final t.Matcher failsThePipeline = t.throwsA(t.isA<PipelineFailure>());

/// The subset of Truth the tests use on results.
class ListSubject {
  ListSubject(this.actual);

  final List<TestDocument> actual;

  static List<String> _paths(List<TestDocument> documents) => <String>[
    for (final TestDocument document in documents)
      document.key.path.canonicalString,
  ];

  /// Exactly [expected], in any order; `.inOrder()` checks the order too.
  Ordered containsExactly(List<TestDocument> expected) {
    t.expect(
      _paths(actual),
      t.unorderedEquals(_paths(expected)),
      reason: 'documents',
    );
    t.expect(actual, t.unorderedEquals(expected));
    return Ordered(actual, expected);
  }

  Ordered containsExactlyElementsIn(List<TestDocument> expected) =>
      containsExactly(expected);

  void isEmpty() => t.expect(_paths(actual), t.isEmpty);

  void hasSize(int size) => t.expect(actual, t.hasLength(size));

  /// The same documents in the same order (Truth's list equality).
  void isEqualTo(List<TestDocument> expected) =>
      t.expect(_paths(actual), t.orderedEquals(_paths(expected)));

  /// Equal to one of the lists.
  void isAnyOf(
    List<TestDocument> a,
    List<TestDocument> b, [
    List<TestDocument>? c,
    List<TestDocument>? d,
  ]) => t.expect(
    _paths(actual),
    t.anyOf(<Object?>[
      for (final List<TestDocument>? expected in <List<TestDocument>?>[
        a,
        b,
        c,
        d,
      ])
        if (expected != null) t.orderedEquals(_paths(expected)),
    ]),
  );
}

class Ordered {
  Ordered(this.actual, this.expected);

  final List<TestDocument> actual;
  final List<TestDocument> expected;

  void inOrder() => t.expect(
    ListSubject._paths(actual),
    t.orderedEquals(ListSubject._paths(expected)),
  );
}

ListSubject assertThat(List<TestDocument> actual) => ListSubject(actual);
