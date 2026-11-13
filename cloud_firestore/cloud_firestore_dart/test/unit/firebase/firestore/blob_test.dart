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
        blob(<int>[0]),
      ])
      ..addEqualityGroup(<Blob>[
        blob(<int>[0, 1]),
        blob(<int>[0, 1]),
      ])
      ..addEqualityGroup(<Blob>[
        blob(<int>[0, 1, 0]),
        blob(<int>[0, 1, 0]),
      ])
      ..addEqualityGroup(<Blob>[
        blob(<int>[0, 1, 1]),
        blob(<int>[0, 1, 1]),
      ])
      ..addEqualityGroup(<Blob>[
        blob(<int>[0, 255]),
        blob(<int>[0, 255]),
      ])
      ..addEqualityGroup(<Blob>[
        blob(<int>[1]),
        blob(<int>[1]),
      ])
      ..addEqualityGroup(<Blob>[
        blob(<int>[1, 0]),
        blob(<int>[1, 0]),
      ])
      ..addEqualityGroup(<Blob>[
        blob(<int>[1, 255]),
        blob(<int>[1, 255]),
      ])
      ..addEqualityGroup(<Blob>[
        blob(<int>[255]),
        blob(<int>[255]),
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
    expect(
      () => Blob.fromBase64String('not base64!'),
      throwsA(isA<FormatException>()),
    );
  });

  test('toJson matches the JS shape and round trips through fromJson', () {
    final Blob value = blob(<int>[1, 2, 3]);
    expect(value.toJson(), <String, Object>{
      'type': 'firestore/bytes/1.0',
      'bytes': 'AQID',
    });
    expect(
      Blob.fromJson(jsonDecode(jsonEncode(value)) as Map<String, Object?>),
      value,
    );
    expect(
      Blob.fromJson(<String, Object?>{
        'type': 'firestore/bytes/1.0',
        'bytes': 'AQID',
        'subtype': 0,
      }),
      value,
    );
  });

  test('fromJson rejects malformed input', () {
    final Matcher throwsArgumentError = throwsA(isA<ArgumentError>());
    expect(
      () => Blob.fromJson(<String, Object?>{'bytes': 'AQID'}),
      throwsArgumentError,
    );
    expect(
      () => Blob.fromJson(<String, Object?>{
        'type': 'firestore/bytes/1.0',
        'bytes': 1,
      }),
      throwsArgumentError,
    );
    expect(
      () => Blob.fromJson(<String, Object?>{
        'type': 'firestore/bytes/1.0',
        'bytes': 'AQID',
        'subtype': 256,
      }),
      throwsArgumentError,
    );
    expect(
      () => Blob.fromJson(<String, Object?>{
        'type': 'firestore/bytes/1.0',
        'bytes': 'AQID',
        'subtype': '4',
      }),
      throwsArgumentError,
    );
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
    expect(
      Blob.bsonBinary(0, Uint8List.fromList(<int>[1])).toJson(),
      Blob(Uint8List.fromList(<int>[1])).toJson(),
    );
  });

  // Ported from the JS SDK's test/unit/api/bytes.test.ts. `Bytes` is [Blob]
  // here; the JS SDK's fromBase64String(base64, subtype) is
  // Blob.bsonBinary(subtype, base64Decode(base64)).
  group('Bytes', () {
    const Map<String, List<int>> base64Mappings = <String, List<int>>{
      '': <int>[],
      'AA==': <int>[0],
      'AAECAwQF': <int>[0, 1, 2, 3, 4, 5],
      'AP8A/w==': <int>[0, 255, 0, 255],
    };

    test('constructs values from Base64', () {
      base64Mappings.forEach((String base64Str, List<int> expectedBytes) {
        final Blob blob = Blob.fromBase64String(base64Str);
        expect(blob.bytes, orderedEquals(expectedBytes));
      });
    });

    test('constructs values from Uint8Array', () {
      base64Mappings.forEach((String base64Str, List<int> bytes) {
        expect(blob(bytes).toBase64(), base64Str);
      });
    });

    test('works with instanceof checks', () {
      expect(Blob.fromBase64String(''), isA<Blob>());
    });

    test('support equality checking with isEqual()', () {
      expect(blob(<int>[1, 2, 3]), blob(<int>[1, 2, 3]));
      expect(blob(<int>[1, 2, 3]), isNot(blob(<int>[4, 5, 6])));
    });

    test('fromJSON reconstructs the value from toJSON', () {
      final Blob bytes = Blob(Uint8List.fromList(<int>[0, 1, 2, 3, 4, 5]));
      expect(Blob.fromJson(bytes.toJson()), bytes);
    });

    test('fromJSON parameter order does not matter', () {
      const String type = 'firestore/bytes/1.0';
      const String bytes = 'AA==';
      expect(
        Blob.fromJson(<String, Object?>{'bytes': bytes, 'type': type}),
        blob(<int>[0]),
      );
      expect(
        Blob.fromJson(<String, Object?>{'type': type, 'bytes': bytes}),
        blob(<int>[0]),
      );
    });

    test('toJSON -> fromJSON bytes comparison', () {
      base64Mappings.forEach((String base64Str, List<int> expected) {
        final Blob bytesToSerialize = Blob.fromBase64String(base64Str);
        final Blob deserializedBytes = Blob.fromJson(bytesToSerialize.toJson());
        expect(deserializedBytes, bytesToSerialize);
        expect(deserializedBytes.bytes, orderedEquals(expected));
      });
    });

    test('fromJSON misisng fields throws', () {
      expect(
        () => Blob.fromJson(<String, Object?>{'type': 'firestore/bytes/1.0'}),
        throwsArgumentError,
      );
      expect(
        () => Blob.fromJson(<String, Object?>{'bytes': 'AA=='}),
        throwsArgumentError,
      );
      expect(
        () => Blob.fromJson(<String, Object?>{'type': 1, 'bytes': 'AA=='}),
        throwsArgumentError,
      );
      expect(
        () => Blob.fromJson(<String, Object?>{
          'type': 'firestore/bytes/1.0',
          'bytes': 1,
        }),
        throwsArgumentError,
      );
    });

    test('rejects invalid subtype values', () {
      final Uint8List arr = Uint8List.fromList(<int>[1, 2, 3]);
      final Matcher throwsRangeMessage = throwsA(
        isA<ArgumentError>().having(
          (ArgumentError e) => e.message,
          'message',
          'The subtype for Blob must be a value in the inclusive [0, 255] '
              'range.',
        ),
      );
      expect(() => Blob.bsonBinary(-1, arr), throwsRangeMessage);
      expect(() => Blob.bsonBinary(256, arr), throwsRangeMessage);
      expect(
        () => Blob.bsonBinary(-1, base64Decode('AA==')),
        throwsRangeMessage,
      );
      expect(
        () => Blob.bsonBinary(256, base64Decode('AA==')),
        throwsRangeMessage,
      );
    });

    test('preserves subtype on construction', () {
      final Uint8List arr = Uint8List.fromList(<int>[1, 2, 3]);
      expect(Blob.bsonBinary(5, arr).subtype, 5);
      expect(Blob.bsonBinary(10, base64Decode('AA==')).subtype, 10);
    });

    test('verifies equality checking with different subtypes', () {
      final Uint8List arr = Uint8List.fromList(<int>[1, 2, 3]);
      final Blob b1 = Blob.bsonBinary(1, arr);
      final Blob b1Again = Blob.bsonBinary(1, arr);
      final Blob b2 = Blob.bsonBinary(2, arr);
      final Blob b0 = Blob.bsonBinary(0, arr);

      expect(b1Again, b1);
      expect(b1Again.hashCode, b1.hashCode);
      expect(b2, isNot(b1));
      expect(b0, isNot(b1));
    });

    test('supports data compatibility getter', () {
      final Uint8List arr = Uint8List.fromList(<int>[1, 2, 3]);
      final Blob b1 = Blob.bsonBinary(5, arr);
      expect(b1.bytes, arr);
    });

    test('serializes toJSON correctly with and without subtype', () {
      final Uint8List arr = Uint8List.fromList(<int>[1, 2, 3]);
      final Blob b0 = Blob.bsonBinary(0, arr);
      final Blob b5 = Blob.bsonBinary(5, arr);

      expect(b0.toJson(), <String, Object>{
        'type': 'firestore/bytes/1.0',
        'bytes': 'AQID',
      });

      expect(b5.toJson(), <String, Object>{
        'type': 'firestore/bytes/1.0',
        'bytes': 'AQID',
        'subtype': 5,
      });
    });

    test('deserializes fromJSON correctly with and without subtype', () {
      final Map<String, Object?> jsonWithoutSubtype = <String, Object?>{
        'type': 'firestore/bytes/1.0',
        'bytes': 'AQID',
      };
      final Map<String, Object?> jsonWithSubtype = <String, Object?>{
        'type': 'firestore/bytes/1.0',
        'bytes': 'AQID',
        'subtype': 5,
      };

      final Blob b0 = Blob.fromJson(jsonWithoutSubtype);
      expect(b0.subtype, 0);
      expect(b0.bytes, Uint8List.fromList(<int>[1, 2, 3]));

      final Blob b5 = Blob.fromJson(jsonWithSubtype);
      expect(b5.subtype, 5);
      expect(b5.bytes, Uint8List.fromList(<int>[1, 2, 3]));
    });
  });
}
