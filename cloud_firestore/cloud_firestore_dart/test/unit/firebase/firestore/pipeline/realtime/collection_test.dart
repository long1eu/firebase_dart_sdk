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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/CollectionTests.kt
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
  test('empty database returns no results', () {
    final pipeline = RealtimePipelineSource().collection('/users');
    final inputDocs = <TestDocument>[];
    final result = runPipeline(pipeline, inputDocs);
    assertThat(result).isEmpty();
  });

  test('empty collection other collection ids returns no results', () {
    final pipeline = RealtimePipelineSource().collection('/users/bob/games');
    final doc1 = doc('users/alice/games/doc1', 1000, <String, Object?>{
      'title': 'minecraft',
    });
    final doc2 = doc('users/charlie/games/doc1', 1000, <String, Object?>{
      'title': 'halo',
    });
    final inputDocs = [doc1, doc2];
    final result = runPipeline(pipeline, inputDocs);
    assertThat(result).isEmpty();
  });

  test('empty collection other parents returns no results', () {
    final pipeline = RealtimePipelineSource().collection('/users/bob/games');
    final doc1 = doc('users/bob/addresses/doc1', 1000, <String, Object?>{
      'city': 'New York',
    });
    final doc2 = doc('users/bob/inventories/doc1', 1000, <String, Object?>{
      'item_id': 42,
    });
    final inputDocs = [doc1, doc2];
    final result = runPipeline(pipeline, inputDocs);
    assertThat(result).isEmpty();
  });

  test('singleton at root returns single document', () {
    final pipeline = RealtimePipelineSource().collection('/users');
    final doc1 = doc('games/42', 1000, <String, Object?>{'title': 'minecraft'});
    final doc2 = doc('users/bob', 1000, <String, Object?>{
      'score': 90,
      'rank': 1,
    });
    final inputDocs = [doc1, doc2];
    final result = runPipeline(pipeline, inputDocs);
    assertThat(result).containsExactly([doc2]);
  });

  test('singleton nested collection returns single document', () {
    final pipeline = RealtimePipelineSource().collection('/users/bob/games');
    final doc1 = doc('users/bob/addresses/doc1', 1000, <String, Object?>{
      'city': 'New York',
    });
    final doc2 = doc('users/bob/games/doc1', 1000, <String, Object?>{
      'title': 'minecraft',
    });
    final doc3 = doc('users/alice/games/doc1', 1000, <String, Object?>{
      'title': 'halo',
    });
    final inputDocs = [doc1, doc2, doc3];
    final result = runPipeline(pipeline, inputDocs);
    assertThat(result).containsExactly([doc2]);
  });

  test('multiple documents at root returns documents', () {
    final pipeline = RealtimePipelineSource().collection('/users');
    final doc1 = doc('users/bob', 1000, <String, Object?>{
      'score': 90,
      'rank': 1,
    });
    final doc2 = doc('users/alice', 1000, <String, Object?>{
      'score': 50,
      'rank': 3,
    });
    final doc3 = doc('users/charlie', 1000, <String, Object?>{
      'score': 97,
      'rank': 2,
    });
    final doc4 = doc('games/doc1', 1000, <String, Object?>{
      'title': 'minecraft',
    });
    final inputDocs = [doc1, doc2, doc3, doc4];
    // Firestore backend sorts by document key as a tie-breaker.
    final result = runPipeline(pipeline, inputDocs);
    assertThat(result).containsExactly([doc2, doc1, doc3]);
  });

  test('multiple documents nested collection returns documents', () {
    // This test seems identical to MultipleDocumentsAtRootReturnsDocuments in C++?
    // Replicating the C++ test name and logic.
    final pipeline = RealtimePipelineSource().collection('/users');
    final doc1 = doc('users/bob', 1000, <String, Object?>{
      'score': 90,
      'rank': 1,
    });
    final doc2 = doc('users/alice', 1000, <String, Object?>{
      'score': 50,
      'rank': 3,
    });
    final doc3 = doc('users/charlie', 1000, <String, Object?>{
      'score': 97,
      'rank': 2,
    });
    final doc4 = doc('games/doc1', 1000, <String, Object?>{
      'title': 'minecraft',
    });
    final inputDocs = [doc1, doc2, doc3, doc4];
    final result = runPipeline(pipeline, inputDocs);
    assertThat(result).containsExactly([doc2, doc1, doc3]);
  });

  test('subcollection not returned', () {
    final pipeline = RealtimePipelineSource().collection('/users');
    final doc1 = doc('users/bob', 1000, <String, Object?>{
      'score': 90,
      'rank': 1,
    });
    final doc2 = doc('users/bob/games/minecraft', 1000, <String, Object?>{
      'title': 'minecraft',
    });
    final doc3 = doc(
      'users/bob/games/minecraft/players/player1',
      1000,
      <String, Object?>{'location': 'sf'},
    );
    final inputDocs = [doc1, doc2, doc3];
    final result = runPipeline(pipeline, inputDocs);
    assertThat(result).containsExactly([doc1]);
  });

  test('skips other collection ids', () {
    final pipeline = RealtimePipelineSource().collection('/users');
    final doc1 = doc('users/bob', 1000, <String, Object?>{
      'score': 90,
      'rank': 1,
    });
    final doc2 = doc('users-other/bob', 1000, <String, Object?>{
      'score': 90,
      'rank': 1,
    });
    final doc3 = doc('users/alice', 1000, <String, Object?>{
      'score': 50,
      'rank': 3,
    });
    final doc4 = doc('users-other/alice', 1000, <String, Object?>{
      'score': 50,
      'rank': 3,
    });
    final doc5 = doc('users/charlie', 1000, <String, Object?>{
      'score': 97,
      'rank': 2,
    });
    final doc6 = doc('users-other/charlie', 1000, <String, Object?>{
      'score': 97,
      'rank': 2,
    });
    final inputDocs = [doc1, doc2, doc3, doc4, doc5, doc6];
    final result = runPipeline(pipeline, inputDocs);
    assertThat(result).containsExactly([doc3, doc1, doc5]);
  });

  test('skips other parents', () {
    final pipeline = RealtimePipelineSource().collection('/users/bob/games');
    final doc1 = doc('users/bob/games/doc1', 1000, <String, Object?>{
      'score': 90,
    });
    final doc2 = doc('users/alice/games/doc1', 1000, <String, Object?>{
      'score': 90,
    });
    final doc3 = doc('users/bob/games/doc2', 1000, <String, Object?>{
      'score': 20,
    });
    final doc4 = doc('users/charlie/games/doc1', 1000, <String, Object?>{
      'score': 20,
    });
    final doc5 = doc('users/bob/games/doc3', 1000, <String, Object?>{
      'score': 30,
    });
    final doc6 = doc('users/alice/games/doc1', 1000, <String, Object?>{
      'score': 30,
    });
    final inputDocs = [doc1, doc2, doc3, doc4, doc5, doc6];
    // Expected order based on key for user bob's games
    final result = runPipeline(pipeline, inputDocs);
    assertThat(result).containsExactly([doc1, doc3, doc5]).inOrder();
  });

  // --- Where Tests ---
  test('where on values', () {
    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(equalAny(field('score'), array(constant(90), constant(97))));

    final doc1 = doc('users/bob', 1000, <String, Object?>{'score': 90});
    final doc2 = doc('users/alice', 1000, <String, Object?>{'score': 50});
    final doc3 = doc('users/charlie', 1000, <String, Object?>{'score': 97});
    final doc4 = doc('users/diane', 1000, <String, Object?>{'score': 97});
    final inputDocs = [doc1, doc2, doc3, doc4];
    final result = runPipeline(pipeline, inputDocs);
    assertThat(result).containsExactly([doc1, doc3, doc4]);
  });

  test('where inequality on values', () {
    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(field('score').greaterThan(80));

    final doc1 = doc('users/bob', 1000, <String, Object?>{'score': 90});
    final doc2 = doc('users/alice', 1000, <String, Object?>{'score': 50});
    final doc3 = doc('users/charlie', 1000, <String, Object?>{'score': 97});
    final inputDocs = [doc1, doc2, doc3];
    final result = runPipeline(pipeline, inputDocs);
    assertThat(result).containsExactly([doc1, doc3]);
  });

  test('where not equal on values', () {
    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(field('score').notEqual(50));

    final doc1 = doc('users/bob', 1000, <String, Object?>{'score': 90});
    final doc2 = doc('users/alice', 1000, <String, Object?>{'score': 50});
    final doc3 = doc('users/charlie', 1000, <String, Object?>{'score': 97});
    final inputDocs = [doc1, doc2, doc3];
    final result = runPipeline(pipeline, inputDocs);
    assertThat(result).containsExactly([doc1, doc3]);
  });

  test('where array contains values', () {
    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .where(field('rounds').arrayContains(constant('round3')));

    final doc1 = doc('users/bob', 1000, <String, Object?>{
      'score': 90,
      'rounds': ['round1', 'round3'],
    });
    final doc2 = doc('users/alice', 1000, <String, Object?>{
      'score': 50,
      'rounds': ['round2', 'round4'],
    });
    final doc3 = doc('users/charlie', 1000, <String, Object?>{
      'score': 97,
      'rounds': ['round2', 'round3', 'round4'],
    });
    final inputDocs = [doc1, doc2, doc3];
    final result = runPipeline(pipeline, inputDocs);
    assertThat(result).containsExactly([doc1, doc3]);
  });

  // --- Sort Tests ---
  test('sort on values', () {
    final pipeline = RealtimePipelineSource().collection('/users').sort([
      field('score').descending(),
    ]);

    final doc1 = doc('users/bob', 1000, <String, Object?>{'score': 90});
    final doc2 = doc('users/alice', 1000, <String, Object?>{'score': 50});
    final doc3 = doc('users/charlie', 1000, <String, Object?>{'score': 97});
    final inputDocs = [doc1, doc2, doc3];
    final result = runPipeline(pipeline, inputDocs);
    assertThat(result).containsExactly([doc3, doc1, doc2]).inOrder();
  });

  test('sort on path', () {
    final pipeline = RealtimePipelineSource().collection('/users').sort([
      Field.of(FieldPath.documentIdField).ascending(),
    ]);

    final doc1 = doc('users/bob', 1000, <String, Object?>{'score': 90});
    final doc2 = doc('users/alice', 1000, <String, Object?>{'score': 50});
    final doc3 = doc('users/charlie', 1000, <String, Object?>{'score': 97});
    final inputDocs = [doc1, doc2, doc3];
    final result = runPipeline(pipeline, inputDocs);
    assertThat(result).containsExactly([doc2, doc1, doc3]).inOrder();
  });

  // --- Limit Tests ---
  test('limit', () {
    final pipeline = RealtimePipelineSource()
        .collection('/users')
        .sort([Field.of(FieldPath.documentIdField).ascending()])
        .limit(2);

    final doc1 = doc('users/bob', 1000, <String, Object?>{'score': 90});
    final doc2 = doc('users/alice', 1000, <String, Object?>{'score': 50});
    final doc3 = doc('users/charlie', 1000, <String, Object?>{'score': 97});
    final inputDocs = [doc1, doc2, doc3];
    final result = runPipeline(pipeline, inputDocs);
    assertThat(result).containsExactly([doc2, doc1]).inOrder();
  });

  // --- Sort on Key Tests ---
  test('sort on key ascending', () {
    final pipeline = RealtimePipelineSource()
        .collection('/users/bob/games')
        .sort([Field.of(FieldPath.documentIdField).ascending()]);

    final doc1 = doc('users/bob/games/a', 1000, <String, Object?>{
      'title': 'minecraft',
    });
    final doc2 = doc('users/bob/games/b', 1000, <String, Object?>{
      'title': 'halo',
    });
    final doc3 = doc('users/bob/games/c', 1000, <String, Object?>{
      'title': 'mariocart',
    });
    final doc4 = doc('users/bob/inventories/a', 1000, <String, Object?>{
      'type': 'sword',
    });
    final doc5 = doc('users/alice/games/c', 1000, <String, Object?>{
      'title': 'skyrim',
    });
    final inputDocs = [doc1, doc2, doc3, doc4, doc5];
    final result = runPipeline(pipeline, inputDocs);
    assertThat(result).containsExactly([doc1, doc2, doc3]).inOrder();
  });

  test('sort on key descending', () {
    final pipeline = RealtimePipelineSource()
        .collection('/users/bob/games')
        .sort([Field.of(FieldPath.documentIdField).descending()]);

    final doc1 = doc('users/bob/games/a', 1000, <String, Object?>{
      'title': 'minecraft',
    });
    final doc2 = doc('users/bob/games/b', 1000, <String, Object?>{
      'title': 'halo',
    });
    final doc3 = doc('users/bob/games/c', 1000, <String, Object?>{
      'title': 'mariocart',
    });
    final doc4 = doc('users/bob/inventories/a', 1000, <String, Object?>{
      'type': 'sword',
    });
    final doc5 = doc('users/alice/games/c', 1000, <String, Object?>{
      'title': 'skyrim',
    });
    final inputDocs = [doc1, doc2, doc3, doc4, doc5];
    final result = runPipeline(pipeline, inputDocs);
    assertThat(result).containsExactly([doc3, doc2, doc1]).inOrder();
  });

  test('duplicate collection name', () {
    final pipeline = RealtimePipelineSource().collection(
      '/users/alice/matches/1/opponents/bob/matches',
    );
    final doc1 = doc(
      'users/alice/matches/1/opponents/bob/matches/1',
      1000,
      <String, Object?>{'score': 90},
    );
    final doc2 = doc(
      'users/alice/matches/1/opponents/bob/matches/2',
      1000,
      <String, Object?>{'score': 90},
    );
    final doc3 = doc(
      'users/not-alice/matches/1/opponents/bob/matches/1',
      1000,
      <String, Object?>{'score': 90},
    );
    final inputDocs = [doc1, doc2, doc3];
    final result = runPipeline(pipeline, inputDocs);
    assertThat(result).containsExactly([doc1, doc2]);
  });
}
