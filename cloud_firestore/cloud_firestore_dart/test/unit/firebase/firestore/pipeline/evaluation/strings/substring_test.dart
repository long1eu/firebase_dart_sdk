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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/strings/SubstringTests.kt
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

void main() {
  test('substring_onString_returnsSubstring', () {
    final expr = substring(constant("abc"), constant(1), constant(2));
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue("bc"),
      "substring(\"abc\", 1, 2)",
    );
  });
  test('substring_onString_largePosition_returnsEmptyString', () {
    final expr = substring(constant("abc"), constant(maxLong), constant(1));
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(""),
      "substring('abc', maxLong, 1)",
    );
  });
  test('substring_onString_positionOnLast_returnsLastCharacter', () {
    final expr = substring(constant("abc"), constant(2), constant(2));
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue("c"),
      "substring(\"abc\", 2, 2)",
    );
  });
  test('substring_onString_positionPastLast_returnsEmptyString', () {
    final expr = substring(constant("abc"), constant(3), constant(2));
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(""),
      "substring(\"abc\", 3, 2)",
    );
  });
  test('substring_onString_positionOnZero_startsFromZero', () {
    final expr = substring(constant("abc"), constant(0), constant(6));
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue("abc"),
      "substring(\"abc\", 0, 6)",
    );
  });
  test('substring_onString_oversizedLength_returnsTruncatedString', () {
    final expr = substring(constant("abc"), constant(1), constant(maxLong));
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue("bc"),
      "substring(\"abc\", 1, maxLong)",
    );
  });
  test('substring_onString_negativePosition', () {
    final expr = substring(constant("abcd"), constant(-3), constant(2));
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue("bc"),
      "substring(\"abcd\", -3, 2)",
    );
  });
  test('substring_onString_negativePosition_startsFromLast', () {
    final expr = substring(constant("abc"), constant(-1), constant(1));
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue("c"),
      "substring(\"abc\", -1, 1)",
    );
  });
  test('substring_onCodePoints_negativePosition_startsFromLast', () {
    final expr = substring(constant("㉇🀄"), constant(-1), constant(1));
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue("🀄"),
      "substring(\"㉇🀄\", -1, 1)",
    );
  });
  test('substring_onString_maxNegativePosition_startsFromZero', () {
    final expr = substring(
      constant("abc".toByteArray()),
      constant(-maxLong),
      constant(2),
    );
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(blobFromByteString("ab".toByteArray())),
      "substring(blob(abc), -maxLong, 2)",
    );
  });
  test('substring_onString_oversizedNegativePosition_startsFromZero', () {
    final expr = substring(
      constant("abc".toByteArray()),
      constant(-4),
      constant(2),
    );
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(blobFromByteString("ab".toByteArray())),
      "substring(blob(abc), -4, 2)",
    );
  });
  test('substring_onNonAsciiString', () {
    final expr = substring(constant("ϖϗϠ"), constant(1), constant(1));
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue("ϗ"),
      "substring(\"ϖϗϠ\", 1, 1)",
    );
  });
  test('substring_onCharacterDecomposition_treatedAsSeparateCharacters', () {
    final umlaut = String.fromCharCodes(<int>[0x0308]);
    final decomposedChar = "u" + umlaut;

    // Assert that the component characters of a decomposed character are trimmed correctly.
    final expr1 = substring(constant(decomposedChar), constant(1), constant(2));
    assertEvaluatesTo(
      evaluate(expr1),
      encodeValue(umlaut),
      "substring(decomposed, 1, 2)",
    );

    final expr2 = substring(constant(decomposedChar), constant(0), constant(1));
    assertEvaluatesTo(
      evaluate(expr2),
      encodeValue("u"),
      "substring(decomposed, 0, 1)",
    );
  });
  test('substring_onComposedCharacter_treatedAsSingleCharacter', () {
    final expr1 = substring(constant("ü"), constant(1), constant(1));
    assertEvaluatesTo(
      evaluate(expr1),
      encodeValue(""),
      "substring(\"ü\", 1, 1)",
    );

    final expr2 = substring(constant("ü"), constant(0), constant(1));
    assertEvaluatesTo(
      evaluate(expr2),
      encodeValue("ü"),
      "substring(\"ü\", 0, 1)",
    );
  });
  test('substring_mixedAsciiNonAsciiString_returnsSubstring', () {
    final expr = substring(constant("aϗbϖϗϠc"), constant(1), constant(3));
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue("ϗbϖ"),
      "substring(\"aϗbϖϗϠc\", 1, 3)",
    );
  });
  test('substring_mixedAsciiNonAsciiString_afterNonAscii', () {
    final expr = substring(constant("aϗbϖϗϠc"), constant(4), constant(2));
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue("ϗϠ"),
      "substring(\"aϗbϖϗϠc\", 4, 2)",
    );
  });
  test('substring_onString_negativeLength_throws', () {
    final expr = substring(
      constant("abc".toByteArray()),
      constant(1),
      constant(-1),
    );
    assertEvaluatesToError(evaluate(expr), "substring with negative length");
  });
  test('substring_onBytes_returnsSubstring', () {
    final expr = substring(
      constant("abc".toByteArray()),
      constant(1),
      constant(2),
    );
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(blobFromByteString("bc".toByteArray())),
      "substring(blob(abc), 1, 2)",
    );
  });
  test('substring_onBytes_returnsInvalidUTF8Substring', () {
    final expr = substring(
      constant(ByteString.fromHex("F9FAFB").toByteArray()),
      constant(1),
      constant(maxLong),
    );
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(blobFromByteString(ByteString.fromHex("FAFB"))),
      "substring invalid utf8",
    );
  });
  test('substring_onCodePoints_returnsSubstring', () {
    final codePoints = "🌎㉇🀄⛹";
    final expr = substring(constant(codePoints), constant(1), constant(2));
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue("㉇🀄"),
      "substring(\"🌎㉇🀄⛹\", 1, 2)",
    );
  });
  test('substring_onCodePoints_andAscii_returnsSubstring', () {
    final codePoints = "🌎㉇foo🀄bar⛹";
    final expr = substring(constant(codePoints), constant(4), constant(4));
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue("o🀄ba"),
      "substring(\"🌎㉇foo🀄bar⛹\", 4, 4)",
    );
  });
  test('substring_onCodePoints_oversizedLength_returnsSubstring', () {
    final codePoints = "🌎㉇🀄⛹";
    final expr = substring(constant(codePoints), constant(1), constant(6));
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue("㉇🀄⛹"),
      "substring(\"🌎㉇🀄⛹\", 1, 6)",
    );
  });
  test('substring_onCodePoints_startingAtZero_returnsSubstring', () {
    final codePoints = "🌎㉇🀄⛹";
    final expr = substring(constant(codePoints), constant(0), constant(3));
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue("🌎㉇🀄"),
      "substring(\"🌎㉇🀄⛹\", 0, 3)",
    );
  });
  test('substring_onSingleCodePointGrapheme_doesNotSplit', () {
    final expr1 = substring(constant("🖖"), constant(0), constant(1));
    assertEvaluatesTo(
      evaluate(expr1),
      encodeValue("🖖"),
      "substring(\"🖖\", 0, 1)",
    );
    final expr2 = substring(constant("🖖"), constant(1), constant(1));
    assertEvaluatesTo(
      evaluate(expr2),
      encodeValue(""),
      "substring(\"🖖\", 1, 1)",
    );
  });
  test('substring_onMultiCodePointGrapheme_splitsGrapheme', () {
    final expr1 = substring(constant("🖖🏻"), constant(0), constant(1));
    assertEvaluatesTo(
      evaluate(expr1),
      encodeValue("🖖"),
      "substring(\"🖖🏻\", 0, 1)",
    );
    // Asserting that when the second half is split, it only returns the skin tone code point.
    final expr2 = substring(constant("🖖🏻"), constant(1), constant(1));
    final skinTone = String.fromCharCodes(<int>[0xD83C, 0xDFFB]);
    assertEvaluatesTo(
      evaluate(expr2),
      encodeValue(skinTone),
      "substring(\"🖖🏻\", 1, 1)",
    );
  });
  test('substring_onBytes_largePosition_returnsEmptyString', () {
    final expr = substring(
      constant("abc".toByteArray()),
      constant(maxLong),
      constant(3),
    );
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(blobFromByteString(ByteString.EMPTY)),
      "substring(blob(abc), maxLong, 3)",
    );
  });
  test('substring_onBytes_positionOnLast_returnsLastByte', () {
    final expr = substring(
      constant("abc".toByteArray()),
      constant(2),
      constant(2),
    );
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(blobFromByteString("c".toByteArray())),
      "substring(blob(abc), 2, 2)",
    );
  });
  test('substring_onBytes_positionPastLast_returnsEmptyByteString', () {
    final expr = substring(
      constant("abc".toByteArray()),
      constant(3),
      constant(2),
    );
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(blobFromByteString(ByteString.EMPTY)),
      "substring(blob(abc), 3, 2)",
    );
  });
  test('substring_onBytes_positionOnZero_startsFromZero', () {
    final expr = substring(
      constant("abc".toByteArray()),
      constant(0),
      constant(6),
    );
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(blobFromByteString("abc".toByteArray())),
      "substring(blob(abc), 0, 6)",
    );
  });
  test('substring_onBytes_negativePosition_startsFromLast', () {
    final expr = substring(
      constant("abc".toByteArray()),
      constant(-1),
      constant(1),
    );
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(blobFromByteString("c".toByteArray())),
      "substring(blob(abc), -1, 1)",
    );
  });
  test('substring_onBytes_oversizedNegativePosition_startsFromZero', () {
    final expr = substring(
      constant("abc".toByteArray()),
      constant(-maxLong),
      constant(3),
    );
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(blobFromByteString("abc".toByteArray())),
      "substring(blob(abc), -maxLong, 3)",
    );
  });
  test('substring_unknownValueType_returnsError', () {
    final expr = substring(constant(20), constant(4), constant(1));
    assertEvaluatesToError(evaluate(expr), "substring on non-string/blob");
  });
  test('substring_unknownPositionType_returnsError', () {
    final expr = substring(constant("abc"), constant("foo"), constant(1));
    assertEvaluatesToError(
      evaluate(expr),
      "substring with non-integer position",
    );
  });
  test('substring_unknownLengthType_returnsError', () {
    final expr = substring(constant("abc"), constant(1), constant("foo"));
    assertEvaluatesToError(evaluate(expr), "substring with non-integer length");
  });
}
