// File created by
// Lung Razvan <long1eu>
// on 27/09/2018

import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_set.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

void main() {
  final Comparator<Document> testComparator = (Document left, Document right) {
    final FieldValue leftValue = left.getField(field('sort'));
    final FieldValue rightValue = right.getField(field('sort'));
    return leftValue.compareTo(rightValue);
  };

  final Document _kDoc1 = doc('docs/1', 0, map(<dynamic>['sort', 2]));
  final Document _kDoc2 = doc('docs/2', 0, map(<dynamic>['sort', 3]));
  final Document _kDoc3 = doc('docs/3', 0, map(<dynamic>['sort', 1]));

  test('testCount', () {
    expect(docSet(testComparator).length, 0);
    expect(
        docSet(testComparator, <Document>[_kDoc1, _kDoc2, _kDoc3]).length, 3);
  });

  test('testHasKey', () {
    final DocumentSet set = docSet(testComparator, <Document>[_kDoc1, _kDoc2]);

    expect(set, contains(_kDoc1.key));
    expect(set, contains(_kDoc2.key));
    expect(set, isNot(contains(_kDoc3.key)));
  });

  test('testDocumentForKey', () {
    final DocumentSet set = docSet(testComparator, <Document>[_kDoc1, _kDoc2]);

    expect(set.getDocument(_kDoc1.key), _kDoc1);
    expect(set.getDocument(_kDoc2.key), _kDoc2);
    expect(set.getDocument(_kDoc3.key), isNull);
  });

  test('testFirstAndLastDocument', () {
    final DocumentSet emptySet = docSet(testComparator);

    expect(emptySet.first, isNull);
    expect(emptySet.last, isNull);

    final DocumentSet set =
        docSet(testComparator, <Document>[_kDoc1, _kDoc2, _kDoc3]);
    expect(set.first, _kDoc3);
    expect(set.last, _kDoc2);
  });

  test('testKeepsDocumentsInTheRightOrder', () {
    final DocumentSet set =
        docSet(testComparator, <Document>[_kDoc1, _kDoc2, _kDoc3]);
    expect(set.toList(), <Document>[_kDoc3, _kDoc1, _kDoc2]);
  });

  test('testPredecessorDocumentForKey', () {
    final DocumentSet set =
        docSet(testComparator, <Document>[_kDoc3, _kDoc1, _kDoc2]);

    expect(set.getPredecessor(_kDoc3.key), isNull);
    expect(set.getPredecessor(_kDoc1.key), _kDoc3);
    expect(set.getPredecessor(_kDoc2.key), _kDoc1);
  });

  test('testDeletes', () {
    final DocumentSet set =
        docSet(testComparator, <Document>[_kDoc1, _kDoc2, _kDoc3]);

    final DocumentSet withoutDoc1 = set.remove(_kDoc1.key);
    expect(withoutDoc1.toList(), <Document>[_kDoc3, _kDoc2]);
    expect(withoutDoc1.length, 2);

    // Original remains unchanged
    expect(set.toList(), <Document>[_kDoc3, _kDoc1, _kDoc2]);

    final DocumentSet withoutDoc3 = withoutDoc1.remove(_kDoc3.key);
    expect(withoutDoc3.toList(), <Document>[_kDoc2]);
    expect(withoutDoc3.length, 1);
  });

  test('testUpdates', () {
    DocumentSet set =
        docSet(testComparator, <Document>[_kDoc1, _kDoc2, _kDoc3]);
    final Document doc2Prime = doc('docs/2', 0, map(<dynamic>['sort', 9]));

    set = set.add(doc2Prime);
    expect(set.length, 3);
    expect(set.getDocument(doc2Prime.key), doc2Prime);
    expect(set.toList(), <Document>[_kDoc3, _kDoc1, doc2Prime]);
  });
  test('testAddsDocsWithEqualComparisonValues', () {
    final Document doc1 = doc('docs/1', 0, map(<dynamic>['sort', 2]));
    final Document doc2 = doc('docs/2', 0, map(<dynamic>['sort', 2]));

    final DocumentSet set = docSet(testComparator, <Document>[doc1, doc2]);
    expect(set.toList(), <Document>[doc1, doc2]);
  });

  test('testIsEqual', () {
    final DocumentSet set1 =
        docSet(Document.keyComparator, <Document>[_kDoc1, _kDoc2, _kDoc3]);
    final DocumentSet set2 =
        docSet(Document.keyComparator, <Document>[_kDoc1, _kDoc2, _kDoc3]);

    expect(set1, set1);
    expect(set2, set1);
    expect(set1 == null, isFalse);

    final DocumentSet sortedSet1 =
        docSet(testComparator, <Document>[_kDoc1, _kDoc2, _kDoc3]);
    final DocumentSet sortedSet2 =
        docSet(testComparator, <Document>[_kDoc1, _kDoc2, _kDoc3]);
    expect(sortedSet1, sortedSet1);
    expect(sortedSet2, sortedSet1);
    expect(sortedSet1 == null, isFalse);

    final DocumentSet shortSet =
        docSet(Document.keyComparator, <Document>[_kDoc1, _kDoc2]);
    expect(shortSet, isNot(set1));
    expect(sortedSet1, isNot(set1));
  });
}

// ignore: always_specify_types
const doc = TestUtil.doc;
// ignore: always_specify_types
const map = TestUtil.map;
// ignore: always_specify_types
const field = TestUtil.field;
// ignore: always_specify_types
const docSet = TestUtil.docSet;
