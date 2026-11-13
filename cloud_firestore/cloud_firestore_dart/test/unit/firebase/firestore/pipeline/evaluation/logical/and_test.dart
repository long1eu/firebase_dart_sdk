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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/logical/AndTests.kt
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
  final errorExpr = error("test").equal(constant("random"));
  final stringExpr = stringBoolean();

  final errorDoc = doc("coll/docError", 1, <String, Object?>{
    "error": 123,
  }); // "error.field" will be UNSET
  final emptyDoc = doc("coll/docEmpty", 1, <String, Object?>{});

  // Test setup follows: https://en.wikipedia.org/wiki/Three-valued_logic#Kleene_and_Priest_logics
  //     F | U | T
  // F | F | F | F
  // U | F | U | U
  // T | F | U | T
  // In our case, U (Unknown) can be NULL or UNSET.
  test('false_false_isFalse', () {
    assertThat(and(falseExpr, falseExpr)).evaluatesTo(false);
  });
  test('false_error_isFalse', () {
    assertThat(and(falseExpr, errorExpr)).evaluatesTo(false);
  });
  test('false_null_isFalse', () {
    assertThat(and(falseExpr, nullExpr)).evaluatesTo(false);
  });
  test('false_true_isFalse', () {
    assertThat(and(falseExpr, trueExpr)).evaluatesTo(false);
  });
  test('error_false_isError', () {
    assertThat(and(errorExpr, falseExpr)).evaluatesToError();
  });
  test('null_false_isFalse', () {
    assertThat(and(nullExpr, falseExpr)).evaluatesTo(false);
  });
  test('error_error_isError', () {
    assertThat(and(errorExpr, errorExpr)).evaluatesToError();
  });
  test('null_null_isNull', () {
    assertThat(and(nullExpr, nullExpr)).evaluatesToNull();
  });
  test('error_true_isError', () {
    assertThat(and(errorExpr, trueExpr)).evaluatesToError();
  });
  test('null_true_isNull', () {
    assertThat(and(nullExpr, trueExpr)).evaluatesToNull();
  });
  test('true_false_isFalse', () {
    assertThat(and(trueExpr, falseExpr)).evaluatesTo(false);
  });
  test('true_error_isError', () {
    assertThat(and(trueExpr, errorExpr)).evaluatesToError();
  });
  test('true_null_isNull', () {
    assertThat(and(trueExpr, nullExpr)).evaluatesToNull();
  });
  test('true_true_isTrue', () {
    assertThat(and(trueExpr, trueExpr)).evaluatesTo(true);
  });
  test('false_false_false_isFalse', () {
    assertThat(and(falseExpr, falseExpr, falseExpr)).evaluatesTo(false);
  });
  test('false_false_error_isFalse', () {
    assertThat(and(falseExpr, falseExpr, errorExpr)).evaluatesTo(false);
  });
  test('false_false_null_isFalse', () {
    assertThat(and(falseExpr, falseExpr, nullExpr)).evaluatesTo(false);
  });
  test('false_false_true_isFalse', () {
    assertThat(and(falseExpr, falseExpr, trueExpr)).evaluatesTo(false);
  });
  test('false_error_false_isFalse', () {
    assertThat(and(falseExpr, errorExpr, falseExpr)).evaluatesTo(false);
  });
  test('false_null_false_isFalse', () {
    assertThat(and(falseExpr, nullExpr, falseExpr)).evaluatesTo(false);
  });
  test('false_error_error_isFalse', () {
    assertThat(and(falseExpr, errorExpr, errorExpr)).evaluatesTo(false);
  });
  test('false_null_null_isFalse', () {
    assertThat(and(falseExpr, nullExpr, nullExpr)).evaluatesTo(false);
  });
  test('false_error_true_isFalse', () {
    assertThat(and(falseExpr, errorExpr, trueExpr)).evaluatesTo(false);
  });
  test('false_null_true_isFalse', () {
    assertThat(and(falseExpr, nullExpr, trueExpr)).evaluatesTo(false);
  });
  test('false_true_false_isFalse', () {
    assertThat(and(falseExpr, trueExpr, falseExpr)).evaluatesTo(false);
  });
  test('false_true_error_isFalse', () {
    assertThat(and(falseExpr, trueExpr, errorExpr)).evaluatesTo(false);
  });
  test('false_true_null_isFalse', () {
    assertThat(and(falseExpr, trueExpr, nullExpr)).evaluatesTo(false);
  });
  test('false_true_true_isFalse', () {
    assertThat(and(falseExpr, trueExpr, trueExpr)).evaluatesTo(false);
  });
  test('error_false_false_isError', () {
    assertThat(and(errorExpr, falseExpr, falseExpr)).evaluatesToError();
  });
  test('null_false_false_isFalse', () {
    assertThat(and(nullExpr, falseExpr, falseExpr)).evaluatesTo(false);
  });
  test('error_false_error_isError', () {
    assertThat(and(errorExpr, falseExpr, errorExpr)).evaluatesToError();
  });
  test('null_false_null_isFalse', () {
    assertThat(and(nullExpr, falseExpr, nullExpr)).evaluatesTo(false);
  });
  test('error_false_true_isError', () {
    assertThat(and(errorExpr, falseExpr, trueExpr)).evaluatesToError();
  });
  test('null_false_true_isFalse', () {
    assertThat(and(nullExpr, falseExpr, trueExpr)).evaluatesTo(false);
  });
  test('error_error_false_isError', () {
    assertThat(and(errorExpr, errorExpr, falseExpr)).evaluatesToError();
  });
  test('null_null_false_isFalse', () {
    assertThat(and(nullExpr, nullExpr, falseExpr)).evaluatesTo(false);
  });
  test('error_error_error_isError', () {
    assertThat(and(errorExpr, errorExpr, errorExpr)).evaluatesToError();
  });
  test('null_null_null_isNull', () {
    assertThat(and(nullExpr, nullExpr, nullExpr)).evaluatesToNull();
  });
  test('error_error_true_isError', () {
    assertThat(and(errorExpr, errorExpr, trueExpr)).evaluatesToError();
  });
  test('null_null_true_isNull', () {
    assertThat(and(nullExpr, nullExpr, trueExpr)).evaluatesToNull();
  });
  test('error_true_false_isError', () {
    assertThat(and(errorExpr, trueExpr, falseExpr)).evaluatesToError();
  });
  test('null_true_false_isFalse', () {
    assertThat(and(nullExpr, trueExpr, falseExpr)).evaluatesTo(false);
  });
  test('error_true_error_isError', () {
    assertThat(and(errorExpr, trueExpr, errorExpr)).evaluatesToError();
  });
  test('null_true_null_isNull', () {
    assertThat(and(nullExpr, trueExpr, nullExpr)).evaluatesToNull();
  });
  test('error_true_true_isError', () {
    assertThat(and(errorExpr, trueExpr, trueExpr)).evaluatesToError();
  });
  test('null_true_true_isNull', () {
    assertThat(and(nullExpr, trueExpr, trueExpr)).evaluatesToNull();
  });
  test('true_false_false_isFalse', () {
    assertThat(and(trueExpr, falseExpr, falseExpr)).evaluatesTo(false);
  });
  test('true_false_error_isFalse', () {
    assertThat(and(trueExpr, falseExpr, errorExpr)).evaluatesTo(false);
  });
  test('true_false_null_isFalse', () {
    assertThat(and(trueExpr, falseExpr, nullExpr)).evaluatesTo(false);
  });
  test('true_false_true_isFalse', () {
    assertThat(and(trueExpr, falseExpr, trueExpr)).evaluatesTo(false);
  });
  test('true_error_false_isError', () {
    assertThat(and(trueExpr, errorExpr, falseExpr)).evaluatesToError();
  });
  test('true_null_false_isFalse', () {
    assertThat(and(trueExpr, nullExpr, falseExpr)).evaluatesTo(false);
  });
  test('true_error_error_isError', () {
    assertThat(and(trueExpr, errorExpr, errorExpr)).evaluatesToError();
  });
  test('true_null_null_isNull', () {
    assertThat(and(trueExpr, nullExpr, nullExpr)).evaluatesToNull();
  });
  test('true_error_true_isError', () {
    assertThat(and(trueExpr, errorExpr, trueExpr)).evaluatesToError();
  });
  test('true_null_true_isNull', () {
    assertThat(and(trueExpr, nullExpr, trueExpr)).evaluatesToNull();
  });
  test('true_true_false_isFalse', () {
    assertThat(and(trueExpr, trueExpr, falseExpr)).evaluatesTo(false);
  });
  test('true_true_error_isError', () {
    assertThat(and(trueExpr, trueExpr, errorExpr)).evaluatesToError();
  });
  test('true_true_null_isNull', () {
    assertThat(and(trueExpr, trueExpr, nullExpr)).evaluatesToNull();
  });
  test('true_true_true_isTrue', () {
    assertThat(and(trueExpr, trueExpr, trueExpr)).evaluatesTo(true);
  });
  test('string_string_isError', () {
    assertThat(and(stringExpr, stringExpr)).evaluatesToError();
  });
  test('string_unset_isError', () {
    assertThat(and(stringExpr, unsetExpr)).evaluatesToError();
  });
  test('unset_string_isError', () {
    assertThat(and(unsetExpr, stringExpr)).evaluatesToError();
  });
  test('string_error_isError', () {
    assertThat(and(stringExpr, errorExpr)).evaluatesToError();
  });
  test('error_string_isError', () {
    assertThat(and(errorExpr, stringExpr)).evaluatesToError();
  });
  test('string_null_isError', () {
    assertThat(and(stringExpr, nullExpr)).evaluatesToError();
  });
  test('null_string_isError', () {
    assertThat(and(nullExpr, stringExpr)).evaluatesToError();
  });
  test('string_true_isError', () {
    assertThat(and(stringExpr, trueExpr)).evaluatesToError();
  });
  test('true_string_isError', () {
    assertThat(and(trueExpr, stringExpr)).evaluatesToError();
  });
  test('string_false_isError', () {
    assertThat(and(stringExpr, falseExpr)).evaluatesToError();
  });
  test('false_string_isFalse', () {
    assertThat(and(falseExpr, stringExpr)).evaluatesTo(false);
  });
  test('unset_unset_isUnset', () {
    assertThat(and(unsetExpr, unsetExpr)).evaluatesToNull();
  });
  test('unset_error_isError', () {
    assertThat(and(unsetExpr, errorExpr)).evaluatesToError();
  });
  test('error_unset_isError', () {
    assertThat(and(errorExpr, unsetExpr)).evaluatesToError();
  });
  test('unset_null_isNull', () {
    assertThat(and(unsetExpr, nullExpr)).evaluatesToNull();
  });
  test('null_unset_isNull', () {
    assertThat(and(nullExpr, unsetExpr)).evaluatesToNull();
  });
  test('unset_true_isNull', () {
    assertThat(and(unsetExpr, trueExpr)).evaluatesToNull();
  });
  test('true_unset_isNull', () {
    assertThat(and(trueExpr, unsetExpr)).evaluatesToNull();
  });
  test('unset_false_isFalse', () {
    assertThat(and(unsetExpr, falseExpr)).evaluatesTo(false);
  });
  test('false_unset_isFalse', () {
    assertThat(and(falseExpr, unsetExpr)).evaluatesTo(false);
  });
  test('nested_and', () {
    final child = and(trueExpr, falseExpr);
    final f = and(child, trueExpr);
    assertThat(f).evaluatesTo(false);
  });
  test('multipleArguments', () {
    assertThat(and(trueExpr, trueExpr, trueExpr)).evaluatesTo(true);
  });
  test('error_null_isError', () {
    assertThat(and(errorExpr, nullExpr)).evaluatesToError();
  });
  test('error_null_false_isError', () {
    assertThat(and(errorExpr, nullExpr, falseExpr)).evaluatesToError();
  });
}
