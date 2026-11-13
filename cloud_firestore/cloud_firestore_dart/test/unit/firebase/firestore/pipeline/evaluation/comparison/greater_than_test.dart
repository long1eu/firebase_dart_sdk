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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/comparison/GreaterThanTests.kt
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
  test('gt equivalent values returns false', () {
    for (final (v1, v2) in equivalentValues) {
      assertEvaluatesTo(
        evaluate(greaterThan(v1, v2)),
        false,
        "gt(%s, %s)",
        v1,
        v2,
      );
    }
  });
  test('gt equivalent values reversed returns false', () {
    for (final (v1, v2) in equivalentValues) {
      assertEvaluatesTo(
        evaluate(greaterThan(v2, v1)),
        false,
        "gt(%s, %s)",
        v2,
        v1,
      );
    }
  });
  test('gt unequal values on greater returns true', () {
    for (final (lesser, greater) in unequalValues) {
      assertEvaluatesTo(
        evaluate(greaterThan(greater, lesser)),
        true,
        "gt(%s, %s)",
        greater,
        lesser,
      );
    }
  });
  test('gt unequal values on lesser returns false', () {
    for (final (lesser, greater) in unequalValues) {
      assertEvaluatesTo(
        evaluate(greaterThan(lesser, greater)),
        false,
        "gt(%s, %s)",
        lesser,
        greater,
      );
    }
  });
  test('gt cross-type on greater returns false', () {
    for (final (lesser, greater) in crossTypeValues) {
      assertEvaluatesTo(
        evaluate(greaterThan(greater, lesser)),
        false,
        "gt(%s, %s)",
        greater,
        lesser,
      );
    }
  });
  test('gt cross-type on lesser returns false', () {
    for (final (lesser, greater) in crossTypeValues) {
      assertEvaluatesTo(
        evaluate(greaterThan(lesser, greater)),
        false,
        "gt(%s, %s)",
        lesser,
        greater,
      );
    }
  });
  test('gt_errorHandling_returnsError', () {
    final errorExpr = error("test");
    final testDoc = doc("test/gtError", 0, <String, Object?>{"a": 123});

    for (final value in allValues) {
      assertEvaluatesToError(
        evaluate(greaterThan(errorExpr, value), testDoc),
        "gt(%s, %s)",
        errorExpr,
        value,
      );
      assertEvaluatesToError(
        evaluate(greaterThan(value, errorExpr), testDoc),
        "gt(%s, %s)",
        value,
        errorExpr,
      );
    }
    assertEvaluatesToError(
      evaluate(greaterThan(errorExpr, errorExpr), testDoc),
      "gt(%s, %s)",
      errorExpr,
      errorExpr,
    );
    assertEvaluatesToError(
      evaluate(greaterThan(errorExpr, nullValue()), testDoc),
      "gt(%s, %s)",
      errorExpr,
      nullValue(),
    );
  });
  test('gt_missingField_returnsFalse', () {
    final missingField = field("nonexistent");
    final presentValue = constant(1);
    final testDoc = doc("test/gtMissing", 0, <String, Object?>{"exists": 10});

    assertEvaluatesTo(
      evaluate(greaterThan(missingField, presentValue), testDoc),
      false,
      "gt(%s, %s)",
      missingField,
      presentValue,
    );

    assertEvaluatesTo(
      evaluate(greaterThan(presentValue, missingField), testDoc),
      false,
      "gt(%s, %s)",
      presentValue,
      missingField,
    );
  });
}
