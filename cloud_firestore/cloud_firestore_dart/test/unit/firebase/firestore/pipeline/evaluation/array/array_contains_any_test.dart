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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/array/ArrayContainsAnyTests.kt
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
  // --- ArrayContainsAny Tests ---
  test('arrayContainsAny - value found in array', () {
    final arrayToSearch = array(42, "matang", true);
    final valuesToFind = array("matang", false);
    final expr = arrayContainsAny(arrayToSearch, valuesToFind);
    assertEvaluatesTo(evaluate(expr), true, "arrayContainsAny value found");
  });
  test('arrayContainsAny - value found in array with null returns true', () {
    final arrayToSearch = array(nullValue(), "hello");
    final valuesToFind = array(nullValue(), "hello");
    final expr = arrayContainsAny(arrayToSearch, valuesToFind);
    assertEvaluatesTo(evaluate(expr), true, "arrayContainsAny with null");
  });
  test('arrayContainsAny - equivalent numerics', () {
    final arrayToSearch = array(42, "matang", true);
    final valuesToFind = array(42.0, 2);
    final expr = arrayContainsAny(arrayToSearch, valuesToFind);
    assertEvaluatesTo(
      evaluate(expr),
      true,
      "arrayContainsAny equivalent numerics",
    );
  });
  test('arrayContainsAny - values not found in array', () {
    final arrayToSearch = array(42, "matang", true);
    final valuesToFind = array(99, "false");
    final expr = arrayContainsAny(arrayToSearch, valuesToFind);
    assertEvaluatesTo(
      evaluate(expr),
      false,
      "arrayContainsAny values not found",
    );
  });
  test(
    'arrayContainsAny - values not found in array with null returns false',
    () {
      final arrayToSearch = array(nullValue(), 42);
      final valuesToFind = array(99, "false");
      final expr = arrayContainsAny(arrayToSearch, valuesToFind);
      assertEvaluatesTo(
        evaluate(expr),
        false,
        "arrayContainsAny values not found with null",
      );
    },
  );
  test(
    'arrayContainsAny - values not found in array only null returns false',
    () {
      final arrayToSearch = array(nullValue(), nullValue());
      final valuesToFind = array(99, "false");
      final expr = arrayContainsAny(arrayToSearch, valuesToFind);
      assertEvaluatesTo(
        evaluate(expr),
        false,
        "arrayContainsAny values not found in only null",
      );
    },
  );
  test('arrayContainsAny - search values with null returns true', () {
    final arrayToSearch = array(nullValue(), 42);
    final valuesToFind = array(nullValue(), "false");
    final expr = arrayContainsAny(arrayToSearch, valuesToFind);
    assertEvaluatesTo(
      evaluate(expr),
      true,
      "arrayContainsAny search values with null",
    );
  });
  test('arrayContainsAny - search values only null returns true', () {
    final arrayToSearch = array(nullValue(), nullValue());
    final valuesToFind = array(nullValue(), nullValue());
    final expr = arrayContainsAny(arrayToSearch, valuesToFind);
    assertEvaluatesTo(
      evaluate(expr),
      true,
      "arrayContainsAny search values only null",
    );
  });
  test(
    'arrayContainsAny - search values array with null and match returns true',
    () {
      final arrayToSearch = array(array(nullValue()), "a");
      final valuesToFind = array(array(nullValue()), "a");
      final expr = arrayContainsAny(arrayToSearch, valuesToFind);
      assertEvaluatesTo(
        evaluate(expr),
        true,
        "arrayContainsAny with array with null and match",
      );
    },
  );
  test(
    'arrayContainsAny - search values array with null and no match returns true',
    () {
      final arrayToSearch = array(array(nullValue()), "a");
      final valuesToFind = array(array(nullValue()), "b");
      final expr = arrayContainsAny(arrayToSearch, valuesToFind);
      assertEvaluatesTo(
        evaluate(expr),
        true,
        "arrayContainsAny with array with null and no match",
      );
    },
  );
  test(
    'arrayContainsAny - search values map with null and match returns true',
    () {
      final arrayToSearch = array(<String, Object?>{"a": nullValue()}, "b");
      final valuesToFind = array(<String, Object?>{"a": nullValue()}, "b");
      final expr = arrayContainsAny(arrayToSearch, valuesToFind);
      assertEvaluatesTo(
        evaluate(expr),
        true,
        "arrayContainsAny with map with null and match",
      );
    },
  );
  test(
    'arrayContainsAny - search values map with null and no match returns true',
    () {
      final arrayToSearch = array(<String, Object?>{"a": nullValue()}, "b");
      final valuesToFind = array(<String, Object?>{"a": nullValue()}, "c");
      final expr = arrayContainsAny(arrayToSearch, valuesToFind);
      assertEvaluatesTo(
        evaluate(expr),
        true,
        "arrayContainsAny with map with null and no match",
      );
    },
  );
  test('arrayContainsAny - both input type is array', () {
    final arrayToSearch = array(array(1, 2, 3), array(4, 5, 6), array(7, 8, 9));
    final valuesToFind = array(array(1, 2, 3), array(4, 5, 6));
    final expr = arrayContainsAny(arrayToSearch, valuesToFind);
    assertEvaluatesTo(evaluate(expr), true, "arrayContainsAny nested arrays");
  });
  test('arrayContainsAny - search is null returns true', () {
    final arrayToSearch = array(null, 1, "matang", true);
    final valuesToFind = array(nullValue()); // Searching for a null
    final expr = arrayContainsAny(arrayToSearch, valuesToFind);
    assertEvaluatesTo(evaluate(expr), true, "arrayContainsAny search for null");
  });
  test('arrayContainsAny - array is not array type returns error', () {
    final expr = arrayContainsAny(constant("matang"), array("matang", false));
    assertEvaluatesToError(
      evaluate(expr),
      "arrayContainsAny first arg not array",
    );
  });
  test('arrayContainsAny - search is not array type returns error', () {
    final expr = arrayContainsAny(array("matang", false), constant("matang"));
    assertEvaluatesToError(
      evaluate(expr),
      "arrayContainsAny second arg not array",
    );
  });
  test('arrayContainsAny - array not found returns null', () {
    final expr = arrayContainsAny(field("not-exist"), array("matang", false));
    // Accessing a non-existent field results in UNSET, which evaluates to NULL.
    assertEvaluatesToNull(
      evaluate(expr),
      "arrayContainsAny field not-exist for array",
    );
  });
  test('arrayContainsAny - search not found returns null', () {
    final arrayToSearch = array(42, "matang", true);
    final expr = arrayContainsAny(arrayToSearch, field("not-exist"));
    // Accessing a non-existent field results in UNSET, which evaluates to NULL.
    assertEvaluatesToNull(
      evaluate(expr),
      "arrayContainsAny field not-exist for search values",
    );
  });
}
