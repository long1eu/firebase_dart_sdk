// Copyright 2026 Google LLC
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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/strings/RegexFindAllTests.kt
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
  test('regexFindAll_mirroringError', () {
    for (final (name, left, right) in BINARY_MIRROR_TEST_CASES) {
      final expr = regexFindAll(left, right);
      assertEvaluatesToNull(evaluate(expr), "regexFindAll($name)");
    }
  });
  test('regexFindAll_getStaticRegex_match', () {
    final cases = [
      ("b", "(a)?b", [null]),
      ("b", "a?b", ["b"]),
      ("ac", "a(b)?c", [null]),
      ("ac", "ab?c", ["ac"]),
      ("acac", "a(b)?c", [null, null]),
      ("acac", "ab?c", ["ac", "ac"]),
      ("acabcac", "a(b)?c", [null, "b", null]),
      ("acabcac", "ab?c", ["ac", "abc", "ac"]),
      ("acabcacabcac", "a(b)?c", [null, "b", null, "b", null]),
      ("acabcacabcac", "ab?c", ["ac", "abc", "ac", "abc", "ac"]),
      ("yummy food", "foo.", ["food"]),
      ("yummy food", "food.", <Object?>[]),
      ("yummy food", "bar", <Object?>[]),
      ("yummy good food", "oo", ["oo", "oo"]),
      ("yummy good food", ".oo.", ["good", "food"]),
      ("yummy good food", "good", ["good"]),
      ("yummy good food", "Good", <Object?>[]),
      ("yummy good food", "(?i)Good", ["good"]),
      ("yummy Good food", "good", <Object?>[]),
      ("yummy Good food", "(?i)good", ["Good"]),
      ("yummy good food", "go*d", ["good"]),
      ("yummy food", ".", ["y", "u", "m", "m", "y", " ", "f", "o", "o", "d"]),
      ("Try `func(x)` or `func(y)`", "`.+?`", ["`func(x)`", "`func(y)`"]),
      ("Try `func(x)` or `func(y)`", "`(.+?)`", ["func(x)", "func(y)"]),
    ];

    for (final (value, regex, result) in cases) {
      final expr = regexFindAll(constant(value), constant(regex));
      assertEvaluatesTo(
        evaluate(expr),
        encodeValue(result),
        "regexFindAll($value, $regex)",
      );
    }
  });
  test('regexFindAll_getInvalidRegex_isError', () {
    final expr = regexFindAll(constant("abcabc"), constant("(abc)\\1"));
    assertEvaluatesToError(evaluate(expr), "regexFindAll invalid regex");
  });
  test('regexFindAll_getNonStringRegex_isError', () {
    final expr = regexFindAll(constant(42), constant("search"));
    assertEvaluatesToError(evaluate(expr), "regexFindAll(42, \"search\")");
  });
  test('regexFindAll_getNonStringValue_isError', () {
    final expr = regexFindAll(constant("ear"), constant(42));
    assertEvaluatesToError(evaluate(expr), "regexFindAll(\"ear\", 42)");
  });
  test('regexFindAll_getMultipleCaptureGroups_isError', () {
    final expr = regexFindAll(
      constant("Date: 2025-11-15"),
      constant("Date: (\\d{4})-(\\d{2})-(\\d{2})"),
    );
    assertEvaluatesToError(
      evaluate(expr),
      "regexFindAll multiple capture groups",
    );
  });
}
