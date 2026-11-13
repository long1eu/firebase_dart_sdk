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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/timestamp/TimestampToUnixMicrosTests.kt
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
  // --- TimestampToUnixMicros Tests ---
  test('timestampToUnixMicros_nonTimestampType_returnsError', () {
    final expr = timestampToUnixMicros(constant(123));
    final result = evaluate(expr);
    assertEvaluatesToError(result, "timestampToUnixMicros(123)");
  });
  test('timestampToUnixMicros_mirroring_errors', () {
    for (final testCase in UNARY_MIRROR_TEST_CASES) {
      assertEvaluatesToNull(
        evaluate(timestampToUnixMicros(testCase.input)),
        "timestampToUnixMicros(\${testCase.name})",
      );
    }
  });
  test('timestampToUnixMicros_timestamp_returnsMicros', () {
    final ts = Timestamp(347068800, 0); // December 31, 1980 00:00:00 UTC
    final expr = timestampToUnixMicros(constant(ts));
    final result = evaluate(expr);
    assertEvaluatesTo(
      result,
      encodeValue(347068800000000),
      "timestampToUnixMicros(Timestamp(347068800, 0))",
    );
  });
  test('timestampToUnixMicros_epochTimestamp_returnsMicros', () {
    final ts = Timestamp(0, 0);
    final expr = timestampToUnixMicros(constant(ts));
    final result = evaluate(expr);
    assertEvaluatesTo(
      result,
      encodeValue(0),
      "timestampToUnixMicros(Timestamp(0, 0))",
    );
  });
  test('timestampToUnixMicros_currentTimestamp_returnsMicros', () {
    // Example: March 15, 2023 12:00:00.123456 UTC
    final ts = Timestamp(1678886400, 123456000);
    final expectedMicros = 1678886400 * 1000000 + 123456;
    final expr = timestampToUnixMicros(constant(ts));
    final result = evaluate(expr);
    assertEvaluatesTo(
      result,
      encodeValue(expectedMicros),
      "timestampToUnixMicros(Timestamp(1678886400, 123456000))",
    );
  });
  test('timestampToUnixMicros_maxTimestamp_returnsMicros', () {
    // Max representable timestamp: seconds=253402300799, nanos=999999999
    final maxTs = Timestamp(253402300799, 999999999);
    // Expected micros: 253402300799 * 1,000,000 + 999999 (nanos truncated to micros)
    final expectedMicros = 253402300799 * 1000000 + 999999;
    final expr = timestampToUnixMicros(constant(maxTs));
    final result = evaluate(expr);
    assertEvaluatesTo(
      result,
      encodeValue(expectedMicros),
      "timestampToUnixMicros(maxTimestamp)",
    );
  });
  test('timestampToUnixMicros_minTimestamp_returnsMicros', () {
    // Min representable timestamp: seconds=-62135596800, nanos=0
    final minTs = Timestamp(-62135596800, 0);
    // Expected micros: -62135596800 * 1,000,000 = -62135596800000000
    final expectedMicros = -62135596800 * 1000000;
    final expr = timestampToUnixMicros(constant(minTs));
    final result = evaluate(expr);
    assertEvaluatesTo(
      result,
      encodeValue(expectedMicros),
      "timestampToUnixMicros(minTimestamp)",
    );
  });
  test('timestampToUnixMicros_timestampTruncatesToMicros', () {
    // Timestamp: seconds=-1, nanos=999999999 (which is 999999.999 micros)
    // Expected Micros: -1 * 1,000,000 + 999999 = -1
    final ts = Timestamp(-1, 999999999);
    final expr = timestampToUnixMicros(constant(ts));
    final result = evaluate(expr);
    assertEvaluatesTo(
      result,
      encodeValue(-1),
      "timestampToUnixMicros(Timestamp(-1, 999999999))",
    );
  });
}
