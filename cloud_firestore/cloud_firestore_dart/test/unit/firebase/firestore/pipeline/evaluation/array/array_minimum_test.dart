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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/array/ArrayMinimumTests.kt
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
  test('arrayMinimum - general cases', () {
    final testCases = [
      (array(1, 2, 3), EvaluateResultValue(encodeValue(1)), "sorted numbers"),
      (array(3, 1, 2), EvaluateResultValue(encodeValue(1)), "unsorted numbers"),
      (array(1), EvaluateResultValue(encodeValue(1)), "single element"),
      (array(), EvaluateResultValue(NULL_VALUE), "empty array"),
      (array(1, null), EvaluateResultValue(encodeValue(1)), "null vs number"),
      (array("b", "a"), EvaluateResultValue(encodeValue("a")), "strings"),
      (nullValue(), EvaluateResultValue(NULL_VALUE), "null input (Unset)"),
      (field("nonexistent"), EvaluateResultValue(NULL_VALUE), "unset input"),
    ];

    for (final testCase in testCases) {
      final expr = arrayMinimum(testCase.array);
      final result = evaluate(expr);
      assertWithMessage(
        "arrayMinimum ${testCase.description}",
      ).that(result).isEqualTo(testCase.expected);
    }
  });
  test('arrayMinimum - error cases', () {
    final testCases = [
      (constant(123), EvaluateResultError, "number input (not array)"),
      (constant("string"), EvaluateResultError, "string input"),
    ];

    for (final testCase in testCases) {
      final expr = arrayMinimum(testCase.array);
      final result = evaluate(expr);
      assertWithMessage(
        "arrayMinimum ${testCase.description}",
      ).that(result).isEqualTo(testCase.expected);
    }
  });
}

typedef TestCase = (dynamic, dynamic, dynamic);

extension TestCaseFields on TestCase {
  dynamic get array => $1;
  dynamic get expected => $2;
  dynamic get description => $3;
}
