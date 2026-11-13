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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/array/ArrayMaximumNTests.kt
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
  test('arrayMaximumN - general cases', () {
    final testCases = [
      (
        array(3, 1, 2),
        constant(2),
        EvaluateResults.list([encodeValue(3), encodeValue(2)]),
        "basic max 2 (descending)",
      ),
      (array(1, 2), constant(0), EvaluateResults.list(<Object?>[]), "n=0"),
      (
        array(1, 2),
        constant(5),
        EvaluateResults.list([encodeValue(2), encodeValue(1)]),
        "n > size",
      ),
      (array(), constant(1), EvaluateResults.list(<Object?>[]), "empty array"),
    ];

    for (final testCase in testCases) {
      final expr = arrayMaximumN(testCase.array, testCase.n);
      final result = evaluate(expr);
      assertWithMessage(
        "arrayMaximumN ${testCase.description}",
      ).that(result).isEqualTo(testCase.expected);
    }
  });
  test('arrayMaximumN - error cases', () {
    final testCases = [
      (array(1), constant(-1), EvaluateResultError, "negative n"),

      // Android expects UNSET for a value that is not an array here; the Enterprise edition emulator returns an error.
      (
        constant("not array"),
        constant(1),
        EvaluateResultError,
        "invalid array type",
      ),
    ];

    for (final testCase in testCases) {
      final expr = arrayMaximumN(testCase.array, testCase.n);
      final result = evaluate(expr);
      assertWithMessage(
        "arrayMaximumN ${testCase.description}",
      ).that(result).isEqualTo(testCase.expected);
    }
  });
}

typedef TestCase = (dynamic, dynamic, dynamic, dynamic);

extension TestCaseFields on TestCase {
  dynamic get array => $1;
  dynamic get n => $2;
  dynamic get expected => $3;
  dynamic get description => $4;
}
