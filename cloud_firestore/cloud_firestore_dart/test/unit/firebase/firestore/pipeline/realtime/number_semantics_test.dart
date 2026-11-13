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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/NumberSemanticsTests.kt
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

import 'package:test/test.dart' show TestOn, expect, test;

import 'realtime_pipeline_test_util.dart';

void main() {
  test('zero negative double zero', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'score': 0,
    }); // Integer 0
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'score': 0.0,
    }); // Double 0.0
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'score': -0.0,
    }); // Double -0.0
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'score': 1,
    }); // Integer 1
    final documents = [doc1, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('score').equal(constant(-0.0)));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc1, doc3, doc4]);
  });

  test('zero negative integer zero', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{'score': 0});
    final doc3 = doc('users/c', 1000, <String, Object?>{'score': 0.0});
    final doc4 = doc('users/d', 1000, <String, Object?>{'score': -0.0});
    final doc5 = doc('users/e', 1000, <String, Object?>{'score': 1});
    final documents = [doc1, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('score').equal(constant(0))); // Firestore -0LL is 0

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc1, doc3, doc4]);
  });

  test('zero positive double zero', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{'score': 0});
    final doc3 = doc('users/c', 1000, <String, Object?>{'score': 0.0});
    final doc4 = doc('users/d', 1000, <String, Object?>{'score': -0.0});
    final doc5 = doc('users/e', 1000, <String, Object?>{'score': 1});
    final documents = [doc1, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('score').equal(constant(0.0)));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc1, doc3, doc4]);
  });

  test('zero positive integer zero', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{'score': 0});
    final doc3 = doc('users/c', 1000, <String, Object?>{'score': 0.0});
    final doc4 = doc('users/d', 1000, <String, Object?>{'score': -0.0});
    final doc5 = doc('users/e', 1000, <String, Object?>{'score': 1});
    final documents = [doc1, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('score').equal(constant(0)));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc1, doc3, doc4]);
  });

  test('equal Nan', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': double.nan,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100,
    });
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('age').equal(constant(double.nan)));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('less than Nan', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': double.nan,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': null,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100,
    });
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('age').lessThan(constant(double.nan)));

    final result = runPipeline(pipeline, documents);
    assertThat(result).isEmpty();
  });

  test('less than equal Nan', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': double.nan,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': null,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100,
    });
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('age').lessThanOrEqual(constant(double.nan)));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('greater than equal Nan', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': double.nan,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 100,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100,
    });
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('age').greaterThanOrEqual(constant(double.nan)));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('greater than Nan', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': double.nan,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 100,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100,
    });
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('age').greaterThan(constant(double.nan)));

    final result = runPipeline(pipeline, documents);
    assertThat(result).isEmpty();
  });

  test('not equal Nan', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': double.nan,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100,
    });
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('age').notEqual(constant(double.nan)));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc2, doc3]);
  });

  test('eqAny contains Nan', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100,
    });
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('name').equalAny(array(double.nan, 'alice')));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('eqAny contains Nan only is empty', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': double.nan,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100,
    });
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('age').equalAny(array(double.nan)));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('arrayContains Nan only is empty', () {
    // Documents where 'age' is scalar, not an array.
    // arrayContains should not match if the field is not an array or if element is NaN.
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': double.nan,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100,
    });
    // Example doc if 'age' were an array:
    // final docWithArray = doc('users/d', 1000, mapOf('name' to 'diana', 'age' to
    // listOf(double.nan)))
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(arrayContains(field('age'), constant(double.nan)));

    // Android: no documents (its realtime `where` drops the error of
    // array_contains over a value that is not an array). The backend fails
    // the whole pipeline instead (array_contains(Field(s), 1) is an error
    // on the Enterprise edition emulator, see emulator_results.golden.jsonl).
    expect(() => runPipeline(pipeline, documents), failsThePipeline);
  });

  test('arrayContainsAny with Nan', () {
    final doc1 = doc('k/a', 1000, <String, Object?>{
      'field': [double.nan],
    });
    final doc2 = doc('k/b', 1000, <String, Object?>{
      'field': [double.nan, 42],
    });
    final doc3 = doc('k/c', 1000, <String, Object?>{
      'field': ['foo', 42],
    });
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('k')
        .where(arrayContainsAny(field('field'), array(double.nan, 'foo')));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc1, doc2, doc3]);
  });

  test('notEqAny contains Nan', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{'age': 42});
    final doc2 = doc('users/b', 1000, <String, Object?>{'age': double.nan});
    final doc3 = doc('users/c', 1000, <String, Object?>{'age': 25});
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(notEqualAny(field('age'), array(double.nan, 42)));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc3]);
  });

  test('notEqAny contains Nan only matches all', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{'age': 42});
    final doc2 = doc('users/b', 1000, <String, Object?>{'age': double.nan});
    final doc3 = doc('users/c', 1000, <String, Object?>{'age': 25});
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(notEqualAny(field('age'), array(double.nan)));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc1, doc3]);
  });

  test('array with Nan', () {
    final doc1 = doc('k/a', 1000, <String, Object?>{
      'foo': [double.nan],
    });
    final doc2 = doc('k/b', 1000, <String, Object?>{
      'foo': [42],
    });
    final documents = [doc1, doc2];

    final pipeline = RealtimePipelineSource()
        .collection('k')
        .where(field('foo').equal(array(double.nan)));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('where eq across types', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{'x': 20});
    final doc2 = doc('users/b', 1000, <String, Object?>{'x': 20});
    final doc3 = doc('users/c', 1000, <String, Object?>{'x': 20.0});
    final doc4 = doc('users/d', 1000, <String, Object?>{'x': 21});
    final documents = [doc1, doc2, doc3, doc4];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('x').equal(constant(20)));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc1, doc2, doc3]);
  });

  test('where neq across types', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{'x': 20});
    final doc2 = doc('users/b', 1000, <String, Object?>{'x': 20});
    final doc3 = doc('users/c', 1000, <String, Object?>{'x': 20.0});
    final doc4 = doc('users/d', 1000, <String, Object?>{'x': 21});
    final doc5 = doc('users/e', 1000, <String, Object?>{'x': double.nan});
    final doc6 = doc('users/f', 1000, <String, Object?>{'x': null});
    final documents = [doc1, doc2, doc3, doc4, doc5, doc6];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('x').notEqual(constant(20)));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc4, doc5, doc6]);
  });

  test('where lt across types', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{'x': 20});
    final doc2 = doc('users/b', 1000, <String, Object?>{'x': 10});
    final documents = [doc1, doc2];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('x').lessThan(constant(20)));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc2]);
  });

  test('where lte across types', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{'x': 20});
    final doc2 = doc('users/b', 1000, <String, Object?>{'x': 10});
    final documents = [doc1, doc2];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('x').lessThanOrEqual(constant(20)));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc1, doc2]);
  });

  test('where gt across types', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{'x': 20});
    final doc2 = doc('users/b', 1000, <String, Object?>{'x': 30});
    final documents = [doc1, doc2];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('x').greaterThan(constant(20)));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc2]);
  });

  test('where gte across types', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{'x': 20});
    final doc2 = doc('users/b', 1000, <String, Object?>{'x': 30});
    final documents = [doc1, doc2];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('x').greaterThanOrEqual(constant(20)));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc1, doc2]);
  });

  test('inequality with singleton range equivalent numerics', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{'score': 42});
    final doc2 = doc('users/b', 1000, <String, Object?>{'score': 42.0});
    final documents = [doc1, doc2];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('score').greaterThanOrEqual(constant(42)))
        .where(field('score').lessThanOrEqual(constant(42.0)));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc1, doc2]);
  });

  test('number type flip flop', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{'score': 42});
    final doc2 = doc('users/b', 1000, <String, Object?>{'score': 42.0});
    final documents = [doc1, doc2];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('score').equal(constant(42)));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc1, doc2]);
  });

  test('array neq with Nan', () {
    final doc1 = doc('k/a', 1000, <String, Object?>{
      'foo': [double.nan],
    });
    final doc2 = doc('k/b', 1000, <String, Object?>{
      'foo': [42],
    });
    final documents = [doc1, doc2];

    final pipeline = RealtimePipelineSource()
        .collection('k')
        .where(field('foo').notEqual(array(double.nan)));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc2]);
  });

  test('map eq with Nan', () {
    final doc1 = doc('k/a', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': double.nan},
    });
    final doc2 = doc('k/b', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': 42},
    });
    final documents = [doc1, doc2];

    final pipeline = RealtimePipelineSource()
        .collection('k')
        .where(field('foo').equal(map(<String, Object?>{'a': double.nan})));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('map neq with Nan', () {
    final doc1 = doc('k/a', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': double.nan},
    });
    final doc2 = doc('k/b', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': 42},
    });
    final documents = [doc1, doc2];

    final pipeline = RealtimePipelineSource()
        .collection('k')
        .where(field('foo').notEqual(map(<String, Object?>{'a': double.nan})));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc2]);
  });

  test('sort zero with null ascending', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/b', 1000, <String, Object?>{'score': 0});
    final documents = [doc1, doc2];

    final pipeline = RealtimePipelineSource().collection('users').sort([
      field('score').ascending(),
    ]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1, doc2]).inOrder();
  });

  test('sort equivalent zeros descending', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{'score': 0.0});
    final doc2 = doc('users/b', 1000, <String, Object?>{'score': -0.0});
    final documents = [doc1, doc2];

    final pipeline = RealtimePipelineSource().collection('users').sort([
      field('score').descending(),
    ]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc1, doc2]);
  });

  test('sort nan in array ascending', () {
    final doc1 = doc('k/a', 1000, <String, Object?>{
      'foo': [double.nan],
    });
    final doc2 = doc('k/b', 1000, <String, Object?>{
      'foo': [1],
    });
    final documents = [doc1, doc2];

    final pipeline = RealtimePipelineSource().collection('k').sort([
      field('foo').ascending(),
    ]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1, doc2]).inOrder();
  });

  test('sort nan in array descending', () {
    final doc1 = doc('k/a', 1000, <String, Object?>{
      'foo': [double.nan],
    });
    final doc2 = doc('k/b', 1000, <String, Object?>{
      'foo': [1],
    });
    final documents = [doc1, doc2];

    final pipeline = RealtimePipelineSource().collection('k').sort([
      field('foo').descending(),
    ]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc2, doc1]).inOrder();
  });

  test('sort nan in map ascending', () {
    final doc1 = doc('k/a', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': double.nan},
    });
    final doc2 = doc('k/b', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': 1},
    });
    final documents = [doc1, doc2];

    final pipeline = RealtimePipelineSource().collection('k').sort([
      field('foo').ascending(),
    ]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1, doc2]).inOrder();
  });

  test('sort nan in map descending', () {
    final doc1 = doc('k/a', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': double.nan},
    });
    final doc2 = doc('k/b', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': 1},
    });
    final documents = [doc1, doc2];

    final pipeline = RealtimePipelineSource().collection('k').sort([
      field('foo').descending(),
    ]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc2, doc1]).inOrder();
  });

  test('sort mixed types with null and unset ascending', () {
    final doc1 = doc('k/1', 1000, <String, Object?>{});
    final doc2 = doc('k/2', 1000, <String, Object?>{'field': null});
    final doc3 = doc('k/3', 1000, <String, Object?>{'field': false});
    final doc4 = doc('k/4', 1000, <String, Object?>{'field': true});
    final doc5 = doc('k/5', 1000, <String, Object?>{'field': 1});
    final doc6 = doc('k/6', 1000, <String, Object?>{'field': double.nan});
    final doc7 = doc('k/7', 1000, <String, Object?>{
      'field': double.negativeInfinity,
    });
    final doc8 = doc('k/8', 1000, <String, Object?>{'field': double.infinity});
    final documents = [doc1, doc2, doc3, doc4, doc5, doc6, doc7, doc8];

    final pipeline = RealtimePipelineSource().collection('k').sort([
      field('field').ascending(),
    ]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).isAnyOf(
      [doc1, doc2, doc3, doc4, doc6, doc7, doc5, doc8],
      [doc2, doc1, doc3, doc4, doc6, doc7, doc5, doc8],
      [doc2, doc1, doc3, doc4, doc7, doc6, doc5, doc8],
      [doc1, doc2, doc3, doc4, doc7, doc6, doc5, doc8],
    );
  });

  test('where exists across types', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{});
    final doc2 = doc('users/2', 1000, <String, Object?>{'x': null});
    final doc3 = doc('users/3', 1000, <String, Object?>{'x': 10});
    final doc4 = doc('users/4', 1000, <String, Object?>{'x': 20});
    final doc5 = doc('users/5', 1000, <String, Object?>{'x': 20.0});
    final doc6 = doc('users/6', 1000, <String, Object?>{'x': double.nan});

    final documents = [doc1, doc2, doc3, doc4, doc5, doc6];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(exists(field('x')));

    final result = runPipeline(pipeline, documents);
    assertThat(
      result,
    ).containsExactlyElementsIn([doc2, doc3, doc4, doc5, doc6]);
  });

  test('eq deeply nested map with nan', () {
    final doc1 = doc('k/a', 1000, <String, Object?>{
      'data': <String, Object?>{
        'a': <String, Object?>{'b': double.nan},
      },
    });
    final documents = [doc1];
    final pipeline = RealtimePipelineSource()
        .collection('k')
        .where(
          field('data').equal(
            map(<String, Object?>{
              'a': <String, Object?>{'b': double.nan},
            }),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('neq deeply nested map with nan', () {
    final doc1 = doc('k/a', 1000, <String, Object?>{
      'data': <String, Object?>{
        'a': <String, Object?>{'b': double.nan},
      },
    });
    final documents = [doc1];
    final pipeline = RealtimePipelineSource()
        .collection('k')
        .where(
          field('data').notEqual(
            map(<String, Object?>{
              'a': <String, Object?>{'b': double.nan},
            }),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).isEmpty();
  });

  test('eq array containing map with nan', () {
    final doc1 = doc('k/a', 1000, <String, Object?>{
      'data': [
        <String, Object?>{'a': double.nan},
      ],
    });
    final documents = [doc1];
    final pipeline = RealtimePipelineSource()
        .collection('k')
        .where(
          field('data').equal(
            array([
              <String, Object?>{'a': double.nan},
            ]),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('neq array containing map with nan', () {
    final doc1 = doc('k/a', 1000, <String, Object?>{
      'data': [
        <String, Object?>{'a': double.nan},
      ],
    });
    final documents = [doc1];
    final pipeline = RealtimePipelineSource()
        .collection('k')
        .where(
          field('data').notEqual(
            array([
              <String, Object?>{'a': double.nan},
            ]),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).isEmpty();
  });
}
