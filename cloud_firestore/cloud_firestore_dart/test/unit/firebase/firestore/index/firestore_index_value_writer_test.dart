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
        RegexValue;
import 'package:cloud_firestore_dart/src/firebase/firestore/geo_point.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/index/firestore_index_value_writer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/index/index_byte_encoder.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/index/index_entry.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/vector_value.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:fixnum/fixnum.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

typedef Expected = void Function(DirectionalIndexByteEncoder encoder);

Uint8List encode(FieldValue value, [SegmentKind kind = SegmentKind.ascending]) {
  final IndexByteEncoder encoder = IndexByteEncoder();
  FirestoreIndexValueWriter.instance
      .writeIndexValue(value, encoder.forKind(kind));
  return encoder.encodedBytes;
}

Uint8List expected(Expected write, [SegmentKind kind = SegmentKind.ascending]) {
  final IndexByteEncoder encoder = IndexByteEncoder();
  write(encoder.forKind(kind));
  return encoder.encodedBytes;
}

const int typeNull = FirestoreIndexValueWriter.indexTypeNull;
const int typeBoolean = FirestoreIndexValueWriter.indexTypeBoolean;
const int typeNan = FirestoreIndexValueWriter.indexTypeNan;
const int typeNumber = FirestoreIndexValueWriter.indexTypeNumber;
const int typeTimestamp = FirestoreIndexValueWriter.indexTypeTimestamp;
const int typeString = FirestoreIndexValueWriter.indexTypeString;
const int typeBlob = FirestoreIndexValueWriter.indexTypeBlob;
const int typeReference = FirestoreIndexValueWriter.indexTypeReference;
const int typeGeopoint = FirestoreIndexValueWriter.indexTypeGeopoint;
const int typeArray = FirestoreIndexValueWriter.indexTypeArray;
const int typeVector = FirestoreIndexValueWriter.indexTypeVector;
const int typeMap = FirestoreIndexValueWriter.indexTypeMap;
const int typeReferenceSegment =
    FirestoreIndexValueWriter.indexTypeReferenceSegment;
const int notTruncated = FirestoreIndexValueWriter.notTruncated;

void main() {
  // Port of FirestoreIndexValueWriterTest of the Android SDK.
  test('writeIndexValueSupportsVector', () {
    final Uint8List actualBytes = encode(wrap(VectorValue(<double>[1, 2, 3])));

    final Uint8List expectedBytes =
        expected((DirectionalIndexByteEncoder encoder) {
      encoder
        ..writeLong(typeVector) // Vector type
        ..writeLong(typeNumber) // Number type
        ..writeLong(3) // vector length
        ..writeLong(typeString) // String type
        ..writeString('value') // Vector value header
        ..writeLong(typeArray) // Array type
        ..writeLong(typeNumber) // Number type
        ..writeDouble(1) // position 0
        ..writeLong(typeNumber) // Number type
        ..writeDouble(2) // position 1
        ..writeLong(typeNumber) // Number type
        ..writeDouble(3) // position 2
        ..writeLong(notTruncated) // Array not truncated
        ..writeInfinity();
    });
    expect(actualBytes, expectedBytes);
  });

  test('writeIndexValueSupportsEmptyVector', () {
    final Uint8List actualBytes = encode(wrap(VectorValue(<double>[])));

    final Uint8List expectedBytes =
        expected((DirectionalIndexByteEncoder encoder) {
      encoder
        ..writeLong(typeVector) // Vector type
        ..writeLong(typeNumber) // Number type
        ..writeLong(0) // vector length
        ..writeLong(typeString) // String type
        ..writeString('value') // Vector value header
        ..writeLong(typeArray) // Array type
        ..writeLong(notTruncated) // Array not truncated
        ..writeInfinity();
    });
    expect(actualBytes, expectedBytes);
  });

  void expectEncoding(Object? value, Expected write) {
    expect(encode(wrap(value)), expected(write));
  }

  test('writeIndexValueSupportsBsonObjectId', () {
    expectEncoding(const BsonObjectId('507f191e810c19729de860ea'),
        (DirectionalIndexByteEncoder encoder) {
      encoder
        ..writeLong(FirestoreIndexValueWriter.indexTypeBsonObjectId)
        ..writeBytes('507f191e810c19729de860ea'.codeUnits)
        ..writeInfinity();
    });
  });

  test('writeIndexValueSupportsBlob', () {
    expectEncoding(Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2, 3])),
        (DirectionalIndexByteEncoder encoder) {
      encoder
        ..writeLong(FirestoreIndexValueWriter.indexTypeBsonBinary)
        ..writeBytes(<int>[1, 1, 2, 3])
        ..writeLong(notTruncated)
        ..writeInfinity();
    });
  });

  test('writeIndexValueSupportsBsonBinarySubtype0', () {
    expect(encode(wrap(Blob.bsonBinary(0, Uint8List.fromList(<int>[1, 2, 3])))),
        encode(wrap(blob(<int>[1, 2, 3]))));
  });

  test('writeIndexValueSupportsBsonBinaryWithEmptyData', () {
    expectEncoding(Blob.bsonBinary(1, Uint8List(0)),
        (DirectionalIndexByteEncoder encoder) {
      encoder
        ..writeLong(FirestoreIndexValueWriter.indexTypeBsonBinary)
        ..writeBytes(<int>[1])
        ..writeLong(notTruncated)
        ..writeInfinity();
    });
  });

  test('writeIndexValueSupportsBsonTimestamp', () {
    expectEncoding(BsonTimestamp(1, 2), (DirectionalIndexByteEncoder encoder) {
      encoder
        ..writeLong(FirestoreIndexValueWriter.indexTypeBsonTimestamp)
        ..writeInt64((Int64(1) << 32) | Int64(2))
        ..writeInfinity();
    });
  });

  test('writeIndexValueSupportsLargestBsonTimestamp', () {
    expectEncoding(BsonTimestamp(4294967295, 4294967295),
        (DirectionalIndexByteEncoder encoder) {
      encoder
        ..writeLong(FirestoreIndexValueWriter.indexTypeBsonTimestamp)
        // 4294967295L << 32 | 4294967295L: all 64 bits set.
        ..writeInt64(Int64(-1))
        ..writeInfinity();
    });
  });

  test('writeIndexValueSupportsSmallestBsonTimestamp', () {
    expectEncoding(BsonTimestamp(0, 0), (DirectionalIndexByteEncoder encoder) {
      encoder
        ..writeLong(FirestoreIndexValueWriter.indexTypeBsonTimestamp)
        ..writeInt64(Int64.ZERO)
        ..writeInfinity();
    });
  });

  test('writeIndexValueSupportsRegex', () {
    expectEncoding(const RegexValue('^foo', 'i'),
        (DirectionalIndexByteEncoder encoder) {
      encoder
        ..writeLong(FirestoreIndexValueWriter.indexTypeRegex)
        ..writeString('^foo') // Regex pattern
        ..writeString('i') // Regex options
        ..writeLong(notTruncated) // writeTruncationMarker
        ..writeInfinity();
    });
  });

  for (final (String name, int value) in <(String, int)>[
    ('writeIndexValueSupportsInt32', 1),
    ('writeIndexValueSupportsLargestInt32', 2147483647),
    ('writeIndexValueSupportsSmallestInt32', -2147483648),
  ]) {
    test(name, () {
      expectEncoding(Int32Value(value), (DirectionalIndexByteEncoder encoder) {
        encoder
          ..writeLong(typeNumber) // Number type
          ..writeDouble(value.toDouble()) // Number value
          ..writeInfinity();
      });
    });
  }

  for (final (String name, String value) in <(String, String)>[
    ('writeIndexValueSupportsDecimal128', '1.2e3'),
    ('writeIndexValueSupportsNegativeDecimal128', '-1.2e3'),
    ('writeIndexValueSupportsLargestDecimal128', 'Infinity'),
    ('writeIndexValueSupportsSmallestDecimal128', '-Infinity'),
  ]) {
    test(name, () {
      expectEncoding(Decimal128Value(value),
          (DirectionalIndexByteEncoder encoder) {
        encoder
          ..writeLong(typeNumber) // Number type
          ..writeDouble(double.parse(value)) // Number value
          ..writeInfinity();
      });
    });
  }

  test('writeIndexValueSupportsSpecialDecimal128', () {
    expectEncoding(Decimal128Value('NaN'),
        (DirectionalIndexByteEncoder encoder) {
      encoder
        ..writeLong(typeNan) // Number type, special case NaN
        ..writeInfinity();
    });
  });

  test('writeIndexValueSupportsMinKey', () {
    expectEncoding(MinKey.instance, (DirectionalIndexByteEncoder encoder) {
      encoder
        ..writeLong(FirestoreIndexValueWriter.indexTypeMinKey)
        ..writeInfinity();
    });
  });

  test('writeIndexValueSupportsMaxKey', () {
    expectEncoding(MaxKey.instance, (DirectionalIndexByteEncoder encoder) {
      encoder
        ..writeLong(FirestoreIndexValueWriter.indexTypeMaxKey)
        ..writeInfinity();
    });
  });

  group('encoding of each type', () {
    void check(Object? value, Expected write) {
      for (final SegmentKind kind in <SegmentKind>[
        SegmentKind.ascending,
        SegmentKind.descending
      ]) {
        expect(
            encode(wrap(value), kind),
            expected((DirectionalIndexByteEncoder encoder) {
              write(encoder);
              encoder.writeInfinity();
            }, kind),
            reason: '$value ${kind.name}');
      }
    }

    test('null', () {
      check(null, (DirectionalIndexByteEncoder e) => e.writeLong(typeNull));
    });

    test('booleans', () {
      check(true, (DirectionalIndexByteEncoder e) {
        e
          ..writeLong(typeBoolean)
          ..writeLong(1);
      });
      check(false, (DirectionalIndexByteEncoder e) {
        e
          ..writeLong(typeBoolean)
          ..writeLong(0);
      });
    });

    test('numbers: integers are written as doubles', () {
      check(42, (DirectionalIndexByteEncoder e) {
        e
          ..writeLong(typeNumber)
          ..writeDouble(42);
      });
      check(1.5, (DirectionalIndexByteEncoder e) {
        e
          ..writeLong(typeNumber)
          ..writeDouble(1.5);
      });
      expect(encode(wrap(1)), encode(wrap(1.0)));
    });

    test('numbers: -0.0, 0 and 0.0 are the same', () {
      expect(encode(wrap(-0.0)), encode(wrap(0.0)));
      expect(encode(wrap(0)), encode(wrap(0.0)));
    });

    test('NaN has its own type label and no value', () {
      check(
          double.nan, (DirectionalIndexByteEncoder e) => e.writeLong(typeNan));
    });

    test('timestamps', () {
      check(Timestamp(100, 42000), (DirectionalIndexByteEncoder e) {
        e
          ..writeLong(typeTimestamp)
          ..writeLong(100)
          ..writeLong(42000);
      });
    });

    test('strings end with the truncation marker', () {
      check('abc', (DirectionalIndexByteEncoder e) {
        e
          ..writeLong(typeString)
          ..writeString('abc')
          ..writeLong(notTruncated);
      });
    });

    test('blobs', () {
      check(blob(<int>[0, 1, 255]), (DirectionalIndexByteEncoder e) {
        e
          ..writeLong(typeBlob)
          ..writeBytes(<int>[0, 1, 255])
          ..writeLong(notTruncated);
      });
    });

    test('references write the segments of the document key and a terminator',
        () {
      check(ref('coll/doc/sub/other'), (DirectionalIndexByteEncoder e) {
        e
          ..writeLong(typeReference)
          ..writeLong(typeReferenceSegment)
          ..writeString('coll')
          ..writeLong(typeReferenceSegment)
          ..writeString('doc')
          ..writeLong(typeReferenceSegment)
          ..writeString('sub')
          ..writeLong(typeReferenceSegment)
          ..writeString('other')
          ..writeLong(notTruncated); // not upstream
      });
    });

    test('geo points', () {
      check(const GeoPoint(1.5, -2.5), (DirectionalIndexByteEncoder e) {
        e
          ..writeLong(typeGeopoint)
          ..writeDouble(1.5)
          ..writeDouble(-2.5);
      });
    });

    test('arrays: every variable length value ends with a truncation marker',
        () {
      check(<Object?>[
        1,
        'a',
        <String, Object?>{'k': true}
      ], (DirectionalIndexByteEncoder e) {
        e
          ..writeLong(typeArray)
          ..writeLong(typeNumber)
          ..writeDouble(1)
          ..writeLong(typeString)
          ..writeString('a')
          ..writeLong(notTruncated) // end of 'a'
          ..writeLong(typeMap)
          ..writeLong(typeString)
          ..writeString('k') // keys have no marker
          ..writeLong(typeBoolean)
          ..writeLong(1)
          ..writeLong(notTruncated) // end of the map
          ..writeLong(notTruncated); // end of the array
      });
    });

    test('maps write their entries sorted by key', () {
      check(<String, Object?>{
        'b': 1,
        'a': <Object?>['x']
      }, (DirectionalIndexByteEncoder e) {
        e
          ..writeLong(typeMap)
          ..writeLong(typeString)
          ..writeString('a')
          ..writeLong(typeArray)
          ..writeLong(typeString)
          ..writeString('x')
          ..writeLong(notTruncated) // end of 'x'
          ..writeLong(notTruncated) // end of the array
          ..writeLong(typeString)
          ..writeString('b')
          ..writeLong(typeNumber)
          ..writeDouble(1)
          ..writeLong(notTruncated);
      });
    });

    test('pending server timestamps are written as their map', () {
      final ServerTimestampValue value =
          ServerTimestampValue(Timestamp(5, 6), wrap('old'));
      expect(encode(value), expected((DirectionalIndexByteEncoder e) {
        e
          ..writeLong(typeMap)
          ..writeLong(typeString)
          ..writeString('__local_write_time__')
          ..writeLong(typeTimestamp)
          ..writeLong(5)
          ..writeLong(6)
          ..writeLong(typeString)
          ..writeString('__previous_value__')
          ..writeLong(typeString)
          ..writeString('old')
          ..writeLong(notTruncated)
          ..writeLong(typeString)
          ..writeString('__type__')
          ..writeLong(typeString)
          ..writeString('server_timestamp')
          ..writeLong(notTruncated)
          ..writeLong(notTruncated)
          ..writeInfinity();
      }));
    });
  });

  group('order', () {
    // In the order of the backend. Equal values share a line.
    final List<List<Object?>> groups = <List<Object?>>[
      <Object?>[null],
      <Object?>[MinKey.instance],
      <Object?>[false],
      <Object?>[true],
      <Object?>[double.nan],
      <Object?>[double.negativeInfinity],
      <Object?>[-9007199254740993],
      <Object?>[-1.5],
      <Object?>[-1, -1.0],
      <Object?>[-0.0, 0, 0.0],
      <Object?>[double.minPositive],
      <Object?>[1, 1.0, Int32Value(1), Decimal128Value('1')],
      <Object?>[1.5, Decimal128Value('1.5')],
      <Object?>[2],
      <Object?>[9007199254740993],
      <Object?>[double.infinity],
      <Object?>[Timestamp(-1, 0)],
      <Object?>[Timestamp(0, 0)],
      <Object?>[Timestamp(0, 1000)],
      <Object?>[Timestamp(1, 0)],
      <Object?>[BsonTimestamp(0, 0)],
      <Object?>[BsonTimestamp(0, 1)],
      <Object?>[BsonTimestamp(1, 0)],
      <Object?>[BsonTimestamp(2147483647, 0)],
      <Object?>[''],
      <Object?>['\u0000'],
      <Object?>['a'],
      <Object?>['a\u0000'],
      <Object?>['aa'],
      <Object?>['b'],
      <Object?>['é'],
      <Object?>['￿'],
      <Object?>['\u{1F600}'],
      <Object?>[blob()],
      <Object?>[
        blob(<int>[0])
      ],
      <Object?>[
        blob(<int>[0, 1])
      ],
      <Object?>[
        blob(<int>[1])
      ],
      <Object?>[
        blob(<int>[255])
      ],
      <Object?>[Blob.bsonBinary(1, Uint8List(0))],
      <Object?>[
        Blob.bsonBinary(1, Uint8List.fromList(<int>[9]))
      ],
      <Object?>[Blob.bsonBinary(2, Uint8List(0))],
      <Object?>[ref('a/a')],
      <Object?>[ref('a/a/b/b')],
      <Object?>[ref('a/b')],
      <Object?>[ref('b/a')],
      <Object?>[const BsonObjectId('507f191e810c19729de860ea')],
      <Object?>[const BsonObjectId('507f191e810c19729de860eb')],
      <Object?>[const GeoPoint(-90, 0)],
      <Object?>[const GeoPoint(0, -180)],
      <Object?>[const GeoPoint(0, 0)],
      <Object?>[const GeoPoint(1, 0)],
      <Object?>[const RegexValue('a', '')],
      <Object?>[const RegexValue('a', 'i')],
      <Object?>[const RegexValue('b', '')],
      <Object?>[<Object?>[]],
      <Object?>[
        <Object?>[1]
      ],
      <Object?>[
        <Object?>[1, 2]
      ],
      <Object?>[
        <Object?>[2]
      ],
      <Object?>[
        <Object?>['a']
      ],
      <Object?>[VectorValue(<double>[])],
      <Object?>[
        VectorValue(<double>[100])
      ],
      <Object?>[
        VectorValue(<double>[1, 2])
      ],
      <Object?>[
        VectorValue(<double>[1, 3])
      ],
      <Object?>[<String, Object?>{}],
      <Object?>[
        <String, Object?>{'a': 1}
      ],
      <Object?>[
        <String, Object?>{'a': 1, 'b': 1}
      ],
      <Object?>[
        <String, Object?>{'a': 2}
      ],
      <Object?>[
        <String, Object?>{'b': 1}
      ],
      <Object?>[MaxKey.instance],
    ];

    test('the encodings sort like the values, in both directions', () {
      for (int i = 0; i < groups.length; i++) {
        for (int j = i; j < groups.length; j++) {
          for (final Object? left in groups[i]) {
            for (final Object? right in groups[j]) {
              final int asc =
                  compareByteArrays(encode(wrap(left)), encode(wrap(right)))
                      .sign;
              final int desc = compareByteArrays(
                      encode(wrap(left), SegmentKind.descending),
                      encode(wrap(right), SegmentKind.descending))
                  .sign;
              expect(asc, i == j ? 0 : -1, reason: 'asc: $left vs $right');
              expect(desc, i == j ? 0 : 1, reason: 'desc: $left vs $right');
            }
          }
        }
      }
    });

    test('the encodings agree with FieldValue.compareTo', () {
      for (int i = 0; i < groups.length; i++) {
        for (int j = 0; j < groups.length; j++) {
          final FieldValue left = wrap(groups[i].first);
          final FieldValue right = wrap(groups[j].first);
          expect(compareByteArrays(encode(left), encode(right)).sign,
              left.compareTo(right).sign,
              reason: '${groups[i].first} vs ${groups[j].first}');
        }
      }
    });

    test('a reference sorts before the references it is a prefix of', () {
      // Not upstream, where a reference has no terminator and `a/a` sorts
      // after `a/a/b/b` in the index (the opposite of the document key
      // order), which makes range scans on reference fields wrong.
      final FieldValue parent = wrap(ref('a/a'));
      final FieldValue child = wrap(ref('a/a/b/b'));
      expect(parent.compareTo(child).sign, -1);
      expect(compareByteArrays(encode(parent), encode(child)).sign, -1);
      expect(
          compareByteArrays(encode(parent, SegmentKind.descending),
                  encode(child, SegmentKind.descending))
              .sign,
          1);
    });

    test('a BSON timestamp past 2^31 seconds sorts before the smaller ones',
        () {
      // Same as upstream: seconds and increment are packed into a signed
      // 64-bit long, which is negative when the top bit of the seconds is set.
      final FieldValue small = wrap(BsonTimestamp(2147483647, 0));
      final FieldValue large = wrap(BsonTimestamp(2147483648, 0));
      expect(small.compareTo(large).sign, -1);
      expect(compareByteArrays(encode(small), encode(large)).sign, 1);
    });

    test('the max value sorts after every value', () {
      Uint8List max(SegmentKind kind) {
        final IndexByteEncoder encoder = IndexByteEncoder();
        FirestoreIndexValueWriter.instance.writeMaxValue(encoder.forKind(kind));
        return encoder.encodedBytes;
      }

      for (final List<Object?> group in groups) {
        expect(
            compareByteArrays(
                    encode(wrap(group.first)), max(SegmentKind.ascending))
                .sign,
            -1,
            reason: '${group.first}');
        expect(
            compareByteArrays(encode(wrap(group.first), SegmentKind.descending),
                    max(SegmentKind.descending))
                .sign,
            1,
            reason: '${group.first}');
      }
    });

    test('a value is not a prefix of the next value of an index entry', () {
      // The entries of a multi segment index are concatenated encodings: 'a'
      // followed by 'b' must sort before 'ab' followed by anything.
      Uint8List pair(String first, String second) {
        final IndexByteEncoder encoder = IndexByteEncoder();
        FirestoreIndexValueWriter.instance
          ..writeIndexValue(wrap(first), encoder.forKind(SegmentKind.ascending))
          ..writeIndexValue(
              wrap(second), encoder.forKind(SegmentKind.ascending));
        return encoder.encodedBytes;
      }

      expect(compareByteArrays(pair('a', 'b'), pair('ab', '')).sign, -1);
      expect(compareByteArrays(pair('a', 'z'), pair('a\u0000', '')).sign, -1);
    });
  });

  test('segments of one entry can have different directions', () {
    final IndexByteEncoder encoder = IndexByteEncoder();
    FirestoreIndexValueWriter.instance
      ..writeIndexValue(wrap('a'), encoder.forKind(SegmentKind.ascending))
      ..writeIndexValue(wrap(1), encoder.forKind(SegmentKind.descending));
    expect(encoder.encodedBytes, <int>[
      ...encode(wrap('a')),
      ...encode(wrap(1), SegmentKind.descending),
    ]);

    encoder.reset();
    expect(encoder.encodedBytes, isEmpty);
  });
}
