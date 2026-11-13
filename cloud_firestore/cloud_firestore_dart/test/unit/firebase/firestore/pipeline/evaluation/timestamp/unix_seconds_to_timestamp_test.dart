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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/timestamp/UnixSecondsToTimestampTests.kt
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
  // --- UnixSecondsToTimestamp Tests ---
  test('unixSecondsToTimestamp_mirrors_errors', () {
    for (final testCase in UNARY_MIRROR_TEST_CASES) {
      assertEvaluatesToNull(
        evaluate(unixSecondsToTimestamp(testCase.input)),
        "unixSecondsToTimestamp(\${testCase.name})",
      );
    }
  });
  test('unixSecondsToTimestamp_stringType_returnsError', () {
    final expr = unixSecondsToTimestamp(constant("abc"));
    final result = evaluate(expr);
    assertEvaluatesToError(result, "unixSecondsToTimestamp(\"abc\")");
  });
  test('unixSecondsToTimestamp_zeroValue_returnsTimestampEpoch', () {
    final expr = unixSecondsToTimestamp(constant(0));
    final result = evaluate(expr);
    assertEvaluatesTo(
      result,
      encodeValue(Timestamp(0, 0)),
      "unixSecondsToTimestamp(0)",
    );
  });
  test('unixSecondsToTimestamp_intType_returnsTimestamp', () {
    final expr = unixSecondsToTimestamp(constant(1));
    final result = evaluate(expr);
    assertEvaluatesTo(
      result,
      encodeValue(Timestamp(1, 0)),
      "unixSecondsToTimestamp(1)",
    );
  });
  test('unixSecondsToTimestamp_longType_returnsTimestamp', () {
    final expr = unixSecondsToTimestamp(constant(9876543210));
    final result = evaluate(expr);
    assertEvaluatesTo(
      result,
      encodeValue(Timestamp(9876543210, 0)),
      "unixSecondsToTimestamp(9876543210)",
    );
  });
  test('unixSecondsToTimestamp_longTypeNegative_returnsTimestamp', () {
    final expr = unixSecondsToTimestamp(constant(-10000));
    final result = evaluate(expr);
    assertEvaluatesTo(
      result,
      encodeValue(Timestamp(-10000, 0)),
      "unixSecondsToTimestamp(-10000)",
    );
  });
  test('unixSecondsToTimestamp_longTypeNegativeOverflow_returnsError', () {
    // Min representable timestamp: seconds=-62135596800, nanos=0
    final minSeconds = -62135596800;

    // Test the boundary value
    final boundaryExpr = unixSecondsToTimestamp(constant(minSeconds));
    final boundaryResult = evaluate(boundaryExpr);
    assertEvaluatesTo(
      boundaryResult,
      encodeValue(Timestamp(minSeconds, 0)),
      "unixSecondsToTimestamp(minSeconds)",
    );

    // Test value just below the boundary (minSeconds - 1)
    final belowMinExpr = unixSecondsToTimestamp(constant(minSeconds - 1));
    final belowMinResult = evaluate(belowMinExpr);
    assertEvaluatesToError(
      belowMinResult,
      "unixSecondsToTimestamp(minSeconds - 1)",
    );
  });
  test('unixSecondsToTimestamp_longTypePositiveOverflow_returnsError', () {
    // Max representable timestamp: seconds=253402300799, nanos=999999999
    // For UnixSecondsToTimestamp, we only care about the seconds part for overflow.
    final maxSeconds = 253402300799;

    // Test the boundary value
    final boundaryExpr = unixSecondsToTimestamp(constant(maxSeconds));
    final boundaryResult = evaluate(boundaryExpr);
    assertEvaluatesTo(
      boundaryResult,
      encodeValue(Timestamp(maxSeconds, 0)),
      "unixSecondsToTimestamp(maxSeconds)",
    );

    // Test value just above the boundary (maxSeconds + 1)
    final aboveMaxExpr = unixSecondsToTimestamp(constant(maxSeconds + 1));
    final aboveMaxResult = evaluate(aboveMaxExpr);
    assertEvaluatesToError(
      aboveMaxResult,
      "unixSecondsToTimestamp(maxSeconds + 1)",
    );
  });
}
