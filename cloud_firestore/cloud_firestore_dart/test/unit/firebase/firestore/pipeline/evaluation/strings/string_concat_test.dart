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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/strings/StringConcatTests.kt
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
  // --- StrConcat Tests ---
  test('stringConcat_multipleStringChildren_returnsCombination', () {
    final expr = stringConcat(constant("foo"), constant(" "), constant("bar"));
    final result = evaluate(expr);
    assertEvaluatesTo(
      result,
      encodeValue("foo bar"),
      "stringConcat(\"foo\", \" \", \"bar\")",
    );
  });
  test('stringConcat_multipleNonStringChildren_returnsError', () {
    // stringConcat should only accept strings or expressions that evaluate to strings.
    // The Kotlin `stringConcat` vararg is `Any`, then converted via `toArrayOfExprOrConstant`.
    // `evaluateStrConcat` checks if all resolved params are strings.
    final expr = stringConcat(constant("foo"), constant(42), constant("bar"));
    final result = evaluate(expr);
    assertEvaluatesToError(result, "stringConcat(\"foo\", 42, \"bar\")");
  });
  test('stringConcat_multipleCalls', () {
    final expr = stringConcat(constant("foo"), constant(" "), constant("bar"));
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue("foo bar"),
      "stringConcat call 1",
    );
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue("foo bar"),
      "stringConcat call 2",
    );
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue("foo bar"),
      "stringConcat call 3",
    );
  });
  test('stringConcat_largeNumberOfInputs', () {
    final argCount = 500;
    final args = List<Object?>.filled(argCount, constant("a"));
    final expectedResult = "a".repeat(argCount);
    final expr = stringConcatAll(args); // Pass varargs correctly
    final result = evaluate(expr);
    assertEvaluatesTo(
      result,
      encodeValue(expectedResult),
      "stringConcat large number of inputs",
    );
  });
  test('stringConcat_largeStrings', () {
    final a500 = "a".repeat(500);
    final b500 = "b".repeat(500);
    final c500 = "c".repeat(500);
    final expr = stringConcat(constant(a500), constant(b500), constant(c500));
    final result = evaluate(expr);
    assertEvaluatesTo(
      result,
      encodeValue(a500 + b500 + c500),
      "stringConcat large strings",
    );
  });
  test('stringConcat_mirrorError', () {
    for (final (name, left, right) in BINARY_MIRROR_TEST_CASES) {
      final expr = stringConcat(left, right);
      assertEvaluatesToNull(evaluate(expr), "stringConcat($name)");
    }
  });
}
