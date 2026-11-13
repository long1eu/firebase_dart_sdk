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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/comparison/GreaterThanOrEqualTests.kt
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
  test('greaterThanOrEqual_equivalentValues_returnTrue', () {
    for (final (v1, v2) in equivalentValues) {
      assertEvaluatesTo(
        evaluate(greaterThanOrEqual(v1, v2)),
        true,
        "gte(%s, %s)",
        v1,
        v2,
      );
    }
  });
  test('greaterThanOrEqual_equivalentValues_reversed_returnTrue', () {
    for (final (v1, v2) in equivalentValues) {
      assertEvaluatesTo(
        evaluate(greaterThanOrEqual(v2, v1)),
        true,
        "gte(%s, %s)",
        v2,
        v1,
      );
    }
  });
  test('greaterThanOrEqual_unequalValues_onLesser_returnsFalse', () {
    for (final (v1, v2) in unequalValues) {
      assertEvaluatesTo(
        evaluate(greaterThanOrEqual(v1, v2)),
        false,
        "gte(%s, %s)",
        v1,
        v2,
      );
    }
  });
  test('greaterThanOrEqual_unequalValues_onGreater_returnsTrue', () {
    for (final (less, greater) in unequalValues) {
      assertEvaluatesTo(
        evaluate(greaterThanOrEqual(greater, less)),
        true,
        "gte(%s, %s)",
        greater,
        less,
      );
    }
  });
  test('greaterThanOrEqual_crossTypeValues_returnsFalse', () {
    for (final (v1, v2) in crossTypeValues) {
      assertEvaluatesTo(
        evaluate(greaterThanOrEqual(v1, v2)),
        false,
        "gte(%s, %s)",
        v1,
        v2,
      );
    }
  });
  test('greaterThanOrEqual_crossTypeValues_reversed_returnsFalse', () {
    for (final (v1, v2) in crossTypeValues) {
      assertEvaluatesTo(
        evaluate(greaterThanOrEqual(v2, v1)),
        false,
        "gte(%s, %s)",
        v2,
        v1,
      );
    }
  });
  test('gte_errorHandling_returnsError', () {
    final errorExpr = error("test");
    final testDoc = doc("test/gteError", 0, <String, Object?>{"a": 123});

    for (final value in allValues) {
      assertEvaluatesToError(
        evaluate(greaterThanOrEqual(errorExpr, value), testDoc),
        "gte(%s, %s)",
        errorExpr,
        value,
      );
      assertEvaluatesToError(
        evaluate(greaterThanOrEqual(value, errorExpr), testDoc),
        "gte(%s, %s)",
        value,
        errorExpr,
      );
    }
    assertEvaluatesToError(
      evaluate(greaterThanOrEqual(errorExpr, errorExpr), testDoc),
      "gte(%s, %s)",
      errorExpr,
      errorExpr,
    );
    assertEvaluatesToError(
      evaluate(greaterThanOrEqual(errorExpr, nullValue()), testDoc),
      "gte(%s, %s)",
      errorExpr,
      nullValue(),
    );
  });
  test('gte_missingField_returnsError', () {
    final missingField = field("nonexistent");
    final presentValue = constant(1);
    final testDoc = doc("test/gteMissing", 0, <String, Object?>{"exists": 10});

    assertEvaluatesTo(
      evaluate(greaterThanOrEqual(missingField, presentValue), testDoc),
      false,
      "gte(%s, %s)",
      missingField,
      presentValue,
    );
    assertEvaluatesTo(
      evaluate(greaterThanOrEqual(presentValue, missingField), testDoc),
      false,
      "gte(%s, %s)",
      presentValue,
      missingField,
    );
  });
}
