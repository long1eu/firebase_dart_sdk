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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/strings/ToUpperTests.kt
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
  test('toUpper_mirror', () {
    for (final testCase in UNARY_MIRROR_TEST_CASES) {
      assertEvaluatesToNull(
        evaluate(toUpper(testCase.input)),
        "toUpper(\${testCase.name})",
      );
    }
  });
  test('toUpper_onLowercaseString', () {
    final expr = toUpper(constant("foo"));
    assertEvaluatesTo(evaluate(expr), encodeValue("FOO"), "toUpper('foo')");
  });
  test('toUpper_onLatinChar', () {
    final expr = toUpper(constant("ÿ"));
    assertEvaluatesTo(evaluate(expr), encodeValue("Ÿ"), "toUpper('ÿ')");
  });
  test('toUpper_onGreekChars', () {
    final expr = toUpper(constant("αβδ"));
    assertEvaluatesTo(evaluate(expr), encodeValue("ΑΒΔ"), "toUpper('αβδ')");
  });
  test('toUpper_onCyrillicChars', () {
    final expr = toUpper(constant("чжд"));
    assertEvaluatesTo(evaluate(expr), encodeValue("ЧЖД"), "toUpper('чжд')");
  });
  test('toUpper_onChineseChars', () {
    final expr = toUpper(constant("宋体"));
    assertEvaluatesTo(evaluate(expr), encodeValue("宋体"), "toUpper('宋体')");
  });
  test('toUpper_onUppercaseString', () {
    final expr = toUpper(constant("FOO"));
    assertEvaluatesTo(evaluate(expr), encodeValue("FOO"), "toUpper('FOO')");
  });
  test('toUpper_onMixedCaseString', () {
    final expr = toUpper(constant("fOobAR"));
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue("FOOBAR"),
      "toUpper('fOobAR')",
    );
  });
  test('toUpper_onEmptyString', () {
    final expr = toUpper(constant(""));
    assertEvaluatesTo(evaluate(expr), encodeValue(""), "toUpper('')");
  });
  test('toUpper_onLowercaseBytes', () {
    final expr = toUpper(
      constant(blobFromByteString(ByteString.copyFromUtf8("foo"))),
    );
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(blobFromByteString(ByteString.copyFromUtf8("FOO"))),
      "toUpper(blob('foo'))",
    );
  });
  test('toUpper_onUppercaseBytes', () {
    final expr = toUpper(
      constant(blobFromByteString(ByteString.copyFromUtf8("FOO"))),
    );
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(blobFromByteString(ByteString.copyFromUtf8("FOO"))),
      "toUpper(blob('FOO'))",
    );
  });
  test('toUpper_onMixedCaseBytes', () {
    final expr = toUpper(
      constant(blobFromByteString(ByteString.copyFromUtf8("fOobAR"))),
    );
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(blobFromByteString(ByteString.copyFromUtf8("FOOBAR"))),
      "toUpper(blob('fOobAR'))",
    );
  });
  test('toUpper_onBytesWithNonAscii', () {
    final nonAscii = blobFromByteString(ByteString.fromHex("F9FAFBFC"));
    final expr = toUpper(constant(nonAscii));
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(nonAscii),
      "toUpper(blob(non-ascii))",
    );
  });
  test('toUpper_onBytesWithNonAsciiAndAscii', () {
    final mixedBytes = blobFromByteString(
      ByteString.copyFromUtf8("foOBaR").concat(ByteString.fromHex("F9FAFBFC")),
    );
    final expectedBytes = blobFromByteString(
      ByteString.copyFromUtf8("FOOBAR").concat(ByteString.fromHex("F9FAFBFC")),
    );
    final expr = toUpper(constant(mixedBytes));
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(expectedBytes),
      "toUpper(blob(mixed))",
    );
  });
  test('toUpper_onEmptyBytes', () {
    final expr = toUpper(constant(blobFromByteString(ByteString.EMPTY)));
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(blobFromByteString(ByteString.EMPTY)),
      "toUpper(blob())",
    );
  });
  test('toUpper_onNull', () {
    final expr = toUpper(nullValue());
    assertEvaluatesToNull(evaluate(expr), "toUpper(null)");
  });
  test('toUpper_onUnsupportedType', () {
    final expr = toUpper(constant(1));
    assertEvaluatesToError(
      evaluate(expr),
      "The function to_upper(...) requires `String | Bytes` but got `INT`",
    );
  });
}
