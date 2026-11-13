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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/array/ArrayConcatTests.kt
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
  // --- ArrayConcat Tests ---
  test('arrayConcat - general cases', () {
    final testCases = [
      (
        array(<Object?>[]),
        array(<Object?>[]),
        array(<Object?>[]),
        "two empty arrays",
      ),
      (
        array([1.0, 2, 3]),
        array([4, double.nan, 6]),
        array([1.0, 2, 3, 4, double.nan, 6]),
        "two arrays with mixed types",
      ),
      (
        array(<Object?>[]),
        array([1, 2, 3]),
        array([1, 2, 3]),
        "empty array with non-empty array",
      ),
      (
        array([1, 2, 3]),
        array(<Object?>[]),
        array([1, 2, 3]),
        "non-empty array with empty array",
      ),
      (
        array([null]),
        array(["d", "l", "c"]),
        array([null, "d", "l", "c"]),
        "array with null with another array",
      ),
      (
        array([null]),
        array([null]),
        array([null, null]),
        "two arrays with null",
      ),
      (nullValue(), array(nullValue()), nullValue(), "null with array"),
      (field("non-existent"), array(1, 2), nullValue(), "unset with array"),
    ];

    for (final testCase in testCases) {
      final expr = arrayConcat(testCase.left, testCase.right);
      final result = evaluate(expr);
      final expected = evaluate(testCase.expected);
      if (testCase.expected == null) {
        assertEvaluatesToNull(
          result,
          "arrayConcat with ${testCase.description}",
        );
      } else {
        assertWithMessage(
          "arrayConcat with ${testCase.description} success",
        ).that(result.isSuccess).isTrue();
        assertWithMessage(
          "arrayConcat with ${testCase.description} value",
        ).that(result).isEqualTo(expected);
      }
    }
  });
  test('arrayConcat - three arrays', () {
    final expr = arrayConcat(array(1, 2), array(3, 4), array(5, 6));
    final result = evaluate(expr);
    assertWithMessage(
      "arrayConcat three arrays success",
    ).that(result.isSuccess).isTrue();
    final expected = encodeValue(
      [1, 2, 3, 4, 5, 6].map((it) => encodeValue(it)).toList(),
    );
    assertWithMessage(
      "arrayConcat three arrays value",
    ).that(result.value).isEqualTo(expected);
  });
  test('arrayConcat - with null input returns null', () {
    final expr = arrayConcat(array(1, 2), nullValue(), array(3, 4));
    final result = evaluate(expr);
    assertEvaluatesToNull(result, "arrayConcat with null input");
  });
  test('arrayConcat - with non array returns error', () {
    final expr = arrayConcat(array(1, 2), constant("not an array"));
    final result = evaluate(expr);
    assertEvaluatesToError(result, "arrayConcat with non array");
  });
  test('arrayConcat - with nested arrays', () {
    final nestedArray1 = array(1, 2);
    final nestedArray2 = array(3, 4);
    final expr = arrayConcat(array(nestedArray1), array(nestedArray2));
    final result = evaluate(expr);
    assertWithMessage(
      "arrayConcat with nested arrays success",
    ).that(result.isSuccess).isTrue();
    final expected = encodeValue([
      encodeValue([1, 2].map((it) => encodeValue(it)).toList()),
      encodeValue([3, 4].map((it) => encodeValue(it)).toList()),
    ]);
    assertWithMessage(
      "arrayConcat with nested arrays value",
    ).that(result.value).isEqualTo(expected);
  });
  test('arrayConcat - mirror behavior', () {
    assertEvaluatesToNull(
      evaluate(arrayConcat(nullValue(), nullValue())),
      "arrayConcat(null, null)",
    );
    assertEvaluatesToNull(
      evaluate(arrayConcat(nullValue(), field("non-existent"))),
      "arrayConcat(null, unset)",
    );
    assertEvaluatesToNull(
      evaluate(arrayConcat(field("non-existent"), nullValue())),
      "arrayConcat(unset, null)",
    );
    assertEvaluatesToNull(
      evaluate(arrayConcat(field("non-existent"), field("non-existent"))),
      "arrayConcat(unset, unset)",
    );
  });
  test('arrayConcat - unsupported argument after null returns error', () {
    final expr = arrayConcat(
      array(1, 2),
      nullValue(),
      constant("not an array"),
    );
    final result = evaluate(expr);
    assertEvaluatesToError(
      result,
      "arrayConcat with unsupported argument after null",
    );
  });
  test('arrayConcat - with multiple arrays and mixed types', () {
    final expr = arrayConcat(
      array(1, 1, 2),
      array(2, double.infinity, 3),
      array("string", "a", "b", "c", "d", "e", "f", "g", "h", "i"),
    );
    final result = evaluate(expr);
    assertWithMessage(
      "arrayConcat with multiple arrays and mixed types success",
    ).that(result.isSuccess).isTrue();
    final expected = evaluate(
      array([
        1,
        1,
        2,
        2,
        double.infinity,
        3,
        "string",
        "a",
        "b",
        "c",
        "d",
        "e",
        "f",
        "g",
        "h",
        "i",
      ]),
    );
    assertWithMessage(
      "arrayConcat with multiple arrays and mixed types value",
    ).that(result).isEqualTo(expected);
  });
}

typedef ConcatTestCase = (dynamic, dynamic, dynamic, dynamic);

extension ConcatTestCaseFields on ConcatTestCase {
  dynamic get left => $1;
  dynamic get right => $2;
  dynamic get expected => $3;
  dynamic get description => $4;
}
