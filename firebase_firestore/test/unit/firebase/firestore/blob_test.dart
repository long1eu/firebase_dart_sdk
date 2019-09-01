// File created by
// Lung Razvan <long1eu>
// on 28/09/2018

import 'dart:typed_data';

import 'package:firebase_firestore/src/firebase/firestore/blob.dart';
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
      ..permitInconsistencyWithEquals()
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
}
