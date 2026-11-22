// Ported from the iOS SDK, FirebaseDatabase/Tests/Unit/FQueryParamsTest.m (firebase-ios-sdk
// cef246fea, Apache-2.0). The two cases that Android's QueryParamsTest has too
// (startAt/endAt null serializable) are in query_params_test.dart.
//
// `limitTo:` (the pre-limitToLast name, equal to `limitToLast`) does not exist in the skeleton; the
// cases that use it are expressed with `limitToLast` and noted.
import 'package:firebase_database_dart/src/core/snap/indexes/key_index.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/path_index.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/priority_index.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/value_index.dart';
import 'package:firebase_database_dart/src/core/view/query_params.dart';
import 'package:test/test.dart';

import 'support.dart';

final QueryParams _def = QueryParams.defaultParams;

QueryParams _viaWire(QueryParams params) =>
    QueryParams.fromWireObject(params.toWireObject());

void _expectEqual(QueryParams a, QueryParams b) {
  expect(a, b);
  expect(a.hashCode, b.hashCode);
}

void main() {
  test('query params equals', () {
    // Limit equals (iOS compares limitToLast with limitTo, which is the same call).
    final limit1 = _def.limitToLast(10);
    _expectEqual(limit1, _def.limitToLast(10));
    expect(limit1, isNot(_def.limitToFirst(10)));
    expect(limit1, isNot(_def.limitToLast(11)));

    // Index equals.
    _expectEqual(_def.orderBy(priorityIndex), _def.orderBy(priorityIndex));
    expect(_def.orderBy(priorityIndex), isNot(_def.orderBy(keyIndex)));

    // startAt equals.
    _expectEqual(_def.startAt(n('value')), _def.startAt(n('value'), null));
    expect(_def.startAt(n('value')), isNot(_def.startAt(n('value-2'))));

    // startAt with child key equals.
    _expectEqual(
      _def.startAt(emptyNode, ck('key')),
      _def.startAt(emptyNode, ck('key')),
    );
    expect(
      _def.startAt(emptyNode, ck('key')),
      isNot(_def.startAt(emptyNode, ck('other-key'))),
    );

    // endAt equals.
    _expectEqual(_def.endAt(n('value')), _def.endAt(n('value'), null));
    expect(_def.endAt(n('value')), isNot(_def.endAt(n('value-2'))));

    // endAt with child key equals.
    _expectEqual(
      _def.endAt(emptyNode, ck('key')),
      _def.endAt(emptyNode, ck('key')),
    );
    expect(
      _def.endAt(emptyNode, ck('key')),
      isNot(_def.endAt(emptyNode, ck('other-key'))),
    );

    // Limit and startAt equals.
    _expectEqual(
      _def.limitToFirst(10).startAt(n('value')),
      _def.limitToFirst(10).startAt(n('value')),
    );
    expect(
      _def.limitToFirst(10).startAt(n('value')),
      isNot(_def.limitToFirst(10).startAt(n('value-2'))),
    );
  });

  test(
    'limitTo equals limitToLast',
    () {},
    skip: 'QueryParams has no limitTo (the legacy alias of limitToLast)',
  );

  test('from wire object equals', () {
    final params = _def
        .limitToLast(10)
        .startAt(n('start-value'), ck('child-key-2'))
        .endAt(n('end-value'), ck('child-key-2'))
        .orderBy(keyIndex);
    _expectEqual(params, _viaWire(params));
  });

  test('can create all indexes', () {
    for (final params in [
      _def.orderBy(keyIndex),
      _def.orderBy(valueIndex),
      _def.orderBy(priorityIndex),
      _def.orderBy(PathIndex(p('subkey'))),
    ]) {
      _expectEqual(params, _viaWire(params));
    }
  });

  test('different limits', () {
    final first = _def.limitToFirst(10);
    final last = _def.limitToLast(10);
    _expectEqual(first, _viaWire(first));
    _expectEqual(last, _viaWire(last));
    expect(first, isNot(last));
  });

  test('startAt null is serializable', () {
    final params = _def.startAt(emptyNode, ck('key'));
    final parsed = _viaWire(params);
    expect(parsed, params);
    expect(parsed.hasStart, isTrue);
  });

  test('endAt null is serializable', () {
    final params = _def.endAt(emptyNode, ck('key'));
    final parsed = _viaWire(params);
    expect(parsed, params);
    expect(parsed.hasEnd, isTrue);
  });
}
