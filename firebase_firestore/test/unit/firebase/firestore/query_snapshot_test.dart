// File created by
// Lung Razvan <long1eu>
// on 28/09/2018

import 'package:firebase_firestore/src/firebase/firestore/core/document_view_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart'
    as core;
import 'package:firebase_firestore/src/firebase/firestore/core/view_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/document_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/metadata_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_set.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/object_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/query_document_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/query_snapshot.dart';
import 'package:test/test.dart';

import '../../../util/test_util.dart' as util;
import 'test_util.dart';

void main() {
  test('testEquals', () {
    final ObjectValue firstValue = util.wrapList(<dynamic>['a', 1]);
    final ObjectValue secondValue = util.wrapList(<dynamic>['b', 1]);

    final QuerySnapshot foo = querySnapshot(
        'foo', util.map(), util.map(<dynamic>['a', firstValue]), true, false);
    final QuerySnapshot fooDup = querySnapshot(
        'foo', util.map(), util.map(<dynamic>['a', firstValue]), true, false);
    final QuerySnapshot differentPath = querySnapshot(
        'bar', util.map(), util.map(<dynamic>['a', firstValue]), true, false);
    final QuerySnapshot differentDoc = querySnapshot(
        'foo', util.map(), util.map(<dynamic>['a', secondValue]), true, false);
    final QuerySnapshot noPendingWrites = querySnapshot(
        'foo', util.map(), util.map(<dynamic>['a', firstValue]), false, false);
    final QuerySnapshot fromCache = querySnapshot(
        'foo', util.map(), util.map(<dynamic>['a', firstValue]), true, true);

    expect(fooDup, foo);
    expect(differentPath, isNot(foo));
    expect(differentDoc, isNot(foo));
    expect(noPendingWrites, isNot(foo));
    expect(fromCache, isNot(foo));

    expect(fooDup.hashCode, foo.hashCode);
    expect(differentPath.hashCode, isNot(foo.hashCode));
    expect(differentDoc.hashCode, isNot(foo.hashCode));
    expect(noPendingWrites.hashCode, isNot(foo.hashCode));
    expect(fromCache.hashCode, isNot(foo.hashCode));
  });

  test('testIncludeMetadataChanges', () {
    final Document doc1Old = util.docForValue('foo/bar', 1,
        util.wrapList(<String>['a', 'b']), DocumentState.localMutations);
    final Document doc1New = util.docForValue(
        'foo/bar', 1, util.wrapList(<String>['a', 'b']), DocumentState.synced);
    final Document doc2Old = util.docForValue(
        'foo/baz', 1, util.wrapList(<String>['a', 'b']), DocumentState.synced);
    final Document doc2New = util.docForValue(
        'foo/baz', 1, util.wrapList(<String>['a', 'c']), DocumentState.synced);

    final DocumentSet oldDocuments =
        util.docSet(Document.keyComparator, <Document>[doc1Old, doc2Old]);
    final DocumentSet newDocuments =
        util.docSet(Document.keyComparator, <Document>[doc1New, doc2New]);

    final List<DocumentViewChange> documentChanges = <DocumentViewChange>[
      DocumentViewChange(DocumentViewChangeType.metadata, doc1New),
      DocumentViewChange(DocumentViewChangeType.modified, doc2New)
    ];

    final core.Query fooQuery = util.query('foo');
    final ViewSnapshot viewSnapshot = ViewSnapshot(
      fooQuery,
      newDocuments,
      oldDocuments,
      documentChanges,
      false /*isFromCache*/,
      util.keySet(),
      true /*didSyncStateChange*/,
      false /*excludesMetadataChanges*/,
    );

    final QuerySnapshot snapshot =
        QuerySnapshot(Query(fooQuery, firestore), viewSnapshot, firestore);

    final QueryDocumentSnapshot doc1Snap = QueryDocumentSnapshot.fromDocument(
      firestore,
      doc1New,
      false /*fromCache*/,
      false /*keySet*/,
    );
    final QueryDocumentSnapshot doc2Snap = QueryDocumentSnapshot.fromDocument(
      firestore,
      doc2New,
      false /*fromCache*/,
      false /*keySet*/,
    );

    expect(snapshot.documentChanges.length, 1);
    final List<DocumentChange> changesWithoutMetadata = <DocumentChange>[
      DocumentChange(
        doc2Snap,
        DocumentChangeType.modified,
        1 /*oldIndex*/,
        1 /*newIndex*/,
      )
    ];
    expect(snapshot.documentChanges, changesWithoutMetadata);

    final List<DocumentChange> changesWithMetadata = <DocumentChange>[
      DocumentChange(
        doc1Snap,
        DocumentChangeType.modified,
        0 /*oldIndex*/,
        0 /*newIndex*/,
      ),
      DocumentChange(
        doc2Snap,
        DocumentChangeType.modified,
        1 /*oldIndex*/,
        1 /*newIndex*/,
      )
    ];
    expect(snapshot.getDocumentChanges(MetadataChanges.include),
        changesWithMetadata);
  });
}
