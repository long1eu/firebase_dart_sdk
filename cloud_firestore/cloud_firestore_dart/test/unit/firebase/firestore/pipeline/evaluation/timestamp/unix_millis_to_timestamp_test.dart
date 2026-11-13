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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/timestamp/UnixMillisToTimestampTests.kt
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

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart' show Timestamp;
import 'package:test/test.dart' show test;

import '../evaluation_test_util.dart';
import '../mirroring_test_cases.dart';

void main() {
  // --- UnixMillisToTimestamp Tests ---
  test('unixMillisToTimestamp_mirrors_errors', () {
    for (final testCase in UNARY_MIRROR_TEST_CASES) {
      assertEvaluatesToNull(
        evaluate(unixMillisToTimestamp(testCase.input)),
        "unixMillisToTimestamp(\${testCase.name})",
      );
    }
  });
  test('unixMillisToTimestamp_stringType_returnsError', () {
    final expr = unixMillisToTimestamp(constant("abc"));
    final result = evaluate(expr);
    assertEvaluatesToError(result, "unixMillisToTimestamp(\"abc\")");
  });
  test('unixMillisToTimestamp_zeroValue_returnsTimestampEpoch', () {
    final expr = unixMillisToTimestamp(constant(0));
    final result = evaluate(expr);
    assertEvaluatesTo(
      result,
      encodeValue(Timestamp(0, 0)),
      "unixMillisToTimestamp(0)",
    );
  });
  test('unixMillisToTimestamp_intType_returnsTimestamp', () {
    // C++ test uses 1000LL, which is 1 second
    final expr = unixMillisToTimestamp(constant(1000));
    final result = evaluate(expr);
    assertEvaluatesTo(
      result,
      encodeValue(Timestamp(1, 0)),
      "unixMillisToTimestamp(1000)",
    );
  });
  test('unixMillisToTimestamp_longType_returnsTimestamp', () {
    // C++ test uses 9876543210LL millis
    // 9876543210 / 1000 = 9876543 seconds
    // 9876543210 % 1000 = 210 millis = 210000000 nanos
    final expr = unixMillisToTimestamp(constant(9876543210));
    final result = evaluate(expr);
    assertEvaluatesTo(
      result,
      encodeValue(Timestamp(9876543, 210000000)),
      "unixMillisToTimestamp(9876543210)",
    );
  });
  test('unixMillisToTimestamp_longTypeNegative_returnsTimestamp', () {
    // -10000 millis = -10 seconds
    final expr = unixMillisToTimestamp(constant(-10000));
    final result = evaluate(expr);
    assertEvaluatesTo(
      result,
      encodeValue(Timestamp(-10, 0)),
      "unixMillisToTimestamp(-10000)",
    );
  });
  test('unixMillisToTimestamp_longTypeNegativeOverflow_returnsError', () {
    // Min representable timestamp: seconds=-62135596800, nanos=0
    // Corresponds to millis: -62135596800 * 1000 = -62135596800000
    final minMillis = -62135596800000;

    // Test the boundary value
    final boundaryExpr = unixMillisToTimestamp(constant(minMillis));
    final boundaryResult = evaluate(boundaryExpr);
    assertEvaluatesTo(
      boundaryResult,
      encodeValue(Timestamp(-62135596800, 0)),
      "unixMillisToTimestamp(minMillis)",
    );

    // Test value just below the boundary (minMillis - 1)
    final belowMinExpr = unixMillisToTimestamp(constant(minMillis - 1));
    final belowMinResult = evaluate(belowMinExpr);
    assertEvaluatesToError(
      belowMinResult,
      "unixMillisToTimestamp(minMillis - 1)",
    );
  });
  test('unixMillisToTimestamp_longTypePositiveOverflow_returnsError', () {
    // Max representable timestamp: seconds=253402300799, nanos=999999999
    // Corresponds to millis: 253402300799 * 1000 + 999 (since nanos are truncated to millis)
    // = 253402300799000 + 999 = 253402300799999
    final maxMillis = 253402300799999;

    // Test the boundary value
    // Nanos are 999000000 because 999 millis * 1,000,000 = 999,000,000 nanos
    final boundaryExpr = unixMillisToTimestamp(constant(maxMillis));
    final boundaryResult = evaluate(boundaryExpr);
    assertEvaluatesTo(
      boundaryResult,
      encodeValue(Timestamp(253402300799, 999000000)), // Nanos from 999 millis
      "unixMillisToTimestamp(maxMillis)",
    );

    // Test value just above the boundary (maxMillis + 1)
    final aboveMaxExpr = unixMillisToTimestamp(constant(maxMillis + 1));
    final aboveMaxResult = evaluate(aboveMaxExpr);
    assertEvaluatesToError(
      aboveMaxResult,
      "unixMillisToTimestamp(maxMillis + 1)",
    );
  });
}
