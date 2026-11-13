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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/logical/CondTests.kt
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
import 'test_expressions.dart';

void main() {
  final trueExpr = constant(true);
  final falseExpr = constant(false);
  final errorExpr = error("error").equal(constant("random"));

  final errorDoc = doc("coll/docError", 1, <String, Object?>{
    "error": 123,
  }); // "error.field" will be UNSET
  final emptyDoc = doc("coll/docEmpty", 1, <String, Object?>{});

  // --- Cond (? :) Tests ---
  test('cond - true condition returns true case', () {
    final expr = conditional(trueExpr, constant("true case"), errorExpr);
    final result = evaluate(expr, emptyDoc);
    assertEvaluatesTo(
      result,
      encodeValue("true case"),
      "cond(true, 'true case', error)",
    );
  });
  test('cond - false condition returns false case', () {
    final expr = conditional(falseExpr, errorExpr, constant("false case"));
    final result = evaluate(expr, emptyDoc);
    assertEvaluatesTo(
      result,
      encodeValue("false case"),
      "cond(false, error, 'false case')",
    );
  });
  test('cond - error condition returns error', () {
    final expr = conditional(
      errorExpr,
      constant("true case"),
      constant("false case"),
    );
    assertEvaluatesToError(
      evaluate(expr, errorDoc),
      "Cond with error condition",
    );
  });
  test('cond - true condition but true case is error returns error', () {
    final expr = conditional(trueExpr, errorExpr, constant("false case"));
    assertEvaluatesToError(
      evaluate(expr, errorDoc),
      "Cond with error true-case",
    );
  });
  test('cond - false condition but false case is error returns error', () {
    final expr = conditional(falseExpr, constant("true case"), errorExpr);
    assertEvaluatesToError(
      evaluate(expr, errorDoc),
      "Cond with error false-case",
    );
  });
  test('cond - null condition returns false case', () {
    final expr = conditional(nullBoolean(), errorExpr, constant("false case"));
    final result = evaluate(expr, emptyDoc);
    assertEvaluatesTo(
      result,
      encodeValue("false case"),
      "cond(null, error, 'false case')",
    );
  });
  test('cond - unset condition returns false case', () {
    final expr = conditional(
      unsetBoolean(),
      constant("true case"),
      constant("false case"),
    );
    final result = evaluate(expr, emptyDoc);
    assertEvaluatesTo(
      result,
      encodeValue("false case"),
      "cond(unset, 'true case', 'false case')",
    );
  });
  test('cond - non-boolean condition returns error', () {
    final expr = conditional(
      stringBoolean(),
      constant("true case"),
      constant("false case"),
    );
    assertEvaluatesToError(
      evaluate(expr, emptyDoc),
      "Cond with non-boolean condition",
    );
  });
}
