// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Ported from the JS SDK's test/unit/model/object_value.test.ts and
// object_value_builder.test.ts: the cases that the Android ObjectValueTest
// port (field_value_test.dart and object_value_test.dart) does not cover.
// The port's ObjectValue is immutable, so set() and delete() return the new
// value.

import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart'
    show
        Blob,
        BsonObjectId,
        BsonTimestamp,
        Decimal128Value,
        Int32Value,
        MaxKey,
        MinKey,
        RegexValue,
        VectorValue;
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

Blob _binary(int subtype) =>
    Blob.bsonBinary(subtype, Uint8List.fromList(<int>[1, 2, 3]));

Map<String, Object?> _bsonFields() => <String, Object?>{
  'objectId': const BsonObjectId('foo'),
  'binary': _binary(1),
  'timestamp': BsonTimestamp(1, 2),
  'min': MinKey.instance,
  'max': MaxKey.instance,
  'regex': const RegexValue('a', 'b'),
  'int32': Int32Value(1),
  'decimal128': Decimal128Value('1.2e3'),
};

void assertObjectEquals(ObjectValue objValue, Map<String, Object?> data) {
  expect(objValue, wrapMap(data));
}

void main() {
  test('can extract fields', () {
    final ObjectValue objValue = wrapMap(<String, Object?>{
      'foo': <String, Object?>{'a': 1, 'b': true, 'c': 'string'},
      'embedding': VectorValue(<double>[1]),
      'bson': _bsonFields(),
    });

    int typeOrderOf(String path) => objValue.get(field(path))!.typeOrder;

    expect(typeOrderOf('foo'), FieldValue.typeOrderObject);
    expect(typeOrderOf('foo.a'), FieldValue.typeOrderNumber);
    expect(typeOrderOf('foo.b'), FieldValue.typeOrderBool);
    expect(typeOrderOf('foo.c'), FieldValue.typeOrderString);
    expect(typeOrderOf('embedding'), FieldValue.typeOrderVector);
    expect(typeOrderOf('bson.objectId'), FieldValue.typeOrderBsonObjectId);
    expect(typeOrderOf('bson.binary'), FieldValue.typeOrderBlob);
    expect(typeOrderOf('bson.timestamp'), FieldValue.typeOrderBsonTimestamp);
    expect(typeOrderOf('bson.min'), FieldValue.typeOrderMinKey);
    expect(typeOrderOf('bson.max'), FieldValue.typeOrderMaxKey);
    expect(typeOrderOf('bson.regex'), FieldValue.typeOrderRegex);
    expect(typeOrderOf('bson.int32'), FieldValue.typeOrderNumber);
    expect(typeOrderOf('bson.decimal128'), FieldValue.typeOrderNumber);

    expect(objValue.get(field('foo.a.b')), isNull);
    expect(objValue.get(field('bar')), isNull);
    expect(objValue.get(field('bar.a')), isNull);

    expect(
      objValue.get(field('foo')),
      wrap(<String, Object?>{'a': 1, 'b': true, 'c': 'string'}),
    );
    expect(objValue.get(field('foo.a')), wrap(1));
    expect(objValue.get(field('foo.b')), wrap(true));
    expect(objValue.get(field('foo.c')), wrap('string'));

    expect(objValue.get(field('bson')), wrap(_bsonFields()));
    expect(
      objValue.get(field('bson.objectId')),
      wrap(const BsonObjectId('foo')),
    );
    expect(objValue.get(field('bson.binary')), wrap(_binary(1)));
    expect(objValue.get(field('bson.timestamp')), wrap(BsonTimestamp(1, 2)));
    expect(objValue.get(field('bson.min')), wrap(MinKey.instance));
    expect(objValue.get(field('bson.max')), wrap(MaxKey.instance));
    expect(objValue.get(field('bson.regex')), wrap(const RegexValue('a', 'b')));
    expect(objValue.get(field('bson.int32')), wrap(Int32Value(1)));
    expect(
      objValue.get(field('bson.decimal128')),
      wrap(Decimal128Value('1.2e3')),
    );
  });

  test('can delete added keys', () {
    ObjectValue objValue = wrapMap(<String, Object?>{});
    objValue = objValue.set(field('a'), wrap('a'));
    objValue = objValue.delete(field('a'));
    assertObjectEquals(objValue, <String, Object?>{});
  });

  test('can delete, resulting in empty object', () {
    ObjectValue objValue = wrapMap(<String, Object?>{
      'foo': <String, Object?>{'bar': 'bar-value'},
    });
    objValue = objValue.delete(field('foo.bar'));
    assertObjectEquals(objValue, <String, Object?>{'foo': <String, Object?>{}});
  });

  test('will not delete nested keys on primitive values', () {
    ObjectValue objValue = wrapMap(<String, Object?>{
      'foo': <String, Object?>{'bar': 'bar-value'},
      'a': 1,
    });
    objValue = objValue.delete(field('foo.baz'));
    objValue = objValue.delete(field('foo.bar.baz'));
    objValue = objValue.delete(field('a.b'));

    final Map<String, Object?> expected = <String, Object?>{
      'foo': <String, Object?>{'bar': 'bar-value'},
      'a': 1,
    };
    assertObjectEquals(objValue, expected);
  });

  test('can delete multiple fields', () {
    ObjectValue objValue = wrapMap(<String, Object?>{
      'a': 'a',
      'b': 'a',
      'c': 'c',
    });

    objValue = objValue.delete(field('a'));
    objValue = objValue.delete(field('b'));
    objValue = objValue.delete(field('c'));

    assertObjectEquals(objValue, <String, Object?>{});
  });

  test('can handle bson types in ObjectValue', () {
    ObjectValue objValue = ObjectValue.empty;
    // Add new fields
    objValue = objValue.set(
      field('objectId'),
      wrap(const BsonObjectId('foo-value')),
    );
    objValue = objValue.set(field('binary'), wrap(_binary(1)));
    objValue = objValue.set(field('timestamp'), wrap(BsonTimestamp(1, 2)));
    objValue = objValue.set(field('regex'), wrap(const RegexValue('a', 'b')));
    objValue = objValue.set(field('int32'), wrap(Int32Value(1)));
    objValue = objValue.set(
      field('decimal128'),
      wrap(Decimal128Value('1.2e3')),
    );
    objValue = objValue.set(field('min'), wrap(MinKey.instance));
    objValue = objValue.set(field('max'), wrap(MaxKey.instance));

    assertObjectEquals(objValue, <String, Object?>{
      'objectId': const BsonObjectId('foo-value'),
      'binary': _binary(1),
      'timestamp': BsonTimestamp(1, 2),
      'regex': const RegexValue('a', 'b'),
      'int32': Int32Value(1),
      'decimal128': Decimal128Value('1.2e3'),
      'min': MinKey.instance,
      'max': MaxKey.instance,
    });

    // Overwrite existing fields
    objValue = objValue.set(
      field('objectId'),
      wrap(const BsonObjectId('new-foo-value')),
    );

    // Create nested objects
    objValue = objValue.set(field('foo.binary'), wrap(_binary(2)));
    objValue = objValue.set(field('foo.timestamp'), wrap(BsonTimestamp(1, 2)));

    // Delete fields
    objValue = objValue.delete(field('binary'));

    // overwrite nested objects
    objValue = objValue.set(field('foo.timestamp'), wrap(BsonTimestamp(2, 1)));

    // Overwrite primitive values to create objects
    objValue = objValue.set(field('min'), wrap(null));

    assertObjectEquals(objValue, <String, Object?>{
      'objectId': const BsonObjectId('new-foo-value'),
      'timestamp': BsonTimestamp(1, 2),
      'regex': const RegexValue('a', 'b'),
      'int32': Int32Value(1),
      'decimal128': Decimal128Value('1.2e3'),
      'min': null,
      'max': MaxKey.instance,
      'foo': <String, Object?>{
        'binary': _binary(2),
        'timestamp': BsonTimestamp(2, 1),
      },
    });
  });

  test('provides field mask', () {
    final ObjectValue objValue = wrapMap(<String, Object?>{
      'a': 'b',
      'map': <String, Object?>{
        'a': 1,
        'b': true,
        'c': 'string',
        'nested': <String, Object?>{'d': 'e'},
      },
      'emptymap': <String, Object?>{},
      'bar': _bsonFields(),
    });
    expect(
      objValue.fieldMask,
      fieldMask(<String>[
        'a',
        'map.a',
        'map.b',
        'map.c',
        'map.nested.d',
        'emptymap',
        'bar.objectId',
        'bar.binary',
        'bar.timestamp',
        'bar.min',
        'bar.max',
        'bar.regex',
        'bar.int32',
        'bar.decimal128',
      ]),
    );
  });

  group('MutableObjectValue', () {
    test('sets empty object', () {
      ObjectValue objectValue = ObjectValue.empty;
      objectValue = objectValue.set(field('foo'), wrap(<String, Object?>{}));

      expect(
        objectValue,
        wrapMap(<String, Object?>{'foo': <String, Object?>{}}),
      );
    });
  });
}
