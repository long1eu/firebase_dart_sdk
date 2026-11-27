// Ported from the iOS SDK, FirebaseDatabase/Tests/Unit/FCompoundWriteTest.m (firebase-ios-sdk
// cef246fea, Apache-2.0). The suite repeats Android's CompoundWriteTest case for case
// (compound_write_test.dart); the cases below differ: iOS builds the added writes with
// `compoundWriteWithValueDictionary` (`CompoundWrite.fromValue`).
import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:test/test.dart';

import 'support.dart';

final _base = n({'child-1': 'value-1', 'child-2': 'value-2'});

void main() {
  test('adding updates at path works (fromValue)', () {
    final updates = CompoundWrite.fromValue({
      'foo': 'foo-value',
      'bar': 'bar-value',
    });
    final write = CompoundWrite.empty.addWrites(p('child-1'), updates);
    final expected = _base.updateImmediateChild(
      ck('child-1'),
      n({'foo': 'foo-value', 'bar': 'bar-value'}),
    );
    expect(write.apply(_base), expected);
  });

  test('adding updates at root works (fromValue, null removes)', () {
    final updates = CompoundWrite.fromValue({
      'child-1': 'new-value-1',
      'child-2': null,
      'child-3': 'value-3',
    });
    final write = CompoundWrite.empty.addWrites(Path.empty, updates);
    expect(
      write.apply(_base),
      n({'child-1': 'new-value-1', 'child-3': 'value-3'}),
    );
  });

  test('removing only affects removed path (fromValue)', () {
    final updates = CompoundWrite.fromValue({
      'child-1': 'new-value-1',
      'child-2': null,
      'child-3': 'value-3',
    });
    var write = CompoundWrite.empty.addWrites(Path.empty, updates);
    write = write.removeWrite(p('child-2'));
    expect(
      write.apply(_base),
      n({'child-1': 'new-value-1', 'child-2': 'value-2', 'child-3': 'value-3'}),
    );
  });
}
