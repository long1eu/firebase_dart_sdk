// File created by
// Lung Razvan <long1eu>
// on 27/09/2018

import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/resource_path.dart';
import 'package:test/test.dart';

import '../../../../util/comparator_test.dart';

void main() {
  test('testConstructor', () {
    final ResourcePath path =
        ResourcePath.fromSegments(<String>['rooms', 'firestore', 'messages', '1']);
    final DocumentKey key = DocumentKey.fromPath(path);
    expect(key.path, path);
  });

  test('testComparison', () {
    final DocumentKey key1 = DocumentKey.fromSegments(<String>['a', 'b', 'c', 'd']);
    final DocumentKey key2 = DocumentKey.fromSegments(<String>['a', 'b', 'c', 'd']);
    final DocumentKey key3 = DocumentKey.fromSegments(<String>['x', 'y', 'z', 'w']);

    expect(key2, key1);
    expect(key3, isNot(key1));

    final DocumentKey empty = DocumentKey.fromSegments(<String>[]);
    final DocumentKey a = DocumentKey.fromSegments(<String>['a', 'a']);
    final DocumentKey b = DocumentKey.fromSegments(<String>['b', 'b']);
    final DocumentKey ab = DocumentKey.fromSegments(<String>['a', 'a', 'b', 'b']);

    ComparatorTester<DocumentKey>()
        .addItem(empty)
        .addItem(a)
        .addItem(ab)
        .addItem(b)
        .permitInconsistencyWithEquals()
        .testCompare();
  });

  test('testUnevenNumberOfSegmentsAreRejected', () {
    expect(() => DocumentKey.fromSegments(<String>['a']), throwsStateError);
  });
}
