// File created by
// Lung Razvan <long1eu>
// on 28/09/2018

import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/blob.dart';
import 'package:test/test.dart';

import '../../../util/comparator_test.dart';
import '../../../util/test_util.dart';

void main() {
  test('testEquals', () {
    expect(blob(<int>[1, 2, 3]), blob(<int>[1, 2, 3]));
    expect(blob(<int>[1, 2]) == blob(<int>[1, 2, 3]), isFalse);
    expect(blob(<int>[1, 2, 3]) == Object(), isFalse);
  });

  test('testComparison', () {
    ComparatorTester<Blob>()
      ..addEqualityGroup(<Blob>[blob(), blob()])
      ..addEqualityGroup(<Blob>[
        blob(<int>[0]),
        blob(<int>[0])
      ])
      ..addEqualityGroup(<Blob>[
        blob(<int>[0, 1]),
        blob(<int>[0, 1])
      ])
      ..addEqualityGroup(<Blob>[
        blob(<int>[0, 1, 0]),
        blob(<int>[0, 1, 0])
      ])
      ..addEqualityGroup(<Blob>[
        blob(<int>[0, 1, 1]),
        blob(<int>[0, 1, 1])
      ])
      ..addEqualityGroup(<Blob>[
        blob(<int>[0, 255]),
        blob(<int>[0, 255])
      ])
      ..addEqualityGroup(<Blob>[
        blob(<int>[1]),
        blob(<int>[1])
      ])
      ..addEqualityGroup(<Blob>[
        blob(<int>[1, 0]),
        blob(<int>[1, 0])
      ])
      ..addEqualityGroup(<Blob>[
        blob(<int>[1, 255]),
        blob(<int>[1, 255])
      ])
      ..addEqualityGroup(<Blob>[
        blob(<int>[255]),
        blob(<int>[255])
      ]).testCompare();
  });

  test('testMutableBytes', () {
    final Uint8List myBytes = Uint8List.fromList(<int>[1, 2, 3]);
    final Blob blob1 = Blob(myBytes);
    final Blob blob2 = Blob(myBytes);
    myBytes[0] = 5;

    final Blob blob3 = Blob(myBytes);
    expect(blob2, blob1); // Equal because array didn't change
    expect(blob1, isNot(blob3)); // Not equal because array changed
  });

  test('base64 round trip', () {
    final Blob value = blob(<int>[0, 1, 2, 250, 255]);
    expect(value.toBase64(), 'AAEC+v8=');
    expect(Blob.fromBase64String('AAEC+v8='), value);
    expect(Blob.fromBase64String(''), blob(<int>[]));
    expect(() => Blob.fromBase64String('not base64!'),
        throwsA(isA<FormatException>()));
  });

  test('toJson matches the JS shape and round trips through fromJson', () {
    final Blob value = blob(<int>[1, 2, 3]);
    expect(value.toJson(),
        <String, Object>{'type': 'firestore/bytes/1.0', 'bytes': 'AQID'});
    expect(Blob.fromJson(jsonDecode(jsonEncode(value)) as Map<String, Object?>),
        value);
    expect(
        Blob.fromJson(<String, Object?>{
          'type': 'firestore/bytes/1.0',
          'bytes': 'AQID',
          'subtype': 0
        }),
        value);
  });

  test('fromJson rejects malformed input', () {
    final Matcher throwsArgumentError = throwsA(isA<ArgumentError>());
    expect(() => Blob.fromJson(<String, Object?>{'bytes': 'AQID'}),
        throwsArgumentError);
    expect(
        () => Blob.fromJson(
            <String, Object?>{'type': 'firestore/bytes/1.0', 'bytes': 1}),
        throwsArgumentError);
    expect(
        () => Blob.fromJson(<String, Object?>{
              'type': 'firestore/bytes/1.0',
              'bytes': 'AQID',
              'subtype': 256
            }),
        throwsArgumentError);
    expect(
        () => Blob.fromJson(<String, Object?>{
              'type': 'firestore/bytes/1.0',
              'bytes': 'AQID',
              'subtype': '4'
            }),
        throwsArgumentError);
  });

  test('toJson and fromJson keep the subtype of BSON binary data', () {
    final Blob value = Blob.bsonBinary(4, Uint8List.fromList(<int>[1, 2, 3]));
    expect(value.toJson(), <String, Object>{
      'type': 'firestore/bytes/1.0',
      'bytes': 'AQID',
      'subtype': 4,
    });
    expect(Blob.fromJson(value.toJson()), value);
    expect(Blob.fromJson(value.toJson()).subtype, 4);
    // A subtype of 0 is a regular blob and is left out.
    expect(Blob.bsonBinary(0, Uint8List.fromList(<int>[1])).toJson(),
        Blob(Uint8List.fromList(<int>[1])).toJson());
  });
}
