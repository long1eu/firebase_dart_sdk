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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/logical/XorTests.kt
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
  final errorExpr = error("error.field").equal(constant("random"));
  final errorDoc = doc("coll/docError", 1, <String, Object?>{
    "error": 123,
  }); // "error.field" will be UNset
  final emptyDoc = doc("coll/docEmpty", 1, <String, Object?>{});

  // --- Xor Tests ---
  // 2 Operands
  test('xor - false, false is false', () {
    final expr = xor(falseExpr, falseExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), false, "XOR(F,F)");
  });
  test('xor - false, error is error', () {
    final expr = xor(falseExpr, errorExpr.asBoolean());
    assertEvaluatesToError(evaluate(expr, errorDoc), "XOR(F,E)");
  });
  test('xor - false, null is null', () {
    final expr = xor(falseExpr, nullExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "XOR(F,N)");
  });
  test('xor - false, true is true', () {
    final expr = xor(falseExpr, trueExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), true, "XOR(F,T)");
  });
  test('xor - error, false is error', () {
    final expr = xor(errorExpr.asBoolean(), falseExpr);
    assertEvaluatesToError(evaluate(expr, errorDoc), "XOR(E,F)");
  });
  test('xor - unset, false is null', () {
    final expr = xor(unsetExpr, falseExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "XOR(U,F)");
  });
  test('xor - null, false is null', () {
    final expr = xor(nullExpr, falseExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "XOR(N,F)");
  });
  test('xor - error, error is error', () {
    final expr = xor(errorExpr.asBoolean(), errorExpr.asBoolean());
    assertEvaluatesToError(evaluate(expr, errorDoc), "XOR(E,E)");
  });
  test('xor - null, null is null', () {
    final expr = xor(nullExpr, nullExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "XOR(N,N)");
  });
  test('xor - error, true is error', () {
    final expr = xor(errorExpr.asBoolean(), trueExpr);
    assertEvaluatesToError(evaluate(expr, errorDoc), "XOR(E,T)");
  });
  test('xor - null, true is null', () {
    final expr = xor(nullExpr, trueExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "XOR(N,T)");
  });
  test('xor - true, false is true', () {
    final expr = xor(trueExpr, falseExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), true, "XOR(T,F)");
  });
  test('xor - true, error is error', () {
    final expr = xor(trueExpr, errorExpr.asBoolean());
    assertEvaluatesToError(evaluate(expr, errorDoc), "XOR(T,E)");
  });
  test('xor - true, null is null', () {
    final expr = xor(trueExpr, nullExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "XOR(T,N)");
  });
  test('xor - true, true is false', () {
    final expr = xor(trueExpr, trueExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), false, "XOR(T,T)");
  });

  // 3 Operands (XOR is true if an odd number of inputs are true)
  test('xor - false, false, false is false', () {
    final expr = xor(falseExpr, falseExpr, falseExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), false, "XOR(F,F,F)");
  });
  test('xor - false, false, error is error', () {
    final expr = xor(falseExpr, falseExpr, errorExpr.asBoolean());
    assertEvaluatesToError(evaluate(expr, errorDoc), "XOR(F,F,E)");
  });
  test('xor - false, false, null is null', () {
    final expr = xor(falseExpr, falseExpr, nullExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "XOR(F,F,N)");
  });
  test('xor - false, false, true is true', () {
    final expr = xor(falseExpr, falseExpr, trueExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), true, "XOR(F,F,T)");
  });
  test('xor - false, error, false is error', () {
    final expr = xor(falseExpr, errorExpr.asBoolean(), falseExpr);
    assertEvaluatesToError(evaluate(expr, errorDoc), "XOR(F,E,F)");
  });
  test('xor - false, null, false is null', () {
    final expr = xor(falseExpr, nullExpr, falseExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "XOR(F,N,F)");
  });
  test('xor - false, error, error is error', () {
    final expr = xor(falseExpr, errorExpr.asBoolean(), errorExpr.asBoolean());
    assertEvaluatesToError(evaluate(expr, errorDoc), "XOR(F,E,E)");
  });
  test('xor - false, null, null is null', () {
    final expr = xor(falseExpr, nullExpr, nullExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "XOR(F,N,N)");
  });
  test('xor - false, error, true is error', () {
    final expr = xor(falseExpr, errorExpr.asBoolean(), trueExpr);
    assertEvaluatesToError(evaluate(expr, errorDoc), "XOR(F,E,T)");
  });
  test('xor - false, null, true is null', () {
    final expr = xor(falseExpr, nullExpr, trueExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "XOR(F,N,T)");
  });
  test('xor - false, true, false is true', () {
    final expr = xor(falseExpr, trueExpr, falseExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), true, "XOR(F,T,F)");
  });
  test('xor - false, true, error is error', () {
    final expr = xor(falseExpr, trueExpr, errorExpr.asBoolean());
    assertEvaluatesToError(evaluate(expr, errorDoc), "XOR(F,T,E)");
  });
  test('xor - false, true, null is null', () {
    final expr = xor(falseExpr, trueExpr, nullExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "XOR(F,T,N)");
  });
  test('xor - false, true, true is false', () {
    final expr = xor(falseExpr, trueExpr, trueExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), false, "XOR(F,T,T)");
  });
  test('xor - error, false, false is error', () {
    final expr = xor(errorExpr.asBoolean(), falseExpr, falseExpr);
    assertEvaluatesToError(evaluate(expr, errorDoc), "XOR(E,F,F)");
  });
  test('xor - null, false, false is null', () {
    final expr = xor(nullExpr, falseExpr, falseExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "XOR(N,F,F)");
  });
  test('xor - error, false, error is error', () {
    final expr = xor(errorExpr.asBoolean(), falseExpr, errorExpr.asBoolean());
    assertEvaluatesToError(evaluate(expr, errorDoc), "XOR(E,F,E)");
  });
  test('xor - null, false, null is null', () {
    final expr = xor(nullExpr, falseExpr, nullExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "XOR(N,F,N)");
  });
  test('xor - error, false, true is error', () {
    final expr = xor(errorExpr.asBoolean(), falseExpr, trueExpr);
    assertEvaluatesToError(evaluate(expr, errorDoc), "XOR(E,F,T)");
  });
  test('xor - null, false, true is null', () {
    final expr = xor(nullExpr, falseExpr, trueExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "XOR(N,F,T)");
  });
  test('xor - error, error, false is error', () {
    final expr = xor(errorExpr.asBoolean(), errorExpr.asBoolean(), falseExpr);
    assertEvaluatesToError(evaluate(expr, errorDoc), "XOR(E,E,F)");
  });
  test('xor - null, null, false is null', () {
    final expr = xor(nullExpr, nullExpr, falseExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "XOR(N,N,F)");
  });
  test('xor - error, error, error is error', () {
    final expr = xor(
      errorExpr.asBoolean(),
      errorExpr.asBoolean(),
      errorExpr.asBoolean(),
    );
    assertEvaluatesToError(evaluate(expr, errorDoc), "XOR(E,E,E)");
  });
  test('xor - null, null, null is null', () {
    final expr = xor(nullExpr, nullExpr, nullExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "XOR(N,N,N)");
  });
  test('xor - error, error, true is error', () {
    final expr = xor(errorExpr.asBoolean(), errorExpr.asBoolean(), trueExpr);
    assertEvaluatesToError(evaluate(expr, errorDoc), "XOR(E,E,T)");
  });
  test('xor - null, null, true is null', () {
    final expr = xor(nullExpr, nullExpr, trueExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "XOR(N,N,T)");
  });
  test('xor - error, true, false is error', () {
    final expr = xor(errorExpr.asBoolean(), trueExpr, falseExpr);
    assertEvaluatesToError(evaluate(expr, errorDoc), "XOR(E,T,F)");
  });
  test('xor - null, true, false is null', () {
    final expr = xor(nullExpr, trueExpr, falseExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "XOR(N,T,F)");
  });
  test('xor - error, true, error is error', () {
    final expr = xor(errorExpr.asBoolean(), trueExpr, errorExpr.asBoolean());
    assertEvaluatesToError(evaluate(expr, errorDoc), "XOR(E,T,E)");
  });
  test('xor - null, true, null is null', () {
    final expr = xor(nullExpr, trueExpr, nullExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "XOR(N,T,N)");
  });
  test('xor - error, true, true is error', () {
    final expr = xor(errorExpr.asBoolean(), trueExpr, trueExpr);
    assertEvaluatesToError(evaluate(expr, errorDoc), "XOR(E,T,T)");
  });
  test('xor - null, true, true is null', () {
    final expr = xor(nullExpr, trueExpr, trueExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "XOR(N,T,T)");
  });
  test('xor - true, false, false is true', () {
    final expr = xor(trueExpr, falseExpr, falseExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), true, "XOR(T,F,F)");
  });
  test('xor - true, false, error is error', () {
    final expr = xor(trueExpr, falseExpr, errorExpr.asBoolean());
    assertEvaluatesToError(evaluate(expr, errorDoc), "XOR(T,F,E)");
  });
  test('xor - true, false, null is null', () {
    final expr = xor(trueExpr, falseExpr, nullExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "XOR(T,F,N)");
  });
  test('xor - true, false, true is false', () {
    final expr = xor(trueExpr, falseExpr, trueExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), false, "XOR(T,F,T)");
  });
  test('xor - true, error, false is error', () {
    final expr = xor(trueExpr, errorExpr.asBoolean(), falseExpr);
    assertEvaluatesToError(evaluate(expr, errorDoc), "XOR(T,E,F)");
  });
  test('xor - true, null, false is null', () {
    final expr = xor(trueExpr, nullExpr, falseExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "XOR(T,N,F)");
  });
  test('xor - true, error, error is error', () {
    final expr = xor(trueExpr, errorExpr.asBoolean(), errorExpr.asBoolean());
    assertEvaluatesToError(evaluate(expr, errorDoc), "XOR(T,E,E)");
  });
  test('xor - true, null, null is null', () {
    final expr = xor(trueExpr, nullExpr, nullExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "XOR(T,N,N)");
  });
  test('xor - true, error, true is error', () {
    final expr = xor(trueExpr, errorExpr.asBoolean(), trueExpr);
    assertEvaluatesToError(evaluate(expr, errorDoc), "XOR(T,E,T)");
  });
  test('xor - true, null, true is null', () {
    final expr = xor(trueExpr, nullExpr, trueExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "XOR(T,N,T)");
  });
  test('xor - true, true, false is false', () {
    final expr = xor(trueExpr, trueExpr, falseExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), false, "XOR(T,T,F)");
  });
  test('xor - true, true, error is error', () {
    final expr = xor(trueExpr, trueExpr, errorExpr.asBoolean());
    assertEvaluatesToError(evaluate(expr, errorDoc), "XOR(T,T,E)");
  });
  test('xor - true, true, null is null', () {
    final expr = xor(trueExpr, trueExpr, nullExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "XOR(T,T,N)");
  });
  test('xor - true, true, true is true', () {
    final expr = xor(trueExpr, trueExpr, trueExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), true, "XOR(T,T,T)");
  });
  test('xor - null, true returns null', () {
    final expr = xor(nullExpr, trueExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "XOR(N,T)");
  });
  test('xor - null, false returns null', () {
    final expr = xor(nullExpr, falseExpr);
    assertEvaluatesToNull(evaluate(expr, emptyDoc), "XOR(N,F)");
  });

  // Nested
  test('xor - nested xor', () {
    final child = xor(trueExpr, falseExpr);
    final expr = xor(child, trueExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), false, "Nested XOR");
  });

  // Multiple Arguments (already covered by 3-operand tests)
  test('xor - multiple arguments', () {
    final expr = xor(trueExpr, falseExpr, trueExpr);
    assertEvaluatesTo(evaluate(expr, emptyDoc), false, "Multiple args XOR");
  });
  test('xor - error, null is error', () {
    final expr = xor(errorExpr.asBoolean(), nullExpr);
    assertEvaluatesToError(evaluate(expr, errorDoc), "XOR(E,N)");
  });
  test('xor - true, false, error, null is error', () {
    final expr = xor(trueExpr, falseExpr, errorExpr.asBoolean(), nullExpr);
    assertEvaluatesToError(evaluate(expr, errorDoc), "XOR(T,F,E,N)");
  });
}
