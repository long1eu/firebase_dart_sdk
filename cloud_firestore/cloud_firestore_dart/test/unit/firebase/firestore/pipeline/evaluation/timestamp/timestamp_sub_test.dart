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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/timestamp/TimestampSubTests.kt
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
import 'package:cloud_firestore_dart/pipelines.dart' show Expression;
import 'package:test/test.dart' show TestOn, test;

import '../evaluation_test_util.dart';

void main() {
  Expression unsetValue() => field("nonexistent");
  test('mirror_error for null and unset values', () {
    final testCases = [
      (nullValue(), constant(1)),
      (unsetValue(), constant(1)),
      (constant(Timestamp(0, 0)), nullValue()),
      (constant(Timestamp(0, 0)), unsetValue()),
      (nullValue(), nullValue()),
      (unsetValue(), unsetValue()),
      (nullValue(), unsetValue()),
      (unsetValue(), nullValue()),
    ];

    for (final (timestamp, amount) in testCases) {
      final expr = timestampSubtract(timestamp, constant("second"), amount);
      assertEvaluatesToNull(
        evaluate(expr),
        "timestampSubtract with args: $timestamp, $amount",
      );
    }
  });
  test('timestampSubtract with invalid timestamp returns error', () {
    final expr = timestampSubtract(
      constant("not a timestamp"),
      constant("second"),
      constant(1),
    );
    assertEvaluatesToError(evaluate(expr), "$expr");
  });
  test('timestampSubtract with invalid amount returns error', () {
    final expr = timestampSubtract(
      constant(Timestamp(0, 0)),
      constant("second"),
      constant("not an amount"),
    );
    assertEvaluatesToError(evaluate(expr), "$expr");
  });
  test('timestampSubtract with invalid time unit returns error', () {
    final expr = timestampSubtract(
      constant(Timestamp(0, 0)),
      constant("not a unit"),
      constant(1),
    );
    assertEvaluatesToError(evaluate(expr), "$expr");
  });
  test('timestampSubtract with null time unit returns error', () {
    final expr = timestampSubtract(
      constant(Timestamp(0, 0)),
      nullValue(),
      constant(1),
    );
    assertEvaluatesToError(evaluate(expr), "$expr");
  });
  test('timestampSubtract from max timestamp', () {
    // Corresponds to 9999-12-31T23:59:59Z - 1 day
    final start = Timestamp(253402300799, 0);
    final expected = Timestamp(253402214399, 0);
    final expr = timestampSubtract(
      constant(start),
      constant("day"),
      constant(1),
    );
    assertEvaluatesTo(evaluate(expr), encodeValue(expected), "$expr");
  });
  test('timestampSubtract from min timestamp', () {
    // Corresponds to 0001-01-01T00:00:00Z - (-1 day) -> + 1 day
    final start = Timestamp(-62135596800, 0);
    final expected = Timestamp(-62135510400, 0);
    final expr = timestampSubtract(
      constant(start),
      constant("day"),
      constant(-1),
    );
    assertEvaluatesTo(evaluate(expr), encodeValue(expected), "$expr");
  });
  test('timestampSubtract positive overflow returns error', () {
    // Corresponds to 9999-12-31T23:59:59Z - (-1 day) -> + 1 day -> Overflow
    final expr = timestampSubtract(
      constant(Timestamp(253402300799, 0)),
      constant("day"),
      constant(-1),
    );
    assertEvaluatesToError(evaluate(expr), "$expr");
  });
  test('timestampSubtract negative overflow returns error', () {
    // Corresponds to 0001-01-01T00:00:00Z - 1 day -> Underflow
    final expr = timestampSubtract(
      constant(Timestamp(-62135596800, 0)),
      constant("day"),
      constant(1),
    );
    assertEvaluatesToError(evaluate(expr), "$expr");
  });
  test('timestampSubtract with amount too large returns error', () {
    final expr = timestampSubtract(
      constant(Timestamp(0, 0)),
      constant("day"),
      constant(maxLong),
    );
    assertEvaluatesToError(evaluate(expr), "$expr");
  });
  test('timestampSubtract with negative amount', () {
    final expr = timestampSubtract(
      constant(Timestamp(0, 1000)),
      constant("microsecond"),
      constant(-1),
    );
    assertEvaluatesTo(evaluate(expr), encodeValue(Timestamp(0, 2000)), "$expr");
  });
  test('timestampSubtract with int amount', () {
    final expr = timestampSubtract(
      constant(Timestamp(0, 2000)),
      constant("microsecond"),
      constant(1),
    );
    assertEvaluatesTo(evaluate(expr), encodeValue(Timestamp(0, 1000)), "$expr");
  });
  test('timestampSubtract with long amount', () {
    final expr = timestampSubtract(
      constant(Timestamp(0, 2000)),
      constant("microsecond"),
      constant(1),
    );
    assertEvaluatesTo(evaluate(expr), encodeValue(Timestamp(0, 1000)), "$expr");
  });
  test('timestampSubtract with various units', () {
    final start = Timestamp(1672531200, 0); // 2023-01-01T00:00:00Z
    final testCases = [
      ("microsecond", Timestamp(1672531199, 999999000)),
      ("millisecond", Timestamp(1672531199, 999000000)),
      ("second", Timestamp(1672531199, 0)),
      ("minute", Timestamp(1672531140, 0)),
      ("hour", Timestamp(1672527600, 0)),
      ("day", Timestamp(1672444800, 0)),
    ];

    for (final (unit, expected) in testCases) {
      final expr = timestampSubtract(
        constant(start),
        constant(unit),
        constant(1),
      );
      assertEvaluatesTo(
        evaluate(expr),
        encodeValue(expected),
        "Subtracting 1 $unit",
      );
    }
  });
}
