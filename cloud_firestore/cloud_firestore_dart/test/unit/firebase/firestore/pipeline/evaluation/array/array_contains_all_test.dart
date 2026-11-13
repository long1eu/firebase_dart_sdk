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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/array/ArrayContainsAllTests.kt
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
  // --- ArrayContainsAll Tests ---
  test('arrayContainsAll - contains all', () {
    final arrayToSearch = array(
      "1",
      42,
      true,
      "additional",
      "values",
      "in",
      "array",
    );
    final valuesToFind = array("1", 42, true);
    final expr = arrayContainsAll(arrayToSearch, valuesToFind);
    assertEvaluatesTo(evaluate(expr), true, "arrayContainsAll basic true case");
  });
  test('arrayContainsAll - does not contain all', () {
    final arrayToSearch = array("1", 42, true);
    final valuesToFind = array("1", 99);
    final expr = arrayContainsAll(arrayToSearch, valuesToFind);
    assertEvaluatesTo(
      evaluate(expr),
      false,
      "arrayContainsAll basic false case",
    );
  });
  test('arrayContainsAll - equivalent numerics', () {
    final arrayToSearch = array(
      42,
      true,
      "additional",
      "values",
      "in",
      "array",
    );
    final valuesToFind = array(42.0, true);
    final expr = arrayContainsAll(arrayToSearch, valuesToFind);
    assertEvaluatesTo(
      evaluate(expr),
      true,
      "arrayContainsAll equivalent numerics",
    );
  });
  test('arrayContainsAll - array to search is empty', () {
    final arrayToSearch = array();
    final valuesToFind = array(42.0, true);
    final expr = arrayContainsAll(arrayToSearch, valuesToFind);
    assertEvaluatesTo(
      evaluate(expr),
      false,
      "arrayContainsAll empty array to search",
    );
  });
  test('arrayContainsAll - search value is empty', () {
    final arrayToSearch = array(42.0, true);
    final valuesToFind = array();
    final expr = arrayContainsAll(arrayToSearch, valuesToFind);
    assertEvaluatesTo(
      evaluate(expr),
      true,
      "arrayContainsAll empty search values",
    );
  });
  test('arrayContainsAll - search value is NaN', () {
    final arrayToSearch = array(double.nan, 42.0);
    final valuesToFind = array(double.nan);
    // Hyperstore behavior: NaN comparisons are true.
    final expr = arrayContainsAll(arrayToSearch, valuesToFind);
    assertEvaluatesTo(
      evaluate(expr),
      true,
      "arrayContainsAll with NaN in search values",
    );
  });
  test('arrayContainsAll - search value has duplicates', () {
    final arrayToSearch = array(true, "hi");
    final valuesToFind = array(true, true, true);
    final expr = arrayContainsAll(arrayToSearch, valuesToFind);
    assertEvaluatesTo(
      evaluate(expr),
      true,
      "arrayContainsAll with duplicate search values",
    );
  });
  test(
    'arrayContainsAll - array to search is empty and search value is empty',
    () {
      final arrayToSearch = array();
      final valuesToFind = array();
      final expr = arrayContainsAll(arrayToSearch, valuesToFind);
      assertEvaluatesTo(evaluate(expr), true, "arrayContainsAll both empty");
    },
  );
  test('arrayContainsAll - large number of elements', () {
    final elements = List<int>.generate(
      500,
      (int i) => i + 1,
    ).map((it) => it.toInt()).toList();
    // Use the statically imported 'array' directly here as it takes List<Expression>
    // The elements.map((it) => constant(it)).toList() is correct as array(List<Expression>) expects
    // Expression elements
    final arrayToSearch = array(elements.map((it) => constant(it)).toList());
    final valuesToFind = array(elements.map((it) => constant(it)).toList());
    final expr = arrayContainsAll(arrayToSearch, valuesToFind);
    assertEvaluatesTo(
      evaluate(expr),
      true,
      "arrayContainsAll large number of elements",
    );
  });

  // /* Null specific tests */
  test('array_singleNull_noMatch_returnsFalse', () {
    final arrayToSearch = array(null, "b");
    final valuesToFind = array("c", "d");
    final expr = arrayContainsAll(arrayToSearch, valuesToFind);
    assertEvaluatesTo(
      evaluate(expr),
      false,
      "array with single null, no match",
    );
  });
  test('array_singleNull_partialMatch_returnsFalse', () {
    final arrayToSearch = array(null, "b");
    final valuesToFind = array("b", "d");
    final expr = arrayContainsAll(arrayToSearch, valuesToFind);
    assertEvaluatesTo(
      evaluate(expr),
      false,
      "array with single null, partial match",
    );
  });
  test('array_singleNull_fullMatch_returnsTrue', () {
    final arrayToSearch = array(null, "b");
    final valuesToFind = array("b", null);
    final expr = arrayContainsAll(arrayToSearch, valuesToFind);
    assertEvaluatesTo(
      evaluate(expr),
      true,
      "array with single null, full match",
    );
  });
  test('array_allNull_noMatch_returnsFalse', () {
    final arrayToSearch = array(null, null);
    final valuesToFind = array("c", "d");
    final expr = arrayContainsAll(arrayToSearch, valuesToFind);
    assertEvaluatesTo(evaluate(expr), false, "array with all nulls, no match");
  });
  test('search_singleNull_noMatch_returnsFalse', () {
    final arrayToSearch = array("a", "b");
    final valuesToFind = array(null, "d");
    final expr = arrayContainsAll(arrayToSearch, valuesToFind);
    assertEvaluatesTo(
      evaluate(expr),
      false,
      "search with single null, no match",
    );
  });
  test('search_singleNull_partialMatch_returnsFalse', () {
    final arrayToSearch = array("a", "b");
    final valuesToFind = array(null, "a");
    final expr = arrayContainsAll(arrayToSearch, valuesToFind);
    assertEvaluatesTo(
      evaluate(expr),
      false,
      "search with single null, partial match",
    );
  });
  test('search_allNull_noMatch_returnsFalse', () {
    final arrayToSearch = array("a", "b");
    final valuesToFind = array(null, null);
    final expr = arrayContainsAll(arrayToSearch, valuesToFind);
    assertEvaluatesTo(evaluate(expr), false, "search with all nulls, no match");
  });
}
