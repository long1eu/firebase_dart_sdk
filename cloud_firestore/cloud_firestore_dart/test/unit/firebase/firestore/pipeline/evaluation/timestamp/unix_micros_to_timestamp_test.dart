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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/timestamp/UnixMicrosToTimestampTests.kt
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

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart' show Timestamp;
import 'package:test/test.dart' show TestOn, test;

import '../evaluation_test_util.dart';
import '../mirroring_test_cases.dart';

void main() {
  // --- UnixMicrosToTimestamp Tests ---
  test('unixMicrosToTimestamp_stringType_returnsError', () {
    final expr = unixMicrosToTimestamp(constant("abc"));
    final result = evaluate(expr);
    assertEvaluatesToError(result, "unixMicrosToTimestamp(\"abc\")");
  });
  test('unixMicrosToTimestamp_mirrors_errors', () {
    for (final testCase in UNARY_MIRROR_TEST_CASES) {
      assertEvaluatesToNull(
        evaluate(unixMicrosToTimestamp(testCase.input)),
        "unixMicrosToTimestamp(\${testCase.name})",
      );
    }
  });
  test('unixMicrosToTimestamp_zeroValue_returnsTimestampEpoch', () {
    final expr = unixMicrosToTimestamp(constant(0));
    final result = evaluate(expr);
    assertEvaluatesTo(
      result,
      encodeValue(Timestamp(0, 0)),
      "unixMicrosToTimestamp(0)",
    );
  });
  test('unixMicrosToTimestamp_intType_returnsTimestamp', () {
    // C++ test uses 1000000LL, which is 1 second
    final expr = unixMicrosToTimestamp(constant(1000000));
    final result = evaluate(expr);
    assertEvaluatesTo(
      result,
      encodeValue(Timestamp(1, 0)),
      "unixMicrosToTimestamp(1000000)",
    );
  });
  test('unixMicrosToTimestamp_longType_returnsTimestamp', () {
    // C++ test uses 9876543210LL micros
    // 9876543210 / 1,000,000 = 9876 seconds
    // 9876543210 % 1,000,000 = 543210 micros = 543210000 nanos
    final expr = unixMicrosToTimestamp(constant(9876543210));
    final result = evaluate(expr);
    assertEvaluatesTo(
      result,
      encodeValue(Timestamp(9876, 543210000)),
      "unixMicrosToTimestamp(9876543210)",
    );
  });
  test('unixMicrosToTimestamp_longTypeNegative_returnsTimestamp', () {
    // -10000 micros = -0.01 seconds
    // seconds = -1 (floor of -0.01)
    // remaining_micros = -10000 - (-1 * 1,000,000) = -10000 + 1,000,000 = 990,000 micros
    // nanos = 990,000 * 1000 = 990,000,000 nanos
    final expr = unixMicrosToTimestamp(constant(-10000));
    final result = evaluate(expr);
    assertEvaluatesTo(
      result,
      encodeValue(Timestamp(-1, 990000000)),
      "unixMicrosToTimestamp(-10000)",
    );
  });
  test('unixMicrosToTimestamp_longTypeNegativeOverflow_returnsError', () {
    // Min representable timestamp: seconds=-62135596800, nanos=0
    // Corresponds to micros: -62135596800 * 1,000,000 = -62135596800000000
    final minMicros = -62135596800000000;

    // Test the boundary value
    final boundaryExpr = unixMicrosToTimestamp(constant(minMicros));
    final boundaryResult = evaluate(boundaryExpr);
    assertEvaluatesTo(
      boundaryResult,
      encodeValue(Timestamp(-62135596800, 0)),
      "unixMicrosToTimestamp(minMicros)",
    );

    // Test value just below the boundary (minMicros - 1)
    // The C++ test uses SubtractExpr for this, we can do it directly.
    final belowMinExpr = unixMicrosToTimestamp(constant(minMicros - 1));
    final belowMinResult = evaluate(belowMinExpr);
    assertEvaluatesToError(
      belowMinResult,
      "unixMicrosToTimestamp(minMicros - 1)",
    );
  });
  test('unixMicrosToTimestamp_longTypePositiveOverflow_returnsError', () {
    // Max representable timestamp: seconds=253402300799, nanos=999999999
    // Corresponds to micros: 253402300799 * 1,000,000 + 999999 (since nanos are truncated to
    // micros)
    // = 253402300799000000 + 999999 = 253402300799999999
    final maxMicros = 253402300799999999;

    // Test the boundary value
    // Nanos are 999999000 because 999999 micros * 1000 = 999999000 nanos
    final boundaryExpr = unixMicrosToTimestamp(constant(maxMicros));
    final boundaryResult = evaluate(boundaryExpr);
    assertEvaluatesTo(
      boundaryResult,
      encodeValue(
        Timestamp(253402300799, 999999000),
      ), // Nanos from 999999 micros
      "unixMicrosToTimestamp(maxMicros)",
    );

    // Test value just above the boundary (maxMicros + 1)
    final aboveMaxExpr = unixMicrosToTimestamp(constant(maxMicros + 1));
    final aboveMaxResult = evaluate(aboveMaxExpr);
    assertEvaluatesToError(
      aboveMaxResult,
      "unixMicrosToTimestamp(maxMicros + 1)",
    );
  });
}
