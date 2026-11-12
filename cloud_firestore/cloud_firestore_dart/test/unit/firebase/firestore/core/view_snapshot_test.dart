// File created by
// Lung Razvan <long1eu>
// on 27/09/2018

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/document_view_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_set.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

void main() {
  test('testConstructor', () {
    final Query query = Query(ResourcePath.fromString('a'));
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
    const bool excludesMetadataChanges = true;
    const bool hasCachedResults = true;

    final ViewSnapshot snapshot = ViewSnapshot(
      query,
      docs,
      oldDocs,
      changes,
      mutatedKeys,
      isFromCache: fromCache,
      didSyncStateChange: syncStateChanges,
      excludesMetadataChanges: excludesMetadataChanges,
      hasCachedResults: hasCachedResults,
    );

    expect(snapshot.query, query);
    expect(snapshot.documents, docs);
    expect(snapshot.oldDocuments, oldDocs);
    expect(snapshot.changes, changes);
    expect(snapshot.isFromCache, fromCache);
    expect(snapshot.mutatedKeys, mutatedKeys);
    expect(snapshot.hasPendingWrites, hasPendingWrites);
    expect(snapshot.didSyncStateChange, syncStateChanges);
    expect(snapshot.excludesMetadataChanges, excludesMetadataChanges);
    expect(snapshot.hasCachedResults, hasCachedResults);
  });
}
