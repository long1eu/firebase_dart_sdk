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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/ComplexPipelineTests.kt
//
// The port keeps the names and the structure of the Kotlin tests;
// realtime_pipeline_test_util.dart has the functions they call. Where the
// expected result differs from Android's, a comment says why.

// ignore_for_file: prefer_single_quotes, always_specify_types
// ignore_for_file: lines_longer_than_80_chars, prefer_final_locals
// ignore_for_file: omit_local_variable_types, unused_local_variable
// ignore_for_file: prefer_const_declarations, prefer_const_constructors

// The documents hold doubles with integral values (1.0, -0.0) and 64-bit
// integers, which compiled to JavaScript are not what they are on the VM.
@TestOn('vm')
library;

import 'package:test/test.dart' show TestOn, test;

import 'realtime_pipeline_test_util.dart';

void main() {
  test('max stages with interleaved complex expressions', () {
    final doc1 = doc('k/a', 1000, <String, Object?>{'val': 1, 'str': 's'});
    final documents = [doc1];

    Expression currentValExpr = field('val');

    for (int i = 1; i <= 31; i++) {
      final prevVal = currentValExpr;
      final Expression valExpr;
      if (i % 5 == 0) {
        valExpr = conditional(
          prevVal.greaterThan(constant(0)),
          add(prevVal, multiply(prevVal, constant(3))),
          prevVal,
        );
      } else {
        valExpr = add(prevVal, constant(1));
      }
      currentValExpr = valExpr;
    }

    final pipeline = RealtimePipelineSource()
        .collection('/k')
        .where(currentValExpr.equal(constant(25937)));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('extreme conditional logic', () {
    final docs = <TestDocument>[];
    for (final c in ['A', 'B', 'C']) {
      docs.add(doc('k/doc$c', 1000, <String, Object?>{'type': c}));
    }
    final docDefault = doc('k/docDefault', 1000, <String, Object?>{
      'type': 'Unknown',
    });
    docs.add(docDefault);

    Expression categoryExpr = constant('DefaultResult');
    for (final c in ['C', 'B', 'A']) {
      final type = c;
      final result = 'Result$type';
      categoryExpr = conditional(
        field('type').equal(constant(type)),
        constant(result),
        categoryExpr,
      );
    }

    final pipeline = RealtimePipelineSource()
        .collection('/k')
        .where(categoryExpr.equal(constant('ResultB')));

    final result = runPipeline(pipeline, docs);
    assertThat(result).containsExactly([docs[1]]); // docB
  });

  test('union with many stages just under limit', () {
    final doc1 = doc('k/a', 1000, <String, Object?>{'foo': 1});
    final doc2 = doc('k/b', 1000, <String, Object?>{'foo': 2});
    final documents = [doc1, doc2];

    final condition1 = field('foo').equal(constant(1));

    BooleanExpression condition2 = field('foo').equal(constant(2));
    for (int i = 0; i < 50; i++) {
      condition2 = and(condition2, field('foo').greaterThan(constant(0)));
    }

    var unionCondition = or(condition1, condition2);

    for (int i = 0; i < 10; i++) {
      unionCondition = and(
        unionCondition,
        field('foo').greaterThan(constant(0)),
      );
    }

    final pipeline = RealtimePipelineSource()
        .collection('/k')
        .where(unionCondition);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn(documents);
  });

  test('deeply nested conditional in filter', () {
    final doc1 = doc('k/a', 1000, <String, Object?>{'x': 1, 'y': 2}); // x < y
    final doc2 = doc('k/b', 1000, <String, Object?>{'x': 2, 'y': 1}); // x > y
    final documents = [doc1, doc2];

    Expression deeplyNestedFilter = field('x').equal(field('y'));
    for (int i = 0; i < 11; i++) {
      final prevBoolean = deeplyNestedFilter.equal(constant(true));

      deeplyNestedFilter = conditional(
        field('x').greaterThan(field('y')),
        deeplyNestedFilter,
        not(prevBoolean),
      );
    }

    final pipeline = RealtimePipelineSource()
        .collection('/k')
        .where(deeplyNestedFilter.equal(constant(true)));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });
}
