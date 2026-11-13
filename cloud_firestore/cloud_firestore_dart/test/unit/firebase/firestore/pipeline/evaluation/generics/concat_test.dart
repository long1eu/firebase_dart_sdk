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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/generics/ConcatTests.kt
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
  test('concat_mirrors_error', () {
    for (final (name, left, right) in BINARY_MIRROR_TEST_CASES) {
      final expr = concat(left, right);
      assertEvaluatesToNull(evaluate(expr), "concat($name)");
    }
  });
  test('stringConcat_withMultipleStrings', () {
    final expr = concat(constant("hello"), constant(" "), constant("world"));
    assertEvaluatesTo(
      evaluate(expr),
      "hello world",
      "stringConcat_withMultipleStrings",
    );
  });
  test('stringConcat_withEmptyString', () {
    final expr = concat(constant("hello"), constant(""), constant("world"));
    assertEvaluatesTo(
      evaluate(expr),
      "helloworld",
      "stringConcat_withEmptyString",
    );
  });
  test('string_null_string_isNull', () {
    final expr = concat(constant("hello"), nullValue(), constant("world"));
    assertEvaluatesToNull(evaluate(expr), "string_null_string_isNull");
  });
  test('string_unset_string_isNull', () {
    final expr = concat(
      constant("hello"),
      field("non-existent"),
      constant("world"),
    );
    assertEvaluatesToNull(evaluate(expr), "string_unset_string_isNull");
  });
  test('bytesConcat_withMultipleByteStrings', () {
    final expr = concat(
      constant(ByteString.copyFromUtf8("hello").toByteArray()),
      constant(ByteString.copyFromUtf8(" ").toByteArray()),
      constant(ByteString.copyFromUtf8("world").toByteArray()),
    );
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(ByteString.copyFromUtf8("hello world").toByteArray()),
      "bytesConcat_withMultipleByteStrings",
    );
  });
  test('bytesConcat_withEmptyByteString', () {
    final expr = concat(
      constant(ByteString.copyFromUtf8("hello").toByteArray()),
      constant(ByteString.EMPTY.toByteArray()),
      constant(ByteString.copyFromUtf8("world").toByteArray()),
    );
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(ByteString.copyFromUtf8("helloworld").toByteArray()),
      "bytesConcat_withEmptyByteString",
    );
  });
  test('bytesConcat_withNull', () {
    final expr = concat(
      constant(ByteString.copyFromUtf8("hello").toByteArray()),
      nullValue(),
      constant(ByteString.copyFromUtf8("world").toByteArray()),
    );
    assertEvaluatesToNull(evaluate(expr), "bytesConcat_withNull");
  });
  test('mixedTypes_stringAndBytes_throwsError', () {
    final expr = concat(
      constant("hello"),
      constant(ByteString.copyFromUtf8("world").toByteArray()),
    );
    assertEvaluatesToError(
      evaluate(expr),
      "mixedTypes_stringAndBytes_throwsError",
    );
  });
  test('mixedTypes_stringAndLong_throwsError', () {
    final expr = concat(constant("hello"), constant(123));
    assertEvaluatesToError(
      evaluate(expr),
      "mixedTypes_stringAndLong_throwsError",
    );
  });
  test('mixedTypes_bytesAndLong_throwsError', () {
    final expr = concat(
      constant(ByteString.copyFromUtf8("hello").toByteArray()),
      constant(123),
    );
    assertEvaluatesToError(
      evaluate(expr),
      "mixedTypes_bytesAndLong_throwsError",
    );
  });
  test('arrayConcat_withMultipleArrays', () {
    final expr = concat(array(1, 2), array(3, 4), array(5, 6));
    final expected = encodeValue(
      [1, 2, 3, 4, 5, 6].map((it) => encodeValue(it)).toList(),
    );
    assertEvaluatesTo(
      evaluate(expr),
      expected,
      "arrayConcat_withMultipleArrays",
    );
  });
  test('arrayConcat_withMixedTypesInArrays', () {
    final expr = concat(array(1, 2), array("three", "four"));
    final expected = encodeValue([
      encodeValue(1),
      encodeValue(2),
      encodeValue("three"),
      encodeValue("four"),
    ]);
    assertEvaluatesTo(
      evaluate(expr),
      expected,
      "arrayConcat_withMixedTypesInArrays",
    );
  });
  test('arrayConcat_withEmptyArray', () {
    final expr = concat(array(1, 2), array());
    final expected = encodeValue([1, 2].map((it) => encodeValue(it)).toList());
    assertEvaluatesTo(evaluate(expr), expected, "arrayConcat_withEmptyArray");
  });
  test('arrayConcat_withNull', () {
    final expr = concat(array(1, 2), nullValue(), array(3, 4));
    assertEvaluatesToNull(evaluate(expr), "arrayConcat_withNull");
  });
  test('mixedTypes_arrayAndString_throwsError', () {
    final expr = concat(array(1, 2), constant("hello"));
    assertEvaluatesToError(
      evaluate(expr),
      "mixedTypes_arrayAndString_throwsError",
    );
  });
  test('mixedTypes_arrayAndBytes_throwsError', () {
    final expr = concat(
      array(1, 2),
      constant(ByteString.copyFromUtf8("world").toByteArray()),
    );
    assertEvaluatesToError(
      evaluate(expr),
      "mixedTypes_arrayAndBytes_throwsError",
    );
  });
  test('mixedTypes_arrayAndLong_throwsError', () {
    final expr = concat(array(1, 2), constant(123));
    assertEvaluatesToError(
      evaluate(expr),
      "mixedTypes_arrayAndLong_throwsError",
    );
  });
  test('mixedTypes_stringAndArray_throwsError', () {
    final expr = concat(constant("foo"), array(2));
    assertEvaluatesToError(
      evaluate(expr),
      "mixedTypes_stringAndArray_throwsError",
    );
  });
  test('mixedTypes_unsupportedAndNull_throwsError', () {
    final expr = concat(constant("foo"), constant(2), constant(1), nullValue());
    assertEvaluatesToError(
      evaluate(expr),
      "mixedTypes_unsupportedAndNull_throwsError",
    );
  });
  test('mixedTypes_stringAndArrayWithNull_throwsError', () {
    final expr = concat(constant("foo"), nullValue(), array(2));
    assertEvaluatesToError(
      evaluate(expr),
      "mixedTypes_stringAndArrayWithNull_throwsError",
    );
  });
}
