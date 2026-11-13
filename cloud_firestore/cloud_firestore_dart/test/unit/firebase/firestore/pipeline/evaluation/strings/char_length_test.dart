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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/strings/CharLengthTests.kt
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

import 'dart:typed_data';

import 'package:test/test.dart' show test;

import '../evaluation_test_util.dart';

void main() {
  // --- CharLength Tests ---
  test('charLength_emptyString_returnsZero', () {
    final expr = charLength(constant(""));
    final result = evaluate(expr);
    assertEvaluatesTo(result, encodeValue(0), "charLength(\"\")");
  });
  test('charLength_bytesType_returnsError', () {
    // charLength expects a string, not bytes/blob
    final charBlobBytes = Uint8List.fromList(<int>[
      'a'.code.toByte(),
      'b'.code.toByte(),
      'c'.code.toByte(),
    ]);
    final expr = charLength(constant(charBlobBytes));
    final result = evaluate(expr);
    assertEvaluatesToError(result, "charLength(blob)");
  });
  test('charLength_baseCaseBmp', () {
    assertEvaluatesTo(
      evaluate(charLength(constant("abc"))),
      encodeValue(3),
      "charLength(\"abc\")",
    );
    assertEvaluatesTo(
      evaluate(charLength(constant("1234"))),
      encodeValue(4),
      "charLength(\"1234\")",
    );
    assertEvaluatesTo(
      evaluate(charLength(constant("abc123!@"))),
      encodeValue(8),
      "charLength(\"abc123!@\")",
    );
    assertEvaluatesTo(
      evaluate(charLength(constant("你好世界"))),
      encodeValue(4),
      "charLength(\"你好世界\")",
    );
    assertEvaluatesTo(
      evaluate(charLength(constant("cafétéria"))),
      encodeValue(9),
      "charLength(\"cafétéria\")",
    );
    assertEvaluatesTo(
      evaluate(charLength(constant("абвгд"))),
      encodeValue(5),
      "charLength(\"абвгд\")",
    );
    assertEvaluatesTo(
      evaluate(charLength(constant("¡Hola! ¿Cómo estás?"))),
      encodeValue(19),
      "charLength(\"¡Hola! ¿Cómo estás?\")",
    );
    assertEvaluatesTo(
      evaluate(charLength(constant("☺"))),
      encodeValue(1),
      "charLength(\"☺\")",
    ); // U+263A
  });
  test('charLength_spaces', () {
    assertEvaluatesTo(
      evaluate(charLength(constant(" "))),
      encodeValue(1),
      "charLength(\" \")",
    );
    assertEvaluatesTo(
      evaluate(charLength(constant("  "))),
      encodeValue(2),
      "charLength(\"  \")",
    );
    assertEvaluatesTo(
      evaluate(charLength(constant("a b"))),
      encodeValue(3),
      "charLength(\"a b\")",
    );
  });
  test('charLength_specialCharacters', () {
    assertEvaluatesTo(
      evaluate(charLength(constant("\n"))),
      encodeValue(1),
      "charLength(\"\\n\")",
    );
    assertEvaluatesTo(
      evaluate(charLength(constant("\t"))),
      encodeValue(1),
      "charLength(\"\\t\")",
    );
    assertEvaluatesTo(
      evaluate(charLength(constant("\\"))),
      encodeValue(1),
      "charLength(\"\\\\\")",
    );
  });
  test('charLength_bmpSmpMix', () {
    // Hello = 5, Smiling Face Emoji (U+1F60A) = 1 code point => 6
    assertEvaluatesTo(
      evaluate(charLength(constant("Hello😊"))),
      encodeValue(6),
      "charLength(\"Hello😊\")",
    );
  });
  test('charLength_smp', () {
    // Strawberry (U+1F353) = 1, Peach (U+1F351) = 1 => 2 code points
    assertEvaluatesTo(
      evaluate(charLength(constant("🍓🍑"))),
      encodeValue(2),
      "charLength(\"🍓🍑\")",
    );
  });
  test('charLength_highSurrogateOnly', () {
    // A lone high surrogate U+D83C is 1 code point in a Java String.
    // The Kotlin `evaluateCharLength` uses `string.length` which counts UTF-16 code units.
    // For a lone surrogate, this is 1.
    // This differs from C++ test which expects an error for invalid UTF-8 sequence.
    // The current Kotlin implementation of charLength is `value.stringValue.length` which is UTF-16
    // code units.
    // This needs to be `value.stringValue.codePointCount(0, value.stringValue.length)` for correct
    // char count.
    // For now, I will write the test based on the current `expressions.kt` (which seems to be
    // `stringValue.length`).
    // If `charLength` is fixed to count code points, this test will need adjustment.
    // Assuming current `evaluateCharLength` uses `s.length()`:
    assertEvaluatesTo(
      evaluate(charLength(constant("\uD83C"))),
      encodeValue(1),
      "charLength(\"\\uD83C\") - lone high surrogate",
    );
  });
  test('charLength_lowSurrogateOnly', () {
    // Similar to high surrogate.
    assertEvaluatesTo(
      evaluate(charLength(constant("\uDF53"))),
      encodeValue(1),
      "charLength(\"\\uDF53\") - lone low surrogate",
    );
  });
  test('charLength_lowAndHighSurrogateSwapped', () {
    // "\uDF53\uD83C" - two UTF-16 code units.
    assertEvaluatesTo(
      evaluate(charLength(constant("\uDF53\uD83C"))),
      encodeValue(2),
      "charLength(\"\\uDF53\\uD83C\") - swapped surrogates",
    );
  });
  test('charLength_largeString', () {
    final largeA = "a".repeat(1500);
    final largeAb = "ab".repeat(1500);

    assertEvaluatesTo(
      evaluate(charLength(constant(largeA))),
      encodeValue(1500),
      "charLength(largeA)",
    );
    assertEvaluatesTo(
      evaluate(charLength(constant(largeAb))),
      encodeValue(3000),
      "charLength(largeAb)",
    );
  });
}
