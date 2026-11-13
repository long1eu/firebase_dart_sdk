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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/strings/ByteLengthTests.kt
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
import '../mirroring_test_cases.dart';

void main() {
  test('byteLength_mirror', () {
    for (final testCase in UNARY_MIRROR_TEST_CASES) {
      assertEvaluatesToNull(
        evaluate(byteLength(testCase.input)),
        "byteLength(${testCase.name})",
      );
    }
  });

  // --- ByteLength Tests ---
  test('byteLength_emptyString_returnsZero', () {
    final expr = byteLength(constant(""));
    final result = evaluate(expr);
    assertEvaluatesTo(result, encodeValue(0), "byteLength(\"\")");
  });
  test('byteLength_emptyByte_returnsZero', () {
    final expr = byteLength(constant(Uint8List.fromList(<int>[])));
    final result = evaluate(expr);
    assertEvaluatesTo(
      result,
      encodeValue(0),
      "byteLength(blob(Uint8List.fromList(<int>[])))",
    );
  });
  test('byteLength_nonStringOrBytes_returnsErrorOrCorrectLength', () {
    // Test with non-string/byte types - should error
    assertEvaluatesToError(
      evaluate(byteLength(constant(123))),
      "byteLength(123)",
    );
    assertEvaluatesToError(
      evaluate(byteLength(constant(true))),
      "byteLength(true)",
    );

    // Test with a valid Blob
    final bytesForBlob = Uint8List.fromList(<int>[
      0x01.toByte(),
      0x02.toByte(),
      0x03.toByte(),
    ]);
    final exprAsBlob = byteLength(
      constant(bytesForBlob),
    ); // Renamed exprBlob to avoid conflict if it was a var
    final resultBlob = evaluate(exprAsBlob);
    assertEvaluatesTo(resultBlob, encodeValue(3), "byteLength(blob(1,2,3))");

    // Test with a valid ByteArray
    final bytesArray = Uint8List.fromList(<int>[
      0x01.toByte(),
      0x02.toByte(),
      0x03.toByte(),
      0x04.toByte(),
    ]);
    final exprByteArray = byteLength(constant(bytesArray));
    final resultByteArray = evaluate(exprByteArray);
    assertEvaluatesTo(
      resultByteArray,
      encodeValue(4),
      "byteLength(Uint8List.fromList(<int>[1,2,3,4]))",
    );
  });
  test('byteLength_highSurrogateOnly', () {
    // UTF-8 encoding of a lone high surrogate is invalid.
    // U+D83C (high surrogate) incorrectly encoded as 3 bytes in ISO-8859-1
    // This test assumes the underlying string processing correctly identifies invalid UTF-8
    final expr = byteLength(
      constant("\uD83C"),
    ); // Java string with lone high surrogate
    final result = evaluate(expr);
    // Depending on implementation, this might error or give a byte length
    // Based on C++ test, it should be an error if strict UTF-8 validation is done.
    // The Kotlin `evaluateByteLength` uses `string.toByteArray(Charsets.UTF_8).size`
    // which for a lone surrogate might throw an exception or produce replacement characters.
    // Let's assume it should error if the input string is not valid UTF-8 representable.
    // Java's toByteArray(UTF_8) replaces unpaired surrogates with '?', which is 1 byte.
    // This behavior differs from the C++ test's expectation of an error.
    // For now, let's match the likely Java behavior. '?' is one byte.
    // UPDATE: The C++ test `\xED\xA0\xBC` is an invalid UTF-8 sequence for U+D83C.
    // Java's `"\uD83C".toByteArray(StandardCharsets.UTF_8)` results in `[0x3f]` (the replacement
    // char '?')
    // So length is 1. The C++ test is more about the validity of the byte sequence itself.
    // The current Kotlin `evaluateByteLength` directly converts string to UTF-8 bytes.
    // If the string itself contains invalid sequences from a C++ perspective,
    // the Java/Kotlin layer might "fix" it before byte conversion.
    // The C++ test `SharedConstant(u"\xED\xA0\xBC")` passes an invalid byte sequence.
    // We can't directly do that with `constant("string")` in Kotlin.
    // We'd have to construct a Blob from invalid bytes if we wanted to test that.
    // For `byteLength(constant("string"))`, if the string is representable, it will give a length.
    // Let's assume the goal is to test the `byteLength` function with string inputs.
    // A lone surrogate in a Java string is valid at the string level.
    // Its UTF-8 representation is a replacement character.
    // Android expects 1 here (Java encodes an unpaired surrogate as '?'); Dart
    // encodes it as U+FFFD, three bytes. Such a string can not be sent to the
    // backend at all.
    assertEvaluatesTo(
      result,
      encodeValue(3),
      "byteLength(\"\\uD83C\") - lone high surrogate",
    );
  });
  test('byteLength_lowSurrogateOnly', () {
    // Similar to high surrogate, Java's toByteArray(UTF_8) replaces with '?'
    final expr = byteLength(
      constant("\uDF53"),
    ); // Java string with lone low surrogate
    final result = evaluate(expr);
    // Android expects 1 here (Java encodes an unpaired surrogate as '?'); Dart
    // encodes it as U+FFFD, three bytes. Such a string can not be sent to the
    // backend at all.
    assertEvaluatesTo(
      result,
      encodeValue(3),
      "byteLength(\"\\uDF53\") - lone low surrogate",
    );
  });
  test('byteLength_lowAndHighSurrogateSwapped', () {
    // "\uDF53\uD83C" - two replacement characters '??'
    final expr = byteLength(constant("\uDF53\uD83C"));
    final result = evaluate(expr);
    // Android expects 2 here: see the note on the lone high surrogate.
    assertEvaluatesTo(
      result,
      encodeValue(6),
      "byteLength(\"\\uDF53\\uD83C\") - swapped surrogates",
    );
  });
  test('byteLength_ascii', () {
    assertEvaluatesTo(
      evaluate(byteLength(constant("abc"))),
      encodeValue(3),
      "byteLength(\"abc\")",
    );
    assertEvaluatesTo(
      evaluate(byteLength(constant("1234"))),
      encodeValue(4),
      "byteLength(\"1234\")",
    );
    assertEvaluatesTo(
      evaluate(byteLength(constant("abc123!@"))),
      encodeValue(8),
      "byteLength(\"abc123!@\")",
    );
  });
  test('byteLength_largeString', () {
    final largeA = "a".repeat(1500);
    final largeAb = "ab".repeat(1500);

    assertEvaluatesTo(
      evaluate(byteLength(constant(largeA))),
      encodeValue(1500),
      "byteLength(largeA)",
    );
    assertEvaluatesTo(
      evaluate(byteLength(constant(largeAb))),
      encodeValue(3000),
      "byteLength(largeAb)",
    );
  });
  test('byteLength_twoBytesPerCharacter', () {
    // UTF-8: é=2, ç=2, ñ=2, ö=2, ü=2 => 10 bytes
    final str = "éçñöü"; // Each char is 2 bytes in UTF-8
    assertEvaluatesTo(
      evaluate(byteLength(constant(str))),
      encodeValue(10),
      "byteLength(\"éçñöü\")",
    );

    final bytesTwo = Uint8List.fromList(<int>[
      0xc3.toByte(),
      0xa9.toByte(),
      0xc3.toByte(),
      0xa7.toByte(),
      0xc3.toByte(),
      0xb1.toByte(),
      0xc3.toByte(),
      0xb6.toByte(),
      0xc3.toByte(),
      0xbc.toByte(),
    ]);
    assertEvaluatesTo(
      evaluate(byteLength(constant(bytesTwo))),
      encodeValue(10),
      "byteLength(blob for \"éçñöü\")",
    );
  });
  test('byteLength_threeBytesPerCharacter', () {
    // UTF-8: 你=3, 好=3, 世=3, 界=3 => 12 bytes
    final str = "你好世界"; // Each char is 3 bytes in UTF-8
    assertEvaluatesTo(
      evaluate(byteLength(constant(str))),
      encodeValue(12),
      "byteLength(\"你好世界\")",
    );

    final bytesThree = Uint8List.fromList(<int>[
      0xe4.toByte(),
      0xbd.toByte(),
      0xa0.toByte(),
      0xe5.toByte(),
      0xa5.toByte(),
      0xbd.toByte(),
      0xe4.toByte(),
      0xb8.toByte(),
      0x96.toByte(),
      0xe7.toByte(),
      0x95.toByte(),
      0x8c.toByte(),
    ]);
    assertEvaluatesTo(
      evaluate(byteLength(constant(bytesThree))),
      encodeValue(12),
      "byteLength(blob for \"你好世界\")",
    );
  });
  test('byteLength_fourBytesPerCharacter', () {
    // UTF-8: 🀘=4, 🂡=4 => 8 bytes (U+1F018, U+1F0A1)
    final str = "🀘🂡"; // Each char is 4 bytes in UTF-8
    assertEvaluatesTo(
      evaluate(byteLength(constant(str))),
      encodeValue(8),
      "byteLength(\"🀘🂡\")",
    );
    final bytesFour = Uint8List.fromList(<int>[
      0xF0.toByte(),
      0x9F.toByte(),
      0x80.toByte(),
      0x98.toByte(),
      0xF0.toByte(),
      0x9F.toByte(),
      0x82.toByte(),
      0xA1.toByte(),
    ]);
    assertEvaluatesTo(
      evaluate(byteLength(constant(bytesFour))),
      encodeValue(8),
      "byteLength(blob for \"🀘🂡\")",
    );
  });
  test('byteLength_mixOfDifferentEncodedLengths', () {
    // a=1, é=2, 好=3, 🂡=4 => 10 bytes
    final str = "aé好🂡";
    assertEvaluatesTo(
      evaluate(byteLength(constant(str))),
      encodeValue(10),
      "byteLength(\"aé好🂡\")",
    );
    final bytesMix = Uint8List.fromList(<int>[
      0x61.toByte(),
      0xc3.toByte(),
      0xa9.toByte(),
      0xe5.toByte(),
      0xa5.toByte(),
      0xbd.toByte(),
      0xF0.toByte(),
      0x9F.toByte(),
      0x82.toByte(),
      0xA1.toByte(),
    ]);
    assertEvaluatesTo(
      evaluate(byteLength(constant(bytesMix))),
      encodeValue(10),
      "byteLength(blob for \"aé好🂡\")",
    );
  });
}
