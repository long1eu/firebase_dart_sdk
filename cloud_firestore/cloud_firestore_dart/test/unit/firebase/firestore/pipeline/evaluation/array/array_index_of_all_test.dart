// Copyright 2026 Google LLC
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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/array/ArrayIndexOfAllTests.kt
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
  test('arrayIndexOfAll - general cases', () {
    final testCases = [
      (
        array("1", 42, true),
        constant("1"),
        EvaluateResultValue(
          encodeValue([0].map((it) => encodeValue(it)).toList()),
        ),
        "basic match single element",
      ),
      (
        array("1", 42, true, 42),
        constant(42),
        EvaluateResultValue(
          encodeValue([1, 3].map((it) => encodeValue(it)).toList()),
        ),
        "basic match multiple elements",
      ),
      (
        array("1", 42, true),
        constant("missing"),
        EvaluateResultValue(
          encodeValue(<Object?>[].map((it) => encodeValue(it)).toList()),
        ),
        "no match",
      ),
      (
        array(1, 1, 1),
        constant(1),
        EvaluateResultValue(
          encodeValue([0, 1, 2].map((it) => encodeValue(it)).toList()),
        ),
        "match all duplicates",
      ),
      (
        array(),
        constant("anything"),
        EvaluateResultValue(
          encodeValue(<Object?>[].map((it) => encodeValue(it)).toList()),
        ),
        "empty array",
      ),
      (
        array("1", null, true, null),
        nullValue(),
        EvaluateResultValue(
          encodeValue([1, 3].map((it) => encodeValue(it)).toList()),
        ),
        "match null element",
      ),
      (
        nullValue(),
        constant("anything"),
        EvaluateResultValue(NULL_VALUE),
        "null input array",
      ),
      (
        field("nonexistent"),
        constant("anything"),
        EvaluateResultValue(NULL_VALUE),
        "unset input array",
      ),
      (
        array("1", 2),
        // Android expects null when the value to look for is missing here; the Enterprise edition emulator returns that nothing was found.
        field("nonexistent"),
        EvaluateResults.list(<Object?>[]),
        "unset input value",
      ),
    ];

    for (final testCase in testCases) {
      final expr = arrayIndexOfAll(testCase.array, testCase.value);
      final result = evaluate(expr);
      assertWithMessage(
        "arrayIndexOfAll ${testCase.description}",
      ).that(result).isEqualTo(testCase.expected);
    }
  });
  test('arrayIndexOfAll - error cases', () {
    final testCases = [
      (
        vector(<double>[1.0, 2.0]),
        constant(1.0),
        EvaluateResultError,
        "received unexpected input type vector",
      ),
      (
        constant("notAnArray"),
        constant("a"),
        EvaluateResultError,
        "received unexpected input type string",
      ),
      (
        constant(123),
        constant(123),
        EvaluateResultError,
        "received unexpected input type long",
      ),
      (
        constant(true),
        constant(true),
        EvaluateResultError,
        "received unexpected input type boolean",
      ),
      (
        map(<String, Object?>{"a": 1}),
        constant("a"),
        EvaluateResultError,
        "received unexpected input type map",
      ),
    ];

    for (final testCase in testCases) {
      final expr = arrayIndexOfAll(testCase.array, testCase.value);
      final result = evaluate(expr);
      assertWithMessage(
        "arrayIndexOfAll ${testCase.description}",
      ).that(result).isEqualTo(testCase.expected);
    }
  });
}

typedef ArrayIndexOfAllTestCase = (dynamic, dynamic, dynamic, dynamic);

extension ArrayIndexOfAllTestCaseFields on ArrayIndexOfAllTestCase {
  dynamic get array => $1;
  dynamic get value => $2;
  dynamic get expected => $3;
  dynamic get description => $4;
}
