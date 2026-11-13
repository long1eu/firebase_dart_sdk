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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/logical/EqAnyTests.kt
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
  final nullExpr = nullValue();
  final nanExpr = constant(double.nan);
  final emptyDoc = doc("coll/docEmpty", 1, <String, Object?>{});

  // --- EqAny Tests ---
  test('eqAny - value found in array', () {
    final expr = equalAny(
      constant("hello"),
      array(constant("hello"), constant("world")),
    );
    assertEvaluatesTo(
      evaluate(expr, emptyDoc),
      true,
      "eqAny(hello, [hello, world])",
    );
  });
  test('eqAny - value not found in array', () {
    final expr = equalAny(
      constant(4),
      array(constant(42), constant("matang"), constant(true)),
    );
    assertEvaluatesTo(
      evaluate(expr, emptyDoc),
      false,
      "eqAny(4, [42, matang, true])",
    );
  });
  test('notEqAny - value not found in array', () {
    final expr = notEqualAny(
      constant(4),
      array(constant(42), constant("matang"), constant(true)),
    );
    assertEvaluatesTo(
      evaluate(expr, emptyDoc),
      true,
      "notEqAny(4, [42, matang, true])",
    );
  });
  test('notEqAny - value found in array', () {
    final expr = notEqualAny(
      constant("hello"),
      array(constant("hello"), constant("world")),
    );
    assertEvaluatesTo(
      evaluate(expr, emptyDoc),
      false,
      "notEqAny(hello, [hello, world])",
    );
  });
  test('eqAny - equivalent numerics', () {
    assertEvaluatesTo(
      evaluate(
        equalAny(
          constant(42),
          array(constant(42.0), constant("matang"), constant(true)),
        ),
        emptyDoc,
      ),
      true,
      "eqAny(42, [42.0,...])",
    );
    assertEvaluatesTo(
      evaluate(
        equalAny(
          constant(42.0),
          array(constant(42), constant("matang"), constant(true)),
        ),
        emptyDoc,
      ),
      true,
      "eqAny(42.0, [42,...])",
    );
  });
  test('eqAny - both input type is array', () {
    final searchArray = array(constant(1), constant(2), constant(3));
    final valuesArray = array(
      array(constant(1), constant(2), constant(3)),
      array(constant(4), constant(5), constant(6)),
    );
    assertEvaluatesTo(
      evaluate(equalAny(searchArray, valuesArray), emptyDoc),
      true,
      "eqAny([1,2,3], [[1,2,3],...])",
    );
  });
  test('eqAny - array not found returns null', () {
    final expr = equalAny(constant("matang"), field("non-existent-field"));
    assertEvaluatesToNull(
      evaluate(expr, emptyDoc),
      "eqAny(matang, non-existent-field)",
    );
  });
  test('eqAny - array is empty returns false', () {
    final expr = equalAny(constant(42), array());
    assertEvaluatesTo(evaluate(expr, emptyDoc), false, "eqAny(42, [])");
  });
  test('eqAny - search reference not found returns false', () {
    final expr = equalAny(field("non-existent-field"), array(constant(42)));
    assertEvaluatesTo(
      evaluate(expr, emptyDoc),
      false,
      "eqAny(non-existent-field, [42])",
    );
  });
  test('eqAny - search is null', () {
    final expr = equalAny(
      nullExpr,
      array(nullExpr, constant(1), constant("matang")),
    );
    assertEvaluatesTo(
      evaluate(expr, emptyDoc),
      true,
      "eqAny(null, [null,1,matang])",
    );
  });
  test('eqAny - search is null empty values array returns false', () {
    final expr = equalAny(nullExpr, array());
    assertEvaluatesTo(evaluate(expr, emptyDoc), false, "eqAny(null, [])");
  });
  test('eqAny - search is nan', () {
    final expr = equalAny(
      nanExpr,
      array(nanExpr, constant(42), constant(3.14)),
    );
    assertEvaluatesTo(
      evaluate(expr, emptyDoc),
      true,
      "eqAny(NaN, [NaN,42,3.14])",
    );
  });
  test('eqAny - search is empty array is empty', () {
    final expr = equalAny(array(), array());
    assertEvaluatesTo(evaluate(expr, emptyDoc), false, "eqAny([], [])");
  });
  test('eqAny - search is empty array contains empty array returns true', () {
    final expr = equalAny(array(), array(array()));
    assertEvaluatesTo(evaluate(expr, emptyDoc), true, "eqAny([], [[]])");
  });
  test('eqAny - value found in array with null', () {
    final expr = equalAny(
      constant("hello"),
      array(nullValue(), constant("hello")),
    );
    assertEvaluatesTo(
      evaluate(expr, emptyDoc),
      true,
      "eqAny(hello, [null, hello])",
    );
  });
  test('eqAny - value not found in array with null', () {
    final expr = equalAny(constant(4), array(nullValue(), constant(42)));
    assertEvaluatesTo(evaluate(expr, emptyDoc), false, "eqAny(4, [null, 42])");
  });
  test('eqAny - value not found in array with only nulls', () {
    final expr = equalAny(constant(4), array(nullValue(), nullValue()));
    assertEvaluatesTo(
      evaluate(expr, emptyDoc),
      false,
      "eqAny(4, [null, null])",
    );
  });
  test('eqAny - search is null in single null array', () {
    final expr = equalAny(nullValue(), array(nullValue()));
    assertEvaluatesTo(evaluate(expr, emptyDoc), true, "eqAny(null, [null])");
  });
  test('eqAny - search is null in array with other values', () {
    final expr = equalAny(nullValue(), array(nullValue(), constant(42)));
    assertEvaluatesTo(
      evaluate(expr, emptyDoc),
      true,
      "eqAny(null, [null, 42])",
    );
  });
  test(
    'eqAny - search is array with null in array with null and array with null',
    () {
      final searchArray = array(nullValue());
      final valuesArray = array(nullValue(), array(nullValue()));
      assertEvaluatesTo(
        evaluate(equalAny(searchArray, valuesArray), emptyDoc),
        true,
        "eqAny([null], [null, [null]])",
      );
    },
  );
  test(
    'eqAny - search is array with null in array with other and array with null',
    () {
      final searchArray = array(nullValue());
      final valuesArray = array(constant(42), array(nullValue()));
      assertEvaluatesTo(
        evaluate(equalAny(searchArray, valuesArray), emptyDoc),
        true,
        "eqAny([null], [42, [null]])",
      );
    },
  );
  test('eqAny - search is empty map in empty array', () {
    final expr = equalAny(map(<String, Object?>{}), array());
    assertEvaluatesTo(evaluate(expr, emptyDoc), false, "eqAny({}, [])");
  });
  test('eqAny - search is empty map in array with empty map', () {
    final expr = equalAny(
      map(<String, Object?>{}),
      array(map(<String, Object?>{})),
    );
    assertEvaluatesTo(evaluate(expr, emptyDoc), true, "eqAny({}, [{}])");
  });
  test('eqAny - search is map with null', () {
    final searchMap = map(<String, Object?>{"a": nullValue()});
    final valuesArray = array(
      nullValue(),
      map(<String, Object?>{"a": nullValue()}),
    );
    assertEvaluatesTo(
      evaluate(equalAny(searchMap, valuesArray), emptyDoc),
      true,
      "eqAny({a:null}, [null, {a:null}])",
    );
  });
  test(
    'eqAny - search is map with null in array with other and map with null',
    () {
      final searchMap = map(<String, Object?>{"a": nullValue()});
      final valuesArray = array(
        constant(42),
        map(<String, Object?>{"a": nullValue()}),
      );
      assertEvaluatesTo(
        evaluate(equalAny(searchMap, valuesArray), emptyDoc),
        true,
        "eqAny({a:null}, [42, {a:null}])",
      );
    },
  );
  test('eqAny - array is not array type returns error', () {
    final expr = equalAny(constant("matang"), constant("values"));
    assertEvaluatesToError(
      evaluate(expr, emptyDoc),
      "The function eq_any(...) requires `Array` but got `STRING`",
    );
  });
  test('eqAny - search is map', () {
    final searchMap = map(<String, Object?>{"foo": constant(42)});
    final valuesArray = array(
      array(constant(123)),
      map(<String, Object?>{"bar": constant(42)}),
      map(<String, Object?>{"foo": constant(42)}),
    );
    assertEvaluatesTo(
      evaluate(equalAny(searchMap, valuesArray), emptyDoc),
      true,
      "eqAny(map, [...,map])",
    );
  });
}
