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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/arithmetic/SqrtTests.kt
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
  test('sqrtMirrorsErrors', () {
    for (final testCase in UNARY_MIRROR_TEST_CASES) {
      assertEvaluatesToNull(
        evaluate(sqrt(testCase.input)),
        "sqrt(\${testCase.name})",
      );
    }
  });
  test('sqrtFunctionTestWithLong', () {
    assertThat(evaluate(sqrt(constant(16))).value).isEqualTo(encodeValue(4.0));
  });
  test('sqrtFunctionTestWithNegativeLong', () {
    assertThat(evaluate(sqrt(constant(-16))).isError).isTrue();
  });
  test('sqrtFunctionTestWithDouble', () {
    assertThat(
      evaluate(sqrt(constant(16.0))).value,
    ).isEqualTo(encodeValue(4.0));
  });
  test('sqrtFunctionTestWithNegativeDouble', () {
    assertThat(evaluate(sqrt(constant(-16.0))).isError).isTrue();
  });
  test('sqrtFunctionTestWithZeroDouble', () {
    assertThat(evaluate(sqrt(constant(0.0))).value).isEqualTo(encodeValue(0.0));
  });
  test('sqrtFunctionTestWithNegativeZeroDouble', () {
    assertThat(
      evaluate(sqrt(constant(-0.0))).value,
    ).isEqualTo(encodeValue(-0.0));
  });
  test('sqrtFunctionTestWithInfinity', () {
    assertThat(
      evaluate(sqrt(constant(double.infinity))).value,
    ).isEqualTo(encodeValue(double.infinity));
  });
  test('sqrtFunctionTestWithNegativeInfinity', () {
    assertThat(
      evaluate(sqrt(constant(double.negativeInfinity))).isError,
    ).isTrue();
  });
  test('sqrtFunctionTestWithNaN', () {
    assertThat(
      evaluate(sqrt(constant(double.nan))).value,
    ).isEqualTo(encodeValue(double.nan));
  });
  test('sqrtFunctionTestWithUnsupportedType', () {
    assertThat(evaluate(sqrt(constant("foo"))).isError).isTrue();
  });
}
