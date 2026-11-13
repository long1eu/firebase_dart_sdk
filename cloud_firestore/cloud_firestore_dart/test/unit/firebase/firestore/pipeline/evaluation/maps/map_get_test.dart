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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/maps/MapGetTests.kt
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
  test('mapGet_dotInKey_returnsUnset', () {
    final mapExpr = map(<String, Object?>{
      "a": <String, Object?>{"b": 1},
    });
    final expr = mapGet(mapExpr, "a.b");
    assertEvaluatesToUnset(
      evaluate(expr),
      "mapGet with dot in key should return unset",
    );
  });
  test('mapGet_nestedMap_returnsMap', () {
    final mapExpr = map(<String, Object?>{
      "a": <String, Object?>{"b": 1},
    });
    final expr = mapGet(mapExpr, "a");
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(<String, Object?>{"b": encodeValue(1)}),
      "mapGet with nested map should return map",
    );
  });
  test('mapGet - get existing key returns value', () {
    final mapExpr = map(<String, Object?>{"a": 1, "b": 2, "c": 3});
    final expr = mapGet(mapExpr, constant("b"));
    assertEvaluatesTo(
      evaluate(expr),
      encodeValue(2),
      "mapGet existing key should return value",
    );
  });
  test('mapGet - get missing key returns unset', () {
    final mapExpr = map(<String, Object?>{"a": 1, "b": 2, "c": 3});
    final expr = mapGet(mapExpr, "d");
    assertEvaluatesToUnset(
      evaluate(expr),
      "mapGet missing key should return unset",
    );
  });
  test('mapGet - get from empty map returns unset', () {
    final mapExpr = map(<String, Object?>{});
    final expr = mapGet(mapExpr, "d");
    assertEvaluatesToUnset(
      evaluate(expr),
      "mapGet from empty map should return unset",
    );
  });
  test('mapGet_nonMapValue_returnsUnset', () {
    final invalidMaps = [
      nullValue(),
      field("non-existent"),
      constant("foo"),
      array(),
      array(1, 2),
      array(<String, Object?>{"foo": 1}),
      constant(15),
      constant(2),
      constant(2.0),
    ];
    // Android expects UNSET for all of these here; the Enterprise edition emulator returns null for a null or missing map and an error for a value of another type.
    for (final (index, mapExpr) in invalidMaps.indexed) {
      final expr = mapGet(mapExpr, "d");
      if (index < 2) {
        assertEvaluatesToNull(evaluate(expr), "mapGet of $mapExpr");
      } else {
        assertEvaluatesToError(evaluate(expr), "mapGet of $mapExpr");
      }
    }
  });
  test('mapGet_unsetKey_returnsError', () {
    final mapExpr = map(<String, Object?>{"a": 1});
    final expr = mapGet(mapExpr, field("non-existent"));
    // Android expects an error for a missing key argument here; the Enterprise edition emulator returns null.
    assertEvaluatesToNull(evaluate(expr), "mapGet with unset key");
  });
  test('mapGet_nullKey_returnsError', () {
    final mapExpr = map(<String, Object?>{"a": 1});
    final expr = mapGet(mapExpr, nullValue());
    // Android expects an error for a null key argument here; the Enterprise edition emulator returns null.
    assertEvaluatesToNull(evaluate(expr), "mapGet with null key");
  });
  test('mapGet - wrong key type returns error', () {
    final mapExpr = map(<String, Object?>{});
    final expr = mapGet(mapExpr, constant(false));
    // This should evaluate to an error because the key argument is not a string.
    assertEvaluatesToError(
      evaluate(expr),
      "mapGet with wrong key type should return error",
    );
  });
}
