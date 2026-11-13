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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/array/ArrayContainsTests.kt
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

void main() {
  // --- ArrayContains Tests ---
  test('arrayContains - value found in array', () {
    final expr = arrayContains(array("hello", "world"), constant("hello"));
    assertEvaluatesTo(evaluate(expr), true, "arrayContains value found");
  });
  test('arrayContains - equivalent numerics', () {
    final arrayToSearch = array(42, "matang", true);
    final expr = arrayContains(arrayToSearch, constant(42.0));
    assertEvaluatesTo(
      evaluate(expr),
      true,
      "arrayContains equivalent numerics",
    );
  });
  test('arrayContains - both input type is array', () {
    final arrayToSearch = array(array(1, 2, 3), array(4, 5, 6), array(7, 8, 9));
    final valueToFind = array(1, 2, 3);
    final expr = arrayContains(arrayToSearch, valueToFind);
    assertEvaluatesTo(evaluate(expr), true, "arrayContains nested arrays");
  });
  test('arrayContains - search value is null returns true', () {
    final arrayToSearch = array(null, 1, "matang", true);
    final expr = arrayContains(arrayToSearch, nullValue());
    assertEvaluatesTo(evaluate(expr), true, "arrayContains search for null");
  });
  test(
    'arrayContains - search value is null empty values array returns false',
    () {
      final expr = arrayContains(array(), nullValue());
      assertEvaluatesTo(
        evaluate(expr),
        false,
        "arrayContains search for null in empty array",
      );
    },
  );
  test('arrayContains - search value is map', () {
    final arrayToSearch = array(
      123,
      <String, Object?>{"foo": 123},
      <String, Object?>{"bar": 42},
      <String, Object?>{"foo": 42},
    );
    final valueToFind = map(<String, Object?>{
      "foo": 42,
    }); // Use Expression.map directly
    final expr = arrayContains(arrayToSearch, valueToFind);
    assertEvaluatesTo(evaluate(expr), true, "arrayContains search for map");
  });
  test('arrayContains - search value is NaN', () {
    final arrayToSearch = array(double.nan, "foo");
    final valueToFind = constant(double.nan);
    final expr = arrayContains(arrayToSearch, valueToFind);
    assertEvaluatesTo(evaluate(expr), true, "arrayContains search for NaN");
  });
  test('arrayContains - array to search is not array type returns error', () {
    final expr = arrayContains(constant("matang"), constant("values"));
    assertEvaluatesToError(evaluate(expr), "arrayContains first arg not array");
  });
  test('arrayContains - array to search not found returns null', () {
    final expr = arrayContains(field("not-exist"), constant("matang"));
    // Accessing a non-existent field results in UNSET, which then causes an error in arrayContains
    assertEvaluatesToNull(
      evaluate(expr),
      "arrayContains field not-exist for array",
    );
  });
  test('arrayContains - array to search is empty returns false', () {
    final expr = arrayContains(array(), constant("matang"));
    assertEvaluatesTo(evaluate(expr), false, "arrayContains empty array");
  });
  test('arrayContains - search value reference not found returns false', () {
    final arrayToSearch = array(42, "matang", true);
    final expr = arrayContains(arrayToSearch, field("not-exist"));
    // Accessing a non-existent field for the search value results in UNSET.
    // arrayContains then attempts to compare with UNSET, which is an error.
    assertEvaluatesTo(
      evaluate(expr),
      false,
      "arrayContains field not-exist for search value",
    );
  });
}
