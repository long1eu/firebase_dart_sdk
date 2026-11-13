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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/ErrorHandlingTests.kt
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
  test('where partial error or', () {
    final doc1 = doc('k/1', 1000, <String, Object?>{
      'a': 'true',
      'b': true,
      'c': false,
    });
    final doc2 = doc('k/2', 1000, <String, Object?>{
      'a': true,
      'b': 'true',
      'c': false,
    });
    final doc3 = doc('k/3', 1000, <String, Object?>{
      'a': true,
      'b': false,
      'c': 'true',
    });
    final doc4 = doc('k/4', 1000, <String, Object?>{
      'a': 'true',
      'b': 'true',
      'c': true,
    });
    final doc5 = doc('k/5', 1000, <String, Object?>{
      'a': 'true',
      'b': true,
      'c': 'true',
    });
    final doc6 = doc('k/6', 1000, <String, Object?>{
      'a': true,
      'b': 'true',
      'c': 'true',
    });
    final documents = [doc1, doc2, doc3, doc4, doc5, doc6];

    final pipeline = RealtimePipelineSource()
        .collection('k')
        .where(
          or(
            equal(field('a'), constant(true)),
            equal(field('b'), constant(true)),
            equal(field('c'), constant(true)),
          ),
        );

    final result = runPipeline(pipeline, documents);
    // In Firestore, comparisons between different types are generally false.
    // The OR evaluates to true if *any* of the fields 'a', 'b', or 'c' is the
    // boolean value `true`. All documents have at least one field that is boolean
    // `true`.
    assertThat(
      result,
    ).containsExactlyElementsIn([doc1, doc2, doc3, doc4, doc5, doc6]);
  });

  test('where partial error and', () {
    final doc1 = doc('k/1', 1000, <String, Object?>{
      'a': 'true',
      'b': true,
      'c': false,
    });
    final doc2 = doc('k/2', 1000, <String, Object?>{
      'a': true,
      'b': 'true',
      'c': false,
    });
    final doc3 = doc('k/3', 1000, <String, Object?>{
      'a': true,
      'b': false,
      'c': 'true',
    });
    final doc4 = doc('k/4', 1000, <String, Object?>{
      'a': 'true',
      'b': 'true',
      'c': true,
    });
    final doc5 = doc('k/5', 1000, <String, Object?>{
      'a': 'true',
      'b': true,
      'c': 'true',
    });
    final doc6 = doc('k/6', 1000, <String, Object?>{
      'a': true,
      'b': 'true',
      'c': 'true',
    });
    final doc7 = doc('k/7', 1000, <String, Object?>{
      'a': true,
      'b': true,
      'c': true,
    });
    final documents = [doc1, doc2, doc3, doc4, doc5, doc6, doc7];

    final pipeline = RealtimePipelineSource()
        .collection('k')
        .where(
          and(
            equal(field('a'), constant(true)),
            equal(field('b'), constant(true)),
            equal(field('c'), constant(true)),
          ),
        );

    final result = runPipeline(pipeline, documents);
    // AND requires all conditions to be true. Type mismatches evaluate EqExpr to
    // false. Only doc7 has a=true, b=true, AND c=true.
    assertThat(result).containsExactly([doc7]);
  });

  test('where partial error xor', () {
    final doc1 = doc('k/1', 1000, <String, Object?>{
      'a': 'true',
      'b': true,
      'c': false,
    });
    final doc2 = doc('k/2', 1000, <String, Object?>{
      'a': true,
      'b': 'true',
      'c': false,
    });
    final doc3 = doc('k/3', 1000, <String, Object?>{
      'a': true,
      'b': false,
      'c': 'true',
    });
    final doc4 = doc('k/4', 1000, <String, Object?>{
      'a': 'true',
      'b': 'true',
      'c': true,
    });
    final doc5 = doc('k/5', 1000, <String, Object?>{
      'a': 'true',
      'b': true,
      'c': 'true',
    });
    final doc6 = doc('k/6', 1000, <String, Object?>{
      'a': true,
      'b': 'true',
      'c': 'true',
    });
    final doc7 = doc('k/7', 1000, <String, Object?>{
      'a': true,
      'b': true,
      'c': true,
    });
    final documents = [doc1, doc2, doc3, doc4, doc5, doc6, doc7];

    final pipeline = RealtimePipelineSource()
        .collection('k')
        .where(
          xor(
            equal(field('a'), constant(true)),
            equal(field('b'), constant(true)),
            equal(field('c'), constant(true)),
          ),
        );

    final result = runPipeline(pipeline, documents);
    // XOR is true if an odd number of inputs are true.
    // Assuming type mismatches evaluate EqExpr to false:
    // doc1: F xor T xor F = T
    // doc2: T xor F xor F = T
    // doc3: T xor F xor F = T
    // doc4: F xor F xor T = T
    // doc5: F xor T xor F = T
    // doc6: T xor F xor F = T
    // doc7: T xor T xor T = T
    assertThat(
      result,
    ).containsExactlyElementsIn([doc1, doc2, doc3, doc4, doc5, doc6, doc7]);
  });

  test('where not error', () {
    final doc1 = doc('k/1', 1000, <String, Object?>{'a': false});
    final doc2 = doc('k/2', 1000, <String, Object?>{'a': 'true'});
    final doc3 = doc('k/3', 1000, <String, Object?>{'b': true});
    final documents = [doc1, doc2, doc3];

    // This test case in C++ was adjusted to match a TS behavior,
    // resulting in a condition `field('a') == false`.
    final pipeline = RealtimePipelineSource()
        .collection('k')
        .where(equal(field('a'), constant(false)));

    final result = runPipeline(pipeline, documents);
    // Only doc1 has a == false.
    assertThat(result).containsExactly([doc1]);
  });

  test('where error producing function returns empty', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': true,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': '42',
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 0,
    });
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('k')
        .where(equal(divide(constant('100'), constant('50')), constant(2)));

    final result = runPipeline(pipeline, documents);
    // Division of string constants should cause an evaluation error,
    // leading to no documents matching.
    assertThat(result).isEmpty();
  });
}
