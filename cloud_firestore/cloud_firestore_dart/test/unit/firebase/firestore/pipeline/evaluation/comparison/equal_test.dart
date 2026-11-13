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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/comparison/EqualTests.kt
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

import 'package:test/test.dart' show test;

import '../evaluation_test_util.dart';
import 'comparison_test_data.dart';

void main() {
  test('eq_equivalentValues_returnTrue', () {
    for (final (v1, v2) in equivalentValues) {
      final result = evaluate(equal(v1, v2));
      assertEvaluatesTo(result, true, "eq(%s, %s)", v1, v2);
    }
  });
  test('eq_unequalValues_returnFalse', () {
    for (final (v1, v2) in unequalValues) {
      // eq(v1, v2)
      final result1 = evaluate(equal(v1, v2));
      assertEvaluatesTo(result1, false, "eq(%s, %s)", v1, v2);
      // eq(v2, v1)
      final result2 = evaluate(equal(v2, v1));
      assertEvaluatesTo(result2, false, "eq(%s, %s)", v2, v1);
    }
  });
  test('eq_crossTypeValues_returnFalse', () {
    for (final (v1, v2) in crossTypeValues) {
      final result1 = evaluate(equal(v1, v2));
      assertEvaluatesTo(result1, false, "eq(%s, %s)", v1, v2);
      final result2 = evaluate(equal(v2, v1));
      assertEvaluatesTo(result2, false, "eq(%s, %s)", v2, v1);
    }
  });
  test('eq_errorHandling_returnsError', () {
    final errorExpr = error("test error");
    final testDoc = doc("test/eqError", 0, <String, Object?>{"a": 123});

    for (final value in allValues) {
      assertEvaluatesToError(
        evaluate(equal(errorExpr, value), testDoc),
        "eq(%s, %s)",
        errorExpr,
        value,
      );
      assertEvaluatesToError(
        evaluate(equal(value, errorExpr), testDoc),
        "eq(%s, %s)",
        value,
        errorExpr,
      );
    }
    assertEvaluatesToError(
      evaluate(equal(errorExpr, errorExpr), testDoc),
      "eq(%s, %s)",
      errorExpr,
      errorExpr,
    );
    assertEvaluatesToError(
      evaluate(equal(errorExpr, nullValue()), testDoc),
      "eq(%s, %s)",
      errorExpr,
      nullValue(),
    );
  });
  test('eq_missingField_returnsFalse', () {
    final missingField = field("nonexistent");
    final presentValue = allValues.first;
    final testDoc = doc("test/eqMissing", 0, <String, Object?>{"exists": 10});

    assertEvaluatesTo(
      evaluate(equal(missingField, presentValue), testDoc),
      false,
      "eq(%s, %s)",
      missingField,
      presentValue,
    );
    assertEvaluatesTo(
      evaluate(equal(presentValue, missingField), testDoc),
      false,
      "eq(%s, %s)",
      presentValue,
      missingField,
    );
  });
}
