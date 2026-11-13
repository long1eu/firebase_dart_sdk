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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/array/ArrayGetTests.kt
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
  // --- ArrayGet Tests ---

  test('arrayGet - general cases', () {
    final testCases = [
      // Positive indexes
      (
        array("a", "b", "c", "d"),
        constant(0),
        EvaluateResultValue(encodeValue("a")),
        "positive index 0",
      ),
      (
        array("a", "b", "c", "d"),
        constant(1),
        EvaluateResultValue(encodeValue("b")),
        "positive index 1",
      ),
      (
        array("a", "b", "c", "d"),
        constant(2),
        EvaluateResultValue(encodeValue("c")),
        "positive index 2",
      ),
      (
        array("a", "b", "c", "d"),
        constant(3),
        EvaluateResultValue(encodeValue("d")),
        "positive index 3",
      ),
      (
        array("a", "b", "c", "d"),
        constant(4),
        EvaluateResultUnset,
        "positive index out of bounds",
      ),
      (
        array("a", "b", "c", "d"),
        constant(0),
        EvaluateResultValue(encodeValue("a")),
        "positive long index 0",
      ),
      (
        array("a", "b", "c", "d"),
        constant(1),
        EvaluateResultValue(encodeValue("b")),
        "positive long index 1",
      ),
      (
        array("a", "b", "c", "d"),
        constant(2),
        EvaluateResultValue(encodeValue("c")),
        "positive long index 2",
      ),
      (
        array("a", "b", "c", "d"),
        constant(3),
        EvaluateResultValue(encodeValue("d")),
        "positive long index 3",
      ),
      (
        array("a", "b", "c", "d"),
        constant(4),
        EvaluateResultUnset,
        "positive long index out of bounds",
      ),

      // Negative indexes
      (
        array("a", "b", "c", "d"),
        constant(-1),
        EvaluateResultValue(encodeValue("d")),
        "negative index -1",
      ),
      (
        array("a", "b", "c", "d"),
        constant(-2),
        EvaluateResultValue(encodeValue("c")),
        "negative index -2",
      ),
      (
        array("a", "b", "c", "d"),
        constant(-3),
        EvaluateResultValue(encodeValue("b")),
        "negative index -3",
      ),
      (
        array("a", "b", "c", "d"),
        constant(-4),
        EvaluateResultValue(encodeValue("a")),
        "negative index -4",
      ),
      (
        array("a", "b", "c", "d"),
        constant(-5),
        EvaluateResultUnset,
        "negative index out of bounds",
      ),
      (
        array("a", "b", "c", "d"),
        constant(-1),
        EvaluateResultValue(encodeValue("d")),
        "negative long index -1",
      ),
      (
        array("a", "b", "c", "d"),
        constant(-2),
        EvaluateResultValue(encodeValue("c")),
        "negative long index -2",
      ),
      (
        array("a", "b", "c", "d"),
        constant(-3),
        EvaluateResultValue(encodeValue("b")),
        "negative long index -3",
      ),
      (
        array("a", "b", "c", "d"),
        constant(-4),
        EvaluateResultValue(encodeValue("a")),
        "negative long index -4",
      ),
      (
        array("a", "b", "c", "d"),
        constant(-5),
        EvaluateResultUnset,
        "negative long index out of bounds",
      ),

      // Far out of bounds indexes
      (array(), constant(0), EvaluateResultUnset, "empty array"),
      (array(), constant(0), EvaluateResultUnset, "empty array long index"),
      (array(), constant(42), EvaluateResultUnset, "empty array far out"),
      (
        array(),
        constant(-42),
        EvaluateResultUnset,
        "empty array far out negative",
      ),
      (
        array("a", "b", "c"),
        constant(42),
        EvaluateResultUnset,
        "far positive index",
      ),
      (
        array("a", "b", "c"),
        constant(-42),
        EvaluateResultUnset,
        "far negative index",
      ),
      (
        array("a", "b", "c"),
        constant(maxLong),
        EvaluateResultUnset,
        "max long index",
      ),
      (
        array("a", "b", "c"),
        constant(minLong),
        EvaluateResultUnset,
        "min long index",
      ),

      // Null/NaN values
      (
        array(nullValue()),
        constant(0),
        EvaluateResultValue(NULL_VALUE),
        "get NULL from array",
      ),
      (
        array(constant(double.nan)),
        constant(0),
        EvaluateResultValue(encodeValue(double.nan)),
        "get NaN from array",
      ),
      (
        array(nullValue(), "a"),
        constant(0),
        EvaluateResultValue(NULL_VALUE),
        "get NULL from array with other values",
      ),
      (
        array("a", nullValue()),
        constant(1),
        EvaluateResultValue(NULL_VALUE),
        "get NULL from array with other values 2",
      ),
      (
        array(constant(double.nan), "a"),
        constant(0),
        EvaluateResultValue(encodeValue(double.nan)),
        "get NaN from array with other values",
      ),
      (
        array("a", constant(double.nan)),
        constant(1),
        EvaluateResultValue(encodeValue(double.nan)),
        "get NaN from array with other values 2",
      ),
    ];

    for (final testCase in testCases) {
      final expr = arrayGet(testCase.array, testCase.index);
      final result = evaluate(expr);
      assertWithMessage(
        "arrayGet - ${testCase.description}",
      ).that(result).isEqualTo(testCase.expected);
    }
  });
  test('arrayGet - invalid array types', () {
    final testCases = [
      // Android expects UNSET for all of these here; the Enterprise edition emulator returns null for a null or missing array and an error for a value of another type.
      (
        field("nonexistent"),
        constant(0),
        EvaluateResults.NULL,
        "array is UNSET",
      ),
      (nullValue(), constant(0), EvaluateResults.NULL, "array is NULL"),
      (
        map(<String, Object?>{"0": 123}),
        constant(0),
        EvaluateResultError,
        "array is MAP",
      ),
      (
        map(<String, Object?>{}),
        constant(0),
        EvaluateResultError,
        "array is empty MAP",
      ),
      (constant("foo"), constant(0), EvaluateResultError, "array is STRING"),
      (constant(2), constant(0), EvaluateResultError, "array is INT"),
      (constant(2.0), constant(0), EvaluateResultError, "array is DOUBLE"),
    ];
    for (final testCase in testCases) {
      final expr = arrayGet(testCase.array, testCase.index);
      final result = evaluate(expr);
      assertWithMessage(
        "arrayGet - ${testCase.description}",
      ).that(result).isEqualTo(testCase.expected);
    }
  });
  test('arrayGet - invalid index types', () {
    final testCases = [
      // Invalid index with a valid array.
      (
        array("a", "b", "c"),
        constant(0.0),
        EvaluateResultError,
        "index is DOUBLE",
      ),
      (
        array("a", "b", "c"),
        constant(-0.0),
        EvaluateResultError,
        "index is -0.0",
      ),
      (
        array("a", "b", "c"),
        constant(1.5),
        EvaluateResultError,
        "index is FLOAT",
      ),
      (
        array("a", "b", "c"),
        // Android expects an error for a missing or null index here; the Enterprise edition emulator returns null.
        field("nonexistent"),
        EvaluateResults.NULL,
        "index is UNSET",
      ),
      (
        array("a", "b", "c"),
        nullValue(),
        EvaluateResults.NULL,
        "index is NULL",
      ),
      (
        array("a", "b", "c"),
        constant("foo"),
        EvaluateResultError,
        "index is STRING",
      ),
      (array("a", "b", "c"), array(1), EvaluateResultError, "index is ARRAY"),
      (
        array("a", "b", "c"),
        map(<String, Object?>{"foo": 1}),
        EvaluateResultError,
        "index is MAP",
      ),

      // Invalid index with an invalid array.
      (
        nullValue(),
        constant(0.0),
        EvaluateResultError,
        "NULL array, DOUBLE index",
      ),
      (
        nullValue(),
        constant(-0.0),
        EvaluateResultError,
        "NULL array, -0.0 index",
      ),
      (
        nullValue(),
        constant(1.5),
        EvaluateResultError,
        "NULL array, FLOAT index",
      ),
      (
        // Android expects an error for a missing or null index here; the
        // Enterprise edition emulator returns null.
        nullValue(),
        field("nonexistent"),
        EvaluateResults.NULL,
        "NULL array, UNSET index",
      ),
      (
        nullValue(),
        nullValue(),
        EvaluateResults.NULL,
        "NULL array, NULL index",
      ),
      (
        nullValue(),
        constant("foo"),
        EvaluateResultError,
        "NULL array, STRING index",
      ),
      (nullValue(), array(1), EvaluateResultError, "NULL array, ARRAY index"),
      (
        nullValue(),
        map(<String, Object?>{"foo": 1}),
        EvaluateResultError,
        "NULL array, MAP index",
      ),
    ];

    for (final testCase in testCases) {
      final expr = arrayGet(testCase.array, testCase.index);
      final result = evaluate(expr);
      assertWithMessage(
        "arrayGet - ${testCase.description}",
      ).that(result).isEqualTo(testCase.expected);
    }
  });
}

typedef ArrayGetTestCase = (dynamic, dynamic, dynamic, dynamic);

extension ArrayGetTestCaseFields on ArrayGetTestCase {
  dynamic get array => $1;
  dynamic get index => $2;
  dynamic get expected => $3;
  dynamic get description => $4;
}
