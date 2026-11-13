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
// packages/firestore/test/unit/core/pipeline/sort.test.ts
//
// The cases keep their JS names; js_pipeline_test_util.dart has the
// functions they call. JS numbers that are integral (1.0) are integers here,
// as the JS SDK encodes them.
//
// The cases that Android's SortTests.kt has too are skipped here (they run in
// ../realtime/sort_test.dart); the reason says when the JS expectation differs.

// ignore_for_file: prefer_single_quotes, always_specify_types
// ignore_for_file: lines_longer_than_80_chars, prefer_final_locals
// ignore_for_file: omit_local_variable_types, unused_local_variable
// ignore_for_file: prefer_const_declarations, prefer_const_constructors

// The documents hold doubles and 64-bit integers, which compiled to
// JavaScript are not what they are on the VM.
@TestOn('vm')
library;

import 'package:test/test.dart' show TestOn, test;

/// Why a case is skipped: Android's SortTests.kt has the same case, ported in
/// ../realtime/sort_test.dart.
const String sameAsAndroid =
    'The same case as in Android\'s SortTests.kt, ported in '
    'realtime/sort_test.dart.';

/// Why a case is skipped: as above, and the JS expectation differs from the
/// Enterprise edition backend, which the local executor and Android follow.
const String sameAsAndroidJsDiffers =
    'The same case as in Android\'s SortTests.kt, ported in '
    'realtime/sort_test.dart. JS expects a different result: its local '
    'evaluation treats null and missing values, NaN and errors differently '
    'from the Enterprise edition backend, which the Dart executor follows.';

void main() {
  test('empty_ascending', () {}, skip: sameAsAndroid);
  test('empty_descending', () {}, skip: sameAsAndroid);
  test('singleResult_ascending', () {}, skip: sameAsAndroid);
  test('singleResult_ascending_explicitExists', () {}, skip: sameAsAndroid);
  test(
    'singleResult_ascending_explicitNotExists_empty',
    () {},
    skip: sameAsAndroid,
  );
  test('singleResult_ascending_implicitExists', () {}, skip: sameAsAndroid);
  test('singleResult_descending', () {}, skip: sameAsAndroid);
  test('singleResult_descending_explicitExists', () {}, skip: sameAsAndroid);
  test('singleResult_descending_implicitExists', () {}, skip: sameAsAndroid);
  test('multipleResults_ambiguousOrder', () {}, skip: sameAsAndroid);
  test(
    'multipleResults_ambiguousOrder_explicitExists',
    () {},
    skip: sameAsAndroid,
  );
  test(
    'multipleResults_ambiguousOrder_implicitExists',
    () {},
    skip: sameAsAndroid,
  );
  test('multipleResults_fullOrder', () {}, skip: sameAsAndroid);
  test('multipleResults_fullOrder_explicitExists', () {}, skip: sameAsAndroid);
  test(
    'multipleResults_fullOrder_explicitNotExists_empty',
    () {},
    skip: sameAsAndroid,
  );
  test('multipleResults_fullOrder_implicitExists', () {}, skip: sameAsAndroid);
  test(
    'multipleResults_fullOrder_partialExplicitExists',
    () {},
    skip: sameAsAndroid,
  );
  test(
    'multipleResults_fullOrder_partialExplicitNotExists',
    () {},
    skip: sameAsAndroid,
  );
  test(
    'multipleResults_fullOrder_partialExplicitNotExists_sortOnNonExistFieldFirst',
    () {},
    skip: sameAsAndroid,
  );
  test(
    'multipleResults_fullOrder_partialImplicitExists',
    () {},
    skip: sameAsAndroid,
  );
  test('missingField_allFields', () {}, skip: sameAsAndroid);
  test('missingField_withExist_empty', () {}, skip: sameAsAndroid);
  test('missingField_partialFields', () {}, skip: sameAsAndroid);
  test('missingField_partialFields_withExist', () {}, skip: sameAsAndroid);
  test('missingField_partialFields_withNotExist', () {}, skip: sameAsAndroid);
  test('limit_afterSort', () {}, skip: sameAsAndroid);
  test('limit_afterSort_withExist', () {}, skip: sameAsAndroid);
  test('limit_afterSort_withNotExist', () {}, skip: sameAsAndroid);
  test('limit_zero_afterSort', () {}, skip: sameAsAndroid);
  test('limit_beforeSort', () {}, skip: sameAsAndroid);
  test('limit_beforeSort_withExist', () {}, skip: sameAsAndroid);
  test('limit_beforeSort_withNotExist', () {}, skip: sameAsAndroid);
  test('limit_beforeNotExistFilter', () {}, skip: sameAsAndroid);
  test('limit_zero_beforeSort', () {}, skip: sameAsAndroid);
  test('sort_expression', () {}, skip: sameAsAndroid);
  test('sort_expression_withExist', () {}, skip: sameAsAndroid);
  test('sort_expression_withNotExist', () {}, skip: sameAsAndroid);
  test('sortOnPathAndOtherField_onDifferentStages', () {}, skip: sameAsAndroid);
  test('sortOnOtherFieldAndPath_onDifferentStages', () {}, skip: sameAsAndroid);
  test('sortOnKeyAndOtherField_onMultipleStages', () {}, skip: sameAsAndroid);
  test('sortOnOtherFieldAndKey_onMultipleStages', () {}, skip: sameAsAndroid);
}
