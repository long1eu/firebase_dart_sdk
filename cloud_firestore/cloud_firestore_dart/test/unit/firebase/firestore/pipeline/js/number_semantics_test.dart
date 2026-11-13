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
// packages/firestore/test/unit/core/pipeline/number_semantics.test.ts
//
// The cases keep their JS names; js_pipeline_test_util.dart has the
// functions they call. JS numbers that are integral (1.0) are integers here,
// as the JS SDK encodes them.
//
// The cases that Android's NumberSemanticsTests.kt has too are skipped here (they run in
// ../realtime/number_semantics_test.dart); the reason says when the JS expectation differs.

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

/// Why a case is skipped: Android's NumberSemanticsTests.kt has the same case, ported in
/// ../realtime/number_semantics_test.dart.
const String sameAsAndroid =
    'The same case as in Android\'s NumberSemanticsTests.kt, ported in '
    'realtime/number_semantics_test.dart.';

/// Why a case is skipped: as above, and the JS expectation differs from the
/// Enterprise edition backend, which the local executor and Android follow.
const String sameAsAndroidJsDiffers =
    'The same case as in Android\'s NumberSemanticsTests.kt, ported in '
    'realtime/number_semantics_test.dart. JS expects a different result: its local '
    'evaluation treats null and missing values, NaN and errors differently '
    'from the Enterprise edition backend, which the Dart executor follows.';

void main() {
  test('notEqAny_containsNanOnly_isEmpty', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{'age': 42});
    final doc2 = doc('users/b', 1000, <String, Object?>{'age': double.nan});
    final doc3 = doc('users/c', 1000, <String, Object?>{'age': 25});

    final pipeline = db
        .pipeline()
        .collection('/users')
        .where(field('age').notEqualAny([constant(double.nan)]));

    // JS expects users/b (NaN) to match: it does not take NaN to equal NaN. On
    // the Enterprise edition backend NaN equals NaN (equal_any(Field(nan), ...)
    // is true in ../evaluation/emulator_results.golden.jsonl).
    expectThat(runPipeline(pipeline, [doc1, doc2, doc3])).toEqual([doc1, doc3]);
  });

  test('zero_negativeDoubleZero', () {}, skip: sameAsAndroid);
  test('zero_negativeIntegerZero', () {}, skip: sameAsAndroid);
  test('zero_positiveDoubleZero', () {}, skip: sameAsAndroid);
  test('zero_positiveIntegerZero', () {}, skip: sameAsAndroid);
  test('equalNan', () {}, skip: sameAsAndroidJsDiffers);
  test('lessThanNan', () {}, skip: sameAsAndroid);
  test('lessThanEqualNan', () {}, skip: sameAsAndroidJsDiffers);
  test('greaterThanEqualNan', () {}, skip: sameAsAndroidJsDiffers);
  test('greaterThanNan', () {}, skip: sameAsAndroid);
  test('notEqualNan', () {}, skip: sameAsAndroidJsDiffers);
  test('eqAny_containsNan', () {}, skip: sameAsAndroid);
  test('eqAny_containsNanOnly_isEmpty', () {}, skip: sameAsAndroidJsDiffers);
  test('arrayContains_nanOnly_isEmpty', () {}, skip: sameAsAndroidJsDiffers);
  test('arrayContainsAny_withNaN', () {}, skip: sameAsAndroidJsDiffers);
  test('notEqAny_containsNan', () {}, skip: sameAsAndroidJsDiffers);
  test('array_withNan', () {}, skip: sameAsAndroid);
}
