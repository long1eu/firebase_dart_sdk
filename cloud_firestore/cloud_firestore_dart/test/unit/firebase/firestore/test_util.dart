// File created by
// Lung Razvan <long1eu>
// on 28/09/2018

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/document_view_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_set.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';

import '../../../util/test_util.dart' as util;

final Firestore firestore = FirebaseFirestoreMock();

CollectionReference collectionReference(String path) {
  return CollectionReferenceInternal.create(ResourcePath.fromString(path), firestore);
}

DocumentReference documentReference(String path) {
  return DocumentReferenceInternal.create(util.key(path), firestore);
}

DocumentSnapshot documentSnapshot(
    String path, Map<String, Object>? data, bool isFromCache) {
  if (data == null) {
    return DocumentSnapshotInternal.fromNoDocument(
      firestore,
      util.key(path),
      isFromCache: isFromCache,
      hasPendingWrites: false,
    );
  } else {
    return DocumentSnapshotInternal.fromDocument(
      firestore,
      util.doc(path, 1, data),
      isFromCache: isFromCache,
      hasPendingWrites: false,
    );
  }
}

Query query(String path) {
  return QueryInternal.create(util.query(path), firestore);
}

/// A convenience method for creating a particular query snapshot for tests.
///
/// [path] to be used in constructing the query.
/// [oldDocs] provides the prior set of documents in the [QuerySnapshot]. Each
/// entry maps to a document, with the key being the document id, and the
/// value being the document contents.
/// [docsToAdd] specifies data to be added into the query snapshot as of now.
/// Each entry maps to a document, with the key being the document id, and the
/// value being the document contents.
/// [isFromCache] whether the query snapshot is cache result.
/// Returns a query snapshot that consists of both sets of documents.
QuerySnapshot querySnapshot(
    String path,
    Map<String, ObjectValue> oldDocs,
    Map<String, ObjectValue> docsToAdd,
    bool hasPendingWrites,
    bool isFromCache) {
  DocumentSet oldDocuments = util.docSet(Document.keyComparator);
  ImmutableSortedSet<DocumentKey> mutatedKeys = DocumentKey.emptyKeySet;
  for (MapEntry<String, ObjectValue> pair in oldDocs.entries) {
    final String docKey = '$path/${pair.key}';
    oldDocuments = oldDocuments.add(util.docForValue(
        docKey,
        1,
        pair.value,
        hasPendingWrites
            ? DocumentState.synced
            : DocumentState.localMutations));

    if (hasPendingWrites) {
      mutatedKeys = mutatedKeys.insert(util.key(docKey));
    }
  }

  DocumentSet newDocuments = util.docSet(Document.keyComparator);
  final List<DocumentViewChange> documentChanges = <DocumentViewChange>[];
  for (MapEntry<String, ObjectValue> pair in docsToAdd.entries) {
    final String docKey = '$path/${pair.key}';
    final Document docToAdd = util.docForValue(docKey, 1, pair.value,
        hasPendingWrites ? DocumentState.synced : DocumentState.localMutations);
    newDocuments = newDocuments.add(docToAdd);
    documentChanges
        .add(DocumentViewChange(DocumentViewChangeType.added, docToAdd));

    if (hasPendingWrites) {
      mutatedKeys = mutatedKeys.insert(util.key(docKey));
    }
  }

  final ViewSnapshot viewSnapshot = ViewSnapshot(
    util.query(path),
    newDocuments,
    oldDocuments,
    documentChanges,
    mutatedKeys,
    isFromCache: isFromCache,
    didSyncStateChange: true,
    excludesMetadataChanges: false,
    hasCachedResults: false,
  );

  return QuerySnapshotInternal.create(query(path), viewSnapshot, firestore);
}

/// A [Firestore] without a client.
// ignore: non_constant_identifier_names
Firestore FirebaseFirestoreMock() =>
    FirestoreInternal.detached(DatabaseId.forProject('project'));
