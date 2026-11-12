// Ported from the BSON cases of the Android SDK's RemoteSerializerTest,
// BundleSerializerTest and UserDataWriterTest.

import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart' hide FieldValue;
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart'
    as model;
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/field_transform.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/numeric_extremum_transform_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/numeric_increment_transform_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/patch_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as proto;
import 'package:cloud_firestore_dart/src/proto/index.dart' as protos;
import 'package:fixnum/fixnum.dart';
import 'package:test/test.dart';

import '../../../util/test_util.dart';
import 'test_util.dart' show documentSnapshot;

proto.Value _map(Map<String, proto.Value> fields) {
  final proto.MapValue map = proto.MapValue.create();
  map.fields.addAll(fields);
  return proto.Value.create()..mapValue = map;
}

proto.Value _null() =>
    proto.Value.create()..nullValue = protos.NullValue.NULL_VALUE;

proto.Value _int(int value) =>
    proto.Value.create()..integerValue = Int64(value);

proto.Value _string(String value) => proto.Value.create()..stringValue = value;

proto.Value _bytes(List<int> value) => proto.Value.create()..bytesValue = value;

Blob _binary(int subtype, List<int> bytes) =>
    Blob.bsonBinary(subtype, Uint8List.fromList(bytes));

void main() {
  final DatabaseId databaseId = DatabaseId.forDatabase('p', 'd');
  final RemoteSerializer serializer = RemoteSerializer(databaseId);

  void assertRoundTrip(Object value, proto.Value data) {
    final FieldValue model = wrap(value);
    expect(serializer.encodeValue(model), data);
    final FieldValue decoded = serializer.decodeValue(data);
    expect(decoded, model);
    expect(decoded.runtimeType, model.runtimeType);
    expect(decoded.value, value);
  }

  group('RemoteSerializer', () {
    test('testEncodesMinKey', () {
      assertRoundTrip(
          MinKey.instance, _map(<String, proto.Value>{'__min__': _null()}));
    });

    test('testEncodesMaxKey', () {
      assertRoundTrip(
          MaxKey.instance, _map(<String, proto.Value>{'__max__': _null()}));
    });

    test('testEncodesInt32Values', () {
      for (final int value in <int>[-2147483648, -1, 0, 12345, 2147483647]) {
        assertRoundTrip(Int32Value(value),
            _map(<String, proto.Value>{'__int__': _int(value)}));
      }
    });

    test('testEncodesDecimal128Values', () {
      for (final String value in <String>[
        '1.2e3',
        '-0',
        'NaN',
        'Infinity',
        '-Infinity',
        '1.000000000000000000000000000000001',
        '9.999999999999999999999999999999999E+6144',
      ]) {
        assertRoundTrip(Decimal128Value(value),
            _map(<String, proto.Value>{'__decimal128__': _string(value)}));
        // The string is not normalized.
        expect(
            (serializer
                    .decodeValue(_map(<String, proto.Value>{
                      '__decimal128__': _string(value)
                    }))
                    .value! as Decimal128Value)
                .stringValue,
            value);
      }
    });

    test('testEncodesBsonObjectIds', () {
      assertRoundTrip(
          BsonObjectId('507f191e810c19729de860ea'),
          _map(<String, proto.Value>{
            '__oid__': _string('507f191e810c19729de860ea')
          }));
    });

    test('testEncodesBsonTimestamps', () {
      assertRoundTrip(
          BsonTimestamp(12345, 67),
          _map(<String, proto.Value>{
            '__request_timestamp__': _map(<String, proto.Value>{
              'seconds': _int(12345),
              'increment': _int(67),
            })
          }));
      assertRoundTrip(
          BsonTimestamp(4294967295, 4294967295),
          _map(<String, proto.Value>{
            '__request_timestamp__': _map(<String, proto.Value>{
              'seconds': _int(4294967295),
              'increment': _int(4294967295),
            })
          }));
    });

    test('testEncodesRegexValues', () {
      assertRoundTrip(
          const RegexValue('^foo', 'i'),
          _map(<String, proto.Value>{
            '__regex__': _map(<String, proto.Value>{
              'pattern': _string('^foo'),
              'options': _string('i'),
            })
          }));
    });

    test('testEncodesBlob', () {
      // A blob with a subtype has the subtype in front of its bytes.
      assertRoundTrip(
          _binary(1, <int>[1, 2, 3]),
          _map(<String, proto.Value>{
            '__binary__': _bytes(<int>[1, 1, 2, 3])
          }));
      assertRoundTrip(
          _binary(255, <int>[]),
          _map(<String, proto.Value>{
            '__binary__': _bytes(<int>[255])
          }));
      // A subtype of 0 is a regular blob.
      expect(serializer.encodeValue(wrap(_binary(0, <int>[1, 2, 3]))),
          _bytes(<int>[1, 2, 3]));
      expect(
          (serializer.decodeValue(_bytes(<int>[1, 2, 3])).value! as Blob)
              .subtype,
          0);
    });

    test('encodes the types inside of arrays and maps', () {
      final FieldValue model = wrap(<String, Object?>{
        'array': <Object?>[Int32Value(1), MinKey.instance],
        'map': <String, Object?>{'oid': BsonObjectId('foo')},
      });
      final proto.Value encoded = serializer.encodeValue(model);
      expect(encoded.mapValue.fields['array']!.arrayValue.values[0],
          _map(<String, proto.Value>{'__int__': _int(1)}));
      expect(encoded.mapValue.fields['map']!.mapValue.fields['oid'],
          _map(<String, proto.Value>{'__oid__': _string('foo')}));
      expect(serializer.decodeValue(encoded), model);
    });

    test('decodes maps that only look like a BSON type as maps', () {
      final List<proto.Value> maps = <proto.Value>[
        _map(<String, proto.Value>{'__min__': _int(1)}),
        _map(<String, proto.Value>{'__max__': _string('a')}),
        _map(<String, proto.Value>{'__min__': _null(), 'a': _int(1)}),
        _map(<String, proto.Value>{'__int__': _string('1')}),
        _map(<String, proto.Value>{'__int__': _int(2147483648)}),
        _map(<String, proto.Value>{'__int__': _int(1), 'a': _int(1)}),
        _map(<String, proto.Value>{'__decimal128__': _int(1)}),
        _map(<String, proto.Value>{'__decimal128__': _string('abc')}),
        _map(<String, proto.Value>{'__oid__': _int(1)}),
        _map(<String, proto.Value>{'__binary__': _string('a')}),
        // Empty, or with a subtype of 0.
        _map(<String, proto.Value>{'__binary__': _bytes(<int>[])}),
        _map(<String, proto.Value>{
          '__binary__': _bytes(<int>[0, 1, 2])
        }),
        _map(<String, proto.Value>{'__request_timestamp__': _int(1)}),
        _map(<String, proto.Value>{
          '__request_timestamp__':
              _map(<String, proto.Value>{'seconds': _int(1)})
        }),
        _map(<String, proto.Value>{
          '__request_timestamp__': _map(<String, proto.Value>{
            'seconds': _int(1),
            'increment': _string('2'),
          })
        }),
        _map(<String, proto.Value>{
          '__request_timestamp__': _map(<String, proto.Value>{
            'seconds': _int(-1),
            'increment': _int(2),
          })
        }),
        _map(<String, proto.Value>{
          '__request_timestamp__': _map(<String, proto.Value>{
            'seconds': _int(1),
            'increment': _int(2),
            'extra': _int(3),
          })
        }),
        _map(<String, proto.Value>{'__regex__': _string('a')}),
        _map(<String, proto.Value>{
          '__regex__': _map(<String, proto.Value>{'pattern': _string('a')})
        }),
        _map(<String, proto.Value>{
          '__regex__': _map(<String, proto.Value>{
            'pattern': _string('a'),
            'options': _int(1),
          })
        }),
      ];
      for (final proto.Value value in maps) {
        final FieldValue decoded = serializer.decodeValue(value);
        expect(decoded, isA<ObjectValue>(), reason: '$value');
        // Nothing is lost.
        expect(serializer.encodeValue(decoded), value);
      }
    });

    test('encodes transforms with BSON operands', () {
      final List<Mutation> mutations = <Mutation>[
        PatchMutation(key('docs/1'), ObjectValue.empty, fieldMask(<String>[]),
            Precondition(exists: true), <FieldTransform>[
          FieldTransform(
              model.FieldPath.fromSingleSegment('a'),
              NumericIncrementTransformOperation(
                  wrap(Int32Value(1)) as NumberValue)),
          FieldTransform(
              model.FieldPath.fromSingleSegment('b'),
              NumericMaximumTransformOperation(
                  wrap(Decimal128Value('1.5')) as NumberValue)),
          FieldTransform(
              model.FieldPath.fromSingleSegment('c'),
              NumericMinimumTransformOperation(
                  wrap(Int32Value(3)) as NumberValue)),
        ]),
      ];
      for (final Mutation mutation in mutations) {
        expect(serializer.decodeMutation(serializer.encodeMutation(mutation)),
            mutation);
      }
    });
  });

  group('BundleSerializer', () {
    final BundleSerializer bundleSerializer = BundleSerializer(serializer);

    Map<String, dynamic> mapValue(Map<String, dynamic> fields) =>
        <String, dynamic>{
          'mapValue': <String, dynamic>{'fields': fields}
        };

    test('testDecodesMinKey', () {
      expect(
          bundleSerializer.decodeValue(mapValue(<String, dynamic>{
            '__min__': <String, dynamic>{'nullValue': null}
          })),
          wrap(MinKey.instance));
    });

    test('testDecodesMaxKey', () {
      expect(
          bundleSerializer.decodeValue(mapValue(<String, dynamic>{
            '__max__': <String, dynamic>{'nullValue': null}
          })),
          wrap(MaxKey.instance));
    });

    test('testDecodesInt32Values', () {
      expect(
          bundleSerializer.decodeValue(mapValue(<String, dynamic>{
            '__int__': <String, dynamic>{'integerValue': '12345'}
          })),
          wrap(Int32Value(12345)));
    });

    test('testDecodesDecimal128Values', () {
      expect(
          bundleSerializer.decodeValue(mapValue(<String, dynamic>{
            '__decimal128__': <String, dynamic>{'stringValue': '1.2e3'}
          })),
          wrap(Decimal128Value('1.2e3')));
    });

    test('testDecodesBsonObjectIdValues', () {
      expect(
          bundleSerializer.decodeValue(mapValue(<String, dynamic>{
            '__oid__': <String, dynamic>{'stringValue': 'foo'}
          })),
          wrap(BsonObjectId('foo')));
    });

    test('testDecodesBsonTimestampValues', () {
      expect(
          bundleSerializer.decodeValue(mapValue(<String, dynamic>{
            '__request_timestamp__': mapValue(<String, dynamic>{
              'seconds': <String, dynamic>{'integerValue': '12345'},
              'increment': <String, dynamic>{'integerValue': '67'},
            })
          })),
          wrap(BsonTimestamp(12345, 67)));
    });

    test('testDecodesRegexValues', () {
      expect(
          bundleSerializer.decodeValue(mapValue(<String, dynamic>{
            '__regex__': mapValue(<String, dynamic>{
              'pattern': <String, dynamic>{'stringValue': '^foo'},
              'options': <String, dynamic>{'stringValue': 'i'},
            })
          })),
          wrap(const RegexValue('^foo', 'i')));
    });

    test('testDecodesBsonBlobValues', () {
      expect(
          bundleSerializer.decodeValue(mapValue(<String, dynamic>{
            // The bytes 1, 1, 2, 3.
            '__binary__': <String, dynamic>{'bytesValue': 'AQECAw=='}
          })),
          wrap(_binary(1, <int>[1, 2, 3])));
    });
  });

  final Map<String, Object> allTypes = <String, Object>{
    'minKey': MinKey.instance,
    'maxKey': MaxKey.instance,
    'int32': Int32Value(-7),
    'decimal128': Decimal128Value('1.2e3'),
    'oid': BsonObjectId('507f191e810c19729de860ea'),
    'timestamp': BsonTimestamp(1, 2),
    'regex': const RegexValue('^foo', 'i'),
    'binary': _binary(128, <int>[1, 2, 3]),
    'nested': <String, Object?>{
      'array': <Object?>[Int32Value(1), MaxKey.instance],
    },
  };

  test('LocalSerializer round trips a document with all the types', () {
    final LocalSerializer localSerializer = LocalSerializer(serializer);
    final Document document = doc('docs/1', 42, allTypes);
    final Document decoded = localSerializer.decodeMaybeDocument(
        localSerializer.encodeMaybeDocument(document)) as Document;
    expect(decoded, document);
    expect(decoded.data, document.data);
  });

  test('DocumentSnapshot returns the public types', () {
    final DocumentSnapshot<dynamic> snapshot =
        documentSnapshot('docs/1', allTypes, false);
    expect(snapshot.data, allTypes);
    expect(snapshot.getMinKey('minKey'), MinKey.instance);
    expect(snapshot.getMaxKey('maxKey'), MaxKey.instance);
    expect(snapshot.getInt32Value('int32'), Int32Value(-7));
    expect(snapshot.getDecimal128Value('decimal128'), Decimal128Value('1200'));
    expect(snapshot.getBsonObjectId('oid'),
        BsonObjectId('507f191e810c19729de860ea'));
    expect(snapshot.getBsonTimestamp('timestamp'), BsonTimestamp(1, 2));
    expect(snapshot.getRegexValue('regex'), const RegexValue('^foo', 'i'));
    expect(snapshot.getBlob('binary'), _binary(128, <int>[1, 2, 3]));
    expect(snapshot.getBlob('binary')!.subtype, 128);
    expect(snapshot.get('nested.array'),
        <Object?>[Int32Value(1), MaxKey.instance]);

    expect(snapshot.getMinKey('missing'), isNull);
    expect(snapshot.getInt32Value('missing'), isNull);
    expect(() => snapshot.getInt32Value('minKey'), throwsStateError);
    expect(() => snapshot.getMaxKey('minKey'), throwsStateError);
  });
}
