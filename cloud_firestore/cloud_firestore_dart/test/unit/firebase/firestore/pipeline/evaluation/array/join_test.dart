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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/array/JoinTests.kt
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
  // --- Join Tests ---
  test('join_bytes', () {
    final expr = join(
      array(
        constant(ByteString.copyFromUtf8("a").toByteArray()),
        constant(ByteString.copyFromUtf8("b").toByteArray()),
        constant(ByteString.copyFromUtf8("c").toByteArray()),
      ),
      constant(ByteString.copyFromUtf8(",").toByteArray()),
    );
    assertEvaluatesTo(
      evaluate(expr),
      // Android expects bytes here; the Enterprise edition emulator returns a
      // string (the bytes read as UTF-8).
      encodeValue("a,b,c"),
      "join_bytes",
    );
  });
  test('join_strings', () {
    final expr = join(array("a", "b", "c"), constant(","));
    assertEvaluatesTo(evaluate(expr), "a,b,c", "join_strings");
  });
  test('joinWithNulls_bytes', () {
    final expr = join(
      array(
        constant(ByteString.copyFromUtf8("a").toByteArray()),
        nullValue(),
        constant(ByteString.copyFromUtf8("c").toByteArray()),
      ),
      constant(ByteString.copyFromUtf8(",").toByteArray()),
    );
    assertEvaluatesTo(
      evaluate(expr),
      // Android expects bytes here; the Enterprise edition emulator returns a
      // string (the bytes read as UTF-8).
      encodeValue("a,c"),
      "joinWithNulls_bytes",
    );
  });
  test('joinWithNulls_strings', () {
    final expr = join(
      array(nullValue(), constant("a"), nullValue(), constant("c")),
      constant(","),
    );
    assertEvaluatesTo(evaluate(expr), "a,c", "joinWithNulls_strings");
  });
  test('joinEmptyArray_bytes', () {
    final expr = join(
      array(),
      constant(ByteString.copyFromUtf8(",").toByteArray()),
    );
    assertEvaluatesTo(
      evaluate(expr),
      // Android expects bytes here; the Enterprise edition emulator returns a
      // string (the bytes read as UTF-8).
      encodeValue(""),
      "joinEmptyArray_bytes",
    );
  });
  test('joinEmptyArray_strings', () {
    final expr = join(array(), constant(","));
    assertEvaluatesTo(evaluate(expr), "", "joinEmptyArray_strings");
  });
  test('joinWithLeadingNull_strings', () {
    final expr = join(
      array(nullValue(), constant("a"), constant("c")),
      constant(","),
    );
    assertEvaluatesTo(evaluate(expr), "a,c", "joinWithLeadingNull_strings");
  });
  test('joinWithLeadingNull_bytes', () {
    final expr = join(
      array(
        nullValue(),
        constant(ByteString.copyFromUtf8("a").toByteArray()),
        constant(ByteString.copyFromUtf8("c").toByteArray()),
      ),
      constant(ByteString.copyFromUtf8(",").toByteArray()),
    );
    assertEvaluatesTo(
      evaluate(expr),
      // Android expects bytes here; the Enterprise edition emulator returns a
      // string (the bytes read as UTF-8).
      encodeValue("a,c"),
      "joinWithLeadingNull_bytes",
    );
  });
  test('joinSingleElement_strings', () {
    final expr = join(array("a"), constant(","));
    assertEvaluatesTo(evaluate(expr), "a", "joinSingleElement_strings");
  });
  test('joinSingleElement_bytes', () {
    final expr = join(
      array(constant(ByteString.copyFromUtf8("a").toByteArray())),
      constant(ByteString.copyFromUtf8(",").toByteArray()),
    );
    assertEvaluatesTo(
      evaluate(expr),
      // Android expects bytes here; the Enterprise edition emulator returns a
      // string (the bytes read as UTF-8).
      encodeValue("a"),
      "joinSingleElement_bytes",
    );
  });
  test('joinWithEmptyDelimiter_strings', () {
    final expr = join(array("a", "b", "c"), constant(""));
    assertEvaluatesTo(evaluate(expr), "abc", "joinWithEmptyDelimiter_strings");
  });
  test('joinWithEmptyDelimiter_bytes', () {
    final expr = join(
      array(
        constant(ByteString.copyFromUtf8("a").toByteArray()),
        constant(ByteString.copyFromUtf8("b").toByteArray()),
        constant(ByteString.copyFromUtf8("c").toByteArray()),
      ),
      constant(ByteString.EMPTY.toByteArray()),
    );
    assertEvaluatesTo(
      evaluate(expr),
      // Android expects bytes here; the Enterprise edition emulator returns a
      // string (the bytes read as UTF-8).
      encodeValue("abc"),
      "joinWithEmptyDelimiter_bytes",
    );
  });
  test('joinAllNulls_strings', () {
    final expr = join(array(nullValue(), nullValue()), constant(","));
    assertEvaluatesTo(evaluate(expr), "", "joinAllNulls_strings");
  });
  test('joinAllNulls_bytes', () {
    final expr = join(
      array(nullValue(), nullValue()),
      constant(ByteString.copyFromUtf8(",").toByteArray()),
    );
    assertEvaluatesTo(
      evaluate(expr),
      // Android expects bytes here; the Enterprise edition emulator returns a
      // string (the bytes read as UTF-8).
      encodeValue(""),
      "joinAllNulls_bytes",
    );
  });
  test('joinSingleNull_strings', () {
    final expr = join(array(nullValue()), constant(","));
    assertEvaluatesTo(evaluate(expr), "", "joinSingleNull_strings");
  });
  test('joinSingleNull_bytes', () {
    final expr = join(
      array(nullValue()),
      constant(ByteString.copyFromUtf8(",").toByteArray()),
    );
    assertEvaluatesTo(
      evaluate(expr),
      // Android expects bytes here; the Enterprise edition emulator returns a
      // string (the bytes read as UTF-8).
      encodeValue(""),
      "joinSingleNull_bytes",
    );
  });
  test('joinWithNonStringValue_strings', () {
    final expr = join(array(1, "b"), constant(","));
    assertEvaluatesToError(evaluate(expr), "Cannot join non-string types");
  });
  test('joinWithNonBytesValue_bytes', () {
    final expr = join(
      array(constant(1), constant(ByteString.copyFromUtf8("b").toByteArray())),
      constant(ByteString.copyFromUtf8(",").toByteArray()),
    );
    assertEvaluatesToError(evaluate(expr), "Cannot join non-string types");
  });
  test('join_numberArray_returnsError', () {
    final expr = join(array(1, 2), constant(","));
    assertEvaluatesToError(evaluate(expr), "Cannot join non-string types");
  });
  test('join_bytesArray_stringDelimiter_returnsError', () {
    final expr = join(
      array(
        constant(ByteString.copyFromUtf8("a").toByteArray()),
        constant(ByteString.copyFromUtf8("b").toByteArray()),
      ),
      constant(","),
    );
    assertEvaluatesToError(evaluate(expr), "Cannot join non-string types");
  });
  test('invalidDelimiterType_returnsError', () {
    final expr = join(array("a", "b"), constant(1));
    assertEvaluatesToError(
      evaluate(expr),
      "The function join(...) requires `String` but got `LONG`",
    );
  });
  test('nullArrayReturnsNull', () {
    final expr = join(nullValue(), constant(","));
    assertEvaluatesToNull(evaluate(expr), "nullArrayReturnsNull");
  });
  test('nullDelimiterReturnsNull', () {
    final expr = join(array("a", "b"), nullValue());
    assertEvaluatesToNull(evaluate(expr), "nullDelimiterReturnsNull");
  });
  test('mixedTypesStringArrayBytesDelimiterReturnsError', () {
    final expr = join(
      array("a", null, "c"),
      constant(ByteString.copyFromUtf8(",").toByteArray()),
    );
    assertEvaluatesToError(evaluate(expr), "Cannot join non-string types");
  });
  test('mixedTypesBytesArrayStringDelimiterReturnsError', () {
    final expr = join(
      array(
        constant(ByteString.copyFromUtf8("a").toByteArray()),
        constant(ByteString.copyFromUtf8("b").toByteArray()),
      ),
      constant(","),
    );
    assertEvaluatesToError(evaluate(expr), "Cannot join non-string types");
  });
  test('invalidArrayElementType_returnsError', () {
    final expr = join(
      array(constant(ByteString.copyFromUtf8("a").toByteArray())),
      constant(","),
    );
    assertEvaluatesToError(evaluate(expr), "Cannot join non-string types");
  });
  test('nullDelimiterReturnsNull_invalidArrayElementType', () {
    final expr = join(
      array(constant(ByteString.copyFromUtf8("a").toByteArray())),
      nullValue(),
    );
    assertEvaluatesToNull(
      evaluate(expr),
      "nullDelimiterReturnsNull_invalidArrayElementType",
    );
  });
  test('errorHasPrecedenceOverNull_invalidDelimiter', () {
    final expr = join(nullValue(), constant(1));
    assertEvaluatesToError(
      evaluate(expr),
      "The function join(...) requires `String` but got `LONG`",
    );
  });
  test('errorHasPrecedenceOverNull_invalidArrayElement', () {
    final expr = join(array("a", 1), nullValue());
    assertEvaluatesToNull(
      evaluate(expr),
      "errorHasPrecedenceOverNull_invalidArrayElement",
    );
  });
  test('errorHasPrecedenceOverNull_mixedArrayElementTypes', () {
    final expr = join(
      array("a", constant(ByteString.copyFromUtf8("b").toByteArray())),
      nullValue(),
    );
    assertEvaluatesToNull(
      evaluate(expr),
      "errorHasPrecedenceOverNull_mixedArrayElementTypes",
    );
  });
}
