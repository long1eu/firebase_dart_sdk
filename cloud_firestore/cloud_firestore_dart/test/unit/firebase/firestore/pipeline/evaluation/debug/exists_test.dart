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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/debug/ExistsTests.kt
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
import '../comparison/comparison_test_data.dart';

void main() {
  // --- Exists Tests ---
  test('valid field returns true for exists', () {
    final existsExpr = exists(field("x"));
    final document = doc("coll/doc1", 1, <String, Object?>{"x": 1});
    assertEvaluatesTo(
      evaluate(existsExpr, document),
      true,
      "exists(existent-field))",
    );
  });
  test('anything but unset returns true for exists', () {
    for (final valueExpr in allValues) {
      if (valueExpr == unsetValue) {
        return;
      }
      assertEvaluatesTo(
        evaluate(exists(valueExpr)),
        true,
        "exists(%s)",
        valueExpr,
      );
    }
  });
  test('null returns true for exists', () {
    assertEvaluatesTo(evaluate(exists(nullValue())), true, "exists(null)");
  });
  test('error returns error for exists', () {
    final errorProducingExpr = arrayLength(constant("notAnArray"));
    assertEvaluatesToError(
      evaluate(exists(errorProducingExpr)),
      "exists(error_expr)",
    );
  });
  test('unset with not exists returns true', () {
    final unsetExpr = field("non-existent-field");
    final existsExpr = exists(unsetExpr);
    assertEvaluatesTo(
      evaluate(not(existsExpr)),
      true,
      "not(exists(non-existent-field))",
    );
  });
  test('unset returns false for exists', () {
    final unsetExpr = field("non-existent-field");
    assertEvaluatesTo(
      evaluate(exists(unsetExpr)),
      false,
      "exists(non-existent-field)",
    );
  });
  test('empty array returns true for exists', () {
    assertEvaluatesTo(evaluate(exists(array())), true, "exists([])");
  });
  test('empty map returns true for exists', () {
    // map() creates an empty map expression
    assertEvaluatesTo(
      evaluate(exists(map(<String, Object?>{}))),
      true,
      "exists({})",
    );
  });
}
