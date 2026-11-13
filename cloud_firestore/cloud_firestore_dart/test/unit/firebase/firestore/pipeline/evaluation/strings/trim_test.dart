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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/strings/TrimTests.kt
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
  // --- Trim Tests ---
  test('trim_mirror', () {
    for (final testCase in UNARY_MIRROR_TEST_CASES) {
      assertEvaluatesToNull(
        evaluate(trim(testCase.input)),
        "trim(\${testCase.name})",
      );
    }
  });
  test('trim_basic', () {
    final expr = trim(constant("  foo bar  "));
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue("foo bar"),
      "trim(\"  foo bar  \")",
    );
  });
  test('trim_noTrimNeeded', () {
    final expr = trim(constant("foo bar"));
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue("foo bar"),
      "trim(\"foo bar\")",
    );
  });
  test('trim_onlyWhitespace', () {
    final expr = trim(constant("   \t\n  "));
    assertEvaluatesTo(evaluate(expr), encodeValue(""), "trim(\"   \t\n  \")");
  });
  test('trim_empty', () {
    final expr = trim(constant(""));
    assertEvaluatesTo(evaluate(expr), encodeValue(""), "trim(\"\")");
  });
  test('trim_extendedWhitespace', () {
    final expr = trim(constant("\t\n\r\n\u000cfoobar\t\n\r\n\u000c"));
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue("foobar"),
      "trim_extendedWhitespace",
    );
  });
  test('trim_singleLengthString', () {
    final expr = trim(constant("t"));
    assertEvaluatesTo(evaluate(expr), encodeValue("t"), "trim('t')");
  });
  test('trim_singleLengthSpace', () {
    final expr = trim(constant(" "));
    assertEvaluatesTo(evaluate(expr), encodeValue(""), "trim(' ')");
  });
  test('trim_singleUnicodeString', () {
    final expr = trim(constant("🖖🏻"));
    assertEvaluatesTo(evaluate(expr), encodeValue("🖖🏻"), "trim('🖖🏻')");
  });
  test('trim_bytes_noWhitespace', () {
    final expr = trim(constant(blob(102, 111, 111, 98, 97, 114))); // "foobar"
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(blob(102, 111, 111, 98, 97, 114)),
      "trim(bytes)",
    );
  });
  test('trim_bytes_withWhitespace', () {
    final expr = trim(
      constant(
        blob(32, 32, 46, 32, 102, 111, 111, 98, 97, 114, 32, 46, 32, 32),
      ),
    ); // "  . foobar .  "
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(blob(46, 32, 102, 111, 111, 98, 97, 114, 32, 46)),
      "trim(bytes_whitespace)",
    );
  });
  test('trim_bytes_withExtendedWhitespace', () {
    final expr = trim(
      constant(
        blob(9, 10, 13, 10, 12, 102, 111, 111, 98, 97, 114, 9, 10, 13, 10, 12),
      ),
    ); // "\t\n\r\n\ffoobar\t\n\r\n\f"
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(blob(102, 111, 111, 98, 97, 114)),
      "trim(bytes_extended_whitespace)",
    );
  });
  test('trim_emptyBytes', () {
    final expr = trim(constant(blob()));
    assertEvaluatesTo(evaluate(expr), encodeValue(blob()), "trim(empty_bytes)");
  });
  test('trim_singleByte', () {
    final expr = trim(constant(blob(97))); // "a"
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(blob(97)),
      "trim(single_byte)",
    );
  });
  test('trim_bytesAllWhitespace', () {
    final expr = trim(constant(blob(32))); // " "
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(blob()),
      "trim(bytes_all_whitespace)",
    );
  });
  test('trim_nonString', () {
    final expr = trim(constant(123));
    assertEvaluatesToError(evaluate(expr), "trim(123)");
  });
  test('trim_null', () {
    final expr = trim(nullValue());
    assertEvaluatesToNull(evaluate(expr), "trim(null)");
  });
}
