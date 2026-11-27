// Ported from the Android SDK, firebase-database/src/test/java/com/google/firebase/database/PushIdGeneratorTest.java
// (firebase-android-sdk 2cfdd0389, Apache-2.0). Android uses `-` and `z` as the smallest and the
// largest push characters, as JS does; the iOS test uses different ones (see next_push_id_test.dart).
import 'package:firebase_database_dart/src/core/util/key_order.dart';
import 'package:firebase_database_dart/src/core/util/numbers.dart';
import 'package:firebase_database_dart/src/core/util/push_id.dart';
import 'package:test/test.dart';

const String _min = '-';
const String _max = 'z';

void main() {
  test('successor special values', () {
    expect(successor(int32Max.toString()), _min);
    expect(successor(_max * maxKeyLength), maxName);
  });

  test('successor basic', () {
    expect(successor('abc'), 'abc$_min');
    expect(successor('abc${_max * (maxKeyLength - 'abc'.length)}'), 'abd');
    expect(successor('abc$_min'), 'abc$_min$_min');
  });

  test('predecessor special values', () {
    expect(predecessor(_min), int32Max.toString());
    expect(predecessor(int32Min.toString()), minName);
  });

  test('predecessor basic', () {
    expect(predecessor('abc'), 'abb${_max * (maxKeyLength - 'abc'.length)}');
    expect(predecessor('abc$_min'), 'abc');
  });
}
