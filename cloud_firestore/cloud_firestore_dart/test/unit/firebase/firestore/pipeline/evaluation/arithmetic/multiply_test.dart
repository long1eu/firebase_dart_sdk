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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/arithmetic/MultiplyTests.kt
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
  test('multiplyFunctionTestWithMirrorError', () {
    for (final (name, left, right) in BINARY_MIRROR_TEST_CASES) {
      final expr = multiply(left, right);
      assertEvaluatesToNull(evaluate(expr), "multiply($name)");
    }
  });
  test('multiplyFunctionTestWithBasicNumerics', () {
    assertThat(
      evaluate(multiply(constant(1), constant(2))).value,
    ).isEqualTo(encodeValue(2));
    assertThat(
      evaluate(multiply(constant(3), constant(2.5))).value,
    ).isEqualTo(encodeValue(7.5));
    assertThat(
      evaluate(multiply(constant(1.0), constant(2))).value,
    ).isEqualTo(encodeValue(2.0));
    assertThat(
      evaluate(multiply(constant(1.3), constant(10.0))).value,
    ).isEqualTo(encodeValue(13.0));
  });
  test('multiplyFunctionTestWithBasicNonNumerics', () {
    assertThat(evaluate(multiply(constant(1), constant("1"))).isError).isTrue();
    assertThat(
      evaluate(multiply(constant("1"), constant(1.0))).isError,
    ).isTrue();
    assertThat(
      evaluate(multiply(constant("1"), constant("1"))).isError,
    ).isTrue();
  });
  test('multiplyFunctionTestWithDoubleLongMultiplicationOverflow', () {
    assertThat(
      evaluate(multiply(constant(maxLong), constant(100.0))).value,
    ).isEqualTo(encodeValue(9.223372036854776E20));
    assertThat(
      evaluate(multiply(constant(maxLong.toDouble()), constant(100))).value,
    ).isEqualTo(encodeValue(9.223372036854776E20));
  });
  test('multiplyFunctionTestWithDoubleMultiplicationOverflow', () {
    assertThat(
      evaluate(
        multiply(constant(double.maxFinite), constant(double.maxFinite)),
      ).value,
    ).isEqualTo(encodeValue(double.infinity));
    assertThat(
      evaluate(
        multiply(constant(-double.maxFinite), constant(double.maxFinite)),
      ).value,
    ).isEqualTo(encodeValue(double.negativeInfinity));
  });
  test('multiplyFunctionTestWithLongMultiplicationOverflow', () {
    assertThat(
      evaluate(multiply(constant(maxLong), constant(10))).isError,
    ).isTrue();
    assertThat(
      evaluate(multiply(constant(minLong), constant(10))).isError,
    ).isTrue();
    assertThat(
      evaluate(multiply(constant(-10), constant(maxLong))).isError,
    ).isTrue();
    assertThat(
      evaluate(multiply(constant(-10), constant(minLong))).isError,
    ).isTrue();
  });
  test('multiplyFunctionTestWithNanNumberReturnNaN', () {
    final nanVal = double.nan;
    assertThat(
      evaluate(multiply(constant(1), constant(nanVal))).value,
    ).isEqualTo(encodeValue(nanVal));
    assertThat(
      evaluate(multiply(constant(1.0), constant(nanVal))).value,
    ).isEqualTo(encodeValue(nanVal));
    assertThat(
      evaluate(multiply(constant(maxLong), constant(nanVal))).value,
    ).isEqualTo(encodeValue(nanVal));
    assertThat(
      evaluate(multiply(constant(minLong), constant(nanVal))).value,
    ).isEqualTo(encodeValue(nanVal));
    assertThat(
      evaluate(multiply(constant(double.maxFinite), constant(nanVal))).value,
    ).isEqualTo(encodeValue(nanVal));
    assertThat(
      evaluate(multiply(constant(double.minPositive), constant(nanVal))).value,
    ).isEqualTo(encodeValue(nanVal));
    assertThat(
      evaluate(multiply(constant(double.infinity), constant(nanVal))).value,
    ).isEqualTo(encodeValue(nanVal));
    assertThat(
      evaluate(
        multiply(constant(double.negativeInfinity), constant(nanVal)),
      ).value,
    ).isEqualTo(encodeValue(nanVal));
  });
  test('multiplyFunctionTestWithNanNotNumberTypeReturnError', () {
    assertThat(
      evaluate(multiply(constant(double.nan), constant("hello world"))).isError,
    ).isTrue();
  });
  test('multiplyFunctionTestWithPositiveInfinity', () {
    assertThat(
      evaluate(multiply(constant(double.infinity), constant(1))).value,
    ).isEqualTo(encodeValue(double.infinity));
    assertThat(
      evaluate(multiply(constant(1), constant(double.infinity))).value,
    ).isEqualTo(encodeValue(double.infinity));
  });
  test('multiplyFunctionTestWithNegativeInfinity', () {
    assertThat(
      evaluate(multiply(constant(double.negativeInfinity), constant(1))).value,
    ).isEqualTo(encodeValue(double.negativeInfinity));
    assertThat(
      evaluate(multiply(constant(1), constant(double.negativeInfinity))).value,
    ).isEqualTo(encodeValue(double.negativeInfinity));
  });
  test(
    'multiplyFunctionTestWithPositiveInfinityNegativeInfinityReturnsNegativeInfinity',
    () {
      assertThat(
        evaluate(
          multiply(
            constant(double.infinity),
            constant(double.negativeInfinity),
          ),
        ).value,
      ).isEqualTo(encodeValue(double.negativeInfinity));
      assertThat(
        evaluate(
          multiply(
            constant(double.negativeInfinity),
            constant(double.infinity),
          ),
        ).value,
      ).isEqualTo(encodeValue(double.negativeInfinity));
    },
  );
  test('multiplyFunctionTestWithMultiArgument', () {
    assertThat(
      evaluate(multiply(multiply(constant(1), constant(2)), constant(3))).value,
    ).isEqualTo(encodeValue(6));
    assertThat(
      evaluate(
        multiply(constant(1.0), multiply(constant(2), constant(3))),
      ).value,
    ).isEqualTo(encodeValue(6.0));
  });
}
