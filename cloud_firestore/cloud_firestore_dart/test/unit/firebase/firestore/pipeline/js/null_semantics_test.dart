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
// packages/firestore/test/unit/core/pipeline/null_semantics.test.ts
//
// The cases keep their JS names; js_pipeline_test_util.dart has the
// functions they call. JS numbers that are integral (1.0) are integers here,
// as the JS SDK encodes them.
//
// The cases that Android's NullSemanticsTests.kt has too are skipped here (they run in
// ../realtime/null_semantics_test.dart); the reason says when the JS expectation differs.

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

/// Why a case is skipped: Android's NullSemanticsTests.kt has the same case, ported in
/// ../realtime/null_semantics_test.dart.
const String sameAsAndroid =
    'The same case as in Android\'s NullSemanticsTests.kt, ported in '
    'realtime/null_semantics_test.dart.';

/// Why a case is skipped: as above, and the JS expectation differs from the
/// Enterprise edition backend, which the local executor and Android follow.
const String sameAsAndroidJsDiffers =
    'The same case as in Android\'s NullSemanticsTests.kt, ported in '
    'realtime/null_semantics_test.dart. JS expects a different result: its local '
    'evaluation treats null and missing values, NaN and errors differently '
    'from the Enterprise edition backend, which the Dart executor follows.';

void main() {
  test('where_isNull_and', () {
    final doc1 = doc('k/1', 1000, <String, Object?>{'a': null, 'b': null});
    final doc2 = doc('k/2', 1000, <String, Object?>{'a': null});
    final doc3 = doc('k/3', 1000, <String, Object?>{'a': null, 'b': true});
    final doc4 = doc('k/4', 1000, <String, Object?>{'a': null, 'b': false});
    final doc5 = doc('k/5', 1000, <String, Object?>{'b': null});
    final doc6 = doc('k/6', 1000, <String, Object?>{'a': true, 'b': null});
    final doc7 = doc('k/7', 1000, <String, Object?>{'a': false, 'b': null});
    final doc8 = doc('k/8', 1000, <String, Object?>{
      'not-a': true,
      'not-b': true,
    });

    final pipeline = db.pipeline().database().where(
      equal(and(field('a'), field('b')), null),
    );

    // JS expects the documents with a missing operand not to match. On the
    // Enterprise edition backend and() with a missing operand is null unless
    // another operand decides it (and(Constant(null), Field(zz)) is null in
    // ../evaluation/emulator_results.golden.jsonl), so equal(..., null) holds
    // for them too.
    expectThat(
      runPipeline(pipeline, [doc1, doc2, doc3, doc4, doc5, doc6, doc7, doc8]),
    ).toEqual([doc1, doc2, doc3, doc5, doc6, doc8]);
  });

  test('where_isNull_or', () {
    final doc1 = doc('k/1', 1000, <String, Object?>{'a': null, 'b': null});
    final doc2 = doc('k/2', 1000, <String, Object?>{'a': null});
    final doc3 = doc('k/3', 1000, <String, Object?>{'a': null, 'b': true});
    final doc4 = doc('k/4', 1000, <String, Object?>{'a': null, 'b': false});
    final doc5 = doc('k/5', 1000, <String, Object?>{'b': null});
    final doc6 = doc('k/6', 1000, <String, Object?>{'a': true, 'b': null});
    final doc7 = doc('k/7', 1000, <String, Object?>{'a': false, 'b': null});
    final doc8 = doc('k/8', 1000, <String, Object?>{
      'not-a': true,
      'not-b': true,
    });

    final pipeline = db.pipeline().database().where(
      or(field('a'), field('b')).equal(null),
    );

    // JS expects the documents with a missing operand not to match. On the
    // Enterprise edition backend or() with a missing operand is null unless
    // another operand decides it (or(Field(zz), Constant(null)) is null in
    // ../evaluation/emulator_results.golden.jsonl), so equal(..., null) holds
    // for them too.
    expectThat(
      runPipeline(pipeline, [doc1, doc2, doc3, doc4, doc5, doc6, doc7, doc8]),
    ).toEqual([doc1, doc2, doc4, doc5, doc7, doc8]);
  });

  test('where_isNull_xor', () {
    final doc1 = doc('k/1', 1000, <String, Object?>{'a': null, 'b': null});
    final doc2 = doc('k/2', 1000, <String, Object?>{'a': null});
    final doc3 = doc('k/3', 1000, <String, Object?>{'a': null, 'b': true});
    final doc4 = doc('k/4', 1000, <String, Object?>{'a': null, 'b': false});
    final doc5 = doc('k/5', 1000, <String, Object?>{'b': null});
    final doc6 = doc('k/6', 1000, <String, Object?>{'a': true, 'b': null});
    final doc7 = doc('k/7', 1000, <String, Object?>{'a': false, 'b': null});
    final doc8 = doc('k/8', 1000, <String, Object?>{
      'not-a': true,
      'not-b': true,
    });

    final pipeline = db.pipeline().database().where(
      xor(field('a'), field('b')).equal(null),
    );

    // JS expects the documents with a missing operand not to match. On the
    // Enterprise edition backend xor() with a missing operand is null unless
    // another operand decides it (xor(Field(zz), Constant(true)) is null in
    // ../evaluation/emulator_results.golden.jsonl), so equal(..., null) holds
    // for them too.
    expectThat(
      runPipeline(pipeline, [doc1, doc2, doc3, doc4, doc5, doc6, doc7, doc8]),
    ).toEqual([doc1, doc2, doc3, doc4, doc5, doc6, doc7, doc8]);
  });

  test('where_isNull_not', () {
    final doc1 = doc('k/1', 1000, <String, Object?>{'a': true});
    final doc2 = doc('k/2', 1000, <String, Object?>{'a': false});
    final doc3 = doc('k/3', 1000, <String, Object?>{'a': null});

    final pipeline = db.pipeline().database().where(
      not(field('a').equal(true)).equal(null),
    );

    expectThat(runPipeline(pipeline, [doc1, doc2, doc3])).toHaveLength(0);
  });

  test('where_isNull', () {}, skip: sameAsAndroid);
  test('where_isNotNull', () {}, skip: sameAsAndroidJsDiffers);
  test('where_isNullAndIsNotNull_empty', () {}, skip: sameAsAndroid);
  test('where_eq_constantAsNull', () {}, skip: sameAsAndroid);
  test('where_eq_fieldAsNull', () {}, skip: sameAsAndroid);
  test('where_eq_segmentField', () {}, skip: sameAsAndroid);
  test('where_eq_singleFieldAndSegmentField', () {}, skip: sameAsAndroid);
  test('where_eq_null_inArray', () {}, skip: sameAsAndroid);
  test('where_eq_null_other_inArray', () {}, skip: sameAsAndroid);
  test('where_eq_null_nan_inArray', () {}, skip: sameAsAndroidJsDiffers);
  test('where_eq_null_inMap', () {}, skip: sameAsAndroid);
  test('where_eq_null_other_inMap', () {}, skip: sameAsAndroid);
  test('where_eq_null_nan_inMap', () {}, skip: sameAsAndroidJsDiffers);
  test('where_eq_map_withNullArray', () {}, skip: sameAsAndroid);
  test('where_eq_map_withNullOtherArray', () {}, skip: sameAsAndroid);
  test('where_eq_map_withNullNanArray', () {}, skip: sameAsAndroidJsDiffers);
  test('where_compositeCondition_withNull', () {}, skip: sameAsAndroid);
  test('where_eqAny_nullOnly', () {}, skip: sameAsAndroidJsDiffers);
  test('where_eqAny_partialNull', () {}, skip: sameAsAndroidJsDiffers);
  test('where_arrayContains_null', () {}, skip: sameAsAndroidJsDiffers);
  test('where_arrayContainsAny_onlyNull', () {}, skip: sameAsAndroid);
  test('where_arrayContainsAny_partialNull', () {}, skip: sameAsAndroid);
  test('where_arrayContainsAll_onlyNull', () {}, skip: sameAsAndroid);
  test('where_arrayContainsAll_partialNull', () {}, skip: sameAsAndroid);
  test('where_neq_constantAsNull', () {}, skip: sameAsAndroidJsDiffers);
  test('where_neq_fieldAsNull', () {}, skip: sameAsAndroidJsDiffers);
  test('where_neq_null_inArray', () {}, skip: sameAsAndroid);
  test('where_neq_null_other_inArray', () {}, skip: sameAsAndroid);
  test('where_neq_null_nan_inArray', () {}, skip: sameAsAndroidJsDiffers);
  test('where_neq_null_inMap', () {}, skip: sameAsAndroid);
  test('where_neq_null_other_inMap', () {}, skip: sameAsAndroid);
  test('where_neq_null_nan_inMap', () {}, skip: sameAsAndroidJsDiffers);
  test('where_notEqAny_withNull', () {}, skip: sameAsAndroid);
  test('where_gt', () {}, skip: sameAsAndroid);
  test('where_gte', () {}, skip: sameAsAndroid);
  test('where_lt', () {}, skip: sameAsAndroid);
  test('where_lte', () {}, skip: sameAsAndroid);
  test('where_and', () {}, skip: sameAsAndroid);
  test('where_isError_and', () {}, skip: sameAsAndroidJsDiffers);
  test('where_or', () {}, skip: sameAsAndroid);
  test('where_isError_or', () {}, skip: sameAsAndroidJsDiffers);
  test('where_xor', () {}, skip: sameAsAndroid);
  test('where_isError_xor', () {}, skip: sameAsAndroidJsDiffers);
  test('where_not', () {}, skip: sameAsAndroid);
  test('where_isError_not', () {}, skip: sameAsAndroid);
  test('sort_null_inArray_ascending', () {}, skip: sameAsAndroid);
  test('sort_null_inArray_descending', () {}, skip: sameAsAndroid);
  test('sort_null_inMap_ascending', () {}, skip: sameAsAndroid);
  test('sort_null_inMap_descending', () {}, skip: sameAsAndroid);
}
