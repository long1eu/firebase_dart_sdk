// Copyright 2026 Google LLC
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

// What the tests ported from Android's androidTest pipeline files call: the
// static functions of Android's `Expression` that Dart has as methods
// (through [ex]), the variadic ones, IntegrationTestUtil's helpers, and the
// subset of Truth the cases use.

// ignore_for_file: non_constant_identifier_names, constant_identifier_names

import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/pipelines.dart' as p;
import 'package:cloud_firestore_dart/pipelines.dart'
    hide and, or, xor, nor, array, switchOn;
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart';
import 'package:test/test.dart' as t;

import '../util/integration_test_util.dart';

export 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
export 'package:cloud_firestore_dart/pipelines.dart'
    hide and, or, xor, nor, array, switchOn;

/// The first argument of Android's static functions: a `String` is a field
/// name, an [Expression] is itself, anything else is a constant.
Expression ex(Object? value) => value is Expression
    ? value
    : value is String
    ? field(value)
    : constant(value);

const Object _none = Object();

List<BooleanExpression> _conditions(List<Object?> args) => <BooleanExpression>[
  for (final Object? arg in args)
    if (!identical(arg, _none)) arg! as BooleanExpression,
];

BooleanExpression _variadic(
  BooleanExpression Function(
    BooleanExpression,
    BooleanExpression, [
    List<BooleanExpression>,
  ])
  fn,
  List<Object?> args,
) {
  final List<BooleanExpression> c = _conditions(args);
  return fn(c[0], c[1], c.sublist(2));
}

/// Android's `and(...)`.
BooleanExpression and(
  Object? a,
  Object? b, [
  Object? c = _none,
  Object? d = _none,
  Object? e = _none,
  Object? f = _none,
]) => _variadic(p.and, <Object?>[a, b, c, d, e, f]);

/// Android's `or(...)`.
BooleanExpression or(
  Object? a,
  Object? b, [
  Object? c = _none,
  Object? d = _none,
  Object? e = _none,
  Object? f = _none,
]) => _variadic(p.or, <Object?>[a, b, c, d, e, f]);

/// Android's `xor(...)`.
BooleanExpression xor(
  Object? a,
  Object? b, [
  Object? c = _none,
  Object? d = _none,
  Object? e = _none,
  Object? f = _none,
]) => _variadic(p.xor, <Object?>[a, b, c, d, e, f]);

/// Android's `nor(...)`.
BooleanExpression nor(
  Object? a,
  Object? b, [
  Object? c = _none,
  Object? d = _none,
  Object? e = _none,
  Object? f = _none,
]) => _variadic(p.nor, <Object?>[a, b, c, d, e, f]);

/// Android's `array(...)`: a list, or the elements one by one.
FunctionExpression array([
  Object? a = _none,
  Object? b = _none,
  Object? c = _none,
  Object? d = _none,
  Object? e = _none,
  Object? f = _none,
]) {
  final List<Object?> args = <Object?>[
    for (final Object? arg in <Object?>[a, b, c, d, e, f])
      if (!identical(arg, _none)) arg,
  ];
  if (args.length == 1 && args[0] is List) {
    return p.array(args[0]! as List<Object?>);
  }
  return p.array(args);
}

/// Android's `switchOn(condition, result, ..., [default])`.
FunctionExpression switchOn(
  Object? a,
  Object? b, [
  Object? c = _none,
  Object? d = _none,
  Object? e = _none,
  Object? f = _none,
  Object? g = _none,
]) => p.switchOn(a! as BooleanExpression, b, <Object?>[
  for (final Object? arg in <Object?>[c, d, e, f, g])
    if (!identical(arg, _none)) arg,
]);

// ---- IntegrationTestUtil ----

/// A new collection of the Enterprise edition emulator with [docs].
Future<CollectionReference<Map<String, Object?>>> testCollectionWithDocs(
  Map<String, Object?> docs,
) async {
  final Firestore firestore =
      await IntegrationTestUtil.testEnterpriseFirestore();
  final CollectionReference<Map<String, Object?>> collection = firestore
      .collection('test-collection_${autoId()}');
  for (final MapEntry<String, Object?> doc in docs.entries) {
    await collection
        .document(doc.key)
        .set((doc.value! as Map<Object?, Object?>).cast<String, Object?>());
  }
  return collection;
}

/// A new, empty collection of the Enterprise edition emulator.
Future<CollectionReference<Map<String, Object?>>> testCollection() =>
    testCollectionWithDocs(<String, Object?>{});

/// JUnit's `assertEquals(expected, actual)`.
void assertEquals(Object? expected, Object? actual) =>
    t.expect(actual, t.equals(expected));

/// JUnit's `assertTrue(condition)`.
void assertTrue(Object? condition) => t.expect(condition, t.isTrue);

/// Android's `PipelineResult.get(field)` as an index operator.
extension PipelineResultGet on PipelineResult {
  Object? operator [](Object field) => get(field);
}

List<Map<String, Object?>> pipelineSnapshotToValues(
  PipelineSnapshot snapshot,
) => <Map<String, Object?>>[
  for (final PipelineResult result in snapshot.results) result.data(),
];

List<String?> pipelineSnapshotToIds(PipelineSnapshot snapshot) => <String?>[
  for (final PipelineResult result in snapshot.results) result.ref?.id,
];

List<Object?> nullList() => <Object?>[null];

/// Android's `checkQueryAndPipelineResultsMatch(query, expectedDocs...)`:
/// the query and `createFrom(query)` return the same documents, and those
/// are [expectedDocs] when given.
Future<void> checkQueryAndPipelineResultsMatch(
  Query<Map<String, Object?>> query, [
  List<String>? expectedDocs,
]) async {
  final QuerySnapshot<Map<String, Object?>> fromQuery = await query.get(
    Source.server,
  );
  final PipelineSnapshot fromPipeline = await query.firestore
      .pipeline()
      .createFrom(query)
      .execute();
  final List<String> queryIds = <String>[
    for (final DocumentSnapshot<Map<String, Object?>> doc in fromQuery.docs)
      doc.id,
  ];
  t.expect(pipelineSnapshotToIds(fromPipeline), queryIds);
  if (expectedDocs != null) {
    t.expect(queryIds, expectedDocs);
  }
}

/// Android's `expectError(body, message)`.
Future<void> expectError(
  Future<Object?> Function() body,
  String message,
) async {
  await t.expectLater(
    body(),
    t.throwsA(t.predicate((Object? e) => '$e'.contains(message), message)),
  );
}

/// JUnit's `assertThrows(type, body)`: the error [body] fails with.
Future<Object> assertThrows(Object? type, dynamic Function() body) async {
  try {
    await body();
  } catch (e) {
    return e;
  }
  t.fail('Expected an exception');
}

/// Android's `waitForException(task)`: the error [future] fails with.
Future<Object> waitForException(Future<Object?> future) =>
    assertThrows(null, () => future);

/// Android's `Blob.fromBytes(bytes)`.
Blob blobFromBytes(List<int> bytes) => Blob(Uint8List.fromList(bytes));

/// [time] truncated to [unit] ('year', 'month', 'day', 'hour', 'minute',
/// 'second') in UTC, or in America/Los_Angeles with [losAngeles] (Android
/// uses a java.util.Calendar for these; Dart has no time zone database, so
/// the US daylight saving rules since 2007 are applied here).
Timestamp truncateTimestamp(
  DateTime time,
  String unit, {
  bool losAngeles = false,
}) {
  final DateTime utc = time.toUtc();
  Duration offset(DateTime utcTime) {
    if (!losAngeles) {
      return Duration.zero;
    }
    final int year = utcTime.year;
    DateTime nthSunday(int month, int n) {
      DateTime day = DateTime.utc(year, month);
      while (day.weekday != DateTime.sunday) {
        day = day.add(const Duration(days: 1));
      }
      return day.add(Duration(days: 7 * (n - 1)));
    }

    // 2:00 local standard time (UTC-8) / daylight time (UTC-7).
    final DateTime dstStart = nthSunday(3, 2).add(const Duration(hours: 10));
    final DateTime dstEnd = nthSunday(11, 1).add(const Duration(hours: 9));
    final bool dst = !utcTime.isBefore(dstStart) && utcTime.isBefore(dstEnd);
    return Duration(hours: dst ? -7 : -8);
  }

  final DateTime local = utc.add(offset(utc));
  final DateTime truncated = switch (unit) {
    'year' => DateTime.utc(local.year),
    'month' => DateTime.utc(local.year, local.month),
    'day' => DateTime.utc(local.year, local.month, local.day),
    'hour' => DateTime.utc(local.year, local.month, local.day, local.hour),
    'minute' => DateTime.utc(
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
    ),
    'second' => DateTime.utc(
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
      local.second,
    ),
    _ => throw ArgumentError(unit),
  };
  // Back to UTC with the offset at the truncated time.
  DateTime back = truncated.subtract(offset(truncated));
  back = truncated.subtract(offset(back));
  return Timestamp.fromDate(back);
}

// ---- Truth ----

/// Android's `DATA_CORRESPONDENCE`: results compared by their data.
const Correspondence DATA_CORRESPONDENCE = Correspondence.data;

/// Android's `ID_CORRESPONDENCE`: results compared by their document id.
const Correspondence ID_CORRESPONDENCE = Correspondence.id;

enum Correspondence { data, id }

Subject assertThat(Object? actual) => Subject(actual);

class Subject {
  Subject(this.actual);

  final Object? actual;

  ResultsSubject comparingElementsUsing(Correspondence correspondence) =>
      ResultsSubject(<Object?>[
        for (final PipelineResult result in actual! as List<PipelineResult>)
          correspondence == Correspondence.data
              ? result.data()
              : result.ref?.id,
      ]);

  void isEmpty() => t.expect(actual, t.isEmpty);
  void isNotEmpty() => t.expect(actual, t.isNotEmpty);
  void hasSize(int size) => t.expect(actual, t.hasLength(size));
  void isEqualTo(Object? expected) => t.expect(actual, expected);
  void isNotEqualTo(Object? expected) =>
      t.expect(actual, t.isNot(t.equals(expected)));
  void isTrue() => t.expect(actual, t.isTrue);
  void isFalse() => t.expect(actual, t.isFalse);
  void isNull() => t.expect(actual, t.isNull);
  void isNotNull() => t.expect(actual, t.isNotNull);
  void isLessThan(Object expected) => t.expect(actual, t.lessThan(expected));
  void isGreaterThan(Object expected) =>
      t.expect(actual, t.greaterThan(expected));
  void isAtMost(Object expected) => t.expect(
    (actual! as Comparable<Object?>).compareTo(expected),
    t.lessThanOrEqualTo(0),
  );
  void isAtLeast(Object expected) => t.expect(
    (actual! as Comparable<Object?>).compareTo(expected),
    t.greaterThanOrEqualTo(0),
  );
  void isInstanceOf<T>() => t.expect(actual, t.isA<T>());

  /// For a list, the same elements in any order; for a map, Truth's
  /// `containsExactly(k1, v1, k2, v2, ...)`.
  ResultsSubject containsExactly(List<Object?> expected) {
    final Object? value = actual;
    if (value is Map) {
      t.expect(value, <Object?, Object?>{
        for (int i = 0; i < expected.length; i += 2)
          expected[i]: expected[i + 1],
      });
      return ResultsSubject(<Object?>[]);
    }
    return ResultsSubject(value! as List<Object?>).containsExactly(expected);
  }

  ResultsSubject containsExactlyElementsIn(List<Object?> expected) =>
      ResultsSubject(actual! as List<Object?>).containsExactly(expected);
  void contains(Object? expected) => t.expect(
    actual,
    actual is String ? t.contains(expected) : t.contains(t.equals(expected)),
  );
  void containsEntry(Object? key, Object? value) =>
      t.expect((actual! as Map<Object?, Object?>)[key], value);
  void containsKey(Object? key) =>
      t.expect((actual! as Map<Object?, Object?>).containsKey(key), t.isTrue);
  void doesNotContainKey(Object? key) =>
      t.expect((actual! as Map<Object?, Object?>).containsKey(key), t.isFalse);
  void isAnyOf(List<Object?> expected) =>
      t.expect(expected, t.contains(actual));
  StringSubject hasMessageThat() => StringSubject('$actual');

  /// `isWithin(tolerance).of(expected)`.
  Tolerance isWithin(num tolerance) => Tolerance(actual! as num, tolerance);
}

class Tolerance {
  Tolerance(this.actual, this.tolerance);

  final num actual;
  final num tolerance;

  void of(num expected) => t.expect(actual, t.closeTo(expected, tolerance));
}

class StringSubject {
  StringSubject(this.actual);

  final String actual;

  void contains(String expected) => t.expect(actual, t.contains(expected));
  void isEqualTo(String expected) => t.expect(actual, t.contains(expected));
}

class ResultsSubject {
  ResultsSubject(this.actual, [this._expected]);

  final List<Object?> actual;
  final List<Object?>? _expected;

  /// The same elements in any order; `.inOrder()` checks the order too.
  ResultsSubject containsExactly(List<Object?> expected) {
    t.expect(actual, t.unorderedEquals(expected));
    return ResultsSubject(actual, expected);
  }

  ResultsSubject containsExactlyElementsIn(List<Object?> expected) =>
      containsExactly(expected);

  void inOrder() => t.expect(actual, t.equals(_expected));
}
