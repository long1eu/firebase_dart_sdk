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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/logical/OrTests.kt
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
  final nullExpr = nullBoolean();
  final unsetExpr = unsetBoolean();
  final stringExpr = stringBoolean();
  final errorExpr = error("error.field").equal(constant("random"));
  final errorDoc = doc("coll/docError", 1, <String, Object?>{
    "error": 123,
  }); // "error.field" will be UNSET
  final emptyDoc = doc("coll/docEmpty", 1, <String, Object?>{});

  // --- Or (||) Tests ---
  // 2 Operands
  test('or - false, false is false', () {
    final expr = or(falseExpr, falseExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), false, "OR(F,F)");
  });
  test('or - false, error is error', () {
    final expr = or(falseExpr, errorExpr.asBoolean());
    assertEvaluatesToError(evaluate(expr, errorDoc), "OR(F,E)");
  });
  test('or - false, null is null', () {
    final expr = or(falseExpr, nullExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "OR(F,N)");
  });
  test('or - false, true is true', () {
    final expr = or(falseExpr, trueExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), true, "OR(F,T)");
  });
  test('or - error, false is error', () {
    final expr = or(errorExpr.asBoolean(), falseExpr);
    assertEvaluatesToError(evaluate(expr, errorDoc), "OR(E,F)");
  });
  test('or - null, false is null', () {
    final expr = or(nullExpr, falseExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "OR(N,F)");
  });
  test('or - error, error is error', () {
    final expr = or(errorExpr.asBoolean(), errorExpr.asBoolean());
    assertEvaluatesToError(evaluate(expr, errorDoc), "OR(E,E)");
  });
  test('or - null, null is null', () {
    final expr = or(nullExpr, nullExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "OR(N,N)");
  });
  test('or - error, true is error', () {
    final expr = or(errorExpr.asBoolean(), trueExpr);
    assertEvaluatesToError(evaluate(expr, errorDoc), "OR(E,T)");
  });
  test('or - null, true is true', () {
    final expr = or(nullExpr, trueExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), true, "OR(N,T)");
  });
  test('or - true, false is true', () {
    final expr = or(trueExpr, falseExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), true, "OR(T,F)");
  });
  test('or - true, error is true', () {
    final expr = or(trueExpr, errorExpr.asBoolean());
    assertEvaluatesTo(evaluate(expr, errorDoc), true, "OR(T,E)");
  });
  test('or - true, null is true', () {
    final expr = or(trueExpr, nullExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), true, "OR(T,N)");
  });
  test('or - true, true is true', () {
    final expr = or(trueExpr, trueExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), true, "OR(T,T)");
  });

  // 3 Operands
  test('or - false, false, false is false', () {
    final expr = or(falseExpr, falseExpr, falseExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), false, "OR(F,F,F)");
  });
  test('or - false, false, error is error', () {
    final expr = or(falseExpr, falseExpr, errorExpr.asBoolean());
    assertEvaluatesToError(evaluate(expr, errorDoc), "OR(F,F,E)");
  });
  test('or - false, false, null is null', () {
    final expr = or(falseExpr, falseExpr, nullExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "OR(F,F,N)");
  });
  test('or - false, false, true is true', () {
    final expr = or(falseExpr, falseExpr, trueExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), true, "OR(F,F,T)");
  });
  test('or - false, error, false is error', () {
    final expr = or(falseExpr, errorExpr.asBoolean(), falseExpr);
    assertEvaluatesToError(evaluate(expr, errorDoc), "OR(F,E,F)");
  });
  test('or - false, null, false is null', () {
    final expr = or(falseExpr, nullExpr, falseExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "OR(F,N,F)");
  });
  test('or - false, error, error is error', () {
    final expr = or(falseExpr, errorExpr.asBoolean(), errorExpr.asBoolean());
    assertEvaluatesToError(evaluate(expr, errorDoc), "OR(F,E,E)");
  });
  test('or - false, null, null is null', () {
    final expr = or(falseExpr, nullExpr, nullExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "OR(F,N,N)");
  });
  test('or - false, error, true is error', () {
    final expr = or(falseExpr, errorExpr.asBoolean(), trueExpr);
    assertEvaluatesToError(evaluate(expr, errorDoc), "OR(F,E,T)");
  });
  test('or - false, null, true is true', () {
    final expr = or(falseExpr, nullExpr, trueExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), true, "OR(F,N,T)");
  });
  test('or - false, true, false is true', () {
    final expr = or(falseExpr, trueExpr, falseExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), true, "OR(F,T,F)");
  });
  test('or - false, true, error is true', () {
    final expr = or(falseExpr, trueExpr, errorExpr.asBoolean());
    assertEvaluatesTo(evaluate(expr, errorDoc), true, "OR(F,T,E)");
  });
  test('or - false, true, null is true', () {
    final expr = or(falseExpr, trueExpr, nullExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), true, "OR(F,T,N)");
  });
  test('or - false, true, true is true', () {
    final expr = or(falseExpr, trueExpr, trueExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), true, "OR(F,T,T)");
  });
  test('or - error, false, false is error', () {
    final expr = or(errorExpr.asBoolean(), falseExpr, falseExpr);
    assertEvaluatesToError(evaluate(expr, errorDoc), "OR(E,F,F)");
  });
  test('or - null, false, false is null', () {
    final expr = or(nullExpr, falseExpr, falseExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "OR(N,F,F)");
  });
  test('or - error, false, error is error', () {
    final expr = or(errorExpr.asBoolean(), falseExpr, errorExpr.asBoolean());
    assertEvaluatesToError(evaluate(expr, errorDoc), "OR(E,F,E)");
  });
  test('or - null, false, null is null', () {
    final expr = or(nullExpr, falseExpr, nullExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "OR(N,F,N)");
  });
  test('or - error, false, true is error', () {
    final expr = or(errorExpr.asBoolean(), falseExpr, trueExpr);
    assertEvaluatesToError(evaluate(expr, errorDoc), "OR(E,F,T)");
  });
  test('or - null, false, true is true', () {
    final expr = or(nullExpr, falseExpr, trueExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), true, "OR(N,F,T)");
  });
  test('or - error, error, false is error', () {
    final expr = or(errorExpr.asBoolean(), errorExpr.asBoolean(), falseExpr);
    assertEvaluatesToError(evaluate(expr, errorDoc), "OR(E,E,F)");
  });
  test('or - null, null, false is null', () {
    final expr = or(nullExpr, nullExpr, falseExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "OR(N,N,F)");
  });
  test('or - error, error, error is error', () {
    final expr = or(
      errorExpr.asBoolean(),
      errorExpr.asBoolean(),
      errorExpr.asBoolean(),
    );
    assertEvaluatesToError(evaluate(expr, errorDoc), "OR(E,E,E)");
  });
  test('or - null, null, null is null', () {
    final expr = or(nullExpr, nullExpr, nullExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "OR(N,N,N)");
  });
  test('or - error, error, true is error', () {
    final expr = or(errorExpr.asBoolean(), errorExpr.asBoolean(), trueExpr);
    assertEvaluatesToError(evaluate(expr, errorDoc), "OR(E,E,T)");
  });
  test('or - null, null, true is true', () {
    final expr = or(nullExpr, nullExpr, trueExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), true, "OR(N,N,T)");
  });
  test('or - error, true, false is error', () {
    final expr = or(errorExpr.asBoolean(), trueExpr, falseExpr);
    assertEvaluatesToError(evaluate(expr, errorDoc), "OR(E,T,F)");
  });
  test('or - null, true, false is true', () {
    final expr = or(nullExpr, trueExpr, falseExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), true, "OR(N,T,F)");
  });
  test('or - error, true, error is error', () {
    final expr = or(errorExpr.asBoolean(), trueExpr, errorExpr.asBoolean());
    assertEvaluatesToError(evaluate(expr, errorDoc), "OR(E,T,E)");
  });
  test('or - null, true, null is true', () {
    final expr = or(nullExpr, trueExpr, nullExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), true, "OR(N,T,N)");
  });
  test('or - error, true, true is error', () {
    final expr = or(errorExpr.asBoolean(), trueExpr, trueExpr);
    assertEvaluatesToError(evaluate(expr, errorDoc), "OR(E,T,T)");
  });
  test('or - null, true, true is true', () {
    final expr = or(nullExpr, trueExpr, trueExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), true, "OR(N,T,T)");
  });
  test('or - true, false, false is true', () {
    final expr = or(trueExpr, falseExpr, falseExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), true, "OR(T,F,F)");
  });
  test('or - true, false, error is true', () {
    final expr = or(trueExpr, falseExpr, errorExpr.asBoolean());
    assertEvaluatesTo(evaluate(expr, errorDoc), true, "OR(T,F,E)");
  });
  test('or - true, false, null is true', () {
    final expr = or(trueExpr, falseExpr, nullExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), true, "OR(T,F,N)");
  });
  test('or - true, false, true is true', () {
    final expr = or(trueExpr, falseExpr, trueExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), true, "OR(T,F,T)");
  });
  test('or - true, error, false is true', () {
    final expr = or(trueExpr, errorExpr.asBoolean(), falseExpr);
    assertEvaluatesTo(evaluate(expr, errorDoc), true, "OR(T,E,F)");
  });
  test('or - true, null, false is true', () {
    final expr = or(trueExpr, nullExpr, falseExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), true, "OR(T,N,F)");
  });
  test('or - true, error, error is true', () {
    final expr = or(trueExpr, errorExpr.asBoolean(), errorExpr.asBoolean());
    assertEvaluatesTo(evaluate(expr, errorDoc), true, "OR(T,E,E)");
  });
  test('or - true, null, null is true', () {
    final expr = or(trueExpr, nullExpr, nullExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), true, "OR(T,N,N)");
  });
  test('or - true, error, true is true', () {
    final expr = or(trueExpr, errorExpr.asBoolean(), trueExpr);
    assertEvaluatesTo(evaluate(expr, errorDoc), true, "OR(T,E,T)");
  });
  test('or - true, null, true is true', () {
    final expr = or(trueExpr, nullExpr, trueExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), true, "OR(T,N,T)");
  });
  test('or - true, true, false is true', () {
    final expr = or(trueExpr, trueExpr, falseExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), true, "OR(T,T,F)");
  });
  test('or - true, true, error is true', () {
    final expr = or(trueExpr, trueExpr, errorExpr.asBoolean());
    assertEvaluatesTo(evaluate(expr, errorDoc), true, "OR(T,T,E)");
  });
  test('or - true, true, null is true', () {
    final expr = or(trueExpr, trueExpr, nullExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), true, "OR(T,T,N)");
  });
  test('or - true, true, true is true', () {
    final expr = or(trueExpr, trueExpr, trueExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), true, "OR(T,T,T)");
  });

  // Nested
  test('or - nested or', () {
    final child = or(trueExpr, trueExpr); // true
    final expr = or(child, falseExpr); // true OR false -> true
    assertEvaluatesTo(evaluate(expr, emptyDoc), true, "Nested OR");
  });

  // Multiple Arguments (already covered by 3-operand tests)
  test('or - multiple arguments', () {
    final expr = or(trueExpr, falseExpr, trueExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), true, "Multiple args OR");
  });
  test('or - error, null is error', () {
    final expr = or(errorExpr.asBoolean(), nullExpr);
    assertEvaluatesToError(evaluate(expr, errorDoc), "OR(E,N)");
  });
  test('or - error, null, true is error', () {
    final expr = or(errorExpr.asBoolean(), nullExpr, trueExpr);
    assertEvaluatesToError(evaluate(expr, errorDoc), "OR(E,N,T)");
  });
  test('or - true, unset is true', () {
    final expr = or(trueExpr, unsetExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), true, "OR(T,U)");
  });
  test('or - unset, true is true', () {
    final expr = or(unsetExpr, trueExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), true, "OR(U,T)");
  });
  test('or - false, unset is null', () {
    final expr = or(falseExpr, unsetExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "OR(F,U)");
  });
  test('or - unset, false is null', () {
    final expr = or(unsetExpr, falseExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "OR(U,F)");
  });
  test('or - unset, unset is null', () {
    final expr = or(unsetExpr, unsetExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "OR(U,U)");
  });
  test('or - unset, error is error', () {
    final expr = or(unsetExpr, errorExpr.asBoolean());
    assertEvaluatesToError(evaluate(expr, errorDoc), "OR(U,E)");
  });
  test('or - error, unset is error', () {
    final expr = or(errorExpr.asBoolean(), unsetExpr);
    assertEvaluatesToError(evaluate(expr, errorDoc), "OR(E,U)");
  });
  test('or - unset, string is error', () {
    final expr = or(unsetExpr, stringExpr);
    assertEvaluatesToError(evaluate(expr, emptyDoc), "OR(U,S)");
  });
}
