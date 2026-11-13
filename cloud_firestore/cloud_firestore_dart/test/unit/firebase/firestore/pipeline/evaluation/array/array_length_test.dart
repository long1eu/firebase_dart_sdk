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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/array/ArrayLengthTests.kt
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
  // --- ArrayLength Tests ---
  test('arrayLength - length', () {
    final expr = arrayLength(array("1", 42, true));
    final result = evaluate(expr);
    assertWithMessage("arrayLength basic").that(result.isSuccess).isTrue();
    assertWithMessage(
      "arrayLength basic value",
    ).that(result.value).isEqualTo(encodeValue(3));
  });
  test('arrayLength - empty array', () {
    final expr = arrayLength(array());
    final result = evaluate(expr);
    assertWithMessage("arrayLength empty").that(result.isSuccess).isTrue();
    assertWithMessage(
      "arrayLength empty value",
    ).that(result.value).isEqualTo(encodeValue(0));
  });
  test('arrayLength - array with duplicate elements', () {
    final expr = arrayLength(array(true, true));
    final result = evaluate(expr);
    assertWithMessage("arrayLength duplicates").that(result.isSuccess).isTrue();
    assertWithMessage(
      "arrayLength duplicates value",
    ).that(result.value).isEqualTo(encodeValue(2));
  });
  test('arrayLength - null and unset inputs', () {
    final testCases = [
      (nullValue(), NULL_VALUE),
      (field("nonexistent"), NULL_VALUE),
    ];
    for (final (input, expected) in testCases) {
      final expr = arrayLength(input);
      final result = evaluate(expr);
      assertWithMessage(
        "arrayLength null/unset input",
      ).that(result.isSuccess).isTrue();
      assertWithMessage(
        "arrayLength null/unset input value",
      ).that(result.value).isEqualTo(expected);
    }
  });
  test('arrayLength - not array type returns error', () {
    assertEvaluatesToError(
      evaluate(arrayLength(vector(<double>[1.0, 2.0]))),
      "The function array_length(...) requires `Array` but got `VECTOR`.",
    );
    assertEvaluatesToError(
      evaluate(arrayLength(constant("notAnArray"))),
      "arrayLength string",
    );
    assertEvaluatesToError(
      evaluate(arrayLength(constant(123))),
      "arrayLength long",
    );
    assertEvaluatesToError(
      evaluate(arrayLength(constant(true))),
      "arrayLength boolean",
    );
    assertEvaluatesToError(
      evaluate(arrayLength(map(<String, Object?>{"a": 1}))),
      "arrayLength map",
    );
  });
}
