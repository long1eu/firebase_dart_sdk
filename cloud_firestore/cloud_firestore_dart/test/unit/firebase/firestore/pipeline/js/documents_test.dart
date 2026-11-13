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

// Ported from the JS SDK:
// packages/firestore/test/unit/core/pipeline/documents.test.ts
//
// The cases keep their JS names; js_pipeline_test_util.dart has the
// functions they call. JS numbers that are integral (1.0) are integers here,
// as the JS SDK encodes them. `docRef(db, path)` is the path: Dart's
// `documents()` takes paths.

// ignore_for_file: prefer_single_quotes, always_specify_types
// ignore_for_file: lines_longer_than_80_chars, prefer_final_locals
// ignore_for_file: omit_local_variable_types, unused_local_variable
// ignore_for_file: prefer_const_declarations, prefer_const_constructors

// The documents hold doubles and 64-bit integers, which compiled to
// JavaScript are not what they are on the VM.
@TestOn('vm')
library;

import 'package:test/test.dart' show TestOn, test;

import 'js_pipeline_test_util.dart';

void main() {
  test('emptyRequest_isRejected', () {
    expectThat(() => runPipeline(db.pipeline().documents([]), [])).toThrow();
  });

  test('duplicateKeys_isRejected', () {
    expectThat(
      () => runPipeline(db.pipeline().documents(['/k/1', '/k/2', '/k/1']), []),
    ).toThrow();
  });

  test('emptyDatabase_returnsNoResults', () {
    expectThat(
      runPipeline(db.pipeline().documents(['/users/a']), []),
    ).toHaveLength(0);
  });

  test('singleDocument_returnsDocument', () {
    final doc1 = doc('users/bob', 1000, <String, Object?>{
      'score': 90,
      'rank': 1,
    });
    expectThat(
      runPipeline(db.pipeline().documents(['/users/bob']), [doc1]),
    ).toEqual([doc1]);
  });

  test('singleMissingDocument_returnsNoResults', () {
    final doc1 = doc('users/bob', 1000, <String, Object?>{
      'score': 90,
      'rank': 1,
    });
    expectThat(
      runPipeline(db.pipeline().documents(['/users/alice']), [doc1]),
    ).toHaveLength(0);
  });

  test('multipleDocuments_returnsDocuments', () {
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

    expectThat(
      runPipeline(
        db.pipeline().documents([
          '/users/bob',
          '/users/alice',
          '/users/charlie',
        ]),
        [doc1, doc2, doc3],
      ),
    ).toEqual([doc2, doc1, doc3]);
  });

  test('hugeDocumentCount_returnsDocuments', () {
    final size = 5000;
    final keys = <Object>[];
    final docs = <TestDocument>[];
    for (var i = 0; i < size; i++) {
      keys.add('/k/${i + 1}');
      docs.add(doc('k/${i + 1}', 1000, <String, Object?>{'v': i}));
    }

    expectThat(
      runPipeline(
        db.pipeline().documents(keys).sort([field('v').ascending()]),
        docs,
      ),
    ).toEqual(docs);
  });

  test('partiallyMissingDocuments_returnsDocuments', () {
    final doc1 = doc('users/bob', 1000, <String, Object?>{
      'score': 90,
      'rank': 1,
    });
    final doc2 = doc('users/diane', 1000, <String, Object?>{
      'score': 50,
      'rank': 3,
    });
    final doc3 = doc('users/charlie', 1000, <String, Object?>{
      'score': 97,
      'rank': 2,
    });

    expectThat(
      runPipeline(
        db.pipeline().documents([
          '/users/bob',
          '/users/alice',
          '/users/charlie',
        ]),
        [doc1, doc2, doc3],
      ),
    ).toEqual([doc1, doc3]);
  });

  test('multipleCollections_returnsDocuments', () {
    final doc1 = doc('c/1', 1000, <String, Object?>{'score': 90, 'rank': 1});
    final doc2 = doc('b/2', 1000, <String, Object?>{'score': 50, 'rank': 3});
    final doc3 = doc('a/3', 1000, <String, Object?>{'score': 97, 'rank': 2});

    expectThat(
      runPipeline(
        db.pipeline().documents(['/a/3', '/b/2', '/c/1']).sort([
          field('__name__').ascending(),
        ]),
        [doc1, doc2, doc3],
      ),
    ).toEqual([doc3, doc2, doc1]);
  });

  test('sort_onPath_ascending', () {
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

    final pipeline = db
        .pipeline()
        .documents(['/users/bob', '/users/alice', '/users/charlie'])
        .sort([field('__name__').ascending()]);

    expectThat(
      runPipeline(pipeline, [doc1, doc2, doc3]),
    ).toEqual([doc2, doc1, doc3]);
  });

  test('sort_onPath_descending', () {
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

    final pipeline = db
        .pipeline()
        .documents(['/users/bob', '/users/alice', '/users/charlie'])
        .sort([field('__name__').descending()]);

    expectThat(
      runPipeline(pipeline, [doc1, doc2, doc3]),
    ).toEqual([doc3, doc1, doc2]);
  });

  test('sort_onKey_ascending', () {
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

    final pipeline = db
        .pipeline()
        .documents(['/users/bob', '/users/alice', '/users/charlie'])
        .sort([field('__name__').ascending()]);

    expectThat(
      runPipeline(pipeline, [doc1, doc2, doc3]),
    ).toEqual([doc2, doc1, doc3]);
  });

  test('sort_onKey_descending', () {
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

    final pipeline = db
        .pipeline()
        .documents(['/users/bob', '/users/alice', '/users/charlie'])
        .sort([field('__name__').descending()]);

    expectThat(
      runPipeline(pipeline, [doc1, doc2, doc3]),
    ).toEqual([doc3, doc1, doc2]);
  });

  test('limit', () {
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

    final pipeline = db
        .pipeline()
        .documents(['/users/bob', '/users/alice', '/users/charlie'])
        .sort([field('__name__').ascending()])
        .limit(2);

    expectThat(runPipeline(pipeline, [doc1, doc2, doc3])).toEqual([doc2, doc1]);
  });
}
