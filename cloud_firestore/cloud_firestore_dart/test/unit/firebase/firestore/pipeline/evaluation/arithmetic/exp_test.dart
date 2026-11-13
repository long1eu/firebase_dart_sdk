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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/arithmetic/ExpTests.kt
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

import 'dart:math' as math;

import 'package:test/test.dart' show test;

import '../evaluation_test_util.dart';
import '../mirroring_test_cases.dart';

void main() {
  test('expMirrorsErrors', () {
    for (final testCase in UNARY_MIRROR_TEST_CASES) {
      assertEvaluatesToNull(
        evaluate(exp(testCase.input)),
        "exp(\${testCase.name})",
      );
    }
  });
  test('expFunctionTestWithDouble', () {
    assertThat(
      evaluate(exp(constant(2.0))).value,
    ).isEqualTo(encodeValue(math.exp(2.0)));
  });
  test('expFunctionTestWithInteger', () {
    assertThat(
      evaluate(exp(constant(2))).value,
    ).isEqualTo(encodeValue(math.exp(2.0)));
  });
  test('expFunctionTestWithLong', () {
    assertThat(
      evaluate(exp(constant(2))).value,
    ).isEqualTo(encodeValue(math.exp(2.0)));
  });
  test('expFunctionTestWithZero', () {
    assertThat(evaluate(exp(constant(0))).value).isEqualTo(encodeValue(1.0));
  });
  test('expFunctionTestWithNegativeZero', () {
    assertThat(evaluate(exp(constant(-0.0))).value).isEqualTo(encodeValue(1.0));
  });
  test('expFunctionTestWithNegative', () {
    assertThat(
      evaluate(exp(constant(-1))).value,
    ).isEqualTo(encodeValue(1 / math.e));
  });
  test('expFunctionTestWithInfinity', () {
    assertThat(
      evaluate(exp(constant(double.infinity))).value,
    ).isEqualTo(encodeValue(double.infinity));
  });
  test('expFunctionTestWithNegativeInfinity', () {
    assertThat(
      evaluate(exp(constant(double.negativeInfinity))).value,
    ).isEqualTo(encodeValue(0.0));
  });
  test('expFunctionTestWithNaN', () {
    assertThat(
      evaluate(exp(constant(double.nan))).value,
    ).isEqualTo(encodeValue(double.nan));
  });
  test('expFunctionTestWithNegativeConstant', () {
    assertThat(
      evaluate(exp(constant(-16.0))).value,
    ).isEqualTo(encodeValue(math.exp(-16.0)));
  });
  test('expFunctionTestWithDoubleOverflow', () {
    assertThat(evaluate(exp(constant(double.maxFinite))).isError).isTrue();
  });
  test('expFunctionTestWithUnsupportedType', () {
    assertThat(evaluate(exp(constant("foo"))).isError).isTrue();
  });
}
