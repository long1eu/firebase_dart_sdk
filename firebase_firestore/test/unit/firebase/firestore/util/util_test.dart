// File created by
// Lung Razvan <long1eu>
// on 08/10/2018

import 'package:firebase_firestore/src/firebase/firestore/util/util.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

void main() {
  test('testToDebugString', () {
    expect('', Util.toDebugString(TestUtil.blob().bytes));
    expect('00ff', Util.toDebugString(TestUtil.blob(<int>[0, 0xFF]).bytes));
    expect('1f3b', Util.toDebugString(TestUtil.blob(<int>[0x1F, 0x3B]).bytes));
    expect(
        '000102030405060708090a0b0c0d0e0f',
        Util.toDebugString(TestUtil.blob(<int>[
          0,
          1,
          2,
          3,
          4,
          5,
          6,
          7,
          8,
          9,
          0xA,
          0xB,
          0xC,
          0xD,
          0xE,
          0xF
        ]).bytes));
  });
}
