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
// packages/firestore/test/unit/core/pipeline/complex.test.ts
//
// The cases keep their JS names; js_pipeline_test_util.dart has the
// functions they call. JS numbers that are integral (1.0) are integers here,
// as the JS SDK encodes them.
//
// The cases that Android's ComplexQueriesTests.kt has too are skipped here (they run in
// ../realtime/complex_queries_test.dart); the reason says when the JS expectation differs.

// ignore_for_file: prefer_single_quotes, always_specify_types
// ignore_for_file: lines_longer_than_80_chars, prefer_final_locals
// ignore_for_file: omit_local_variable_types, unused_local_variable
// ignore_for_file: prefer_const_declarations, prefer_const_constructors

// The documents hold doubles and 64-bit integers, which compiled to
// JavaScript are not what they are on the VM.
@TestOn('vm')
library;

import 'package:test/test.dart' show TestOn, test;

/// Why a case is skipped: Android's ComplexQueriesTests.kt has the same case, ported in
/// ../realtime/complex_queries_test.dart.
const String sameAsAndroid =
    'The same case as in Android\'s ComplexQueriesTests.kt, ported in '
    'realtime/complex_queries_test.dart.';

/// Why a case is skipped: as above, and the JS expectation differs from the
/// Enterprise edition backend, which the local executor and Android follow.
const String sameAsAndroidJsDiffers =
    'The same case as in Android\'s ComplexQueriesTests.kt, ported in '
    'realtime/complex_queries_test.dart. JS expects a different result: its local '
    'evaluation treats null and missing values, NaN and errors differently '
    'from the Enterprise edition backend, which the Dart executor follows.';

void main() {
  test('where_withMaxNumberOfStages', () {}, skip: sameAsAndroid);
  test('eqAny_withMaxNumberOfElements', () {}, skip: sameAsAndroid);
  test(
    'eqAny_withMaxNumberOfElements_onMultipleFields',
    () {},
    skip: sameAsAndroid,
  );
  test('notEqAny_withMaxNumberOfElements', () {}, skip: sameAsAndroid);
  test(
    'notEqAny_withMaxNumberOfElements_onMultipleFields',
    () {},
    skip: sameAsAndroid,
  );
  test(
    'arrayContainsAny_withLargeNumberOfElements',
    () {},
    skip: sameAsAndroid,
  );
  test(
    'arrayContainsAny_withMaxNumberOfElements_onMultipleFields',
    () {},
    skip: sameAsAndroid,
  );
  test('sortByMaxNumOfFields_withoutIndex', () {}, skip: sameAsAndroid);
  test('where_withNestedAddFunction_maxDepth', () {}, skip: sameAsAndroid);
  test('where_withLargeNumberOrs', () {}, skip: sameAsAndroid);
  test('where_withLargeNumberOfConjunctions', () {}, skip: sameAsAndroid);
}
