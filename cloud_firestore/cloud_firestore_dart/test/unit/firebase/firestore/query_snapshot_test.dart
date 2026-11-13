// File created by
// Lung Razvan <long1eu>
// on 28/09/2018

import 'package:cloud_firestore_dart/src/firebase/firestore/core/document_view_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart'
    as core;
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/metadata_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_set.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query_document_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/server_timestamp_behavior.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../util/test_util.dart' as util;
import 'test_util.dart';

void main() {
  test('testEquals', () {
    final ObjectValue firstValue = util.wrapList(<Object>['a', 1]);
    final ObjectValue secondValue = util.wrapList(<Object>['b', 1]);

    final QuerySnapshot foo = querySnapshot(
      'foo',
      util.map(),
      util.map(<dynamic>['a', firstValue]),
      true,
      false,
    );
    final QuerySnapshot fooDup = querySnapshot(
      'foo',
      util.map(),
      util.map(<dynamic>['a', firstValue]),
      true,
      false,
    );
    final QuerySnapshot differentPath = querySnapshot(
      'bar',
      util.map(),
      util.map(<dynamic>['a', firstValue]),
      true,
      false,
    );
    final QuerySnapshot differentDoc = querySnapshot(
      'foo',
      util.map(),
      util.map(<dynamic>['a', secondValue]),
      true,
      false,
    );
    final QuerySnapshot noPendingWrites = querySnapshot(
      'foo',
      util.map(),
      util.map(<dynamic>['a', firstValue]),
      false,
      false,
    );
    final QuerySnapshot fromCache = querySnapshot(
      'foo',
      util.map(),
      util.map(<dynamic>['a', firstValue]),
      true,
      true,
    );

    expect(fooDup, foo);
    expect(differentPath, isNot(foo));
    expect(differentDoc, isNot(foo));
    expect(noPendingWrites, isNot(foo));
    expect(fromCache, isNot(foo));

    // Note: `foo` and `differentDoc` have the same hash code since we no longer
    // take document contents into account.
    expect(fooDup.hashCode, foo.hashCode);
    expect(differentPath.hashCode, isNot(foo.hashCode));
    expect(noPendingWrites.hashCode, isNot(foo.hashCode));
    expect(fromCache.hashCode, isNot(foo.hashCode));
  });

  // Android's toObjects(Class, ServerTimestampBehavior) maps every document
  // to a POJO; the Dart SDK has no POJO mapping, so the port reads each
  // document's data with the same server timestamp behavior.
  test('testToObjects', () {
    final ObjectValue objectData = ObjectValue.fromMap(<String, FieldValue>{
      'timestamp': ServerTimestampValue(Timestamp.now(), null),
    });
    // The helper builds an untyped snapshot: its data are raw maps.
    final QuerySnapshot<dynamic> foo = querySnapshot(
      'foo',
      util.map(),
      util.map(<dynamic>['a', objectData]),
      true,
      false,
    );

    List<Map<String, Object?>?> docs = <Map<String, Object?>?>[
      for (final QueryDocumentSnapshot<dynamic> doc in foo.docs)
        doc.data as Map<String, Object?>?,
    ];
    expect(docs, hasLength(1));
    expect(docs[0]!['timestamp'], isNull);

    docs = <Map<String, Object?>?>[
      for (final QueryDocumentSnapshot<dynamic> doc in foo.docs)
        doc.getData(ServerTimestampBehavior.estimate) as Map<String, Object?>?,
    ];
    expect(docs, hasLength(1));
    expect(docs[0]!['timestamp'], isNotNull);
  });

  test('testIncludeMetadataChanges', () {
    final Document doc1Old = util.docForValue(
      'foo/bar',
      1,
      util.wrapList(<String>['a', 'b']),
      DocumentState.localMutations,
    );
    final Document doc1New = util.docForValue(
      'foo/bar',
      1,
      util.wrapList(<String>['a', 'b']),
      DocumentState.synced,
    );
    final Document doc2Old = util.docForValue(
      'foo/baz',
      1,
      util.wrapList(<String>['a', 'b']),
      DocumentState.synced,
    );
    final Document doc2New = util.docForValue(
      'foo/baz',
      1,
      util.wrapList(<String>['a', 'c']),
      DocumentState.synced,
    );

    final DocumentSet oldDocuments = util.docSet(
      Document.keyComparator,
      <Document>[doc1Old, doc2Old],
    );
    final DocumentSet newDocuments = util.docSet(
      Document.keyComparator,
      <Document>[doc1New, doc2New],
    );

    final List<DocumentViewChange> documentChanges = <DocumentViewChange>[
      DocumentViewChange(DocumentViewChangeType.metadata, doc1New),
      DocumentViewChange(DocumentViewChangeType.modified, doc2New),
    ];

    final core.Query fooQuery = util.query('foo');
    final ViewSnapshot viewSnapshot = ViewSnapshot(
      fooQuery,
      newDocuments,
      oldDocuments,
      documentChanges,
      util.keySet(),
      isFromCache: false,
      didSyncStateChange: true,
      excludesMetadataChanges: false,
      hasCachedResults: false,
    );

    final QuerySnapshot snapshot = QuerySnapshotInternal.create(
      QueryInternal.create(fooQuery, firestore),
      viewSnapshot,
      firestore,
    );

    final QueryDocumentSnapshot doc1Snap =
        QueryDocumentSnapshotInternal.fromDocument(
          firestore,
          doc1New,
          fromCache: false,
          hasPendingWrites: false,
        );
    final QueryDocumentSnapshot doc2Snap =
        QueryDocumentSnapshotInternal.fromDocument(
          firestore,
          doc2New,
          fromCache: false,
          hasPendingWrites: false,
        );

    expect(snapshot.documentChanges.length, 1);
    final List<DocumentChange> changesWithoutMetadata = <DocumentChange>[
      DocumentChangeInternal.create(
        doc2Snap,
        DocumentChangeType.modified,
        1 /*oldIndex*/,
        1 /*newIndex*/,
      ),
    ];
    expect(snapshot.documentChanges, changesWithoutMetadata);

    final List<DocumentChange> changesWithMetadata = <DocumentChange>[
      DocumentChangeInternal.create(
        doc1Snap,
        DocumentChangeType.modified,
        0 /*oldIndex*/,
        0 /*newIndex*/,
      ),
      DocumentChangeInternal.create(
        doc2Snap,
        DocumentChangeType.modified,
        1 /*oldIndex*/,
        1 /*newIndex*/,
      ),
    ];
    expect(
      snapshot.getDocumentChanges(MetadataChanges.include),
      changesWithMetadata,
    );
  });
}
