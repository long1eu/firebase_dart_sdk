// File created by
// Lung Razvan <long1eu>
// on 27/09/2018

import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:test/test.dart';

import '../../../../util/comparator_test.dart';

void main() {
  test('testConstructor', () {
    final ResourcePath path = ResourcePath.fromSegments(
        <String>['rooms', 'firestore', 'messages', '1']);
    final DocumentKey key = DocumentKey.fromPath(path);
    expect(key.path, path);
  });

  test('testComparison', () {
    final DocumentKey key1 =
        DocumentKey.fromSegments(<String>['a', 'b', 'c', 'd']);
    final DocumentKey key2 =
        DocumentKey.fromSegments(<String>['a', 'b', 'c', 'd']);
    final DocumentKey key3 =
        DocumentKey.fromSegments(<String>['x', 'y', 'z', 'w']);

    expect(key2, key1);
    expect(key3, isNot(key1));

    final DocumentKey empty = DocumentKey.fromSegments(<String>[]);
    final DocumentKey a = DocumentKey.fromSegments(<String>['a', 'a']);
    final DocumentKey b = DocumentKey.fromSegments(<String>['b', 'b']);
    final DocumentKey ab =
        DocumentKey.fromSegments(<String>['a', 'a', 'b', 'b']);

    ComparatorTester<DocumentKey>()
        .addItem(empty)
        .addItem(a)
        .addItem(ab)
        .addItem(b)
        .testCompare();
  });

  test('testUnevenNumberOfSegmentsAreRejected', () {
    expect(() => DocumentKey.fromSegments(<String>['a']),
        throwsA(isA<AssertionError>()));
  });

  test('testUtf8ByteOrderOfSegments', () {
    // Characters outside the BMP sort after U+E000..U+FFFF in UTF-8 order.
    final DocumentKey bmp = DocumentKey.fromSegments(<String>['c', '\uE000']);
    final DocumentKey bmpTop =
        DocumentKey.fromSegments(<String>['c', '\uFFFF']);
    final DocumentKey supplementary =
        DocumentKey.fromSegments(<String>['c', '\u{10000}']);
    expect(bmp.compareTo(supplementary), lessThan(0));
    expect(bmpTop.compareTo(supplementary), lessThan(0));
    expect(supplementary.compareTo(bmp), greaterThan(0));
  });

  test('testNumericIdSegmentsSortNumericallyFirst', () {
    final List<String> ids = <String>[
      'A',
      'a',
      'Aa',
      '7',
      '12',
      '__id7__',
      '__id12__',
      '__id-2__',
      '__id1_',
      '_id1__',
      '__id',
      '__id9223372036854775807__',
      '__id-9223372036854775808__',
    ];
    final List<DocumentKey> keys = ids
        .map((String id) => DocumentKey.fromSegments(<String>['coll', id]))
        .toList()
      ..sort();
    expect(keys.map((DocumentKey key) => key.path.last).toList(), <String>[
      '__id-9223372036854775808__',
      '__id-2__',
      '__id7__',
      '__id12__',
      '__id9223372036854775807__',
      '12',
      '7',
      'A',
      'Aa',
      '__id',
      '__id1_',
      '_id1__',
      'a',
    ]);
  });
}
