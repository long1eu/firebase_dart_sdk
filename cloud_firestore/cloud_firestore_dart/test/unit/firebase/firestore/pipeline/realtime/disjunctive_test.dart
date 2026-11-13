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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/DisjunctiveTests.kt
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
  test('basic eqAny', () {
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
        .collection('/users')
        .where(
          field('name').equalAny(
            array(
              constant('alice'),
              constant('bob'),
              constant('charlie'),
              constant('diane'),
              constant('eric'),
            ),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(
      result,
    ).containsExactlyElementsIn([doc1, doc2, doc3, doc4, doc5]);
  });

  test('multiple eqAny', () {
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
        .collection('/users')
        .where(
          and(
            field('name').equalAny(
              array(
                constant('alice'),
                constant('bob'),
                constant('charlie'),
                constant('diane'),
                constant('eric'),
              ),
            ),
            field('age').equalAny(array(constant(10.0), constant(25.0))),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc2, doc4, doc5]);
  });

  test('eqAny multiple stages', () {
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
        .collection('/users')
        .where(
          field('name').equalAny(
            array(
              constant('alice'),
              constant('bob'),
              constant('charlie'),
              constant('diane'),
              constant('eric'),
            ),
          ),
        )
        .where(field('age').equalAny(array(constant(10.0), constant(25.0))));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc2, doc4, doc5]);
  });

  test('multiple eqAnys with or', () {
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
        .collection('/users')
        .where(
          or(
            field('name').equalAny(array(constant('alice'), constant('bob'))),
            field('age').equalAny(array(constant(10.0), constant(25.0))),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc1, doc2, doc4, doc5]);
  });

  test('eqAny on collectionGroup', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('other_users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25.0,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100.0,
    });
    final doc4 = doc('root/child/users/d', 1000, <String, Object?>{
      'name': 'diane',
      'age': 10.0,
    });
    final doc5 = doc('root/child/other_users/e', 1000, <String, Object?>{
      'name': 'eric',
      'age': 10.0,
    });
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collectionGroup('users')
        .where(
          field('name').equalAny(
            array(
              constant('alice'),
              constant('bob'),
              constant('diane'),
              constant('eric'),
            ),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc1, doc4]);
  });

  test('eqAny with sort on different field', () {
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
    }); // Not matched
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
        .collection('/users')
        .where(
          field('name').equalAny(
            array(
              constant('alice'),
              constant('bob'),
              constant('diane'),
              constant('eric'),
            ),
          ),
        )
        .sort([field('age').ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc4, doc5, doc2, doc1]).inOrder();
  });

  test('eqAny with sort on eqAny field', () {
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
    }); // Not matched
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
        .collection('/users')
        .where(
          field('name').equalAny(
            array(
              constant('alice'),
              constant('bob'),
              constant('diane'),
              constant('eric'),
            ),
          ),
        )
        .sort([field('name').ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1, doc2, doc4, doc5]).inOrder();
  });

  test('eqAny with additional equality different fields', () {
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
        .collection('/users')
        .where(
          and(
            field('name').equalAny(
              array(
                constant('alice'),
                constant('bob'),
                constant('charlie'),
                constant('diane'),
                constant('eric'),
              ),
            ),
            field('age').equal(constant(10.0)),
          ),
        )
        .sort([field('name').ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc4, doc5]).inOrder();
  });

  test('eqAny with additional equality same field', () {
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
        .collection('/users')
        .where(
          and(
            field('name').equalAny(
              array(constant('alice'), constant('diane'), constant('eric')),
            ),
            field('name').equal(constant('eric')),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc5]);
  });

  test('eqAny with additional equality same field empty result', () {
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
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          and(
            field('name').equalAny(array(constant('alice'), constant('bob'))),
            field('name').equal(constant('other')),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).isEmpty();
  });

  test('eqAny with inequalities exclusive range', () {
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
    }); // Not matched
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          and(
            field('name').equalAny(
              array(
                constant('alice'),
                constant('bob'),
                constant('charlie'),
                constant('diane'),
              ),
            ),
            field('age').greaterThan(constant(10.0)),
            field('age').lessThan(constant(100.0)),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc1, doc2]);
  });

  test('eqAny with inequalities inclusive range', () {
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
    }); // Not matched
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          and(
            field('name').equalAny(
              array(
                constant('alice'),
                constant('bob'),
                constant('charlie'),
                constant('diane'),
              ),
            ),
            field('age').greaterThanOrEqual(constant(10.0)),
            field('age').lessThanOrEqual(constant(100.0)),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc1, doc2, doc3, doc4]);
  });

  test('eqAny with inequalities and sort', () {
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
    }); // Not matched
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          and(
            field('name').equalAny(
              array(
                constant('alice'),
                constant('bob'),
                constant('charlie'),
                constant('diane'),
              ),
            ),
            field('age').greaterThan(constant(10.0)),
            field('age').lessThan(constant(100.0)),
          ),
        )
        .sort([field('age').ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc2, doc1]).inOrder();
  });

  test('eqAny with notEqual', () {
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
    }); // Not matched
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          and(
            field('name').equalAny(
              array(
                constant('alice'),
                constant('bob'),
                constant('charlie'),
                constant('diane'),
              ),
            ),
            field('age').notEqual(constant(100.0)),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc1, doc2, doc4]);
  });

  test('eqAny sort on eqAny field again', () {
    // Renamed from C++ duplicate
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
    }); // Not matched
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          field('name').equalAny(
            array(
              constant('alice'),
              constant('bob'),
              constant('charlie'),
              constant('diane'),
            ),
          ),
        )
        .sort([field('name').ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1, doc2, doc3, doc4]).inOrder();
  });

  test('eqAny single value sort on in field ambiguous order', () {
    final doc1 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100.0,
    }); // Not matched
    final doc2 = doc('users/d', 1000, <String, Object?>{
      'name': 'diane',
      'age': 10.0,
    });
    final doc3 = doc('users/e', 1000, <String, Object?>{
      'name': 'eric',
      'age': 10.0,
    });
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(field('age').equalAny(array(constant(10.0))))
        .sort([field('age').ascending()]);

    final result = runPipeline(pipeline, documents);
    // Order of doc2 and doc3 is by key after sorting by constant age
    assertThat(result).containsExactly([doc2, doc3]).inOrder();
  });

  test('eqAny with extra equality sort on eqAny field', () {
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
        .collection('/users')
        .where(
          and(
            field('name').equalAny(
              array(
                constant('alice'),
                constant('bob'),
                constant('charlie'),
                constant('diane'),
                constant('eric'),
              ),
            ),
            field('age').equal(constant(10.0)),
          ),
        )
        .sort([field('name').ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc4, doc5]).inOrder();
  });

  test('eqAny with extra equality sort on equality', () {
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
        .collection('/users')
        .where(
          and(
            field('name').equalAny(
              array(
                constant('alice'),
                constant('bob'),
                constant('charlie'),
                constant('diane'),
                constant('eric'),
              ),
            ),
            field('age').equal(constant(10.0)),
          ),
        )
        .sort([field('age').ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(
      result,
    ).containsExactly([doc4, doc5]).inOrder(); // Sorted by key after age
  });

  test('eqAny with inequality on same field', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    }); // Not matched
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
    }); // Not matched
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'name': 'eric',
      'age': 10.0,
    }); // Not matched
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          and(
            field(
              'age',
            ).equalAny(array(constant(10.0), constant(25.0), constant(100.0))),
            field('age').greaterThan(constant(20.0)),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc2, doc3]);
  });

  test('eqAny with different inequality sort on eqAny field', () {
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
    }); // Not matched
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'name': 'eric',
      'age': 10.0,
    }); // Not matched
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          and(
            field('name').equalAny(
              array(
                constant('alice'),
                constant('bob'),
                constant('charlie'),
                constant('diane'),
              ),
            ),
            field('age').greaterThan(constant(20.0)),
          ),
        )
        .sort([
          field('age').ascending(),
        ]); // C++ test sorts by age (inequality field)

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc2, doc1, doc3]).inOrder();
  });

  test('eqAny contains null', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': null,
      'age': 25.0,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'age': 100.0,
    }); // name missing
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(field('name').equalAny(array(nullValue(), constant('alice'))));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc1, doc2]);
  });

  test('arrayContains null', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'field': [null, 42],
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'field': [101, null],
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'field': <Object?>[null],
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'field': ['foo', 'bar'],
    });
    final documents = [doc1, doc2, doc3, doc4];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(arrayContains(field('field'), nullValue()));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc1, doc2, doc3]);
  });

  test('arrayContainsAny null', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'field': [null, 42],
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'field': [101, null],
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'field': ['foo', 'bar'],
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'not_field': ['foo', 'bar'],
    });
    final documents = [doc1, doc2, doc3, doc4];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          field('field').arrayContainsAny(array(nullValue(), constant('foo'))),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc1, doc2, doc3]);
  });

  test('eqAny contains null only', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': null,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25.0,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100.0,
    });
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(field('age').equalAny(array(nullValue())));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc1]);
  });

  test('basic arrayContainsAny', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'groups': [1, 2, 3],
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'groups': [1, 2, 4],
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'groups': [2, 3, 4],
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'name': 'diane',
      'groups': [2, 3, 5],
    });
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'name': 'eric',
      'groups': [3, 4, 5],
    });
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          field('groups').arrayContainsAny(array(constant(1), constant(5))),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc1, doc2, doc4, doc5]);
  });

  test('multiple arrayContainsAny', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'groups': [1, 2, 3],
      'records': ['a', 'b', 'c'],
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'groups': [1, 2, 4],
      'records': ['b', 'c', 'd'],
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'groups': [2, 3, 4],
      'records': ['b', 'c', 'e'],
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'name': 'diane',
      'groups': [2, 3, 5],
      'records': ['c', 'd', 'e'],
    });
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'name': 'eric',
      'groups': [3, 4, 5],
      'records': ['c', 'd', 'f'],
    });
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          and(
            field('groups').arrayContainsAny(array(constant(1), constant(5))),
            field(
              'records',
            ).arrayContainsAny(array(constant('a'), constant('e'))),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc1, doc4]);
  });

  test('arrayContainsAny with inequality', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'groups': [1, 2, 3],
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'groups': [1, 2, 4],
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'groups': [2, 3, 4],
    }); // Filtered by LT
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'name': 'diane',
      'groups': [2, 3, 5],
    });
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'name': 'eric',
      'groups': [3, 4, 5],
    });
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          and(
            field('groups').arrayContainsAny(array(constant(1), constant(5))),
            field(
              'groups',
            ).lessThan(array(constant(3), constant(4), constant(5))),
          ),
        );
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc1, doc2, doc4]);
  });

  test('arrayContainsAny with in', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'groups': [1, 2, 3],
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'groups': [1, 2, 4],
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'groups': [2, 3, 4],
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'name': 'diane',
      'groups': [2, 3, 5],
    });
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'name': 'eric',
      'groups': [3, 4, 5],
    });
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          and(
            field('groups').arrayContainsAny(array(constant(1), constant(5))),
            field('name').equalAny(array(constant('alice'), constant('bob'))),
          ),
        );
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc1, doc2]);
  });

  test('basic or', () {
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
    final documents = [doc1, doc2, doc3, doc4];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          or(
            field('name').equal(constant('bob')),
            field('age').equal(constant(10.0)),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc2, doc4]);
  });

  test('multiple or', () {
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
    final documents = [doc1, doc2, doc3, doc4];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          or(
            field('name').equal(constant('bob')),
            field('name').equal(constant('diane')),
            field('age').equal(constant(25.0)),
            field('age').equal(constant(100.0)),
          ),
        );
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc2, doc3, doc4]);
  });

  test('or multiple stages', () {
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
    final documents = [doc1, doc2, doc3, doc4];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          or(
            field('name').equal(constant('bob')),
            field('age').equal(constant(10.0)),
          ),
        )
        .where(
          or(
            field('name').equal(constant('diane')),
            field('age').equal(constant(100.0)),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([
      doc4,
    ]); // (name=bob OR age=10) AND (name=diane OR age=100)
  });

  test('or two conjunctions', () {
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
    final documents = [doc1, doc2, doc3, doc4];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          or(
            and(
              field('name').equal(constant('bob')),
              field('age').equal(constant(25.0)),
            ),
            and(
              field('name').equal(constant('diane')),
              field('age').equal(constant(10.0)),
            ),
          ),
        );
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc2, doc4]);
  });

  test('or with in and', () {
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
    final documents = [doc1, doc2, doc3, doc4];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          and(
            or(
              field('name').equal(constant('bob')),
              field('age').equal(constant(10.0)),
            ),
            field('age').lessThan(constant(80.0)),
          ),
        );
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc2, doc4]);
  });

  test('and of two ors', () {
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
    final documents = [doc1, doc2, doc3, doc4];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          and(
            or(
              field('name').equal(constant('bob')),
              field('age').equal(constant(10.0)),
            ),
            or(
              field('name').equal(constant('diane')),
              field('age').equal(constant(100.0)),
            ),
          ),
        );
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc4]);
  });

  test('or of two ors', () {
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
    final documents = [doc1, doc2, doc3, doc4];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          or(
            or(
              field('name').equal(constant('bob')),
              field('age').equal(constant(10.0)),
            ),
            or(
              field('name').equal(constant('diane')),
              field('age').equal(constant(100.0)),
            ),
          ),
        );
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc2, doc3, doc4]);
  });

  test('or with empty range in one disjunction', () {
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
    final documents = [doc1, doc2, doc3, doc4];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          or(
            field('name').equal(constant('bob')),
            and(
              field('age').equal(constant(10.0)),
              field('age').greaterThan(constant(20.0)),
            ),
          ),
        );
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc2]);
  });

  test('or with sort', () {
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
    final documents = [doc1, doc2, doc3, doc4];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          or(
            field('name').equal(constant('diane')),
            field('age').greaterThan(constant(20.0)),
          ),
        )
        .sort([field('age').ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc4, doc2, doc1, doc3]).inOrder();
  });

  test('or with inequality and sort same field', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25.0,
    }); // Not matched
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100.0,
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'name': 'diane',
      'age': 10.0,
    });
    final documents = [doc1, doc2, doc3, doc4];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          or(
            field('age').lessThan(constant(20.0)),
            field('age').greaterThan(constant(50.0)),
          ),
        )
        .sort([field('age').ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc4, doc1, doc3]).inOrder();
  });

  test('or with inequality and sort different fields', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25.0,
    }); // Not matched
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100.0,
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'name': 'diane',
      'age': 10.0,
    });
    final documents = [doc1, doc2, doc3, doc4];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          or(
            field('age').lessThan(constant(20.0)),
            field('age').greaterThan(constant(50.0)),
          ),
        )
        .sort([field('name').ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1, doc3, doc4]).inOrder();
  });

  test('or with inequality and sort multiple fields', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 25.0,
      'height': 170.0,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25.0,
      'height': 180.0,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100.0,
      'height': 155.0,
    }); // Not matched
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'name': 'diane',
      'age': 10.0,
      'height': 150.0,
    });
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'name': 'eric',
      'age': 25.0,
      'height': 170.0,
    });
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          or(
            field('age').lessThan(constant(80.0)),
            field('height').greaterThan(constant(160.0)),
          ),
        )
        .sort([
          field('age').ascending(),
          field('height').descending(),
          field('name').ascending(),
        ]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc4, doc2, doc1, doc5]).inOrder();
  });

  test('or with sort on partial missing field', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25.0,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'diane',
    }); // age missing
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'name': 'diane',
      'height': 150.0,
    }); // age missing
    final documents = [doc1, doc2, doc3, doc4];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          or(
            field('name').equal(constant('diane')),
            field('age').greaterThan(constant(20.0)),
          ),
        )
        .sort([field('age').ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc3, doc4, doc2, doc1]).inOrder();
  });

  test('or with limit', () {
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
    final documents = [doc1, doc2, doc3, doc4];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          or(
            field('name').equal(constant('diane')),
            field('age').greaterThan(constant(20.0)),
          ),
        )
        .sort([field('age').ascending()])
        .limit(2);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc4, doc2]).inOrder();
  });

  test('or eq null and eq on same field', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{'a': 1});
    final doc2 = doc('users/b', 1000, <String, Object?>{'a': 1.0});
    final doc3 = doc('users/c', 1000, <String, Object?>{'a': 1, 'b': 1});
    final doc4 = doc('users/d', 1000, <String, Object?>{'a': null});
    final doc5 = doc('users/e', 1000, <String, Object?>{'a': double.nan});
    final doc6 = doc('users/f', 1000, <String, Object?>{
      'b': 'abc',
    }); // 'a' missing
    final documents = [doc1, doc2, doc3, doc4, doc5, doc6];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          or(field('a').equal(constant(1)), field('a').equal(nullValue())),
        );

    final result = runPipeline(pipeline, documents);
    // C++ test expects 1.0 to match 1 in this context.
    // isNull matches explicit nulls.
    assertThat(result).containsExactlyElementsIn([doc1, doc2, doc3, doc4]);
  });

  test('or eq null and eq on different field', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{'a': 1});
    final doc2 = doc('users/b', 1000, <String, Object?>{'a': 1.0});
    final doc3 = doc('users/c', 1000, <String, Object?>{'a': 1, 'b': 1});
    final doc4 = doc('users/d', 1000, <String, Object?>{'a': null});
    final doc5 = doc('users/e', 1000, <String, Object?>{'a': double.nan});
    final doc6 = doc('users/f', 1000, <String, Object?>{'b': 'abc'});
    final documents = [doc1, doc2, doc3, doc4, doc5, doc6];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          or(field('b').equal(constant(1)), field('a').equal(nullValue())),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc3, doc4]);
  });

  test('or not eq null and eq on same field', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{'a': 1});
    final doc2 = doc('users/b', 1000, <String, Object?>{'a': 1.0});
    final doc3 = doc('users/c', 1000, <String, Object?>{'a': 1, 'b': 1});
    final doc4 = doc('users/d', 1000, <String, Object?>{'a': null});
    final doc5 = doc('users/e', 1000, <String, Object?>{'a': double.nan});
    final doc6 = doc('users/f', 1000, <String, Object?>{
      'b': 'abc',
    }); // 'a' missing
    final documents = [doc1, doc2, doc3, doc4, doc5, doc6];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          or(
            field('a').greaterThan(constant(1)),
            and(exists(field('a')), field('a').notEqual(nullValue())),
          ),
        );

    final result = runPipeline(pipeline, documents);
    // a > 1 (none) OR a IS NOT NULL (doc1, doc2, doc3, doc5)
    assertThat(result).containsExactlyElementsIn([doc1, doc2, doc3, doc5]);
  });

  test('or not eq null and eq on different field', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{'a': 1});
    final doc2 = doc('users/b', 1000, <String, Object?>{'a': 1.0});
    final doc3 = doc('users/c', 1000, <String, Object?>{'a': 1, 'b': 1});
    final doc4 = doc('users/d', 1000, <String, Object?>{'a': null});
    final doc5 = doc('users/e', 1000, <String, Object?>{'a': double.nan});
    final doc6 = doc('users/f', 1000, <String, Object?>{'b': 'abc'});
    final documents = [doc1, doc2, doc3, doc4, doc5, doc6];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          or(
            field('b').equal(constant(1)),
            and(exists(field('a')), field('a').notEqual(nullValue())),
          ),
        );

    final result = runPipeline(pipeline, documents);
    // b == 1 (doc3) OR a IS NOT NULL (doc1, doc2, doc3, doc5)
    assertThat(result).containsExactlyElementsIn([doc1, doc2, doc3, doc5]);
  });

  test('or eq null and eq NaN on same field', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{'a': null});
    final doc2 = doc('users/b', 1000, <String, Object?>{'a': double.nan});
    final doc3 = doc('users/c', 1000, <String, Object?>{'a': 'abc'});
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          or(
            field('a').equal(nullValue()),
            field('a').equal(constant(double.nan)),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc1, doc2]);
  });

  test('or eq null and eq NaN on different field', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{'a': null});
    final doc2 = doc('users/b', 1000, <String, Object?>{'a': double.nan});
    final doc3 = doc('users/c', 1000, <String, Object?>{'a': 'abc'});
    final doc4 = doc('users/d', 1000, <String, Object?>{'b': null});
    final doc5 = doc('users/e', 1000, <String, Object?>{'b': double.nan});
    final doc6 = doc('users/f', 1000, <String, Object?>{'b': 'abc'});
    final documents = [doc1, doc2, doc3, doc4, doc5, doc6];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          or(
            field('a').equal(nullValue()),
            field('b').equal(constant(double.nan)),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc1, doc5]);
  });

  test('basic notEqAny', () {
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
        .collection('/users')
        .where(
          field('name').notEqualAny(array(constant('alice'), constant('bob'))),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc3, doc4, doc5]);
  });

  test('multiple notEqAnys', () {
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
        .collection('/users')
        .where(
          and(
            field(
              'name',
            ).notEqualAny(array(constant('alice'), constant('bob'))),
            field('age').notEqualAny(array(constant(10.0), constant(25.0))),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc3]);
  });

  test('multiple notEqAnys with or', () {
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
        .collection('/users')
        .where(
          or(
            field(
              'name',
            ).notEqualAny(array(constant('alice'), constant('bob'))),
            field('age').notEqualAny(array(constant(10.0), constant(25.0))),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc1, doc3, doc4, doc5]);
  });

  test('notEqAny on collectionGroup', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('other_users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25.0,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100.0,
    });
    final doc4 = doc('root/child/users/d', 1000, <String, Object?>{
      'name': 'diane',
      'age': 10.0,
    });
    final doc5 = doc('root/child/other_users/e', 1000, <String, Object?>{
      'name': 'eric',
      'age': 10.0,
    });
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collectionGroup('users')
        .where(
          field('name').notEqualAny(
            array(constant('alice'), constant('bob'), constant('diane')),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc3]);
  });

  test('notEqAny with sort', () {
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
        .collection('/users')
        .where(
          field(
            'name',
          ).notEqualAny(array(constant('alice'), constant('diane'))),
        )
        .sort([field('age').ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc5, doc2, doc3]).inOrder();
  });

  test('notEqAny with additional equality different fields', () {
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
        .collection('/users')
        .where(
          and(
            field(
              'name',
            ).notEqualAny(array(constant('alice'), constant('bob'))),
            field('age').equal(constant(10.0)),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc4, doc5]);
  });

  test('notEqAny with additional equality same field', () {
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
        .collection('/users')
        .where(
          and(
            field(
              'name',
            ).notEqualAny(array(constant('alice'), constant('diane'))),
            field('name').equal(constant('eric')),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc5]);
  });

  test('notEqAny with inequalities exclusive range', () {
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
        .collection('/users')
        .where(
          and(
            field(
              'name',
            ).notEqualAny(array(constant('alice'), constant('charlie'))),
            field('age').greaterThan(constant(10.0)),
            field('age').lessThan(constant(100.0)),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc2]);
  });

  test('notEqAny with inequalities inclusive range', () {
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
        .collection('/users')
        .where(
          and(
            field('name').notEqualAny(
              array(constant('alice'), constant('bob'), constant('eric')),
            ),
            field('age').greaterThanOrEqual(constant(10.0)),
            field('age').lessThanOrEqual(constant(100.0)),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc3, doc4]);
  });

  test('notEqAny with inequalities and sort', () {
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
        .collection('/users')
        .where(
          and(
            field(
              'name',
            ).notEqualAny(array(constant('alice'), constant('diane'))),
            field('age').greaterThan(constant(10.0)),
            field('age').lessThanOrEqual(constant(100.0)),
          ),
        )
        .sort([field('age').ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc2, doc3]).inOrder();
  });

  test('notEqAny with notEqual', () {
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
        .collection('/users')
        .where(
          and(
            field(
              'name',
            ).notEqualAny(array(constant('alice'), constant('bob'))),
            field('age').notEqual(constant(100.0)),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc4, doc5]);
  });

  test('notEqAny sort on notEqAny field', () {
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
        .collection('/users')
        .where(
          field('name').notEqualAny(array(constant('alice'), constant('bob'))),
        )
        .sort([field('name').ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc3, doc4, doc5]).inOrder();
  });

  test('notEqAny single value sort on notEqAny field ambiguous order', () {
    final doc1 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100.0,
    });
    final doc2 = doc('users/d', 1000, <String, Object?>{
      'name': 'diane',
      'age': 10.0,
    });
    final doc3 = doc('users/e', 1000, <String, Object?>{
      'name': 'eric',
      'age': 10.0,
    });
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(field('age').notEqualAny(array(constant(100.0))))
        .sort([field('age').ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(
      result,
    ).containsExactly([doc2, doc3]).inOrder(); // Sorted by key after age
  });

  test('notEqAny with extra equality sort on notEqAny field', () {
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
        .collection('/users')
        .where(
          and(
            field(
              'name',
            ).notEqualAny(array(constant('alice'), constant('bob'))),
            field('age').equal(constant(10.0)),
          ),
        )
        .sort([field('name').ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc4, doc5]).inOrder();
  });

  test('notEqAny with extra equality sort on equality', () {
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
        .collection('/users')
        .where(
          and(
            field(
              'name',
            ).notEqualAny(array(constant('alice'), constant('bob'))),
            field('age').equal(constant(10.0)),
          ),
        )
        .sort([field('age').ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(
      result,
    ).containsExactly([doc4, doc5]).inOrder(); // Sorted by key after age
  });

  test('notEqAny with inequality on same field', () {
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
        .collection('/users')
        .where(
          and(
            field('age').notEqualAny(array(constant(10.0), constant(100.0))),
            field('age').greaterThan(constant(20.0)),
          ),
        )
        .sort([field('age').ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc2, doc1]).inOrder();
  });

  test('notEqAny with different inequality sort on in field', () {
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
        .collection('/users')
        .where(
          and(
            field(
              'name',
            ).notEqualAny(array(constant('alice'), constant('diane'))),
            field('age').greaterThan(constant(20.0)),
          ),
        )
        .sort([
          field('age').ascending(),
        ]); // C++ test sorts by age (inequality field)

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc2, doc3]).inOrder();
  });

  test('no limit on num of disjunctions', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 25.0,
      'height': 170.0,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25.0,
      'height': 180.0,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100.0,
      'height': 155.0,
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'name': 'diane',
      'age': 10.0,
      'height': 150.0,
    });
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'name': 'eric',
      'age': 25.0,
      'height': 170.0,
    });
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          // Kotlin's or() takes any number of conditions; here the method.
          field('name').equal(constant('alice')).or(
            field('name').equal(constant('bob')),
            [
              field('name').equal(constant('charlie')),
              field('name').equal(constant('diane')),
              field('age').equal(constant(10.0)),
              field('age').equal(constant(25.0)),
              field('age').equal(constant(40.0)), // No doc matches this
              field('age').equal(constant(100.0)),
              field('height').equal(constant(150.0)),
              field('height').equal(constant(160.0)), // No doc matches this
              field('height').equal(constant(170.0)),
              field('height').equal(constant(180.0)),
            ],
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(
      result,
    ).containsExactlyElementsIn([doc1, doc2, doc3, doc4, doc5]);
  });

  test('eqAny duplicate values', () {
    final doc1 = doc('users/bob', 1000, <String, Object?>{'score': 90});
    final doc2 = doc('users/alice', 1000, <String, Object?>{'score': 50});
    final doc3 = doc('users/charlie', 1000, <String, Object?>{'score': 97});
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          field('score').equalAny(
            array(constant(50), constant(97), constant(97), constant(97)),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc2, doc3]);
  });

  test('notEqAny duplicate values', () {
    final doc1 = doc('users/bob', 1000, <String, Object?>{'score': 90});
    final doc2 = doc('users/alice', 1000, <String, Object?>{'score': 50});
    final doc3 = doc('users/charlie', 1000, <String, Object?>{'score': 97});
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(field('score').notEqualAny(array(constant(50), constant(50))));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc1, doc3]);
  });

  test('arrayContainsAny duplicate values', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'scores': [1, 2, 3],
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'scores': [4, 5, 6],
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'scores': [7, 8, 9],
    });
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          field('scores').arrayContainsAny(
            array(constant(1), constant(2), constant(2), constant(2)),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('arrayContainsAll duplicate values', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'scores': [1, 2, 3],
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'scores': [1, 2, 2, 2, 3],
    });
    final documents = [doc1, doc2];

    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(
          field('scores').arrayContainsAll(
            array(
              constant(1),
              constant(2),
              constant(2),
              constant(2),
              constant(3),
            ),
          ),
        );
    final result = runPipeline(pipeline, documents);
    // The C++ test `EXPECT_THAT(RunPipeline(pipeline, documents), ElementsAre(doc1, doc2));`
    // indicates an ordered check. Aligning with this.
    assertThat(result).containsExactly([doc1, doc2]).inOrder();
  });
}
