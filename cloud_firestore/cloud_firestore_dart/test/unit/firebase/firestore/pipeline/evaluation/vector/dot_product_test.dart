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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/vector/DotProductTests.kt
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
  test('dotProduct - mirroring errors', () {
    for (final (name, left, right) in BINARY_MIRROR_TEST_CASES) {
      final expr = dotProduct(left, right);
      assertEvaluatesToNull(evaluate(expr), "dotProduct($name)");
    }
  });
  test('dotProduct - calculates dot product', () {
    final vector1 = vector([2.0, 1.0].toDoubleArray());
    final vector2 = vector([1.0, 5.0].toDoubleArray());
    final expr = dotProduct(vector1, vector2);
    final result = evaluate(expr);
    assertWithMessage("dotProduct basic").that(result.isSuccess).isTrue();
    assertWithMessage(
      "dotProduct basic value",
    ).that(result.value).isEqualTo(encodeValue(7.0));
  });
  test('dotProduct - orthogonal vectors', () {
    final vector1 = vector([1.0, 0.0].toDoubleArray());
    final vector2 = vector([0.0, 5.0].toDoubleArray());
    final expr = dotProduct(vector1, vector2);
    final result = evaluate(expr);
    assertWithMessage("dotProduct orthogonal").that(result.isSuccess).isTrue();
    assertWithMessage(
      "dotProduct orthogonal value",
    ).that(result.value).isEqualTo(encodeValue(0.0));
  });
  test('dotProduct - zero vector returns zero', () {
    final vector1 = vector([0.0, 0.0].toDoubleArray());
    final vector2 = vector([5.0, 100.0].toDoubleArray());
    final expr = dotProduct(vector1, vector2);
    final result = evaluate(expr);
    assertWithMessage("dotProduct zero vector").that(result.isSuccess).isTrue();
    assertWithMessage(
      "dotProduct zero vector value",
    ).that(result.value).isEqualTo(encodeValue(0.0));
  });
  test('dotProduct - empty vectors returns zero', () {
    final vector1 = vector(<Object?>[].toDoubleArray());
    final vector2 = vector(<Object?>[].toDoubleArray());
    final expr = dotProduct(vector1, vector2);
    final result = evaluate(expr);
    assertWithMessage(
      "dotProduct empty vectors",
    ).that(result.isSuccess).isTrue();
    assertWithMessage(
      "dotProduct empty vectors value",
    ).that(result.value).isEqualTo(encodeValue(0.0));
  });
  test('dotProduct - different vector lengths returns error', () {
    final vector1 = vector([1.0].toDoubleArray());
    final vector2 = vector([2.0, 3.0].toDoubleArray());
    final expr = dotProduct(vector1, vector2);
    assertEvaluatesToError(
      evaluate(expr),
      "dotProduct different vector lengths",
    );
  });
  test('dotProduct - wrong input type returns error', () {
    final vector1 = vector([1.0, 2.0].toDoubleArray());
    final array2 = array(3.0, 4.0);
    final expr = dotProduct(vector1, array2);
    assertEvaluatesToError(evaluate(expr), "dotProduct wrong input type");
  });
}
