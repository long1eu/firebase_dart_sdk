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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/CollectionGroupTests.kt
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
  test('returns no result from empty db', () {
    final pipeline = RealtimePipelineSource().collectionGroup('users');
    final documents = <TestDocument>[];
    final result = runPipeline(pipeline, documents);
    assertThat(result).isEmpty();
  });

  test('returns single document', () {
    final pipeline = RealtimePipelineSource().collectionGroup('users');
    final doc1 = doc('users/bob', 1000, <String, Object?>{
      'score': 90,
      'rank': 1,
    });
    final documents = [doc1];
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('returns multiple documents', () {
    final pipeline = RealtimePipelineSource().collectionGroup('users');
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
    final documents = [doc1, doc2, doc3];
    final result = runPipeline(pipeline, documents);
    // Expected order by key: alice, bob, charlie
    assertThat(result).containsExactly([doc2, doc1, doc3]).inOrder();
  });

  test('skips other collection ids', () {
    final pipeline = RealtimePipelineSource().collectionGroup('users');
    final doc1 = doc('users/bob', 1000, <String, Object?>{'score': 90});
    final doc2 = doc('users-other/bob', 1000, <String, Object?>{'score': 90});
    final doc3 = doc('users/alice', 1000, <String, Object?>{'score': 50});
    final doc4 = doc('users-other/alice', 1000, <String, Object?>{'score': 50});
    final doc5 = doc('users/charlie', 1000, <String, Object?>{'score': 97});
    final doc6 = doc('users-other/charlie', 1000, <String, Object?>{
      'score': 97,
    });
    final documents = [doc1, doc2, doc3, doc4, doc5, doc6];
    final expectedDocs = [
      doc3,
      doc1,
      doc5,
    ]; // Expected order by key: alice, bob, charlie (from 'users' only)
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn(expectedDocs).inOrder();
  });

  test('skips docs with collection group in parent path', () {
    final pipeline = RealtimePipelineSource().collectionGroup('users');

    final doc1 = doc('users/alice', 1000, <String, Object?>{'score': 50});
    final doc2 = doc('users/bob/games/halo', 1000, <String, Object?>{
      'score': 90,
    });
    final doc3 = doc('users/charlie', 1000, <String, Object?>{'score': 97});
    final doc4 = doc('users/david/games/halo/play/1', 1000, <String, Object?>{
      'score': 90,
    });
    final doc5 = doc('games/halo/users/david/play/1', 1000, <String, Object?>{
      'score': 90,
    });

    final documents = [doc1, doc2, doc3, doc4, doc5];
    final expectedDocs = [doc1, doc3];

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn(expectedDocs).inOrder();
  });

  test('skips docs with collection group in parent path with in on name', () {
    final doc1 = doc('users/charlie', 1000, <String, Object?>{'score': 97});
    final doc2 = doc('users/david/games/halo', 1000, <String, Object?>{
      'score': 90,
    });
    // Extra doc that should be filtered out by query
    final doc3 = doc('users/alice', 1000, <String, Object?>{'score': 50});

    final pipeline = RealtimePipelineSource()
        .collectionGroup('users')
        .where(
          equalAny(
            Field.of(FieldPath.documentIdField),
            array(
              constant(ref(doc1.key.path.canonicalString)),
              constant(ref(doc2.key.path.canonicalString)),
            ),
          ),
        );

    final documents = [doc1, doc2, doc3];
    final expectedDocs = [doc1];

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn(expectedDocs);
  });

  test('duplicate collection name', () {
    final pipeline = RealtimePipelineSource().collectionGroup('matches');

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
    final doc4 = doc(
      'users/not-alice/matches/1/opponents/bob/matches/2',
      1000,
      <String, Object?>{'score': 90},
    );

    final documents = [doc1, doc2, doc3, doc4];
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn(documents);
  });

  test('different parents', () {
    final pipeline = RealtimePipelineSource().collectionGroup('games').sort([
      field('order').ascending(),
    ]);
    final doc1 = doc('users/bob/games/game1', 1000, <String, Object?>{
      'score': 90,
      'order': 1,
    });
    final doc2 = doc('users/alice/games/game1', 1000, <String, Object?>{
      'score': 90,
      'order': 2,
    });
    final doc3 = doc('users/bob/games/game2', 1000, <String, Object?>{
      'score': 20,
      'order': 3,
    });
    final doc4 = doc('users/charlie/games/game1', 1000, <String, Object?>{
      'score': 20,
      'order': 4,
    });
    final doc5 = doc('users/bob/games/game3', 1000, <String, Object?>{
      'score': 30,
      'order': 5,
    });
    final doc6 = doc('users/alice/games/game2', 1000, <String, Object?>{
      'score': 30,
      'order': 6,
    });
    final doc7 = doc('users/charlie/profiles/profile1', 1000, <String, Object?>{
      'order': 7,
    }); // Different collection ID

    final documents = [doc1, doc2, doc3, doc4, doc5, doc6, doc7];
    final expectedDocs = [doc1, doc2, doc3, doc4, doc5, doc6];
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn(expectedDocs).inOrder();
  });

  test('different parents stable ordering on path', () {
    final pipeline = RealtimePipelineSource().collectionGroup('games').sort([
      Field.of(FieldPath.documentIdField).ascending(),
    ]);

    final doc1 = doc('users/bob/games/1', 1000, <String, Object?>{'score': 90});
    final doc2 = doc('users/alice/games/2', 1000, <String, Object?>{
      'score': 90,
    });
    final doc3 = doc('users/bob/games/3', 1000, <String, Object?>{'score': 20});
    final doc4 = doc('users/charlie/games/4', 1000, <String, Object?>{
      'score': 20,
    });
    final doc5 = doc('users/bob/games/5', 1000, <String, Object?>{'score': 30});
    final doc6 = doc('users/alice/games/6', 1000, <String, Object?>{
      'score': 30,
    });
    final doc7 = doc(
      'users/charlie/profiles/7',
      1000,
      <String, Object?>{},
    ); // Different collection ID

    final documents = [doc1, doc2, doc3, doc4, doc5, doc6, doc7];
    // Expected order:
    // users/alice/games/2
    // users/alice/games/6
    // users/bob/games/1
    // users/bob/games/3
    // users/bob/games/5
    // users/charlie/games/4
    final expectedDocs = [doc2, doc6, doc1, doc3, doc5, doc4];
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn(expectedDocs).inOrder();
  });

  test('different parents stable ordering on key', () {
    // This test is identical to DifferentParentsStableOrderingOnPath
    final pipeline = RealtimePipelineSource().collectionGroup('games').sort([
      Field.of(FieldPath.documentIdField).ascending(),
    ]);

    final doc1 = doc('users/bob/games/1', 1000, <String, Object?>{'score': 90});
    final doc2 = doc('users/alice/games/2', 1000, <String, Object?>{
      'score': 90,
    });
    final doc3 = doc('users/bob/games/3', 1000, <String, Object?>{'score': 20});
    final doc4 = doc('users/charlie/games/4', 1000, <String, Object?>{
      'score': 20,
    });
    final doc5 = doc('users/bob/games/5', 1000, <String, Object?>{'score': 30});
    final doc6 = doc('users/alice/games/6', 1000, <String, Object?>{
      'score': 30,
    });
    final doc7 = doc(
      'users/charlie/profiles/7',
      1000,
      <String, Object?>{},
    ); // Different collection ID

    final documents = [doc1, doc2, doc3, doc4, doc5, doc6, doc7];
    final expectedDocs = [doc2, doc6, doc1, doc3, doc5, doc4];
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn(expectedDocs).inOrder();
  });

  test('where on values', () {
    final pipeline = RealtimePipelineSource()
        .collectionGroup('users')
        .where(equalAny(field('score'), array(90, 97)));

    final doc1 = doc('users/bob', 1000, <String, Object?>{'score': 90});
    final doc2 = doc('users/alice', 1000, <String, Object?>{'score': 50});
    final doc3 = doc('users/charlie', 1000, <String, Object?>{'score': 97});
    final doc4 = doc('users/diane', 1000, <String, Object?>{'score': 97});
    final doc5 = doc('profiles/admin/users/bob', 1000, <String, Object?>{
      'score': 90,
    }); // Different path, same collection ID

    final documents = [doc1, doc2, doc3, doc4, doc5];
    // Expected: bob(profiles), bob(users), charlie(users), diane(users) - sorted by key
    final expectedDocs = [doc5, doc1, doc3, doc4];
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn(expectedDocs).inOrder();
  });

  test('where inequality on values', () {
    final pipeline = RealtimePipelineSource()
        .collectionGroup('users')
        .where(greaterThan(field('score'), 80));

    final doc1 = doc('users/bob', 1000, <String, Object?>{'score': 90});
    final doc2 = doc('users/alice', 1000, <String, Object?>{'score': 50});
    final doc3 = doc('users/charlie', 1000, <String, Object?>{'score': 97});
    final doc4 = doc('profiles/admin/users/bob', 1000, <String, Object?>{
      'score': 90,
    }); // Different path

    final documents = [doc1, doc2, doc3, doc4];
    // Expected: bob(profiles), bob(users), charlie(users) - sorted by key
    final expectedDocs = [doc4, doc1, doc3];
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn(expectedDocs).inOrder();
  });

  test('where not equal on values', () {
    final pipeline = RealtimePipelineSource()
        .collectionGroup('users')
        .where(notEqual(field('score'), 50));

    final doc1 = doc('users/bob', 1000, <String, Object?>{'score': 90});
    final doc2 = doc('users/alice', 1000, <String, Object?>{
      'score': 50,
    }); // This will be filtered out
    final doc3 = doc('users/charlie', 1000, <String, Object?>{'score': 97});
    final doc4 = doc('profiles/admin/users/bob', 1000, <String, Object?>{
      'score': 90,
    }); // Different path

    final documents = [doc1, doc2, doc3, doc4];
    // Expected: bob(profiles), bob(users), charlie(users) - sorted by key
    final expectedDocs = [doc4, doc1, doc3];
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn(expectedDocs).inOrder();
  });

  test('where array contains values', () {
    final pipeline = RealtimePipelineSource()
        .collectionGroup('users')
        .where(arrayContains(field('rounds'), 'round3'));

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
    final doc4 = doc('profiles/admin/users/bob', 1000, <String, Object?>{
      'score': 90,
      'rounds': ['round1', 'round3'],
    }); // Different path

    final documents = [doc1, doc2, doc3, doc4];
    // Expected: bob(profiles), bob(users), charlie(users) - sorted by key
    final expectedDocs = [doc4, doc1, doc3];
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn(expectedDocs).inOrder();
  });

  test('sort on values', () {
    final pipeline = RealtimePipelineSource().collectionGroup('users').sort([
      field('score').descending(),
    ]);

    final doc1 = doc('users/bob', 1000, <String, Object?>{'score': 90});
    final doc2 = doc('users/alice', 1000, <String, Object?>{'score': 50});
    final doc3 = doc('users/charlie', 1000, <String, Object?>{'score': 97});
    final doc4 = doc('profiles/admin/users/bob', 1000, <String, Object?>{
      'score': 90,
    }); // Different path

    final documents = [doc1, doc2, doc3, doc4];
    // Expected: charlie(97), bob(profiles, 90), bob(users, 90), alice(50)
    // Tie is broken by document key (ascending), where 'profiles/admin/users/bob' (doc4)
    // comes before 'users/bob' (doc1).
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc3, doc4, doc1, doc2]).inOrder();
  });

  test('sort on values has dense semantics', () {
    final pipeline = RealtimePipelineSource().collectionGroup('users').sort([
      field('score').descending(),
    ]);

    final doc1 = doc('users/bob', 1000, <String, Object?>{'score': 90});
    final doc2 = doc('users/alice', 1000, <String, Object?>{'score': 50});
    final doc3 = doc('users/charlie', 1000, <String, Object?>{
      'number': 97,
    }); // Missing 'score'
    final doc4 = doc('profiles/admin/users/bob', 1000, <String, Object?>{
      'score': 90,
    }); // Different path

    final documents = [doc1, doc2, doc3, doc4];
    // Missing fields sort last in descending order (or first in ascending).
    // So, charlie (doc3) with missing 'score' comes after alice (doc2) with score 50.
    // Order for scores: 90, 90, 50, missing.
    final expectedDocs = [doc4, doc1, doc2, doc3];
    final result = runPipeline(pipeline, documents);
    // Tie for 'score' is broken by document key (ascending), where 'profiles/admin/users/bob'
    // (doc4)
    // comes before 'users/bob' (doc1). Documents with missing 'score' (doc3) sort after
    // documents with 'score' when sorting descending by 'score'.
    assertThat(result).containsExactly([doc4, doc1, doc2, doc3]).inOrder();
  });

  test('sort on path', () {
    final pipeline = RealtimePipelineSource().collectionGroup('users').sort([
      Field.of(FieldPath.documentIdField).ascending(),
    ]);

    final doc1 = doc('users/bob', 1000, <String, Object?>{'score': 90});
    final doc2 = doc('users/alice', 1000, <String, Object?>{'score': 50});
    final doc3 = doc('users/charlie', 1000, <String, Object?>{'score': 97});
    final doc4 = doc('profiles/admin/users/bob', 1000, <String, Object?>{
      'score': 90,
    }); // Different path

    final documents = [doc1, doc2, doc3, doc4];
    // Expected: sorted by path:
    // profiles/admin/users/bob (doc4)
    // users/alice (doc2)
    // users/bob (doc1)
    // users/charlie (doc3)
    final expectedDocs = [doc4, doc2, doc1, doc3];
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn(expectedDocs).inOrder();
  });

  test('limit', () {
    final pipeline = RealtimePipelineSource()
        .collectionGroup('users')
        .sort([Field.of(FieldPath.documentIdField).ascending()])
        .limit(2);

    final doc1 = doc('users/bob', 1000, <String, Object?>{'score': 90});
    final doc2 = doc('users/alice', 1000, <String, Object?>{'score': 50});
    final doc3 = doc('users/charlie', 1000, <String, Object?>{'score': 97});
    final doc4 = doc('profiles/admin/users/bob', 1000, <String, Object?>{
      'score': 90,
    }); // Different path

    final documents = [doc1, doc2, doc3, doc4];
    // Expected: sorted by path, then limited:
    // profiles/admin/users/bob (doc4)
    // users/alice (doc2)
    final expectedDocs = [doc4, doc2];
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn(expectedDocs).inOrder();
  });
}
