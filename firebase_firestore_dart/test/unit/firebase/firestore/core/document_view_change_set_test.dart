// File created by
// Lung Razvan <long1eu>
// on 25/09/2018

import 'package:firebase_firestore/src/firebase/firestore/core/document_view_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/document_view_change_set.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

void main() async {
  test('testDocumentViewChangeConstructor', () {
    final Document doc1 = doc('a/b', 0, emptyMap);
    const DocumentViewChangeType type = DocumentViewChangeType.modified;
    final DocumentViewChange change = DocumentViewChange(type, doc1);
    expect(doc1, change.document);
    expect(type, change.type);
  });

  test('testTrack', () {
    final DocumentViewChangeSet set = DocumentViewChangeSet();

    final Document added = doc('a/1', 0, emptyMap);
    final Document removed = doc('a/2', 0, emptyMap);
    final Document modified = doc('a/3', 0, emptyMap);

    final Document addedThenModified = doc('b/1', 0, emptyMap);
    final Document addedThenRemoved = doc('b/2', 0, emptyMap);
    final Document removedThenAdded = doc('b/3', 0, emptyMap);
    final Document modifiedThenRemoved = doc('b/4', 0, emptyMap);
    final Document modifiedThenModified = doc('b/5', 0, emptyMap);

    set
      ..addChange(DocumentViewChange(DocumentViewChangeType.added, added))
      ..addChange(DocumentViewChange(DocumentViewChangeType.removed, removed))
      ..addChange(DocumentViewChange(DocumentViewChangeType.modified, modified))
      ..addChange(DocumentViewChange(DocumentViewChangeType.added, addedThenModified))
      ..addChange(DocumentViewChange(DocumentViewChangeType.modified, addedThenModified))
      ..addChange(DocumentViewChange(DocumentViewChangeType.added, addedThenRemoved))
      ..addChange(DocumentViewChange(DocumentViewChangeType.removed, addedThenRemoved))
      ..addChange(DocumentViewChange(DocumentViewChangeType.removed, removedThenAdded))
      ..addChange(DocumentViewChange(DocumentViewChangeType.added, removedThenAdded))
      ..addChange(DocumentViewChange(DocumentViewChangeType.modified, modifiedThenRemoved))
      ..addChange(DocumentViewChange(DocumentViewChangeType.removed, modifiedThenRemoved))
      ..addChange(DocumentViewChange(DocumentViewChangeType.modified, modifiedThenModified))
      ..addChange(DocumentViewChange(DocumentViewChangeType.modified, modifiedThenModified));

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
