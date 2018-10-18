// File created by
// Lung Razvan <long1eu>
// on 27/09/2018

import 'package:firebase_database_collection/firebase_database_collection.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/document_view_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/view_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_set.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/resource_path.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

void main() {
  test('testConstructor', () {
    final Query query = Query.atPath(ResourcePath.fromString('a'));
    final DocumentSet docs = DocumentSet.emptySet(Document.keyComparator)
        .add(doc('c/foo', 1, map()));
    final DocumentSet oldDocs = DocumentSet.emptySet(Document.keyComparator);
    final List<DocumentViewChange> changes = <DocumentViewChange>[
      DocumentViewChange(DocumentViewChangeType.added, doc('c/foo', 1, map()))
    ];

    final ImmutableSortedSet<DocumentKey> mutatedKeys =
        keySet(<DocumentKey>[key('c/foo')]);
    const bool fromCache = true;
    const bool hasPendingWrites = true;
    const bool syncStateChanges = true;

    final ViewSnapshot snapshot = ViewSnapshot(query, docs, oldDocs, changes,
        fromCache, mutatedKeys, syncStateChanges);

    expect(query, snapshot.query);
    expect(docs, snapshot.documents);
    expect(oldDocs, snapshot.oldDocuments);
    expect(changes, snapshot.changes);
    expect(fromCache, snapshot.isFromCache);
    expect(mutatedKeys, snapshot.mutatedKeys);
    expect(hasPendingWrites, snapshot.hasPendingWrites);
    expect(syncStateChanges, snapshot.didSyncStateChange);
  });
}
