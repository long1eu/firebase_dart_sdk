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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/arithmetic/DivideTests.kt
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

// The cases of this file use doubles with integral values (1.0, -0.0,
// Double.MAX_VALUE) or 64-bit integers. Compiled to JavaScript (dart2js) an
// integral double is an int and an int beyond 2^53 is not exact, so they run
// on the VM only. web_numbers_test.dart covers evaluation compiled to
// JavaScript.
@TestOn('vm')
library;

import 'package:test/test.dart' show TestOn, test;

import '../evaluation_test_util.dart';
import '../mirroring_test_cases.dart';

void main() {
  test('divideMirrorsErrors', () {
    for (final (name, left, right) in BINARY_MIRROR_TEST_CASES) {
      final expr = divide(left, right);
      assertEvaluatesToNull(evaluate(expr), "divide($name)");
    }
  });
  test('divideFunctionTestWithBasicNumerics', () {
    assertThat(
      evaluate(divide(constant(10), constant(2))).value,
    ).isEqualTo(encodeValue(5));
    assertThat(
      evaluate(divide(constant(10), constant(2.0))).value,
    ).isEqualTo(encodeValue(5.0));
    assertThat(
      evaluate(divide(constant(10.0), constant(3))).value,
    ).isEqualTo(encodeValue(10.0 / 3.0));
    assertThat(
      evaluate(divide(constant(10.0), constant(7.0))).value,
    ).isEqualTo(encodeValue(10.0 / 7.0));
  });
  test('divideFunctionTestWithBasicNonNumerics', () {
    assertThat(evaluate(divide(constant(1), constant("1"))).isError).isTrue();
    assertThat(evaluate(divide(constant("1"), constant(1.0))).isError).isTrue();
    assertThat(evaluate(divide(constant("1"), constant("1"))).isError).isTrue();
  });
  test('divideFunctionTestWithLongDivision', () {
    assertThat(
      evaluate(divide(constant(10), constant(3))).value,
    ).isEqualTo(encodeValue(3));
    assertThat(
      evaluate(divide(constant(-10), constant(3))).value,
    ).isEqualTo(encodeValue(-3));
    assertThat(
      evaluate(divide(constant(10), constant(-3))).value,
    ).isEqualTo(encodeValue(-3));
    assertThat(
      evaluate(divide(constant(-10), constant(-3))).value,
    ).isEqualTo(encodeValue(3));
  });
  test('divideFunctionTestWithDoubleDivisionOverflow', () {
    assertThat(
      evaluate(divide(constant(double.maxFinite), constant(0.5))).value,
    ).isEqualTo(encodeValue(double.infinity));
    assertThat(
      evaluate(divide(constant(-double.maxFinite), constant(0.5))).value,
    ).isEqualTo(encodeValue(double.negativeInfinity));
  });
  test('divideFunctionTestWithByZero', () {
    assertThat(evaluate(divide(constant(1), constant(0))).isError).isTrue();
    assertThat(
      evaluate(divide(constant(1.1), constant(0.0))).value,
    ).isEqualTo(encodeValue(double.infinity));
    assertThat(
      evaluate(divide(constant(1.1), constant(-0.0))).value,
    ).isEqualTo(encodeValue(double.negativeInfinity));
    assertThat(
      evaluate(divide(constant(0.0), constant(0.0))).value,
    ).isEqualTo(encodeValue(double.nan));
  });
  test('divideFunctionTestWithNanNumberReturnNaN', () {
    final nanVal = double.nan;
    assertThat(
      evaluate(divide(constant(1), constant(nanVal))).value,
    ).isEqualTo(encodeValue(nanVal));
    assertThat(
      evaluate(divide(constant(nanVal), constant(1))).value,
    ).isEqualTo(encodeValue(nanVal));
    assertThat(
      evaluate(divide(constant(1.0), constant(nanVal))).value,
    ).isEqualTo(encodeValue(nanVal));
    assertThat(
      evaluate(divide(constant(nanVal), constant(1.0))).value,
    ).isEqualTo(encodeValue(nanVal));
    assertThat(
      evaluate(divide(constant(double.infinity), constant(nanVal))).value,
    ).isEqualTo(encodeValue(nanVal));
    assertThat(
      evaluate(divide(constant(nanVal), constant(nanVal))).value,
    ).isEqualTo(encodeValue(nanVal));
    assertThat(
      evaluate(
        divide(constant(double.negativeInfinity), constant(nanVal)),
      ).value,
    ).isEqualTo(encodeValue(nanVal));
    assertThat(
      evaluate(
        divide(constant(nanVal), constant(double.negativeInfinity)),
      ).value,
    ).isEqualTo(encodeValue(nanVal));
  });
  test('divideFunctionTestWithNanNotNumberTypeReturnError', () {
    assertThat(
      evaluate(divide(constant(double.nan), constant("hello world"))).isError,
    ).isTrue();
  });
  test('divideFunctionTestWithPositiveInfinity', () {
    assertThat(
      evaluate(divide(constant(double.infinity), constant(1))).value,
    ).isEqualTo(encodeValue(double.infinity));
    assertThat(
      evaluate(divide(constant(1), constant(double.infinity))).value,
    ).isEqualTo(encodeValue(0.0));
  });
  test('divideFunctionTestWithNegativeInfinity', () {
    assertThat(
      evaluate(divide(constant(double.negativeInfinity), constant(1))).value,
    ).isEqualTo(encodeValue(double.negativeInfinity));
    assertThat(
      evaluate(divide(constant(1), constant(double.negativeInfinity))).value,
    ).isEqualTo(encodeValue(-0.0));
  });
  test('divideFunctionTestWithPositiveInfinityNegativeInfinityReturnsNan', () {
    assertThat(
      evaluate(
        divide(constant(double.infinity), constant(double.negativeInfinity)),
      ).value,
    ).isEqualTo(encodeValue(double.nan));
    assertThat(
      evaluate(
        divide(constant(double.negativeInfinity), constant(double.infinity)),
      ).value,
    ).isEqualTo(encodeValue(double.nan));
  });
}
