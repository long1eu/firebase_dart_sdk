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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/comparison/NotEqualTests.kt
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
  test('neq_equivalentValues_returnFalse', () {
    for (final (v1, v2) in equivalentValues) {
      assertEvaluatesTo(
        evaluate(notEqual(v1, v2)),
        false,
        "neq(%s, %s)",
        v1,
        v2,
      );
    }
  });
  test('neq_unequalValues_returnTrue', () {
    for (final (v1, v2) in unequalValues) {
      assertEvaluatesTo(
        evaluate(notEqual(v1, v2)),
        true,
        "neq(%s, %s)",
        v1,
        v2,
      );
      assertEvaluatesTo(
        evaluate(notEqual(v2, v1)),
        true,
        "neq(%s, %s)",
        v2,
        v1,
      );
    }
  });
  test('neq_crossTypeValues_returnTrue', () {
    for (final (v1, v2) in crossTypeValues) {
      assertEvaluatesTo(
        evaluate(notEqual(v1, v2)),
        true,
        "neq(%s, %s)",
        v1,
        v2,
      );
      assertEvaluatesTo(
        evaluate(notEqual(v2, v1)),
        true,
        "neq(%s, %s)",
        v2,
        v1,
      );
    }
  });
  test('neq_errorHandling_returnsError', () {
    final errorExpr = error("sample error");
    final testDoc = doc("test/neqError", 0, <String, Object?>{"a": 123});
    final nanExpr = doubleNaN;

    for (final value in allValues) {
      assertEvaluatesToError(
        evaluate(notEqual(errorExpr, value), testDoc),
        "neq(%s, %s)",
        errorExpr,
        value,
      );
      assertEvaluatesToError(
        evaluate(notEqual(value, errorExpr), testDoc),
        "neq(%s, %s)",
        value,
        errorExpr,
      );
    }
    assertEvaluatesToError(
      evaluate(notEqual(errorExpr, errorExpr), testDoc),
      "neq(%s, %s)",
      errorExpr,
      errorExpr,
    );
    assertEvaluatesToError(
      evaluate(notEqual(errorExpr, nullValue()), testDoc),
      "neq(%s, %s)",
      errorExpr,
      nullValue(),
    );
    assertEvaluatesToError(
      evaluate(notEqual(errorExpr, nanExpr), testDoc),
      "neq(%s, %s)",
      errorExpr,
      nanExpr,
    );
    assertEvaluatesToError(
      evaluate(notEqual(nanExpr, errorExpr), testDoc),
      "neq(%s, %s)",
      nanExpr,
      errorExpr,
    );
  });
}
