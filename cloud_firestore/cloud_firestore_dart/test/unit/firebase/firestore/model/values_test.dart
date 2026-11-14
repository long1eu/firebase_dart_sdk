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

// Ported from upstream ValuesTest (Android main): the bounds, canonical id and
// BSON detection cases. testValueEquality and testValueOrdering are ported in
// field_value_test.dart and bson_values_test.dart.

import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart'
    show
        Blob,
        BsonObjectId,
        BsonTimestamp,
        Decimal128Value,
        GeoPoint,
        Int32Value,
        MaxKey,
        MinKey,
        RegexValue,
        Timestamp,
        VectorValue;
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/canonical_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/value_bounds.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as proto_v1;
import 'package:fixnum/fixnum.dart';
import 'package:test/test.dart';

import '../../../../util/comparator_test.dart';
import '../../../../util/test_util.dart';

Blob _bsonBinary(int subtype, List<int> bytes) =>
    Blob.bsonBinary(subtype, Uint8List.fromList(bytes));

FieldValue _wrapRef(String project, String database, String path) =>
    ReferenceValue.valueOf(dbId(project, database), key(path));

/// The proto map `{__binary__: <subtype byte><bytes>}`, built by hand.
proto_v1.Value _manualBsonBinary(int subtype, List<int> bytes) {
  return proto_v1.Value(
    mapValue: proto_v1.MapValue(
      fields: <String, proto_v1.Value>{
        '__binary__': proto_v1.Value(bytesValue: <int>[subtype, ...bytes]),
      }.entries,
    ),
  );
}

void main() {
  final DateTime date1 = DateTime.utc(2016, 5, 20, 10, 20);
  final RemoteSerializer serializer = RemoteSerializer(
    dbId('project', 'database'),
  );

  FieldValue lower(Object? value) =>
      ValueBounds.getLowerBound(value is FieldValue ? value : wrap(value));

  FieldValue upper(Object? value) =>
      ValueBounds.getUpperBound(value is FieldValue ? value : wrap(value));

  test('testLowerBound', () {
    ComparatorTester<FieldValue>()
        // lower bound of null is null
        .addEqualityGroup(<FieldValue>[lower(null), wrap(null)])
        // lower bound of MinKey is MinKey
        .addEqualityGroup(<FieldValue>[
          lower(MinKey.instance),
          wrap(MinKey.instance),
        ])
        // booleans
        .addEqualityGroup(<FieldValue>[wrap(false), lower(true)])
        .addEqualityGroup(<FieldValue>[wrap(true)])
        // numbers
        // Note: 32-bit,64-bit integers and 128-bit decimals shares the same
        // lower bound
        .addEqualityGroup(<FieldValue>[
          lower(1.0),
          wrap(double.nan),
          lower(Int32Value(1)),
          lower(Decimal128Value('1')),
        ])
        .addEqualityGroup(<FieldValue>[wrap(double.negativeInfinity)])
        .addEqualityGroup(<FieldValue>[wrap(IntegerValue.min)])
        // dates
        .addEqualityGroup(<FieldValue>[lower(date1)])
        .addEqualityGroup(<FieldValue>[wrap(date1)])
        // bson timestamps
        .addEqualityGroup(<FieldValue>[
          lower(BsonTimestamp(4294967295, 4294967295)),
          wrap(BsonTimestamp(0, 0)),
        ])
        .addEqualityGroup(<FieldValue>[wrap(BsonTimestamp(1, 1))])
        // strings
        .addEqualityGroup(<FieldValue>[lower('foo'), wrap('')])
        .addEqualityGroup(<FieldValue>[wrap('\u0000')])
        // blobs & bson binaries
        .addEqualityGroup(<FieldValue>[
          lower(blob(<int>[1, 2, 3])),
          lower(_bsonBinary(128, <int>[1, 2, 3])),
          lower(serializer.decodeValue(_manualBsonBinary(1, <int>[1, 2]))),
          wrap(blob()),
          wrap(_bsonBinary(0, <int>[])),
        ])
        .addEqualityGroup(<FieldValue>[
          wrap(blob(<int>[0])),
          wrap(_bsonBinary(0, <int>[0])),
        ])
        // resource names
        .addEqualityGroup(<FieldValue>[
          lower(_wrapRef('foo', 'bar', 'x/y')),
          _wrapRef('', '', ''),
        ])
        .addEqualityGroup(<FieldValue>[_wrapRef('', '', 'a/a')])
        // bson object ids
        .addEqualityGroup(<FieldValue>[
          lower(const BsonObjectId('zzz')),
          wrap(const BsonObjectId('')),
        ])
        .addEqualityGroup(<FieldValue>[wrap(const BsonObjectId('a'))])
        // geo points
        .addEqualityGroup(<FieldValue>[
          lower(const GeoPoint(-90, 0)),
          wrap(const GeoPoint(-90, -180)),
        ])
        .addEqualityGroup(<FieldValue>[wrap(const GeoPoint(-90, 0))])
        // regular expressions
        .addEqualityGroup(<FieldValue>[
          lower(const RegexValue('^foo', 'i')),
          wrap(const RegexValue('', '')),
        ])
        .addEqualityGroup(<FieldValue>[wrap(const RegexValue('^foo', 'i'))])
        // arrays
        .addEqualityGroup(<FieldValue>[
          lower(<Object>[false]),
          wrap(<Object>[]),
        ])
        .addEqualityGroup(<FieldValue>[
          wrap(<Object>[false]),
        ])
        // vectors
        .addEqualityGroup(<FieldValue>[
          lower(VectorValue(<double>[1.0])),
          wrap(VectorValue(const <double>[])),
        ])
        .addEqualityGroup(<FieldValue>[
          wrap(VectorValue(<double>[1.0])),
        ])
        // objects
        .addEqualityGroup(<FieldValue>[
          lower(<String, Object>{'foo': 'bar'}),
          wrap(<String, Object>{}),
        ])
        // maxKey
        .addEqualityGroup(<FieldValue>[wrap(MaxKey.instance)])
        .testCompare();
  });

  test('testUpperBound', () {
    ComparatorTester<FieldValue>()
        // null first
        .addEqualityGroup(<FieldValue>[wrap(null)])
        // upper value of null is MinKey
        .addEqualityGroup(<FieldValue>[upper(null), wrap(MinKey.instance)])
        // upper value of MinKey is boolean `false`
        .addEqualityGroup(<FieldValue>[wrap(false), upper(MinKey.instance)])
        // booleans
        .addEqualityGroup(<FieldValue>[wrap(true)])
        .addEqualityGroup(<FieldValue>[upper(false), wrap(double.nan)])
        // numbers
        .addEqualityGroup(<FieldValue>[
          wrap(Int32Value(2147483647)),
        ]) // largest int32 value
        .addEqualityGroup(<FieldValue>[wrap(IntegerValue.max)])
        .addEqualityGroup(<FieldValue>[wrap(double.infinity)])
        .addEqualityGroup(<FieldValue>[
          upper(0),
          upper(Int32Value(0)),
          upper(Decimal128Value('-0.0')),
        ])
        // dates
        .addEqualityGroup(<FieldValue>[wrap(date1)])
        .addEqualityGroup(<FieldValue>[upper(date1)])
        // bson timestamps
        .addEqualityGroup(<FieldValue>[
          wrap(BsonTimestamp(4294967295, 4294967295)),
        ]) // largest bson timestamp value
        .addEqualityGroup(<FieldValue>[upper(BsonTimestamp(1, 1))])
        // strings
        .addEqualityGroup(<FieldValue>[wrap('\u0000')])
        .addEqualityGroup(<FieldValue>[upper('\u0000')])
        // blobs & bson binaries
        .addEqualityGroup(<FieldValue>[
          wrap(blob(<int>[255])),
        ])
        .addEqualityGroup(<FieldValue>[
          wrap(_bsonBinary(128, <int>[1, 2])),
        ])
        .addEqualityGroup(<FieldValue>[
          upper(blob(<int>[255])),
          upper(_bsonBinary(128, <int>[1, 2])),
          upper(_bsonBinary(0, <int>[])),
          upper(serializer.decodeValue(_manualBsonBinary(1, <int>[]))),
        ])
        // resource names
        .addEqualityGroup(<FieldValue>[_wrapRef('', '', 'a/a')])
        .addEqualityGroup(<FieldValue>[upper(_wrapRef('', '', 'a/a'))])
        // bson object ids
        .addEqualityGroup(<FieldValue>[wrap(const BsonObjectId('zzz'))])
        .addEqualityGroup(<FieldValue>[upper(const BsonObjectId('a'))])
        // geo points
        .addEqualityGroup(<FieldValue>[wrap(const GeoPoint(90, 180))])
        .addEqualityGroup(<FieldValue>[upper(const GeoPoint(90, 180))])
        // regular expressions
        .addEqualityGroup(<FieldValue>[wrap(const RegexValue('^foo', 'i'))])
        .addEqualityGroup(<FieldValue>[upper(const RegexValue('', ''))])
        // arrays
        .addEqualityGroup(<FieldValue>[
          wrap(<Object>[false]),
        ])
        .addEqualityGroup(<FieldValue>[
          upper(<Object>[false]),
        ])
        // vectors
        .addEqualityGroup(<FieldValue>[
          wrap(VectorValue(<double>[1.0])),
        ])
        .addEqualityGroup(<FieldValue>[
          upper(VectorValue(<double>[1.0])),
        ])
        // objects
        .addEqualityGroup(<FieldValue>[
          wrap(<String, Object>{'a': 'b'}),
        ])
        // upper value of objects is MaxKey
        .addEqualityGroup(<FieldValue>[
          upper(<String, Object>{'a': 'b'}),
          wrap(MaxKey.instance),
        ])
        .testCompare();
  });

  test(
    'testCanonicalIds',
    skip:
        'the canonical ids of the port are the ones of the JS SDK, which '
        'differ from Android for doubles ("1" instead of "1.0") and bytes '
        '(base64 instead of hex); the JS test is ported in '
        'model/value/canonical_value_test.dart',
    () {
      expect(wrap(null).toString(), 'null');
      expect(wrap(true).toString(), 'true');
      expect(wrap(false).toString(), 'false');
      expect(wrap(1).toString(), '1');
      expect(wrap(1.0).toString(), '1.0');
      expect(wrap(const Timestamp(30, 1000)).toString(), 'time(30,1000)');
      expect(wrap('a').toString(), 'a');
      expect(wrap(blob(<int>[1, 2, 3])).toString(), '010203');
      expect(_wrapRef('p1', 'd1', 'c1/doc1').toString(), 'c1/doc1');
      expect(wrap(const GeoPoint(30, 60)).toString(), 'geo(30.0,60.0)');
      expect(wrap(<int>[1, 2, 3]).toString(), '[1,2,3]');
      expect(
        wrap(<String, Object>{'a': 1, 'b': 2, 'c': '3'}).toString(),
        '{a:1,b:2,c:3}',
      );
      expect(
        wrap(<String, Object>{
          'a': <Object>[
            'b',
            <String, Object>{'c': const GeoPoint(30, 60)},
          ],
        }).toString(),
        '{a:[b,{c:geo(30.0,60.0)}]}',
      );

      expect(
        wrap(const RegexValue('a', 'b')).toString(),
        '{__regex__:{options:b,pattern:a}}',
      );

      expect(wrap(const BsonObjectId('foo')).toString(), '{__oid__:foo}');
      expect(
        wrap(BsonTimestamp(1, 2)).toString(),
        '{__request_timestamp__:{increment:2,seconds:1}}',
      );
      expect(wrap(Int32Value(1)).toString(), '{__int__:1}');
      expect(
        wrap(Decimal128Value('1.2e3')).toString(),
        '{__decimal128__:1.2e3}',
      );
      expect(
        wrap(_bsonBinary(1, <int>[1, 2, 3])).toString(),
        '{__binary__:01010203}',
      );
      expect(
        wrap(_bsonBinary(128, <int>[1, 2, 3])).toString(),
        '{__binary__:80010203}',
      );
      expect(wrap(MinKey.instance).toString(), '{__min__:null}');
      expect(wrap(MaxKey.instance).toString(), '{__max__:null}');
    },
  );

  test('testObjectCanonicalIdsIgnoreSortOrder', () {
    expect(
      canonifyValue(wrap(<String, Object>{'a': 1, 'b': 2, 'c': '3'})),
      '{a:1,b:2,c:3}',
    );
    expect(
      canonifyValue(wrap(<String, Object>{'c': 3, 'b': 2, 'a': '1'})),
      '{a:1,b:2,c:3}',
    );
  });

  test('DetectsBsonTypesCorrectly', () {
    // PORTING NOTE: the port has no proto-level Values.isMinKey() & co. The
    // serializer detects the BSON maps when it decodes a proto value, so this
    // checks the type each encoded value decodes to.
    FieldValue roundTrip(Object value) =>
        serializer.decodeValue(serializer.encodeValue(wrap(value)));

    expect(roundTrip(MinKey.instance), isA<MinKeyValue>());
    expect(roundTrip(MaxKey.instance), isA<MaxKeyValue>());
    expect(roundTrip(Int32Value(1)), isA<Int32FieldValue>());
    expect(roundTrip(Decimal128Value('1.2e3')), isA<Decimal128FieldValue>());
    expect(roundTrip(const RegexValue('^foo', 'i')), isA<RegexFieldValue>());
    expect(roundTrip(BsonTimestamp(1, 2)), isA<BsonTimestampValue>());
    expect(roundTrip(const BsonObjectId('foo')), isA<BsonObjectIdValue>());
    expect(roundTrip(_bsonBinary(1, <int>[])), wrap(_bsonBinary(1, <int>[])));
    expect(
      roundTrip(_bsonBinary(1, <int>[1, 2, 4])),
      wrap(_bsonBinary(1, <int>[1, 2, 4])),
    );

    final proto_v1.Value emptyBytesBinaryMap = proto_v1.Value(
      mapValue: proto_v1.MapValue(
        fields: <String, proto_v1.Value>{
          '__binary__': proto_v1.Value(bytesValue: <int>[]),
        }.entries,
      ),
    );
    final proto_v1.Value subtypeZeroEmptyBinaryMap = _manualBsonBinary(
      0,
      <int>[],
    );
    final proto_v1.Value subtypeZeroNonEmptyBinaryMap = _manualBsonBinary(
      0,
      <int>[1, 2],
    );

    expect(serializer.decodeValue(emptyBytesBinaryMap), isA<ObjectValue>());
    expect(
      serializer.decodeValue(subtypeZeroEmptyBinaryMap),
      isA<ObjectValue>(),
    );
    expect(
      serializer.decodeValue(subtypeZeroNonEmptyBinaryMap),
      isA<ObjectValue>(),
    );
    expect(
      serializer.decodeValue(_manualBsonBinary(1, <int>[])),
      wrap(_bsonBinary(1, <int>[])),
    );
  });

  // Ported from the JS SDK's test/unit/model/values.test.ts. The port reads
  // the BSON maps in the serializer, so these decode the proto values.

  test('detectMapRepresentation handles single-key regular maps correctly', () {
    final proto_v1.Value singleKeyRegularMap = proto_v1.Value(
      mapValue: proto_v1.MapValue(
        fields: <String, proto_v1.Value>{
          'name': proto_v1.Value(stringValue: 'Alice'),
        }.entries,
      ),
    );
    expect(
      serializer.decodeValue(singleKeyRegularMap),
      wrap(<String, Object>{'name': 'Alice'}),
    );
  });

  test('isInt32Value correctly identifies integer value 0', () {
    final proto_v1.Value intZero = proto_v1.Value(
      mapValue: proto_v1.MapValue(
        fields: <String, proto_v1.Value>{
          '__int__': proto_v1.Value(integerValue: Int64.ZERO),
        }.entries,
      ),
    );
    expect(serializer.decodeValue(intZero), wrap(Int32Value(0)));
  });
}
