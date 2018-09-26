// File created by
// Lung Razvan <long1eu>
// on 25/09/2018

import 'package:firebase_firestore/src/firebase/firestore/core/document_view_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:test/test.dart';

import '../../../util/test_util.dart';

void main() async {
  test('testDocumentViewChangeConstructor', () {
    final Document doc1 =
        TestUtil.docForMap('a/b', 0, TestUtil.emptyMap, false);
    const DocumentViewChangeType type = DocumentViewChangeType.modified;
    final DocumentViewChange change = DocumentViewChange(type, doc1);
    expect(doc1, change.document);
    expect(type, change.type);
  });

  test('testTrack', () {});
}
