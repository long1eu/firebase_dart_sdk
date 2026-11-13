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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/arithmetic/RoundToDecimalTests.kt
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
  test('roundToPrecisionMirrorsError', () {
    for (final (name, left, right) in BINARY_MIRROR_TEST_CASES) {
      final expr = roundToPrecision(left, right);
      assertEvaluatesToNull(evaluate(expr), "roundToPrecision($name)");
    }
  });
  test('roundToDecimalFunctionTestOnZero', () {
    assertThat(
      evaluate(roundToPrecision(constant(0), constant(0))).value,
    ).isEqualTo(encodeValue(0));
  });
  test('roundToDecimalFunctionTestPositiveHalfwayRoundsUp', () {
    assertThat(
      evaluate(roundToPrecision(constant(15.5), constant(0))).value,
    ).isEqualTo(encodeValue(16.0));
  });
  test('roundToDecimalFunctionTestNegativeHalfwayRoundsDown', () {
    assertThat(
      evaluate(roundToPrecision(constant(-15.5), constant(0))).value,
    ).isEqualTo(encodeValue(-16.0));
  });
  test('roundToDecimalFunctionTestPositiveDecimalPlaces', () {
    assertThat(
      evaluate(roundToPrecision(constant(15.48924), constant(1))).value,
    ).isEqualTo(encodeValue(15.5));
  });
  test('roundToDecimalFunctionTestPositiveDecimalPlacesLong', () {
    assertThat(
      evaluate(roundToPrecision(constant(-15.48924), constant(2))).value,
    ).isEqualTo(encodeValue(-15.49));
  });
  test('roundToDecimalFunctionTestLargePositiveDecimalPlaces', () {
    assertThat(
      evaluate(roundToPrecision(constant(15.48924), constant(maxLong))).value,
    ).isEqualTo(encodeValue(15.48924));
  });
  test('roundToDecimalFunctionTestNegativeDecimalPlaces', () {
    assertThat(
      evaluate(roundToPrecision(constant(15.48924), constant(-1))).value,
    ).isEqualTo(encodeValue(20.0));
  });
  test('roundToDecimalFunctionTestLargeNegativeDecimalPlaces', () {
    assertThat(
      evaluate(roundToPrecision(constant(15.48924), constant(-maxLong))).value,
    ).isEqualTo(encodeValue(0.0));
  });
  test('roundToDecimalFunctionTestLargeNegativeDecimalPlacesNegativeValue', () {
    assertThat(
      evaluate(roundToPrecision(constant(-15.48924), constant(-maxLong))).value,
    ).isEqualTo(encodeValue(0.0));
  });
  test('roundToDecimalFunctionTestZeroDecimalPlacesRoundsWhole', () {
    assertThat(
      evaluate(roundToPrecision(constant(-15.48924), constant(0))).value,
    ).isEqualTo(encodeValue(-15.0));
  });
  test('roundToDecimalFunctionTestLargeValueAndDecimalPlaces', () {
    assertThat(
      evaluate(
        roundToPrecision(constant(double.maxFinite), constant(maxLong)),
      ).value,
    ).isEqualTo(encodeValue(double.maxFinite));
  });
  test('roundToDecimalFunctionTestLargeValueAndSmallDecimalPlaces', () {
    assertThat(
      evaluate(
        roundToPrecision(constant(double.maxFinite), constant(-maxLong)),
      ).value,
    ).isEqualTo(encodeValue(0.0));
  });
  test('roundToDecimalFunctionTestRoundMaxDouble', () {
    assertThat(
      evaluate(roundToPrecision(constant(double.maxFinite), constant(0))).value,
    ).isEqualTo(encodeValue(double.maxFinite));
  });
  test('roundToDecimalFunctionTestRoundMaxNegativeDouble', () {
    assertThat(
      evaluate(
        roundToPrecision(constant(-double.maxFinite), constant(0)),
      ).value,
    ).isEqualTo(encodeValue(-double.maxFinite));
  });
  test('roundToDecimalFunctionTestRoundMaxDoubleOverflow', () {
    assertThat(
      evaluate(
        roundToPrecision(constant(double.maxFinite), constant(-307)),
      ).isError,
    ).isTrue();
  });
  test('roundToDecimalFunctionTestRoundMaxNegativeDoubleOverflow', () {
    assertThat(
      evaluate(
        roundToPrecision(constant(-double.maxFinite), constant(-307)),
      ).isError,
    ).isTrue();
  });
  test('roundToDecimalFunctionTestRoundLong', () {
    assertThat(
      evaluate(roundToPrecision(constant(15), constant(0))).value,
    ).isEqualTo(encodeValue(15));
  });
  test('roundToDecimalFunctionTestRoundNegativeLong', () {
    assertThat(
      evaluate(roundToPrecision(constant(-15), constant(0))).value,
    ).isEqualTo(encodeValue(-15));
  });
  test('roundToDecimalFunctionTestRoundLongNegativeDecimalPlaces', () {
    assertThat(
      evaluate(roundToPrecision(constant(15), constant(-1))).value,
    ).isEqualTo(encodeValue(20));
  });
  test('roundToDecimalFunctionTestRoundLongLargeNegativeDecimalPlaces', () {
    assertThat(
      evaluate(roundToPrecision(constant(15), constant(-maxLong))).value,
    ).isEqualTo(encodeValue(0));
  });
  test('roundToDecimalFunctionTestRoundLongOverflow', () {
    assertThat(
      evaluate(roundToPrecision(constant(maxLong), constant(-1))).isError,
    ).isTrue();
  });
  test('roundToDecimalFunctionTestRoundLongNegativeOverflow', () {
    assertThat(
      evaluate(roundToPrecision(constant(-maxLong), constant(-1))).isError,
    ).isTrue();
  });
  test('roundToDecimalFunctionTestRoundMaxLong', () {
    assertThat(
      evaluate(roundToPrecision(constant(maxLong), constant(0))).value,
    ).isEqualTo(encodeValue(maxLong));
  });
  test('roundToDecimalFunctionTestRoundMinLong', () {
    assertThat(
      evaluate(roundToPrecision(constant(-maxLong), constant(0))).value,
    ).isEqualTo(encodeValue(-maxLong));
  });
  test('roundToDecimalFunctionTestRoundLongPositiveDecimalPlaces', () {
    assertThat(
      evaluate(roundToPrecision(constant(15), constant(maxLong))).value,
    ).isEqualTo(encodeValue(15));
  });
  test('roundToDecimalFunctionTestRoundInteger', () {
    assertThat(
      evaluate(roundToPrecision(constant(15), constant(0))).value,
    ).isEqualTo(encodeValue(15));
  });
  test('roundToDecimalFunctionTestRoundNegativeInteger', () {
    assertThat(
      evaluate(roundToPrecision(constant(-15), constant(0))).value,
    ).isEqualTo(encodeValue(-15));
  });
  test('roundToDecimalFunctionTestRoundIntegerNegativeDecimalPlaces', () {
    assertThat(
      evaluate(roundToPrecision(constant(15), constant(-1))).value,
    ).isEqualTo(encodeValue(20));
  });
  test(
    'roundToDecimalFunctionTestRoundNegativeIntegerNegativeDecimalPlaces',
    () {
      assertThat(
        evaluate(roundToPrecision(constant(-15), constant(-1))).value,
      ).isEqualTo(encodeValue(-20));
    },
  );
  test('roundToDecimalFunctionTestRoundIntegerLargeNegativeDecimalPlaces', () {
    assertThat(
      evaluate(roundToPrecision(constant(15), constant(-maxLong))).value,
    ).isEqualTo(encodeValue(0));
  });
  test('roundToDecimalFunctionTestRoundIntegerOverflow', () {
    assertThat(
      evaluate(roundToPrecision(constant(maxLong), constant(-1))).isError,
    ).isTrue();
  });
  test('roundToDecimalFunctionTestRoundIntegerPositiveDecimalPlaces', () {
    assertThat(
      evaluate(roundToPrecision(constant(15), constant(maxLong))).value,
    ).isEqualTo(encodeValue(15));
  });
  test('roundToDecimalFunctionTestRoundInfinity', () {
    assertThat(
      evaluate(
        roundToPrecision(constant(double.infinity), constant(-maxLong)),
      ).value,
    ).isEqualTo(encodeValue(double.infinity));
  });
  test('roundToDecimalFunctionTestRoundNaN', () {
    assertThat(
      evaluate(
        roundToPrecision(constant(double.nan), constant(-maxLong)),
      ).value,
    ).isEqualTo(encodeValue(double.nan));
  });
  test('roundToDecimalFunctionTestMaxLongDecimalPlaces', () {
    assertThat(
      evaluate(roundToPrecision(constant(15.3924532), constant(maxLong))).value,
    ).isEqualTo(encodeValue(15.3924532));
  });
  test('roundToDecimalFunctionTestMaxNegativeLongDecimalPlaces', () {
    assertThat(
      evaluate(
        roundToPrecision(constant(15.3924532), constant(-maxLong)),
      ).value,
    ).isEqualTo(encodeValue(0.0));
  });
  test('roundToDecimalFunctionTestNearMinDouble', () {
    assertThat(
      evaluate(
        roundToPrecision(constant(double.maxFinite - 1), constant(-10)),
      ).value,
    ).isEqualTo(encodeValue(double.maxFinite - 1));
  });
  test('roundToDecimalFunctionTestNearMaxDouble', () {
    assertThat(
      evaluate(
        roundToPrecision(constant(-double.maxFinite + 1), constant(10)),
      ).value,
    ).isEqualTo(encodeValue(-double.maxFinite + 1));
  });
  test('roundToDecimalFunctionTestRoundUnknownValueType', () {
    assertThat(
      evaluate(roundToPrecision(constant("foo"), constant(-maxLong))).isError,
    ).isTrue();
  });
  test('roundToDecimalFunctionTestRoundInvalidDecimalPlacesType', () {
    assertThat(
      evaluate(roundToPrecision(constant(15.3924532), constant("foo"))).isError,
    ).isTrue();
  });
}
