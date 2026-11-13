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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/comparison/LessThanTests.kt
//
// The port keeps the names and the structure of the Kotlin tests;
// evaluation_test_util.dart has the functions they call. Where the expected
// result differs from Android's, the Enterprise edition emulator was asked
// and a comment says so.

// ignore_for_file: non_constant_identifier_names, prefer_const_constructors
// ignore_for_file: prefer_const_declarations, unnecessary_lambdas, directives_ordering
// ignore_for_file: prefer_interpolation_to_compose_strings, constant_identifier_names
// ignore_for_file: always_specify_types, prefer_final_locals, unnecessary_brace_in_string_interps
// ignore_for_file: prefer_const_literals_to_create_immutables, prefer_single_quotes
// ignore_for_file: unnecessary_string_escapes, unused_local_variable, lines_longer_than_80_chars

// The cases of this file use doubles with integral values (1.0, -0.0,
// Double.MAX_VALUE) or 64-bit integers. Compiled to JavaScript (dart2js) an
// integral double is an int and an int beyond 2^53 is not exact, so they run
// on the VM only. web_numbers_test.dart covers evaluation compiled to
// JavaScript.
@TestOn('vm')
library;

import 'package:test/test.dart' show TestOn, test;

import '../evaluation_test_util.dart';
import 'comparison_test_data.dart';

void main() {
  test('lessThan_equalCases_returnsFalse', () {
    for (final (v1, v2) in equivalentValues) {
      assertEvaluatesTo(
        evaluate(lessThan(v1, v2)),
        false,
        "lt(%s, %s)",
        v1,
        v2,
      );
    }
  });
  test('lessThan_unequalValues_onLesser_returnsTrue', () {
    for (final (v1, v2) in unequalValues) {
      final result = evaluate(lessThan(v1, v2));
      assertEvaluatesTo(result, true, "lt(%s, %s)", v1, v2);
    }
  });
  test('lessThan_unequalValues_onGreater_returnsFalse', () {
    for (final (less, greater) in unequalValues) {
      assertEvaluatesTo(
        evaluate(lessThan(greater, less)),
        false,
        "lt(%s, %s)",
        greater,
        less,
      );
    }
  });
  test('lessThan_crossTypeComparison_returnsFalse', () {
    for (final (v1, v2) in crossTypeValues) {
      assertEvaluatesTo(
        evaluate(lessThan(v1, v2)),
        false,
        "lt(%s, %s)",
        v1,
        v2,
      );
      assertEvaluatesTo(
        evaluate(lessThan(v2, v1)),
        false,
        "lt(%s, %s)",
        v2,
        v1,
      );
    }
  });
  test('lt_nanComparisons_returnFalse', () {
    final nanExpr = doubleNaN;
    assertEvaluatesTo(
      evaluate(lessThan(nanExpr, nanExpr)),
      false,
      "lt(%s, %s)",
      nanExpr,
      nanExpr,
    );

    for (final value in allValues) {
      if (value != nanExpr) {
        assertEvaluatesTo(
          evaluate(lessThan(nanExpr, value)),
          false,
          "lt(%s, %s)",
          nanExpr,
          value,
        );
        assertEvaluatesTo(
          evaluate(lessThan(value, nanExpr)),
          false,
          "lt(%s, %s)",
          value,
          nanExpr,
        );
      }
    }

    final arrayWithNaN1 = array(constant(double.nan));
    final arrayWithNaN2 = array(constant(double.nan));
    assertEvaluatesTo(
      evaluate(lessThan(arrayWithNaN1, arrayWithNaN2)),
      false,
      "lt(%s, %s)",
      arrayWithNaN1,
      arrayWithNaN2,
    );
  });
  test('lt_errorHandling_returnsError', () {
    final errorExpr = error("test");
    final testDoc = doc("test/ltError", 0, <String, Object?>{"a": 123});

    for (final value in allValues) {
      assertEvaluatesToError(
        evaluate(lessThan(errorExpr, value), testDoc),
        "lt(%s, %s)",
        errorExpr,
        value,
      );
      assertEvaluatesToError(
        evaluate(lessThan(value, errorExpr), testDoc),
        "lt(%s, %s)",
        value,
        errorExpr,
      );
    }
    assertEvaluatesToError(
      evaluate(lessThan(errorExpr, errorExpr), testDoc),
      "lt(%s, %s)",
      errorExpr,
      errorExpr,
    );
    assertEvaluatesToError(
      evaluate(lessThan(errorExpr, nullValue()), testDoc),
      "lt(%s, %s)",
      errorExpr,
      nullValue(),
    );
  });
  test('lt_missingField_returnsFalse', () {
    final missingField = field("nonexistent");
    final presentValue = constant(1);
    final testDoc = doc("test/ltMissing", 0, <String, Object?>{"exists": 10});

    assertEvaluatesTo(
      evaluate(lessThan(missingField, presentValue), testDoc),
      false,
      "lt(%s, %s)",
      missingField,
      presentValue,
    );
    assertEvaluatesTo(
      evaluate(lessThan(presentValue, missingField), testDoc),
      false,
      "lt(%s, %s)",
      presentValue,
      missingField,
    );
  });
}
