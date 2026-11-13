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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/strings/ToLowerTests.kt
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
  test('toLower_mirror', () {
    for (final testCase in UNARY_MIRROR_TEST_CASES) {
      assertEvaluatesToNull(
        evaluate(toLower(testCase.input)),
        "toLower(${testCase.name})",
      );
    }
  });
  test('toLower_onLowercaseString', () {
    final expr = toLower(constant("foo"));
    assertEvaluatesTo(evaluate(expr), encodeValue("foo"), "toLower('foo')");
  });
  test('toLower_onLatinChar', () {
    final expr = toLower(constant("Ÿ"));
    assertEvaluatesTo(evaluate(expr), encodeValue("ÿ"), "toLower('Ÿ')");
  });
  test('toLower_onGreekChars', () {
    final expr = toLower(constant("Δ"));
    assertEvaluatesTo(evaluate(expr), encodeValue("δ"), "toLower('Δ')");
  });
  test('toLower_onCyrillicChars', () {
    final expr = toLower(constant("ЧЖД"));
    assertEvaluatesTo(evaluate(expr), encodeValue("чжд"), "toLower('ЧЖД')");
  });
  test('toLower_onChineseChars', () {
    final expr = toLower(constant("宋体"));
    assertEvaluatesTo(evaluate(expr), encodeValue("宋体"), "toLower('宋体')");
  });
  test('toLower_onUppercaseString', () {
    final expr = toLower(constant("FOO"));
    assertEvaluatesTo(evaluate(expr), encodeValue("foo"), "toLower('FOO')");
  });
  test('toLower_onMixedCaseString', () {
    final expr = toLower(constant("fOobAR"));
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue("foobar"),
      "toLower('fOobAR')",
    );
  });
  test('toLower_onEmptyString', () {
    final expr = toLower(constant(""));
    assertEvaluatesTo(evaluate(expr), encodeValue(""), "toLower('')");
  });
  test('toLower_onStringWithNonAscii', () {
    final expr = toLower(constant("é🦆"));
    assertEvaluatesTo(evaluate(expr), encodeValue("é🦆"), "toLower('é🦆')");
  });
  test('toLower_onLowercaseBytes', () {
    final expr = toLower(
      constant(blobFromByteString(ByteString.copyFromUtf8("foo"))),
    );
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(blobFromByteString(ByteString.copyFromUtf8("foo"))),
      "toLower(blob('foo'))",
    );
  });
  test('toLower_onUppercaseBytes', () {
    final expr = toLower(
      constant(blobFromByteString(ByteString.copyFromUtf8("FOO"))),
    );
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(blobFromByteString(ByteString.copyFromUtf8("foo"))),
      "toLower(blob('FOO'))",
    );
  });
  test('toLower_onMixedCaseBytes', () {
    final expr = toLower(
      constant(blobFromByteString(ByteString.copyFromUtf8("fOobAR"))),
    );
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(blobFromByteString(ByteString.copyFromUtf8("foobar"))),
      "toLower(blob('fOobAR'))",
    );
  });
  test('toLower_onBytesWithNonAscii', () {
    final nonAscii = blobFromByteString(ByteString.fromHex("F9FAFBFC"));
    final expr = toLower(constant(nonAscii));
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(nonAscii),
      "toLower(blob(non-ascii))",
    );
  });
  test('toLower_onBytesWithNonAsciiAndAscii', () {
    final mixedBytes = blobFromByteString(
      ByteString.copyFromUtf8("foOBaR").concat(ByteString.fromHex("F9FAFBFC")),
    );
    final expectedBytes = blobFromByteString(
      ByteString.copyFromUtf8("foobar").concat(ByteString.fromHex("F9FAFBFC")),
    );
    final expr = toLower(constant(mixedBytes));
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(expectedBytes),
      "toLower(blob(mixed))",
    );
  });
  test('toLower_onEmptyBytes', () {
    final expr = toLower(constant(blobFromByteString(ByteString.EMPTY)));
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(blobFromByteString(ByteString.EMPTY)),
      "toLower(blob())",
    );
  });
}
