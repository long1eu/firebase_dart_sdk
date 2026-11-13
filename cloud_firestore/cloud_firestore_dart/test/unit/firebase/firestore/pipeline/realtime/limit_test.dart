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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/LimitTests.kt
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
  List<TestDocument> createDocs() {
    final doc1 = doc('k/a', 1000, <String, Object?>{'a': 1, 'b': 2});
    final doc2 = doc('k/b', 1000, <String, Object?>{'a': 3, 'b': 4});
    final doc3 = doc('k/c', 1000, <String, Object?>{'a': 5, 'b': 6});
    final doc4 = doc('k/d', 1000, <String, Object?>{'a': 7, 'b': 8});
    return [doc1, doc2, doc3, doc4];
  }

  test('limit zero', () {
    final documents = createDocs();
    final pipeline = RealtimePipelineSource().collection('k').limit(0);

    final result = runPipeline(pipeline, documents);
    assertThat(result).isEmpty();
  });

  test('limit zero duplicated', () {
    final documents = createDocs();
    final pipeline = RealtimePipelineSource()
        .collection('k')
        .limit(0)
        .limit(0)
        .limit(0);

    final result = runPipeline(pipeline, documents);
    assertThat(result).isEmpty();
  });

  test('limit one', () {
    final documents = createDocs();
    final pipeline = RealtimePipelineSource().collection('k').limit(1);

    final result = runPipeline(pipeline, documents);
    assertThat(result).hasSize(1);
  });

  test('limit one duplicated', () {
    final documents = createDocs();
    final pipeline = RealtimePipelineSource()
        .collection('k')
        .limit(1)
        .limit(1)
        .limit(1);

    final result = runPipeline(pipeline, documents);
    assertThat(result).hasSize(1);
  });

  test('limit two', () {
    final documents = createDocs();
    final pipeline = RealtimePipelineSource().collection('k').limit(2);

    final result = runPipeline(pipeline, documents);
    assertThat(result).hasSize(2);
  });

  test('limit two duplicated', () {
    final documents = createDocs();
    final pipeline = RealtimePipelineSource()
        .collection('k')
        .limit(2)
        .limit(2)
        .limit(2);

    final result = runPipeline(pipeline, documents);
    assertThat(result).hasSize(2);
  });

  test('limit three', () {
    final documents = createDocs();
    final pipeline = RealtimePipelineSource().collection('k').limit(3);

    final result = runPipeline(pipeline, documents);
    assertThat(result).hasSize(3);
  });

  test('limit three duplicated', () {
    final documents = createDocs();
    final pipeline = RealtimePipelineSource()
        .collection('k')
        .limit(3)
        .limit(3)
        .limit(3);

    final result = runPipeline(pipeline, documents);
    assertThat(result).hasSize(3);
  });

  test('limit four', () {
    final documents = createDocs();
    final pipeline = RealtimePipelineSource().collection('k').limit(4);

    final result = runPipeline(pipeline, documents);
    assertThat(result).hasSize(4);
  });

  test('limit four duplicated', () {
    final documents = createDocs();
    final pipeline = RealtimePipelineSource()
        .collection('k')
        .limit(4)
        .limit(4)
        .limit(4);

    final result = runPipeline(pipeline, documents);
    assertThat(result).hasSize(4);
  });

  test('limit five', () {
    final documents = createDocs(); // Only 4 docs created
    final pipeline = RealtimePipelineSource().collection('k').limit(5);

    final result = runPipeline(pipeline, documents);
    assertThat(result).hasSize(4); // Limited by actual doc count
  });

  test('limit five duplicated', () {
    final documents = createDocs(); // Only 4 docs created
    final pipeline = RealtimePipelineSource()
        .collection('k')
        .limit(5)
        .limit(5)
        .limit(5);

    final result = runPipeline(pipeline, documents);
    assertThat(result).hasSize(4); // Limited by actual doc count
  });

  test('limit max', () {
    final documents = createDocs();
    final pipeline = RealtimePipelineSource().collection('k').limit(maxInt);

    final result = runPipeline(pipeline, documents);
    assertThat(result).hasSize(4);
  });

  test('limit max duplicated', () {
    final documents = createDocs();
    final pipeline = RealtimePipelineSource()
        .collection('k')
        .limit(maxInt)
        .limit(maxInt)
        .limit(maxInt);

    final result = runPipeline(pipeline, documents);
    assertThat(result).hasSize(4);
  });
}
