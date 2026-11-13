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
// packages/firestore/test/unit/core/pipeline/database.test.ts
//
// The cases keep their JS names; js_pipeline_test_util.dart has the
// functions they call. JS numbers that are integral (1.0) are integers here,
// as the JS SDK encodes them.

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
  test('emptyDatabase_returnsEmptyResults', () {
    expectThat(runPipeline(db.pipeline().database(), [])).toHaveLength(0);
  });

  test('returnsAllDocuments', () {
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
      runPipeline(db.pipeline().database(), [doc1, doc2, doc3]),
    ).toEqual([doc2, doc1, doc3]);
  });

  test('returnsMultipleCollections', () {
    final doc1 = doc('a/doc1', 1000, <String, Object?>{'score': 90, 'rank': 1});
    final doc2 = doc('b/doc1', 1000, <String, Object?>{'score': 50, 'rank': 3});
    final doc3 = doc('c/doc1', 1000, <String, Object?>{'score': 97, 'rank': 2});

    expectThat(
      runPipeline(db.pipeline().database(), [doc1, doc2, doc3]),
    ).toEqual([doc1, doc2, doc3]);
  });

  test('where_onKey', () {
    final doc1 = doc('a/1', 1000, <String, Object?>{'score': 90, 'rank': 1});
    final doc2 = doc('b/2', 1000, <String, Object?>{'score': 50, 'rank': 3});
    final doc3 = doc('c/3', 1000, <String, Object?>{'score': 97, 'rank': 2});

    final pipeline = db.pipeline().database().where(
      field('__name__').equal(constant(ref('b/2'))),
    );

    expectThat(runPipeline(pipeline, [doc1, doc2, doc3])).toEqual([doc2]);
  });
}
