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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/strings/RegexFindTests.kt
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
  // --- RegexFind Tests ---
  test('regexFind_mirroringError', () {
    for (final (name, left, right) in BINARY_MIRROR_TEST_CASES) {
      final expr = regexFind(left, right);
      assertEvaluatesToNull(evaluate(expr), "regexFind($name)");
    }
  });
  test('regexFind_getStaticRegex_match', () {
    final cases = [
      ("b", "(a)?b", null),
      ("b", "a?b", "b"),
      ("", ".*", ""),
      ("funny", "", ""),
      ("ac", "a(b)?c", null),
      ("ac", "ab?c", "ac"),
      ("acac", "a(b)?c", null),
      ("acac", "ab?c", "ac"),
      ("acabcac", "a(b)?c", null),
      ("acabcac", "ab?c", "ac"),
      ("acabcacabcac", "a(b)?c", null),
      ("acabcacabcac", "ab?c", "ac"),
      ("yummy food", "foo.", "food"),
      ("yummy food", "food.", null),
      ("yummy food", "bar", null),
      ("yummy good food", "oo", "oo"),
      ("yummy good food", ".oo.", "good"),
      ("yummy good food", "good", "good"),
      ("yummy good food", "Good", null),
      ("yummy good food", "(?i)Good", "good"),
      ("yummy Good food", "good", null),
      ("yummy Good food", "(?i)good", "Good"),
      ("yummy good food", "go*d", "good"),
      ("yummy good food", ".", "y"),
      ("Try `func(x)` or `func(y)`", "`.+?`", "`func(x)`"),
      ("Try `func(x)` or `func(y)`", "`(.+?)`", "func(x)"),
    ];

    for (final (value, regex, result) in cases) {
      final expr = regexFind(constant(value), constant(regex));
      if (result == null) {
        assertEvaluatesToNull(evaluate(expr), "regexFind($value, $regex)");
      } else {
        assertEvaluatesTo(evaluate(expr), result, "regexFind($value, $regex)");
      }
    }
  });
  test('regexFind_getDynamicRegex', () {
    final expr = regexFind(constant("yummy food"), field("regex"));
    final doc1 = doc("coll/doc1", 0, <String, Object?>{"regex": "yummy"});
    final doc2 = doc("coll/doc2", 0, <String, Object?>{"regex": "food"});
    final doc3 = doc("coll/doc3", 0, <String, Object?>{"regex": ".*"});

    assertEvaluatesTo(evaluate(expr, doc1), "yummy", "regexFind dynamic doc1");
    assertEvaluatesTo(evaluate(expr, doc2), "food", "regexFind dynamic doc2");
    assertEvaluatesTo(
      evaluate(expr, doc3),
      "yummy food",
      "regexFind dynamic doc3",
    );
  });
  test('regexFind_getInvalidRegex_isError', () {
    final expr = regexFind(constant("abcabc"), constant("(abc)\\1"));
    assertEvaluatesToError(evaluate(expr), "regexFind invalid regex");
  });
  test('regexFind_getNonStringRegex_isError', () {
    final expr = regexFind(constant(42), constant("search"));
    assertEvaluatesToError(evaluate(expr), "regexFind(42, \"search\")");
  });
  test('regexFind_getNonStringValue_isError', () {
    final expr = regexFind(constant("ear"), constant(42));
    assertEvaluatesToError(evaluate(expr), "regexFind(\"ear\", 42)");
  });
  test('regexFind_getMultipleCaptureGroups_isError', () {
    final expr = regexFind(
      constant("Date: 2025-11-15"),
      constant("Date: (\\d{4})-(\\d{2})-(\\d{2})"),
    );
    assertEvaluatesToError(evaluate(expr), "regexFind multiple capture groups");
  });
}
