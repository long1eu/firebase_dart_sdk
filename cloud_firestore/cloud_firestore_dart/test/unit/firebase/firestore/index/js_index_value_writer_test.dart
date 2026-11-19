// The JS SDK's index value encoding (JsIndexValueWriter), which the IndexedDB cache stores in `indexEntries`. The
// expected bytes were produced by `FirestoreIndexValueWriter` and `IndexByteEncoder` of firebase-js-sdk
// (`@firebase/firestore` 4.17.2 sources, bundled with esbuild and run in Node) for the same values.

import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/blob.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/geo_point.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/index/js_index_value_writer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/value_bounds.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:test/test.dart';

String _hex(List<int> bytes) =>
    bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  final List<(String, FieldValue, SegmentKind, String)>
  cases = <(String, FieldValue, SegmentKind, String)>[
    (
      'a null',
      NullValue.nullValue(),
      SegmentKind.ascending,
      '08c014000000000000ffff',
    ),
    (
      'true',
      BoolValue.valueOf(true),
      SegmentKind.ascending,
      '08c02400000000000008bff0000000000000ffff',
    ),
    (
      'the integer 42',
      IntegerValue.valueOf(42),
      SegmentKind.ascending,
      '08c02e00000000000008c045000000000000ffff',
    ),
    (
      'the integer -7, descending',
      IntegerValue.valueOf(-7),
      SegmentKind.descending,
      'f73fd1fffffffffffff7c01c0000000000000000',
    ),
    (
      'the double 3.5',
      DoubleValue.valueOf(3.5),
      SegmentKind.ascending,
      '08c02e00000000000008c00c000000000000ffff',
    ),
    (
      'NaN',
      DoubleValue.valueOf(double.nan),
      SegmentKind.ascending,
      '08c02a000000000000ffff',
    ),
    (
      '-0.0 (as 0)',
      DoubleValue.valueOf(-0.0),
      SegmentKind.ascending,
      '08c02e000000000000088000000000000000ffff',
    ),
    (
      'a timestamp (the seconds as a string)',
      TimestampValue.valueOf(const Timestamp(1700000000, 123456789)),
      SegmentKind.ascending,
      '08c03400000000000031373030303030303030000108c19d6f3454000000ffff',
    ),
    (
      'the epoch, descending (seconds as an empty string)',
      TimestampValue.valueOf(const Timestamp(0, 0)),
      SegmentKind.descending,
      'f73fcbfffffffffffffffef77fffffffffffffff0000',
    ),
    (
      'a string with NUL and a surrogate pair',
      StringValue.valueOf('h\u00e9llo\u0000\u{1F600}'),
      SegmentKind.ascending,
      '08c03900000000000068c3a96c6c6f00fff09f9880000108c000000000000000ffff',
    ),
    (
      'a string, descending',
      StringValue.valueOf('abc'),
      SegmentKind.descending,
      'f73fc6ffffffffffff9e9d9cfffef73fffffffffffffff0000',
    ),
    (
      'bytes',
      BlobValue.valueOf(Blob(Uint8List.fromList(<int>[0, 1, 255]))),
      SegmentKind.ascending,
      '08c03e00000000000000ff01ff00000108c000000000000000ffff',
    ),
    (
      'a reference',
      ReferenceValue.valueOf(
        DatabaseId.forProject('p'),
        DocumentKey.fromPathString('a/b'),
      ),
      SegmentKind.ascending,
      '08c04280000000000008c04e00000000000061000108c04e000000000000620001ffff',
    ),
    (
      'a geo point',
      GeoPointValue.valueOf(const GeoPoint(-0.0, 12.5)),
      SegmentKind.ascending,
      '08c04680000000000008800000000000000008c029000000000000ffff',
    ),
    (
      'an array',
      ArrayValue.fromList(<FieldValue>[
        IntegerValue.valueOf(1),
        StringValue.valueOf('x'),
      ]),
      SegmentKind.ascending,
      '08c04900000000000008c02e00000000000008bff000000000000008c03900000000000078000108c00000000000000008c000000000000000ffff',
    ),
    (
      'a vector',
      VectorFieldValue.fromList(const <double>[1, 2.5]),
      SegmentKind.ascending,
      '08c04a80000000000008c02e00000000000008c00000000000000008c03900000000000076616c7565000108c04900000000000008c02e00000000000008bff000000000000008c02e00000000000008c00400000000000008c000000000000000ffff',
    ),
    (
      'the internal maximum',
      InternalMaxValue.instance,
      SegmentKind.ascending,
      '08c33fffffffffffffffff',
    ),
    (
      '1e300, descending',
      DoubleValue.valueOf(1e300),
      SegmentKind.descending,
      'f73fd1fffffffffffff701c81bc377ff8a630000',
    ),
    (
      'a pending server timestamp with a previous value',
      ServerTimestampValue(
        const Timestamp(1700000000, 5),
        IntegerValue.valueOf(3),
      ),
      SegmentKind.ascending,
      '08c04b80000000000008c0390000000000005f5f747970655f5f000108c0390000000000007365727665725f74696d657374616d70000108c00000000000000008c0390000000000005f5f6c6f63616c5f77726974655f74696d655f5f000108c03400000000000031373030303030303030000108c01400000000000008c0390000000000005f5f70726576696f75735f76616c75655f5f000108c02e00000000000008c00800000000000008c000000000000000ffff',
    ),
  ];
  for (final (
        String description,
        FieldValue value,
        SegmentKind kind,
        String expected,
      )
      in cases) {
    test('writes $description as the JS SDK does', () {
      final JsIndexByteEncoder encoder = JsIndexByteEncoder();
      JsIndexValueWriter.instance.writeIndexValue(value, encoder.forKind(kind));
      expect(_hex(encoder.encodedBytes), expected);
    });
  }

  test('writes the ordered document key as a reference value', () {
    final JsIndexByteEncoder key = JsIndexByteEncoder();
    JsIndexValueWriter.instance.writeDocumentKey(
      DocumentKey.fromPathString('a/b'),
      key.forKind(SegmentKind.ascending),
    );
    expect(
      _hex(key.encodedBytes),
      '08c04280000000000008c04e00000000000061000108c04e000000000000620001ffff',
    );
  });
}
