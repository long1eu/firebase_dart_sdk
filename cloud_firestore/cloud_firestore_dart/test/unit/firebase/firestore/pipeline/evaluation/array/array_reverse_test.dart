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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/array/ArrayReverseTests.kt
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
  // --- ArrayReverse Tests ---
  test('arrayReverse - null and unset inputs', () {
    final testCases = [
      (nullValue(), NULL_VALUE),
      (field("nonexistent"), NULL_VALUE),
    ];
    for (final (input, expected) in testCases) {
      final expr = arrayReverse(input);
      final result = evaluate(expr);
      assertWithMessage(
        "arrayReverse null/unset input",
      ).that(result.isSuccess).isTrue();
      assertWithMessage(
        "arrayReverse null/unset input value",
      ).that(result.value).isEqualTo(expected);
    }
  });
  test('arrayReverse - one element', () {
    final expr = arrayReverse(array(42));
    final result = evaluate(expr);
    assertWithMessage(
      "arrayReverse one element success",
    ).that(result.isSuccess).isTrue();
    final expected = encodeValue([42].map((it) => encodeValue(it)).toList());
    assertWithMessage(
      "arrayReverse one element value",
    ).that(result.value).isEqualTo(expected);
  });
  test('arrayReverse - duplicate elements', () {
    final expr = arrayReverse(array(1, 2, 2, 3));
    final result = evaluate(expr);
    assertWithMessage(
      "arrayReverse duplicate elements success",
    ).that(result.isSuccess).isTrue();
    final expected = encodeValue(
      [3, 2, 2, 1].map((it) => encodeValue(it)).toList(),
    );
    assertWithMessage(
      "arrayReverse duplicate elements value",
    ).that(result.value).isEqualTo(expected);
  });
  test('arrayReverse - mixed types', () {
    final input = array("1", 42, true);
    final expr = arrayReverse(input);
    final result = evaluate(expr);
    assertWithMessage(
      "arrayReverse mixed types success",
    ).that(result.isSuccess).isTrue();
    final expected = encodeValue([
      encodeValue(true),
      encodeValue(42),
      encodeValue("1"),
    ]);
    assertWithMessage(
      "arrayReverse mixed types value",
    ).that(result.value).isEqualTo(expected);
  });
  test('arrayReverse - large array', () {
    final elements = List<int>.generate(
      500,
      (int i) => i + 1,
    ).map((it) => it.toInt()).toList();
    final arrayToReverse = array(elements.map((it) => constant(it)).toList());
    final expr = arrayReverse(arrayToReverse);
    final result = evaluate(expr);
    assertWithMessage(
      "arrayReverse large array success",
    ).that(result.isSuccess).isTrue();
    final expected = encodeValue(
      elements.reversed.map((it) => encodeValue(it)).toList(),
    );
    assertWithMessage(
      "arrayReverse large array value",
    ).that(result.value).isEqualTo(expected);
  });
  test('arrayReverse - not array type returns error', () {
    assertEvaluatesToError(
      evaluate(arrayReverse(constant("notAnArray"))),
      "arrayReverse string",
    );
    assertEvaluatesToError(
      evaluate(arrayReverse(constant(123))),
      "arrayReverse long",
    );
    assertEvaluatesToError(
      evaluate(arrayReverse(constant(true))),
      "arrayReverse boolean",
    );
    assertEvaluatesToError(
      evaluate(arrayReverse(map(<String, Object?>{"a": 1}))),
      "The function array_reverse(...) requires `Array` but got `MAP`.",
    );
  });
}
