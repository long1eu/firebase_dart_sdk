// File created by
// Lung Razvan <long1eu>
// on 25/09/2018

import 'package:firebase_firestore/src/firebase/firestore/core/document_view_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/document_view_change_set.dart';
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

  test('testTrack', () {
    final DocumentViewChangeSet set = DocumentViewChangeSet();

    final Document added =
        TestUtil.docForMap('a/1', 0, TestUtil.emptyMap, false);
    final Document removed =
        TestUtil.docForMap('a/2', 0, TestUtil.emptyMap, false);
    final Document modified =
        TestUtil.docForMap('a/3', 0, TestUtil.emptyMap, false);

    final Document addedThenModified =
        TestUtil.docForMap('b/1', 0, TestUtil.emptyMap, false);
    final Document addedThenRemoved =
        TestUtil.docForMap('b/2', 0, TestUtil.emptyMap, false);
    final Document removedThenAdded =
        TestUtil.docForMap('b/3', 0, TestUtil.emptyMap, false);
    final Document modifiedThenRemoved =
        TestUtil.docForMap('b/4', 0, TestUtil.emptyMap, false);
    final Document modifiedThenModified =
        TestUtil.docForMap('b/5', 0, TestUtil.emptyMap, false);

    set.addChange(DocumentViewChange(DocumentViewChangeType.added, added));
    set.addChange(DocumentViewChange(DocumentViewChangeType.removed, removed));
    set.addChange(
        DocumentViewChange(DocumentViewChangeType.modified, modified));

    set.addChange(
        DocumentViewChange(DocumentViewChangeType.added, addedThenModified));
    set.addChange(
        DocumentViewChange(DocumentViewChangeType.modified, addedThenModified));
    set.addChange(
        DocumentViewChange(DocumentViewChangeType.added, addedThenRemoved));
    set.addChange(
        DocumentViewChange(DocumentViewChangeType.removed, addedThenRemoved));
    set.addChange(
        DocumentViewChange(DocumentViewChangeType.removed, removedThenAdded));
    set.addChange(
        DocumentViewChange(DocumentViewChangeType.added, removedThenAdded));
    set.addChange(DocumentViewChange(
        DocumentViewChangeType.modified, modifiedThenRemoved));
    set.addChange(DocumentViewChange(
        DocumentViewChangeType.removed, modifiedThenRemoved));
    set.addChange(DocumentViewChange(
        DocumentViewChangeType.modified, modifiedThenModified));
    set.addChange(DocumentViewChange(
        DocumentViewChangeType.modified, modifiedThenModified));

    final List<DocumentViewChange> changes = set.getChanges();

    expect(changes.length, 7);
    expect(changes[0].document, added);
    expect(changes[0].type, DocumentViewChangeType.added);
    expect(changes[1].document, removed);
    expect(changes[1].type, DocumentViewChangeType.removed);
    expect(changes[2].document, modified);
    expect(changes[2].type, DocumentViewChangeType.modified);
    expect(changes[3].document, addedThenModified);
    expect(changes[3].type, DocumentViewChangeType.added);
    expect(changes[4].document, removedThenAdded);
    expect(changes[4].type, DocumentViewChangeType.modified);
    expect(changes[5].document, modifiedThenRemoved);
    expect(changes[5].type, DocumentViewChangeType.removed);
    expect(changes[6].document, modifiedThenModified);
    expect(changes[6].type, DocumentViewChangeType.modified);
  });
}
