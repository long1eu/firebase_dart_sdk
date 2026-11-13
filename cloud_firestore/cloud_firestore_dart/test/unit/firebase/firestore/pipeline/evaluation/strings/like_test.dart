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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/strings/LikeTests.kt
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
  test('like_mirrorError', () {
    for (final (name, left, right) in BINARY_MIRROR_TEST_CASES) {
      final expr = like(left, right);
      assertEvaluatesToNull(evaluate(expr), "like($name)");
    }
  });
  test('like_getNonStringLike_isError', () {
    final expr = like(constant(42), constant("search"));
    assertEvaluatesToError(evaluate(expr), "like(42, \"search\")");
  });
  test('like_getNonStringValue_isError', () {
    final expr = like(constant("ear"), constant(42));
    assertEvaluatesToError(evaluate(expr), "like(\"ear\", 42)");
  });
  test('like_getStaticLike', () {
    final expr = like(constant("yummy food"), constant("%food"));
    assertEvaluatesTo(evaluate(expr), true, "like(\"yummy food\", \"%food\")");
  });
  test('like_getEmptySearchString', () {
    final expr = like(constant(""), constant("%hi%"));
    assertEvaluatesTo(evaluate(expr), false, "like(\"\", \"%hi%\")");
  });
  test('like_getEmptyLike', () {
    final expr = like(constant("yummy food"), constant(""));
    assertEvaluatesTo(evaluate(expr), false, "like(\"yummy food\", \"\")");
  });
  test('like_getEscapedLike', () {
    final expr = like(constant("yummy food??"), constant("%food??"));
    assertEvaluatesTo(
      evaluate(expr),
      true,
      "like(\"yummy food??\", \"%food??\")",
    );
  });
  test('like_badRegex_isError', () {
    final expr = like(constant("yummy food"), constant("%\\"));
    assertEvaluatesToError(evaluate(expr), "like with bad regex");
  });
  test('like_getEscapedLike_withBackslashes', () {
    final expr = like(constant("high-% _food_"), field("pattern"));
    final doc1 = doc("coll/doc1", 0, <String, Object?>{"pattern": "%\\%_\\_%"});
    final doc2 = doc("coll/doc2", 0, <String, Object?>{"pattern": "%\\__\\%%"});
    final doc3 = doc("coll/doc3", 0, <String, Object?>{"pattern": "%\\i%"});
    final doc4 = doc("coll/doc4", 0, <String, Object?>{"pattern": "%\\j%"});

    assertEvaluatesTo(evaluate(expr, doc1), true, "like dynamic escaped doc1");
    assertEvaluatesTo(evaluate(expr, doc2), false, "like dynamic escaped doc2");
    assertEvaluatesTo(evaluate(expr, doc3), true, "like dynamic escaped doc3");
    assertEvaluatesTo(evaluate(expr, doc4), false, "like dynamic escaped doc4");
  });
  test('like_getDynamicLike', () {
    final expr = like(constant("yummy food"), field("regex"));
    final doc1 = doc("coll/doc1", 0, <String, Object?>{"regex": "yummy%"});
    final doc2 = doc("coll/doc2", 0, <String, Object?>{"regex": "food%"});
    final doc3 = doc("coll/doc3", 0, <String, Object?>{"regex": "yummy_food"});

    assertEvaluatesTo(evaluate(expr, doc1), true, "like dynamic doc1");
    assertEvaluatesTo(evaluate(expr, doc2), false, "like dynamic doc2");
    assertEvaluatesTo(evaluate(expr, doc3), true, "like dynamic doc3");
  });
}
