// File created by
// Lung Razvan <long1eu>
// on 28/09/2018

import 'package:_firebase_database_collection_vm/_firebase_database_collection_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/collection_reference.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/document_view_change.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_set.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/query_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/watch_change_aggregator.dart';
import 'package:meta/meta.dart';
import 'package:mockito/mockito.dart';

import '../../../util/test_util.dart' as util;

final Firestore firestore = FirebaseFirestoreMock();

CollectionReference collectionReference(String path) {
  return CollectionReference(ResourcePath.fromString(path), firestore);
}

DocumentReference documentReference(String path) {
  return DocumentReference(util.key(path), firestore);
}

DocumentSnapshot documentSnapshot(
    String path, Map<String, Object> data, bool isFromCache) {
  if (data == null) {
    return DocumentSnapshot.fromNoDocument(
      firestore,
      util.key(path),
      isFromCache: isFromCache,
      hasPendingWrites: false,
    );
  } else {
    return DocumentSnapshot.fromDocument(
      firestore,
      util.doc(path, 1, data),
      isFromCache: isFromCache,
      hasPendingWrites: false,
    );
  }
}

Query query(String path) {
  return Query(util.query(path), firestore);
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
  );

  return QuerySnapshot(query(path), viewSnapshot, firestore);
}

TestTargetMetadataProvider get testTargetMetadataProvider {
  final Map<int, ImmutableSortedSet<DocumentKey>> syncedKeys =
      <int, ImmutableSortedSet<DocumentKey>>{};
  final Map<int, QueryData> queryDataMap = <int, QueryData>{};

  return TestTargetMetadataProvider(
    syncedKeys,
    queryDataMap,
    getQueryDataForTarget: (int targetId) => queryDataMap[targetId],
    getRemoteKeysForTarget: (int targetId) =>
        syncedKeys[targetId] ?? DocumentKey.emptyKeySet,
  );
}

/// An implementation of [TargetMetadataProvider] that provides controlled
/// access to the [TargetMetadataProvider] callbacks. Any target accessed via
/// these callbacks must be registered beforehand via [setSyncedKeys].
class TestTargetMetadataProvider extends TargetMetadataProvider {
  TestTargetMetadataProvider(
      this.syncedKeys,
      this.queryDataMap,
      {@required
          ImmutableSortedSet<DocumentKey> Function(int targetId)
              getRemoteKeysForTarget,
      @required
          QueryData Function(int targetId) getQueryDataForTarget})
      : super(
          getRemoteKeysForTarget: getRemoteKeysForTarget,
          getQueryDataForTarget: getQueryDataForTarget,
        );

  final Map<int, ImmutableSortedSet<DocumentKey>> syncedKeys;

  final Map<int, QueryData> queryDataMap;

  /// Sets or replaces the local state for the provided query data.
  void setSyncedKeys(
      QueryData queryData, ImmutableSortedSet<DocumentKey> keys) {
    queryDataMap[queryData.targetId] = queryData;
    syncedKeys[queryData.targetId] = keys;
  }
}

class FirebaseFirestoreMock extends Mock implements Firestore {}
