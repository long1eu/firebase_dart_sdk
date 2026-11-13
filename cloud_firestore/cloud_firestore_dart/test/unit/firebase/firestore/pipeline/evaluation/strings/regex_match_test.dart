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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/strings/RegexMatchTests.kt
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
import '../comparison/comparison_test_data.dart';

void main() {
  // --- RegexMatch Tests ---
  test('regexMatch_mirrorError', () {
    for (final (name, left, right) in BINARY_MIRROR_TEST_CASES) {
      final expr = regexMatch(left, right);
      assertEvaluatesToNull(evaluate(expr), "regexMatch($name)");
    }
  });
  test('regexMatch_getNonStringRegex_isError', () {
    final expr = regexMatch(constant(42), constant("search"));
    assertEvaluatesToError(evaluate(expr), "regexMatch(42, \"search\")");
  });
  test('regexMatch_getNonStringValue_isError', () {
    final expr = regexMatch(constant("ear"), constant(42));
    assertEvaluatesToError(evaluate(expr), "regexMatch(\"ear\", 42)");
  });
  test('regexMatch_getNaNRegex_isError', () {
    final expr = regexMatch(constant("foo"), doubleNaN);
    assertEvaluatesToError(evaluate(expr), "regexMatch(foo, NaN)");
  });
  test('regexMatch_getNaNValue_isError', () {
    final expr = regexMatch(doubleNaN, constant("foo"));
    assertEvaluatesToError(evaluate(expr), "regexMatch(NaN, foo)");
  });
  test('regexMatch_getInvalidRegex_isError', () {
    final expr = regexMatch(constant("abcabc"), constant("(abc)\\1"));
    assertEvaluatesToError(evaluate(expr), "regexMatch invalid regex");
  });
  test('regexMatch_getStaticRegex', () {
    final expr = regexMatch(constant("yummy food"), constant(".*oo.*"));
    assertEvaluatesTo(evaluate(expr), true, "regexMatch static");
  });
  test('regexMatch_getSubStringLiteral', () {
    final expr = regexMatch(constant("yummy good food"), constant("good"));
    assertEvaluatesTo(
      evaluate(expr),
      false,
      "regexMatch substringing literal (false)",
    );
  });
  test('regexMatch_getSubStringRegex', () {
    final expr = regexMatch(constant("yummy good food"), constant("go*d"));
    assertEvaluatesTo(
      evaluate(expr),
      false,
      "regexMatch substringing regex (false)",
    );
  });
  test('regexMatch_getDynamicRegex', () {
    final expr = regexMatch(constant("yummy food"), field("regex"));
    final doc1 = doc("coll/doc1", 0, <String, Object?>{
      "regex": "^yummy.*",
    }); // Should be true
    final doc2 = doc("coll/doc2", 0, <String, Object?>{"regex": "fooood\$"});
    final doc3 = doc("coll/doc3", 0, <String, Object?>{"regex": ".*"});
    final doc4 = doc("coll/doc4", 0, <String, Object?>{
      "regex": "yummy",
    }); // Should be false

    assertEvaluatesTo(evaluate(expr, doc1), true, "regexMatch dynamic doc1");
    assertEvaluatesTo(evaluate(expr, doc2), false, "regexMatch dynamic doc2");
    assertEvaluatesTo(evaluate(expr, doc3), true, "regexMatch dynamic doc3");
    assertEvaluatesTo(evaluate(expr, doc4), false, "regexMatch dynamic doc4");
  });
}
