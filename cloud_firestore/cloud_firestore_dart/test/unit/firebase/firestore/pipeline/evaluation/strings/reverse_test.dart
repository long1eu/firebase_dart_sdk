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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/strings/ReverseTests.kt
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
  // --- Reverse Tests ---
  test('reverse_mirror', () {
    for (final testCase in UNARY_MIRROR_TEST_CASES) {
      assertEvaluatesToNull(
        evaluate(reverse(testCase.input)),
        "reverse(${testCase.name})",
      );
    }
  });
  test('reverse_onSimpleString', () {
    final expr = reverse(constant("foobar"));
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue("raboof"),
      "reverse on simple string",
    );
  });
  test('reverse_onSingleLengthString', () {
    final expr = reverse(constant("t"));
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue("t"),
      "reverse on single length string",
    );
  });
  test('reverse_onMultiCodePointGrapheme_breaksGrapheme', () {
    // Since we only support code-point level support, multi-code point graphemes are treated as two
    // separate characters.
    final expr = reverse(constant("🖖🏻"));
    final expected = String.fromCharCodes(<int>[0xD83C, 0xDFFB]) + "🖖";
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(expected),
      "reverse on multi-codepoint grapheme",
    );
  });
  test('reverse_onComposedCharacter_treatedAsSingleCharacter', () {
    final expr = reverse(constant("ü"));
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue("ü"),
      "reverse on composed character",
    );
  });
  test('reverse_onDecomposedCharacter_treatedAsSeparateCharacters', () {
    final umlaut = String.fromCharCodes(<int>[0x0308]);
    final decomposedChar = "u" + umlaut;
    final expr = reverse(constant(decomposedChar));
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(umlaut + "u"),
      "reverse on decomposed character",
    );
  });
  test('reverse_onEmptyString', () {
    final expr = reverse(constant(""));
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(""),
      "reverse on empty string",
    );
  });
  test('reverse_onStringWithNonAscii', () {
    final expr = reverse(constant("é🦆🖖🌎"));
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue("🌎🖖🦆é"),
      "reverse on string with non-ascii",
    );
  });
  test('reverse_onStringWithAsciiAndNonAscii', () {
    final expr = reverse(constant("é🦆foo🖖b🌎ar"));
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue("ra🌎b🖖oof🦆é"),
      "reverse on string with ascii and non-ascii",
    );
  });
  test('reverse_onBytes', () {
    final expr = reverse(
      constant(ByteString.copyFromUtf8("foo").toByteArray()),
    );
    final expected = blobFromByteString(ByteString.copyFromUtf8("oof"));
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(expected),
      "reverse on bytes",
    );
  });
  test('reverse_onBytesWithNonAsciiAndAscii', () {
    final nonAscii = ByteString.copyFromUtf8(
      "foOBaR",
    ).concat(ByteString.fromHex("F9FAFBFC"));
    final expr = reverse(constant(nonAscii.toByteArray()));
    final expectedBytes = ByteString.fromHex(
      "FCFBFAF9",
    ).concat(ByteString.copyFromUtf8("RaBOof"));
    final expected = blobFromByteString(expectedBytes);
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(expected),
      "reverse on bytes with non-ascii and ascii",
    );
  });
  test('reverse_onEmptyBytes', () {
    final expr = reverse(constant(ByteString.EMPTY.toByteArray()));
    final expected = blobFromByteString(ByteString.EMPTY);
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(expected),
      "reverse on empty bytes",
    );
  });
  test('reverse_onSingleByte', () {
    final expr = reverse(constant(ByteString.copyFromUtf8("a").toByteArray()));
    final expected = blobFromByteString(ByteString.copyFromUtf8("a"));
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(expected),
      "reverse on single byte",
    );
  });
  test('reverse_onUnsupportedType', () {
    final expr = reverse(constant(1));
    assertEvaluatesToError(
      evaluate(expr),
      "The function string_reverse(...) requires `String | Bytes` but got `LONG`",
    );
  });
  test('reverse_onBoolean', () {
    final expr = reverse(constant(true));
    assertEvaluatesToError(
      evaluate(expr),
      "The function string_reverse(...) requires `String | Bytes` but got `BOOLEAN`",
    );
  });
  test('reverse_onDouble', () {
    final expr = reverse(constant(1.0));
    assertEvaluatesToError(
      evaluate(expr),
      "The function string_reverse(...) requires `String | Bytes` but got `DOUBLE`",
    );
  });
  test('reverse_onMap', () {
    final expr = reverse(map(<String, Object?>{}));
    assertEvaluatesToError(
      evaluate(expr),
      "The function string_reverse(...) requires `String | Bytes` but got `MAP`",
    );
  });
}
