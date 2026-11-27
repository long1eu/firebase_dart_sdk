// Ported from the Android SDK, firebase-database/src/test/java/com/google/firebase/database/core/view/QueryParamsTest.java
// (firebase-android-sdk 2cfdd0389, Apache-2.0). `getWireProtocolParams` is `toWireObject`,
// `fromQueryObject` is `QueryParams.fromWireObject`, `toJSON` is `jsonEncode(toWireObject())`.
import 'dart:convert';

import 'package:firebase_database_dart/src/core/view/query_params.dart';
import 'package:test/test.dart';

import 'support.dart';

QueryParams _roundTrip(QueryParams params) {
  final json = jsonEncode(params.toWireObject());
  final object = (jsonDecode(json) as Map).cast<String, Object?>();
  final fromJson = QueryParams.fromWireObject(object);
  expect(fromJson, params);
  expect(fromJson.hashCode, params.hashCode);
  return fromJson;
}

void main() {
  test('startAt null is serializable', () {
    final params = QueryParams.defaultParams.startAt(emptyNode, ck('key'));
    final parsed = QueryParams.fromWireObject(params.toWireObject());
    expect(parsed, params);
    expect(params.hasStart, isTrue);
  });

  test('endAt null is serializable', () {
    final params = QueryParams.defaultParams.endAt(emptyNode, ck('key'));
    final parsed = QueryParams.fromWireObject(params.toWireObject());
    expect(parsed, params);
    expect(params.hasEnd, isTrue);
  });

  test('query params round trip through JSON', () {
    final def = QueryParams.defaultParams;
    _roundTrip(def);
    _roundTrip(def.startAt(n(100.0)));
    _roundTrip(def.startAt(n(100.4)));
    _roundTrip(def.startAt(n('one hundred')));
    _roundTrip(
      def
          .startAt(n(100.0), ck('a'))
          .endAt(n('one hundred'), ck('b'))
          .limitToFirst(5),
    );
    _roundTrip(def.startAt(n(100.0), ck('a')).limitToLast(5));
  });
}
