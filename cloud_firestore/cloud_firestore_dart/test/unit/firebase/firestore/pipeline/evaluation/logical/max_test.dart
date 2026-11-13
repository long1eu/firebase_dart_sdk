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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/logical/MaxTests.kt
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

// The cases of this file use doubles with integral values (1.0, -0.0,
// Double.MAX_VALUE) or 64-bit integers. Compiled to JavaScript (dart2js) an
// integral double is an int and an int beyond 2^53 is not exact, so they run
// on the VM only. web_numbers_test.dart covers evaluation compiled to
// JavaScript.
@TestOn('vm')
library;

import 'package:test/test.dart' show TestOn, test;

import '../evaluation_test_util.dart';

void main() {
  final errorExpr1 = error("error-1");
  final errorExpr2 = error("error-2");
  final emptyDoc = doc("coll/docEmpty", 1, <String, Object?>{});

  final generalCases = [
    // Testing the relative priority of different types, following TypeComparator.
    // Boolean(2) < Number(3) < String(6) < Array(14) < Map(16). Null/Unset always have the
    // lowest priority.
    ([constant(true), nullValue()], constant(true)),
    ([nullValue(), constant(true)], constant(true)), // for UNSET
    ([constant(0), constant(false)], constant(0)),
    ([constant(0.0), constant(true)], constant(0.0)),
    ([constant(""), constant(0)], constant("")),
    ([constant(0.0), constant("foo")], constant("foo")),
    ([array(2, 3), constant("foo")], array(2, 3)),
    ([map(<String, Object?>{}), array(<Object?>[])], map(<String, Object?>{})),
    ([array(<Object?>[]), map(<String, Object?>{})], map(<String, Object?>{})),

    // Testing numeric comparisons are equal across types.
    ([constant(1.0), constant(2)], constant(2)),
    ([constant(1.1), constant(1)], constant(1.1)),
    ([constant(-20), constant(4.24)], constant(4.24)),
    ([constant(1), constant(2.0), constant(3)], constant(3)),
    ([constant(2.5), constant(2.6)], constant(2.6)), // Decimal128
    ([constant(double.negativeInfinity), constant(minLong)], constant(minLong)),
    ([constant(double.infinity), constant(maxLong)], constant(double.infinity)),

    // Testing comparisons within the same type.
    ([constant(true), constant(false)], constant(true)),
    ([constant(1), constant(0)], constant(1)),
    ([constant(1), constant(2), constant(3)], constant(3)),
    ([constant(-0.4), constant(0.0)], constant(0.0)),
    ([constant("b"), constant("a")], constant("b")),
    ([constant("b"), constant("aaaa")], constant("b")),
    ([nullValue(), nullValue()], nullValue()),
    ([nullValue(), nullValue()], nullValue()), // for UNSET
    // List comparison is based on the comparison of the first elements, or size as a
    // tie-breaker.
    ([array(2), array(1)], array(2)),
    ([array(2), array(1, 1, 2, 3, 4)], array(2)),
    ([array(2, 3), array(2, 2)], array(2, 3)),
    ([array(2), array(2, -10)], array(2, -10)),

    // Map comparison is based on the comparison of the smallest keys and their values, or
    // size as a tie-breaker.
    (
      [
        map(<String, Object?>{"b": 1}),
        map(<String, Object?>{"a": 10}),
      ],
      map(<String, Object?>{"b": 1}),
    ),
    (
      [
        map(<String, Object?>{"b": 1}),
        map(<String, Object?>{"b": 0}),
      ],
      map(<String, Object?>{"b": 1}),
    ),
    (
      [
        map(<String, Object?>{"b": 1, "c": 2}),
        map(<String, Object?>{"a": 3, "b": 5}),
      ],
      map(<String, Object?>{"b": 1, "c": 2}),
    ),
    (
      [
        map(<String, Object?>{"b": 1, "a": 1}),
        map(<String, Object?>{"a": 3, "b": 0}),
      ],
      map(<String, Object?>{"a": 3, "b": 0}),
    ),
    (
      [
        map(<String, Object?>{"b": 1, "a": 2}),
        map(<String, Object?>{"b": 1}),
      ],
      map(<String, Object?>{"b": 1}),
    ),
    (
      [
        map(<String, Object?>{"b": 1, "c": 2}),
        map(<String, Object?>{"b": 1}),
      ],
      map(<String, Object?>{"b": 1, "c": 2}),
    ),

    // Testing across different value types
    (
      [
        array(2, 3),
        constant(2),
        map(<String, Object?>{"2": 2, "3": 3}),
      ],
      map(<String, Object?>{"2": 2, "3": 3}),
    ),
    ([constant("a"), constant("b"), constant("c")], constant("c")),
    ([constant(1), constant("1"), constant(0)], constant("1")),
    ([constant(double.nan), constant(0)], constant(0)),
    ([constant(double.nan), constant(1)], constant(1)),
    ([nullValue(), constant(1)], constant(1)),
    ([nullValue(), constant(1)], constant(1)), // for UNSET
    ([nullValue(), constant(12)], constant(12)),
    ([nullValue(), constant(12)], constant(12)), // for UNSET
  ];

  final equalCases = [
    (constant(1.0), constant(1)),
    (constant(1), constant(1.0)),
    (constant(1), constant(1.0)),
    (constant(-0.0), constant(0.0)),
    (constant(0), constant(-0.0)),
    (constant(1), constant(1.0)), // Decimal128.fromString("1.0")
    (constant(-1), constant(-1)),
    (constant(double.nan), constant(double.nan)), // Decimal128.NAN
    (
      constant(double.negativeInfinity),
      constant(double.negativeInfinity),
    ), // Decimal128.NEGATIVE_INFINITY
    (
      constant(double.infinity),
      constant(double.infinity),
    ), // Decimal128.POSITIVE_INFINITY
    (constant(-0.0), constant(-0.0)), // Decimal128.NEGATIVE_ZERO
    (constant(0.0), constant(0.0)), // Decimal128.POSITIVE_ZERO
    (array(2), array(2.0)),
    (map(<String, Object?>{"a": 2}), map(<String, Object?>{"a": 2.0})),
  ];
  test('max with general values', () {
    for (final (inputs, expected) in generalCases) {
      final expr = logicalMaximumAll(inputs as List<Object?>);
      assertEvaluatesTo(
        evaluate(expr, emptyDoc),
        evaluate(expected, emptyDoc),
        "Max(${inputs.join(', ')}) should be $expected",
      );
    }
  });
  test('max on equal values returns first input', () {
    for (final (left, right) in equalCases) {
      assertEvaluatesTo(
        evaluate(logicalMaximum(left, right), emptyDoc),
        evaluate(left, emptyDoc),
        "Max($left, $right) should be $left",
      );
      assertEvaluatesTo(
        evaluate(logicalMaximum(right, left), emptyDoc),
        evaluate(right, emptyDoc),
        "Max($right, $left) should be $right",
      );
    }
  });
  test('one argument evaluates to error', () {
    final result = evaluate(logicalMaximum(constant(1)), emptyDoc);
    assertEvaluatesToError(result, "1");
  });
  test('error value isError', () {
    final result = evaluate(logicalMaximum(errorExpr1, constant(1)), emptyDoc);
    assertEvaluatesToError(result, "error-1");
  });
  test('value error isError', () {
    final result = evaluate(logicalMaximum(constant(1), errorExpr2), emptyDoc);
    assertEvaluatesToError(result, "error-2");
  });
  test('error error isError', () {
    final result = evaluate(logicalMaximum(errorExpr1, errorExpr2), emptyDoc);
    assertEvaluatesToError(result, "error-1");
  });
}

typedef VariadicValueTestCase = (dynamic, dynamic);

extension VariadicValueTestCaseFields on VariadicValueTestCase {
  dynamic get inputs => $1;
  dynamic get expected => $2;
}

typedef EqualValues = (dynamic, dynamic);

extension EqualValuesFields on EqualValues {
  dynamic get left => $1;
  dynamic get right => $2;
}
