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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/arithmetic/ModTests.kt
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
  test('modFunctionTestWithMirrorError', () {
    for (final (name, left, right) in BINARY_MIRROR_TEST_CASES) {
      final expr = mod(left, right);
      assertEvaluatesToNull(evaluate(expr), "mod($name)");
    }
  });
  test('modFunctionTestWithDivisorZero', () {
    assertThat(evaluate(mod(constant(42), constant(0))).isError).isTrue();
    assertThat(
      evaluate(mod(constant(42.0), constant(0.0))).value,
    ).isEqualTo(encodeValue(double.nan));
    assertThat(
      evaluate(mod(constant(42.0), constant(-0.0))).value,
    ).isEqualTo(encodeValue(double.nan));
  });
  test('modFunctionTestWithDividendZeroReturnsZero', () {
    assertThat(
      evaluate(mod(constant(0), constant(42))).value,
    ).isEqualTo(encodeValue(0));
    assertThat(
      evaluate(mod(constant(0.0), constant(42.0))).value,
    ).isEqualTo(encodeValue(0.0));
    assertThat(
      evaluate(mod(constant(-0.0), constant(42.0))).value,
    ).isEqualTo(encodeValue(-0.0));
  });
  test('modFunctionTestWithLongPositivePositive', () {
    assertThat(
      evaluate(mod(constant(10), constant(3))).value,
    ).isEqualTo(encodeValue(1));
  });
  test('modFunctionTestWithLongNegativeNegative', () {
    assertThat(
      evaluate(mod(constant(-10), constant(-3))).value,
    ).isEqualTo(encodeValue(-1));
  });
  test('modFunctionTestWithLongPositiveNegative', () {
    assertThat(
      evaluate(mod(constant(10), constant(-3))).value,
    ).isEqualTo(encodeValue(1));
  });
  test('modFunctionTestWithLongNegativePositive', () {
    assertThat(
      evaluate(mod(constant(-10), constant(3))).value,
    ).isEqualTo(encodeValue(-1));
  });
  test('modFunctionTestWithDoublePositivePositive', () {
    // 10.5 % 3.0 is exactly 1.5
    assertThat(
      evaluate(mod(constant(10.5), constant(3.0))).value,
    ).isEqualTo(encodeValue(1.5));
  });
  test('modFunctionTestWithDoubleNegativeNegative', () {
    final resultValue = evaluate(mod(constant(-7.3), constant(-1.8))).value;
    assertThat(resultValue?.doubleValue).isWithin(1e-9).of(-0.1);
  });
  test('modFunctionTestWithDoublePositiveNegative', () {
    final resultValue = evaluate(mod(constant(9.8), constant(-2.5))).value;
    assertThat(resultValue?.doubleValue).isWithin(1e-9).of(2.3);
  });
  test('modFunctionTestWithDoubleNegativePositive', () {
    final resultValue = evaluate(mod(constant(-7.5), constant(2.3))).value;
    assertThat(resultValue?.doubleValue).isWithin(1e-9).of(-0.6);
  });
  test('modFunctionTestWithLongPerfectlyDivisible', () {
    assertThat(
      evaluate(mod(constant(10), constant(5))).value,
    ).isEqualTo(encodeValue(0));
    assertThat(
      evaluate(mod(constant(-10), constant(5))).value,
    ).isEqualTo(encodeValue(0));
    assertThat(
      evaluate(mod(constant(10), constant(-5))).value,
    ).isEqualTo(encodeValue(0));
    assertThat(
      evaluate(mod(constant(-10), constant(-5))).value,
    ).isEqualTo(encodeValue(0));
  });
  test('modFunctionTestWithDoublePerfectlyDivisible', () {
    assertThat(
      evaluate(mod(constant(10.0), constant(2.5))).value,
    ).isEqualTo(encodeValue(0.0));
    assertThat(
      evaluate(mod(constant(10.0), constant(-2.5))).value,
    ).isEqualTo(encodeValue(0.0));
    assertThat(
      evaluate(mod(constant(-10.0), constant(2.5))).value,
    ).isEqualTo(encodeValue(-0.0));
    assertThat(
      evaluate(mod(constant(-10.0), constant(-2.5))).value,
    ).isEqualTo(encodeValue(-0.0));
  });
  test('modFunctionTestWithNonNumericsReturnError', () {
    assertThat(evaluate(mod(constant(10), constant("1"))).isError).isTrue();
    assertThat(evaluate(mod(constant("1"), constant(10))).isError).isTrue();
    assertThat(evaluate(mod(constant("1"), constant("1"))).isError).isTrue();
  });
  test('modFunctionTestWithNanNumberReturnNaN', () {
    final nanVal = double.nan;
    assertThat(
      evaluate(mod(constant(1), constant(nanVal))).value,
    ).isEqualTo(encodeValue(nanVal));
    assertThat(
      evaluate(mod(constant(1.0), constant(nanVal))).value,
    ).isEqualTo(encodeValue(nanVal));
    assertThat(
      evaluate(mod(constant(maxLong), constant(nanVal))).value,
    ).isEqualTo(encodeValue(nanVal));
    assertThat(
      evaluate(mod(constant(minLong), constant(nanVal))).value,
    ).isEqualTo(encodeValue(nanVal));
    assertThat(
      evaluate(mod(constant(double.maxFinite), constant(nanVal))).value,
    ).isEqualTo(encodeValue(nanVal));
    assertThat(
      evaluate(mod(constant(double.minPositive), constant(nanVal))).value,
    ).isEqualTo(encodeValue(nanVal));
    assertThat(
      evaluate(mod(constant(double.infinity), constant(nanVal))).value,
    ).isEqualTo(encodeValue(nanVal));
    assertThat(
      evaluate(mod(constant(double.negativeInfinity), constant(nanVal))).value,
    ).isEqualTo(encodeValue(nanVal));
  });
  test('modFunctionTestWithNanNotNumberTypeReturnError', () {
    assertThat(
      evaluate(mod(constant(double.nan), constant("hello world"))).isError,
    ).isTrue();
  });
  test('modFunctionTestWithNumberPosInfinityReturnSelf', () {
    assertThat(
      evaluate(mod(constant(1), constant(double.infinity))).value,
    ).isEqualTo(encodeValue(1.0));
    assertThat(
      evaluate(mod(constant(42.123), constant(double.infinity))).value,
    ).isEqualTo(encodeValue(42.123));
    assertThat(
      evaluate(mod(constant(-99.9), constant(double.infinity))).value,
    ).isEqualTo(encodeValue(-99.9));
  });
  test('modFunctionTestWithPosInfinityNumberReturnNaN', () {
    assertThat(
      evaluate(mod(constant(double.infinity), constant(1))).value,
    ).isEqualTo(encodeValue(double.nan));
    assertThat(
      evaluate(mod(constant(double.infinity), constant(42.123))).value,
    ).isEqualTo(encodeValue(double.nan));
    assertThat(
      evaluate(mod(constant(double.infinity), constant(-99.9))).value,
    ).isEqualTo(encodeValue(double.nan));
  });
  test('modFunctionTestWithNumberNegInfinityReturnSelf', () {
    assertThat(
      evaluate(mod(constant(1), constant(double.negativeInfinity))).value,
    ).isEqualTo(encodeValue(1.0));
    assertThat(
      evaluate(mod(constant(42.123), constant(double.negativeInfinity))).value,
    ).isEqualTo(encodeValue(42.123));
    assertThat(
      evaluate(mod(constant(-99.9), constant(double.negativeInfinity))).value,
    ).isEqualTo(encodeValue(-99.9));
  });
  test('modFunctionTestWithNegInfinityNumberReturnNaN', () {
    assertThat(
      evaluate(mod(constant(double.negativeInfinity), constant(1))).value,
    ).isEqualTo(encodeValue(double.nan));
    assertThat(
      evaluate(mod(constant(double.negativeInfinity), constant(42.123))).value,
    ).isEqualTo(encodeValue(double.nan));
    assertThat(
      evaluate(mod(constant(double.negativeInfinity), constant(-99.9))).value,
    ).isEqualTo(encodeValue(double.nan));
  });
  test('modFunctionTestWithPosAndNegInfinityReturnNaN', () {
    assertThat(
      evaluate(
        mod(constant(double.infinity), constant(double.negativeInfinity)),
      ).value,
    ).isEqualTo(encodeValue(double.nan));
  });
}
