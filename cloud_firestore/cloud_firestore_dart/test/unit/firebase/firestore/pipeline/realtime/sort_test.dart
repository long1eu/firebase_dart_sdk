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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/SortTests.kt
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
  test('empty ascending', () {
    final documents = <TestDocument>[];
    final pipeline = RealtimePipelineSource().collection('users').sort([
      field('age').ascending(),
    ]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).isEmpty();
  });

  test('empty descending', () {
    final documents = <TestDocument>[];
    final pipeline = RealtimePipelineSource().collection('users').sort([
      field('age').descending(),
    ]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).isEmpty();
  });

  test('single result ascending', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 10,
    });
    final documents = [doc1];
    final pipeline = RealtimePipelineSource().collection('users').sort([
      field('age').ascending(),
    ]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('single result ascending explicit exists', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 10,
    });
    final documents = [doc1];
    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(exists(field('age')))
        .sort([field('age').ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('single result ascending explicit not exists empty', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 10,
    });
    final documents = [doc1];
    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(not(exists(field('age'))))
        .sort([field('age').ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).isEmpty();
  });

  test('single result ascending implicit exists', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 10,
    });
    final documents = [doc1];
    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('age').equal(10))
        .sort([field('age').ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('single result descending', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 10,
    });
    final documents = [doc1];
    final pipeline = RealtimePipelineSource().collection('users').sort([
      field('age').descending(),
    ]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('single result descending explicit exists', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 10,
    });
    final documents = [doc1];
    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(exists(field('age')))
        .sort([field('age').descending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('single result descending implicit exists', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 10,
    });
    final documents = [doc1];
    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('age').equal(10))
        .sort([field('age').descending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('multiple results ambiguous order', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25.0,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100.0,
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'name': 'diane',
      'age': 10.0,
    });
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'name': 'eric',
      'age': 10.0,
    });
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource().collection('users').sort([
      field('age').descending(),
    ]);

    // Order: doc3 (100.0), doc1 (75.5), doc2 (25.0), then doc4 and doc5 (10.0) are ambiguous
    // Firestore backend sorts by document key as a tie-breaker.
    // So expected order: doc3, doc1, doc2, doc4, doc5 (if 'd' < 'e') or doc3, doc1, doc2, doc5,
    // doc4 (if 'e' < 'd')
    // Since the C++ test uses UnorderedElementsAre, we'll use containsExactlyElementsIn.
    final result = runPipeline(pipeline, documents);
    assertThat(
      result,
    ).containsExactlyElementsIn([doc3, doc1, doc2, doc4, doc5]).inOrder();
    // Actually, the local pipeline implementation might not guarantee tie-breaking by key unless
    // explicitly added.
    // The C++ test uses UnorderedElementsAre, which means the exact order of doc4 and doc5 is not
    // tested.
    // Let's stick to what the C++ test implies: the overall set is correct, but the order of tied
    // elements is not strictly defined by this single sort.
    // However, the local pipeline *does* sort by key as a final tie-breaker.
    // Expected: doc3 (100.0), doc1 (75.5), doc2 (25.0), doc4 (10.0, key d), doc5 (10.0, key e)
    // So the order should be doc3, doc1, doc2, doc4, doc5
    assertThat(
      result,
    ).containsExactly([doc3, doc1, doc2, doc4, doc5]).inOrder();
  });

  test('multiple results ambiguous order explicit exists', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25.0,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100.0,
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'name': 'diane',
      'age': 10.0,
    });
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'name': 'eric',
      'age': 10.0,
    });
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(exists(field('age')))
        .sort([field('age').descending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(
      result,
    ).containsExactly([doc3, doc1, doc2, doc4, doc5]).inOrder();
  });

  test('multiple results ambiguous order implicit exists', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25.0,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100.0,
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'name': 'diane',
      'age': 10.0,
    });
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'name': 'eric',
      'age': 10.0,
    });
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('age').greaterThan(0.0))
        .sort([field('age').descending()]);
    final result = runPipeline(pipeline, documents);
    assertThat(
      result,
    ).containsExactly([doc3, doc1, doc2, doc4, doc5]).inOrder();
  });

  test('multiple results full order', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25.0,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100.0,
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'name': 'diane',
      'age': 10.0,
    });
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'name': 'eric',
      'age': 10.0,
    });
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource().collection('users').sort([
      field('age').descending(),
      field('name').ascending(),
    ]);

    final result = runPipeline(pipeline, documents);
    // age desc: 100(c), 75.5(a), 25(b), 10(d), 10(e)
    // name asc for 10: diane(d), eric(e)
    // Expected: c, a, b, d, e
    assertThat(
      result,
    ).containsExactly([doc3, doc1, doc2, doc4, doc5]).inOrder();
  });

  test('multiple results full order explicit exists', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25.0,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100.0,
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'name': 'diane',
      'age': 10.0,
    });
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'name': 'eric',
      'age': 10.0,
    });
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(exists(field('age')))
        .where(exists(field('name')))
        .sort([field('age').descending(), field('name').ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(
      result,
    ).containsExactly([doc3, doc1, doc2, doc4, doc5]).inOrder();
  });

  test('multiple results full order explicit not exists empty', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{'name': 'bob'});
    final doc3 = doc('users/c', 1000, <String, Object?>{'age': 100.0});
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'other_name': 'diane',
    }); // Matches
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'other_age': 10.0,
    }); // Matches
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(not(exists(field('age'))))
        .where(not(exists(field('name'))))
        .sort([field('age').descending(), field('name').ascending()]);
    // Filtered: doc4, doc5
    // Sort by missing age (no op), then missing name (no op), then by key ascending.
    // d < e
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc4, doc5]).inOrder();
  });

  test('multiple results full order implicit exists', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25.0,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100.0,
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'name': 'diane',
      'age': 10.0,
    });
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'name': 'eric',
      'age': 10.0,
    });
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('age').equal(field('age'))) // Implicit exists age
        .where(field('name').regexMatch('.*')) // Implicit exists name
        .sort([field('age').descending(), field('name').ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(
      result,
    ).containsExactly([doc3, doc1, doc2, doc4, doc5]).inOrder();
  });

  test('multiple results full order partial explicit exists', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25.0,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100.0,
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'name': 'diane',
      'age': 10.0,
    });
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'name': 'eric',
      'age': 10.0,
    });
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(exists(field('name')))
        .sort([field('age').descending(), field('name').ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(
      result,
    ).containsExactly([doc3, doc1, doc2, doc4, doc5]).inOrder();
  });

  test('multiple results full order partial explicit not exists', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'age': 25.0,
    }); // name missing -> Match
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100.0,
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'name': 'diane',
    }); // age missing, name exists
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'name': 'eric',
    }); // age missing, name exists
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(not(exists(field('name')))) // Only doc2 matches
        .sort([field('age').descending(), field('name').descending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc2]);
  });

  test(
    'multiple results full order partial explicit not exists sort on non exist field first',
    () {
      final doc1 = doc('users/a', 1000, <String, Object?>{
        'name': 'alice',
        'age': 75.5,
      });
      final doc2 = doc('users/b', 1000, <String, Object?>{
        'age': 25.0,
      }); // name missing -> Match
      final doc3 = doc('users/c', 1000, <String, Object?>{
        'name': 'charlie',
        'age': 100.0,
      });
      final doc4 = doc('users/d', 1000, <String, Object?>{
        'name': 'diane',
      }); // age missing, name exists
      final doc5 = doc('users/e', 1000, <String, Object?>{
        'name': 'eric',
      }); // age missing, name exists
      final documents = [doc1, doc2, doc3, doc4, doc5];

      final pipeline = RealtimePipelineSource()
          .collection('users')
          .where(not(exists(field('name')))) // Only doc2 matches
          .sort([field('name').descending(), field('age').descending()]);

      final result = runPipeline(pipeline, documents);
      assertThat(result).containsExactly([doc2]);
    },
  );

  test('multiple results full order partial implicit exists', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25.0,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100.0,
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'name': 'diane',
      'age': 10.0,
    });
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'name': 'eric',
      'age': 10.0,
    });
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('name').regexMatch('.*'))
        .sort([field('age').descending(), field('name').ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(
      result,
    ).containsExactly([doc3, doc1, doc2, doc4, doc5]).inOrder();
  });

  test('missing field all fields', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25.0,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100.0,
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'name': 'diane',
      'age': 10.0,
    });
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'name': 'eric',
      'age': 10.0,
    });
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource().collection('users').sort([
      field('not_age').descending(),
    ]);

    // Sorting by a missing field results in undefined order relative to each other,
    // but documents are secondarily sorted by key.
    // Since it's descending for not_age (all are null essentially), key order will be ascending.
    final result = runPipeline(pipeline, documents);
    assertThat(
      result,
    ).containsExactly([doc1, doc2, doc3, doc4, doc5]).inOrder();
  });

  test('missing field with exist empty', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final documents = [doc1];
    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(exists(field('not_age')))
        .sort([field('not_age').descending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).isEmpty();
  });

  test('missing field partial fields', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
    }); // age missing
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100.0,
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'name': 'diane',
    }); // age missing
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'name': 'eric',
      'age': 10.0,
    });
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource().collection('users').sort([
      field('age').ascending(),
    ]);

    // Missing fields sort first in ascending order, then by key. b < d
    // Then existing fields sorted by value: e (10.0) < a (75.5) < c (100.0)
    // Expected: doc2, doc4, doc5, doc1, doc3
    final result = runPipeline(pipeline, documents);
    assertThat(
      result,
    ).containsExactly([doc2, doc4, doc5, doc1, doc3]).inOrder();
  });

  test('missing field partial fields with exist', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{'name': 'bob'});
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100.0,
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{'name': 'diane'});
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'name': 'eric',
      'age': 10.0,
    });
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(exists(field('age'))) // Filters to doc1, doc3, doc5
        .sort([field('age').ascending()]);

    // Sort remaining: doc5 (10.0), doc1 (75.5), doc3 (100.0)
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc5, doc1, doc3]).inOrder();
  });

  test('missing field partial fields with not exist', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
    }); // Match
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100.0,
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'name': 'diane',
    }); // Match
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'name': 'eric',
      'age': 10.0,
    });
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(not(exists(field('age')))) // Filters to doc2, doc4
        .sort([
          field('age').ascending(),
        ]); // Sort by non-existent field, then key

    // Sort remaining by key: doc2, doc4
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc2, doc4]).inOrder();
  });

  test('limit after sort', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25.0,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100.0,
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'name': 'diane',
      'age': 10.0,
    });
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'name': 'eric',
      'age': 10.0,
    });
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .sort([
          field('age').ascending(),
        ]) // Sort: d, e, b, a, c (key tie-break for d,e)
        .limit(2);

    // Expected: doc4, doc5
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc4, doc5]).inOrder();
  });

  test('limit after sort with exist', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'age': 25.0,
    }); // name missing
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100.0,
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'name': 'diane',
    }); // age missing
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'name': 'eric',
      'age': 10.0,
    });
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(exists(field('age'))) // Filter: a, b, c, e
        .sort([
          field('age').ascending(),
        ]) // Sort: e (10), b (25), a (75.5), c (100)
        .limit(2); // Limit 2: e, b

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc5, doc2]).inOrder();
  });

  test('limit after sort with not exist', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'age': 25.0,
    }); // name missing
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100.0,
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'name': 'diane',
    }); // age missing -> Match
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'name': 'eric',
    }); // age missing -> Match
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(not(exists(field('age')))) // Filter: d, e
        .sort([
          field('age').ascending(),
        ]) // Sort by missing field -> key order: d, e
        .limit(2); // Limit 2: d, e

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc4, doc5]).inOrder();
  });

  test('limit zero after sort', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final documents = [doc1];
    final pipeline = RealtimePipelineSource()
        .collection('users')
        .sort([field('age').ascending()])
        .limit(0);

    final result = runPipeline(pipeline, documents);
    assertThat(result).isEmpty();
  });

  test('limit before sort', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25.0,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100.0,
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'name': 'diane',
      'age': 10.0,
    });
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'name': 'eric',
      'age': 10.0,
    });
    final documents = [doc1, doc2, doc3, doc4, doc5];
    // Note: Limit before sort has different semantics online vs offline.
    // Offline evaluation applies limit first based on implicit key order.
    final pipeline = RealtimePipelineSource()
        .collectionGroup('users') // C++ test uses CollectionGroupSource here
        .limit(
          1,
        ) // Limits to doc1 (key 'users/a' is first by default key order)
        .sort([field('age').ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('limit before sort with exist', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{'age': 25.0});
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100.0,
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{'name': 'diane'});
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'name': 'eric',
      'age': 10.0,
    });
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collectionGroup('users')
        .where(
          exists(field('age')),
        ) // Filter: a,b,c,e. Implicit key order: a,b,c,e
        .limit(1) // Limits to doc1 (key 'users/a')
        .sort([field('age').ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('limit before sort with not exist', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{'age': 25.0});
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100.0,
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'name': 'diane',
    }); // Match
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'name': 'eric',
    }); // Match
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collectionGroup('users')
        .where(
          not(exists(field('age'))),
        ) // Filter: d, e. Implicit key order: d, e
        .limit(1) // Limits to doc4 (key 'users/d')
        .sort([field('age').ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc4]);
  });

  test('limit before not exist filter', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{'age': 75.5});
    final doc2 = doc('users/b', 1000, <String, Object?>{'age': 25.0});
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100.0,
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{'name': 'diane'});
    final doc5 = doc('users/e', 1000, <String, Object?>{'name': 'eric'});
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collectionGroup('users')
        .limit(2) // Limit to a, b (by key)
        .where(not(exists(field('age')))) // Filter out a, b (both have age)
        .sort([field('age').ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).isEmpty();
  });

  test('limit zero before sort', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final documents = [doc1];
    final pipeline = RealtimePipelineSource()
        .collectionGroup('users')
        .limit(0)
        .sort([field('age').ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).isEmpty();
  });

  test('sort expression', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 10,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 30,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 50,
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'name': 'diane',
      'age': 40,
    });
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'name': 'eric',
      'age': 20,
    });
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource().collectionGroup('users').sort([
      add(field('age'), constant(10)).descending(),
    ]); // age + 10

    // Sort by (age+10) desc:
    // doc3: 50+10 = 60
    // doc4: 40+10 = 50
    // doc2: 30+10 = 40
    // doc5: 20+10 = 30
    // doc1: 10+10 = 20
    // Expected: doc3, doc4, doc2, doc5, doc1
    final result = runPipeline(pipeline, documents);
    assertThat(
      result,
    ).containsExactly([doc3, doc4, doc2, doc5, doc1]).inOrder();
  });

  test('sort expression with exist', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 10,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'age': 30,
    }); // name missing
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 50,
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'name': 'diane',
    }); // age missing
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'name': 'eric',
      'age': 20,
    });
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collectionGroup('users')
        .where(exists(field('age'))) // Filter: a, b, c, e
        .sort([add(field('age'), constant(10)).descending()]);

    // Filtered: doc1 (10), doc2 (30), doc3 (50), doc5 (20)
    // Sort by (age+10) desc:
    // doc3: 50+10 = 60
    // doc2: 30+10 = 40
    // doc5: 20+10 = 30
    // doc1: 10+10 = 20
    // Expected: doc3, doc2, doc5, doc1
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc3, doc2, doc5, doc1]).inOrder();
  });

  test('sort expression with not exist', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 10,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{'age': 30});
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 50,
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'name': 'diane',
    }); // age missing -> Match
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'name': 'eric',
    }); // age missing -> Match
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collectionGroup('users')
        .where(not(exists(field('age')))) // Filter: d, e
        .sort([
          add(field('age'), constant(10)).descending(),
        ]); // Sort by missing field -> key order

    // Filtered: doc4, doc5
    // Sort by (age+10) desc where age is missing. This means they are treated as null for the
    // expression.
    // Then tie-broken by key: d, e
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc4, doc5]).inOrder();
  });

  test('sort on path and other field on different stages', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{
      'name': 'alice',
      'age': 40,
    });
    final doc2 = doc('users/2', 1000, <String, Object?>{
      'name': 'bob',
      'age': 30,
    });
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 50,
    });
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(
          exists(Field.of(FieldPath.documentIdField)),
        ) // Ensure __name__ is considered
        .sort([
          Field.of(FieldPath.documentIdField).ascending(),
        ]) // Sort by key: 1, 2, 3
        .sort([
          field('age').ascending(),
        ]); // Sort by age: 2(30), 1(40), 3(50) - Last sort takes precedence

    // The C++ test implies that the *last* sort stage defines the primary sort order.
    // This is different from how multiple orderBy clauses usually work in Firestore (they form a
    // composite sort).
    // However, if these are separate stages, the last one would indeed re-sort the entire output of
    // the previous.
    // Let's assume the Kotlin pipeline behaves this way for separate .orderBy() calls.
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc2, doc1, doc3]).inOrder();
  });

  test('sort on other field and path on different stages', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{
      'name': 'alice',
      'age': 40,
    });
    final doc2 = doc('users/2', 1000, <String, Object?>{
      'name': 'bob',
      'age': 30,
    });
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 50,
    });
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(exists(Field.of(FieldPath.documentIdField)))
        .sort([field('age').ascending()]) // Sort by age: 2(30), 1(40), 3(50)
        .sort([
          Field.of(FieldPath.documentIdField).ascending(),
        ]); // Sort by key: 1, 2, 3

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1, doc2, doc3]).inOrder();
  });

  // The C++ tests `SortOnKeyAndOtherFieldOnMultipleStages` and
  // `SortOnOtherFieldAndKeyOnMultipleStages`
  // are identical to the `Path` versions because `kDocumentKeyPath` is used.
  // These are effectively duplicates of the above two tests in Kotlin if we use
  // `PublicFieldPath.documentId()`.
  // I'll include them for completeness, mirroring the C++ structure.
  test('sort on key and other field on multiple stages', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{
      'name': 'alice',
      'age': 40,
    });
    final doc2 = doc('users/2', 1000, <String, Object?>{
      'name': 'bob',
      'age': 30,
    });
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 50,
    });
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(exists(Field.of(FieldPath.documentIdField)))
        .sort([Field.of(FieldPath.documentIdField).ascending()])
        .sort([field('age').ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc2, doc1, doc3]).inOrder();
  });

  test('sort on other field and key on multiple stages', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{
      'name': 'alice',
      'age': 40,
    });
    final doc2 = doc('users/2', 1000, <String, Object?>{
      'name': 'bob',
      'age': 30,
    });
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 50,
    });
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(exists(Field.of(FieldPath.documentIdField)))
        .sort([field('age').ascending()])
        .sort([Field.of(FieldPath.documentIdField).ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1, doc2, doc3]).inOrder();
  });
}
