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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/evaluation/comparison/ComparisonTestData.kt
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

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart'
    show GeoPoint, Timestamp;
import 'package:cloud_firestore_dart/pipelines.dart' show Expression;

import '../evaluation_test_util.dart';

// Test data ported from Hyperstore's ComparisonFunctionTestCases.java to ensure alignment.
// ComparisonTestData
const int MAX_DOUBLE_SAFE_INTEGER = 9007199254740992; // 2^53
const int MIN_DOUBLE_SAFE_INTEGER = -9007199254740992; // -2^53

final doubleNaN = constant(double.nan);

final unsetValue = field("nonexistent");

// /** Test cases for values that should be considered equal. */
final equivalentValues = [
  (
    // Int / Long
    constant(1), constant(1),
  ),
  (constant(-1), constant(-1)),
  (constant(0), constant(0)),
  (constant(maxInt.toInt()), constant(maxInt)),
  (constant(minInt.toInt()), constant(minInt)),
  (constant(-1), constant(-1)),

  (
    // Int / Double
    constant(1), constant(1.0),
  ),
  (constant(0), constant(0.0)),
  (constant(0), constant(-0.0)),
  (constant(-1), constant(-1.0)),
  (constant(maxInt), constant(maxInt.toDouble())),
  (constant(minInt), constant(minInt.toDouble())),

  (
    // Long / Double
    constant(1), constant(1.0),
  ),
  (constant(0), constant(0.0)),
  (constant(0), constant(-0.0)),
  (constant(-1), constant(-1.0)),
  (
    constant(MAX_DOUBLE_SAFE_INTEGER),
    constant(MAX_DOUBLE_SAFE_INTEGER.toDouble()),
  ),
  (
    constant(MIN_DOUBLE_SAFE_INTEGER),
    constant(MIN_DOUBLE_SAFE_INTEGER.toDouble()),
  ),
  (constant(0), constant(-0.0)),
  (constant(-0.0), constant(0.0)),

  (
    // NaN
    doubleNaN, doubleNaN,
  ),

  (
    // NaN in lists
    array(doubleNaN), array(doubleNaN),
  ),
  (array(doubleNaN, doubleNaN), array(doubleNaN, doubleNaN)),
  (array(doubleNaN, constant(1)), array(doubleNaN, constant(1))),
  (array(constant(1), doubleNaN), array(constant(1), doubleNaN)),
  (array(doubleNaN, nullValue()), array(doubleNaN, nullValue())),
  (array(nullValue(), doubleNaN), array(nullValue(), doubleNaN)),

  (
    // NaN in maps
    map(<String, Object?>{"a": nullValue(), "b": doubleNaN}),
    map(<String, Object?>{"a": nullValue(), "b": doubleNaN}),
  ),
  (
    map(<String, Object?>{"a": doubleNaN, "b": nullValue()}),
    map(<String, Object?>{"a": doubleNaN, "b": nullValue()}),
  ),

  (
    // Null
    nullValue(), nullValue(),
  ),
  (unsetValue, unsetValue),

  (
    // Null in Lists
    array(nullValue()), array(nullValue()),
  ),
  (array(nullValue(), nullValue()), array(nullValue(), nullValue())),
  (array(nullValue(), constant(1)), array(nullValue(), constant(1))),
  (array(constant(1), nullValue()), array(constant(1), nullValue())),

  (
    // Null in maps
    map(<String, Object?>{"a": nullValue()}),
    map(<String, Object?>{"a": nullValue()}),
  ),
  (
    map(<String, Object?>{"a": nullValue(), "b": nullValue()}),
    map(<String, Object?>{"a": nullValue(), "b": nullValue()}),
  ),
  (
    map(<String, Object?>{"a": constant(1), "b": nullValue()}),
    map(<String, Object?>{"a": constant(1), "b": nullValue()}),
  ),
  (
    map(<String, Object?>{"a": nullValue(), "b": constant(1)}),
    map(<String, Object?>{"a": nullValue(), "b": constant(1)}),
  ),

  (
    // Empty / simple collections
    array(), array(),
  ),
  (array(constant(1), constant(2)), array(constant(1), constant(2))),
  (map(<String, Object?>{}), map(<String, Object?>{})),
  (
    map(<String, Object?>{"a": constant(1)}),
    map(<String, Object?>{"a": constant(1)}),
  ),

  (
    // Deep fuzzed equality
    array(array(null)), array(array(null)),
  ),
  (array(constant(2)), array(constant(2.0))),
  (
    map(<String, Object?>{"a": constant(2.0)}),
    map(<String, Object?>{"a": constant(2)}),
  ),
  (
    map(<String, Object?>{"foo": constant(1), "bar": constant(42.0)}),
    map(<String, Object?>{"bar": constant(42), "foo": constant(1.0)}),
  ),

  (
    // Bytes
    constant(blob()), constant(blob()),
  ),
  (constant(blob(0x66, 0x6f, 0x6f)), constant(blob(0x66, 0x6f, 0x6f))),
  (
    // "foo"

    // Strings
    constant(""), constant(""),
  ),
  (constant("foo"), constant("foo")),

  (
    // Booleans
    constant(true), constant(true),
  ),
  (constant(false), constant(false)),

  (
    // Geo Points
    constant(GeoPoint(10.0, 20.0)), constant(GeoPoint(10.0, 20.0)),
  ),
  (constant(GeoPoint(-10.0, -20.0)), constant(GeoPoint(-10.0, -20.0))),

  (
    // Entity References
    constant(ref("c2/doc1")), constant(ref("c2/doc1")),
  ),
];

// /** Test cases for values that should be considered not equal, ordered from lesser to greater. */
final unequalValues = [
  (
    // Boolean Comparison
    constant(false), constant(true),
  ),

  (
    // Numeric Value Comparison
    constant(double.negativeInfinity), constant(-double.maxFinite),
  ),
  (constant(-double.maxFinite), constant(minLong)),
  (constant(minLong), constant(-2)),
  (constant(-2), constant(-1)),
  (constant(-1), constant(-0.5)),
  (constant(-0.5), constant(-0.0)),
  (constant(0), constant(double.minPositive)),
  (constant(0), constant(2.2250738585072014E-308)),
  (constant(-0.0), constant(0.5)),
  (constant(0.5), constant(1)),
  (constant(1), constant(1.1)),
  (constant(1), constant(2)),
  (constant(2), constant(maxLong)),
  (constant(maxLong), constant(double.maxFinite)),
  (constant(double.maxFinite), constant(double.infinity)),

  (
    // Timestamp Comparison
    constant(Timestamp(-62_135_596_800, 0)), constant(Timestamp(0, 0)),
  ),
  (
    // MIN_VALUE vs EPOCH
    constant(Timestamp(0, 0)), constant(Timestamp(253402300799, 999999999)),
  ),
  (
    // EPOCH vs MAX_VALUE
    constant(Timestamp(-42, 0)), constant(Timestamp(-41, 0)),
  ),
  (constant(Timestamp(0, 0)), constant(Timestamp(0, 10000))),
  (constant(Timestamp(42, 0)), constant(Timestamp(42, 10000))),

  (
    // GeoPoint Comparison
    constant(GeoPoint(-87.0, -92.0)), constant(GeoPoint(-87.0, 0.0)),
  ),
  (constant(GeoPoint(-87.0, 0.0)), constant(GeoPoint(-87.0, 42.0))),
  (constant(GeoPoint(-87.0, 42.0)), constant(GeoPoint(0.0, -92.0))),
  (constant(GeoPoint(0.0, -92.0)), constant(GeoPoint(0.0, 0.0))),
  (constant(GeoPoint(0.0, 0.0)), constant(GeoPoint(0.0, 42.0))),
  (constant(GeoPoint(0.0, 42.0)), constant(GeoPoint(42.0, -92.0))),
  (constant(GeoPoint(42.0, -92.0)), constant(GeoPoint(42.0, 0.0))),
  (constant(GeoPoint(42.0, 0.0)), constant(GeoPoint(42.0, 42.0))),

  (
    // String Comparison
    constant(""), constant("abc"),
  ),
  (constant("abc"), constant("santé")),
  (constant("a"), constant("aa")),

  (
    // Byte Comparison
    constant(blob()), constant(blob(0, 2, 56, 42)),
  ),
  (constant(blob(2, 26)), constant(blob(2, 26, 31))),

  (
    // EntityRef Comparison
    // This is a simplified version.
    constant(ref("foo/bar")), constant(ref("foo/baz")),
  ),
  (constant(ref("foo/bar/qux/a")), constant(ref("foo/bar/qux/b"))),
  (constant(ref("foo/bar")), constant(ref("foo/bar/baz/foo"))),

  (
    // Array Comparison
    array(), array(constant(true), constant(15)),
  ),
  (array(constant(1)), array(constant(2))),
  (array(constant(1), constant(2)), array(constant(2))),
  (
    array(constant(1), constant(2), constant(3)),
    array(constant(2), constant(1)),
  ),
  (
    array(map(<String, Object?>{"a": constant(1)})),
    array(map(<String, Object?>{"a": constant(2)})),
  ),
  (array(constant(1)), array(constant(1), constant(2))),
  (array(nullValue()), array(nullValue(), constant(1))),
  (array(nullValue()), array(nullValue(), nullValue())),
  (array(doubleNaN), array(doubleNaN, nullValue())),

  (
    // Array with Null/NaN
    array(constant(1)), array(constant(1), doubleNaN),
  ),
  (array(doubleNaN), array(doubleNaN, doubleNaN)),
  (array(doubleNaN), array(constant(double.negativeInfinity))),
  (
    // This is a cross-type comparison
    array(constant(1), nullValue()), array(constant(2), nullValue()),
  ),
  (array(constant(1)), array(constant(1), nullValue())),
  (array(nullValue()), array(constant(1))),

  (
    // Map comparison
    map(<String, Object?>{"a": constant(1), "b": nullValue()}),
    map(<String, Object?>{"b": constant(2)}),
  ),
  (
    map(<String, Object?>{"a": constant(1)}),
    map(<String, Object?>{"a": constant(1), "b": constant(2)}),
  ),
  (map(<String, Object?>{}), map(<String, Object?>{"a": nullValue()})),
  (map(<String, Object?>{}), map(<String, Object?>{"a": doubleNaN})),
  (
    map(<String, Object?>{"a": doubleNaN}),
    map(<String, Object?>{"a": doubleNaN, "b": nullValue()}),
  ),
  (
    map(<String, Object?>{"a": nullValue(), "b": constant(1)}),
    map(<String, Object?>{
      "a": nullValue(),
      "b": constant(1),
      "c": constant(2),
    }),
  ),
  (
    map(<String, Object?>{"a": nullValue()}),
    map(<String, Object?>{"a": nullValue(), "b": constant(1)}),
  ),
  (
    map(<String, Object?>{"a": nullValue(), "b": nullValue()}),
    map(<String, Object?>{"a": nullValue(), "b": doubleNaN}),
  ),
  (
    map(<String, Object?>{"a": nullValue(), "b": doubleNaN}),
    map(<String, Object?>{"a": nullValue(), "b": constant("foo")}),
  ),
  (
    map(<String, Object?>{"a": nullValue(), "b": constant(1)}),
    map(<String, Object?>{"a": nullValue(), "b": constant(2)}),
  ),
];

// /** Test cases for comparing different types, ordered by Firestore's type hierarchy. */
final crossTypeValues = [
  (
    // unset < null
    unsetValue, nullValue(),
  ),

  (
    // Null < Boolean
    nullValue(), constant(false),
  ),

  (
    // Boolean < NaN
    constant(true), doubleNaN,
  ),

  (
    // NaN < Numeric
    doubleNaN, constant(double.negativeInfinity),
  ),

  (
    // Numeric < Timestamp
    constant(double.infinity), constant(Timestamp(-62_135_596_800, 0)),
  ),

  (
    // Timestamp < String
    constant(Timestamp(253_402, 999_999_999)), constant(""),
  ),

  (
    // String < ByteString
    constant("foo"), constant(blob()),
  ),

  (
    // ByteString < EntityRef
    constant(blob(1, 2, 3)), constant(ref("foo/bar")),
  ),

  (
    // EntityRef < GeoPoint
    constant(ref("foo/bar")), constant(GeoPoint(-90.0, -180.0)),
  ),

  (
    // GeoPoint < Array
    constant(GeoPoint(90.0, 180.0)), array(),
  ),

  (
    // Array < Map
    array(constant("foo"), constant("bar")), map(<String, Object?>{}),
  ),
];

// A collection of all values for testing against null, NaN, or errors.
final allValues = <Expression>[
  for (final (a, b) in <(Expression, Expression)>[
    ...equivalentValues,
    ...unequalValues,
    ...crossTypeValues,
  ]) ...<Expression>[a, b],
];
