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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/arithmetic/AddTests.kt
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
  test('addMirrorsErrors', () {
    for (final (name, left, right) in BINARY_MIRROR_TEST_CASES) {
      final expr = add(left, right);
      assertEvaluatesToNull(evaluate(expr), "add($name)");
    }
  });
  test('addFunctionTestWithBasicNumerics', () {
    assertThat(
      evaluate(add(constant(1), constant(2))).value,
    ).isEqualTo(encodeValue(3));
    assertThat(
      evaluate(add(constant(1), constant(2.5))).value,
    ).isEqualTo(encodeValue(3.5));
    assertThat(
      evaluate(add(constant(1.0), constant(2))).value,
    ).isEqualTo(encodeValue(3.0));
    assertThat(
      evaluate(add(constant(1.0), constant(2.0))).value,
    ).isEqualTo(encodeValue(3.0));
  });
  test('addFunctionTestWithBasicNonNumerics', () {
    assertThat(evaluate(add(constant(1), constant("1"))).isError).isTrue();
    assertThat(evaluate(add(constant("1"), constant(1.0))).isError).isTrue();
    assertThat(evaluate(add(constant("1"), constant("1"))).isError).isTrue();
  });
  test('addFunctionTestWithDoubleLongAdditionOverflow', () {
    assertThat(
      evaluate(add(constant(maxLong), constant(1.0))).value,
    ).isEqualTo(encodeValue(9.223372036854776E18));
    assertThat(
      evaluate(add(constant(maxLong.toDouble()), constant(100))).value,
    ).isEqualTo(encodeValue(9.223372036854776E18));
  });
  test('addFunctionTestWithDoubleAdditionOverflow', () {
    assertThat(
      evaluate(
        add(constant(double.maxFinite), constant(double.maxFinite)),
      ).value,
    ).isEqualTo(encodeValue(double.infinity));
    assertThat(
      evaluate(
        add(constant(-double.maxFinite), constant(-double.maxFinite)),
      ).value,
    ).isEqualTo(encodeValue(double.negativeInfinity));
  });
  test('addFunctionTestWithSumPosAndNegInfinityReturnNaN', () {
    assertThat(
      evaluate(
        add(constant(double.infinity), constant(double.negativeInfinity)),
      ).value,
    ).isEqualTo(encodeValue(double.nan));
  });
  test('addFunctionTestWithLongAdditionOverflow', () {
    assertThat(evaluate(add(constant(maxLong), constant(1))).isError).isTrue();
    assertThat(evaluate(add(constant(minLong), constant(-1))).isError).isTrue();
    assertThat(evaluate(add(constant(1), constant(maxLong))).isError).isTrue();
  });
  test('addFunctionTestWithNanNumberReturnNaN', () {
    final nanVal = double.nan;
    assertThat(
      evaluate(add(constant(1), constant(nanVal))).value,
    ).isEqualTo(encodeValue(nanVal));
    assertThat(
      evaluate(add(constant(1.0), constant(nanVal))).value,
    ).isEqualTo(encodeValue(nanVal));
    assertThat(
      evaluate(add(constant(maxLong), constant(nanVal))).value,
    ).isEqualTo(encodeValue(nanVal));
    assertThat(
      evaluate(add(constant(minLong), constant(nanVal))).value,
    ).isEqualTo(encodeValue(nanVal));
    assertThat(
      evaluate(add(constant(double.maxFinite), constant(nanVal))).value,
    ).isEqualTo(encodeValue(nanVal));
    assertThat(
      evaluate(add(constant(double.minPositive), constant(nanVal))).value,
    ).isEqualTo(encodeValue(nanVal));
    assertThat(
      evaluate(add(constant(double.infinity), constant(nanVal))).value,
    ).isEqualTo(encodeValue(nanVal));
    assertThat(
      evaluate(add(constant(double.negativeInfinity), constant(nanVal))).value,
    ).isEqualTo(encodeValue(nanVal));
  });
  test('addFunctionTestWithNanNotNumberTypeReturnError', () {
    assertThat(
      evaluate(add(constant(double.nan), constant("hello world"))).isError,
    ).isTrue();
  });
  test('addFunctionTestWithMultiArgument', () {
    assertThat(
      evaluate(add(add(constant(1), constant(2)), constant(3))).value,
    ).isEqualTo(encodeValue(6));
    assertThat(
      evaluate(add(add(constant(1.0), constant(2)), constant(3))).value,
    ).isEqualTo(encodeValue(6.0));
  });
}
