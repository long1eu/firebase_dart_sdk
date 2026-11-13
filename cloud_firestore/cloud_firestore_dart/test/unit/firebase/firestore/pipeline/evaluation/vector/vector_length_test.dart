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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/vector/VectorLengthTests.kt
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
import '../mirroring_test_cases.dart';

void main() {
  test('vectorLength - mirroring errors', () {
    for (final testCase in UNARY_MIRROR_TEST_CASES) {
      assertEvaluatesToNull(
        evaluate(vectorLength(testCase.input)),
        "vectorLength(\${testCase.name})",
      );
    }
  });
  test('vectorLength - length', () {
    final vectorValue = vector([1.0, 2.0].toDoubleArray());
    final expr = vectorLength(vectorValue);
    final result = evaluate(expr);
    assertWithMessage("vectorLength basic").that(result.isSuccess).isTrue();
    assertWithMessage(
      "vectorLength basic value",
    ).that(result.value).isEqualTo(encodeValue(2));
  });
  test('vectorLength - empty vector', () {
    final vectorValue = vector(<Object?>[].toDoubleArray());
    final expr = vectorLength(vectorValue);
    final result = evaluate(expr);
    assertWithMessage("vectorLength empty").that(result.isSuccess).isTrue();
    assertWithMessage(
      "vectorLength empty value",
    ).that(result.value).isEqualTo(encodeValue(0));
  });
  test('vectorLength - zero vector', () {
    final vectorValue = vector([2.0].toDoubleArray());
    final expr = vectorLength(vectorValue);
    final result = evaluate(expr);
    assertWithMessage("vectorLength zero").that(result.isSuccess).isTrue();
    assertWithMessage(
      "vectorLength zero value",
    ).that(result.value).isEqualTo(encodeValue(1));
  });
  test('vectorLength - not vector type returns error', () {
    assertEvaluatesToError(
      evaluate(vectorLength(array(1))),
      "vectorLength array",
    );
    assertEvaluatesToError(
      evaluate(vectorLength(constant("notAnArray"))),
      "vectorLength string",
    );
  });
}
