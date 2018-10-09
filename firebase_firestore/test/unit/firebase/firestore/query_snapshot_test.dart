// File created by
// Lung Razvan <long1eu>
// on 28/09/2018

import 'package:firebase_firestore/src/firebase/firestore/core/document_view_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart'
    as core;
import 'package:firebase_firestore/src/firebase/firestore/core/view_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/document_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore.dart';
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
    final ObjectValue firstValue = wrapList(<dynamic>['a', 1]);
    final ObjectValue secondValue = wrapList(<dynamic>['b', 1]);

    final QuerySnapshot foo = TestUtil.querySnapshot(
        'foo', map(), map(<dynamic>['a', firstValue]), true, false);
    final QuerySnapshot fooDup = TestUtil.querySnapshot(
        'foo', map(), map(<dynamic>['a', firstValue]), true, false);
    final QuerySnapshot differentPath = TestUtil.querySnapshot(
        'bar', map(), map(<dynamic>['a', firstValue]), true, false);
    final QuerySnapshot differentDoc = TestUtil.querySnapshot(
        'foo', map(), map(<dynamic>['a', secondValue]), true, false);
    final QuerySnapshot noPendingWrites = TestUtil.querySnapshot(
        'foo', map(), map(<dynamic>['a', firstValue]), false, false);
    final QuerySnapshot fromCache = TestUtil.querySnapshot(
        'foo', map(), map(<dynamic>['a', firstValue]), true, true);

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
    final Document doc1Old = doc(
        'foo/bar',
        1,
        wrapList(<String>['a', 'b']),
        /*hasLocalMutations:*/ true);
    final Document doc1New = doc(
        'foo/bar',
        1,
        wrapList(<String>['a', 'b']),
        /*hasLocalMutations:*/
        false);

    final Document doc2Old = doc(
        'foo/baz',
        1,
        wrapList(<String>['a', 'b']),
        /*hasLocalMutations:*/
        false);
    final Document doc2New = doc(
        'foo/baz',
        1,
        wrapList(<String>['a', 'c']),
        /*hasLocalMutations:*/
        false);

    final DocumentSet oldDocuments =
        docSet(Document.keyComparator, <Document>[doc1Old, doc2Old]);
    final DocumentSet newDocuments =
        docSet(Document.keyComparator, <Document>[doc1New, doc2New]);

    final List<DocumentViewChange> documentChanges = <DocumentViewChange>[
      DocumentViewChange(DocumentViewChangeType.metadata, doc1New),
      DocumentViewChange(DocumentViewChangeType.modified, doc2New)
    ];

    final FirebaseFirestore firestore = TestUtil.firestore;
    final core.Query fooQuery = query('foo');
    final ViewSnapshot viewSnapshot = ViewSnapshot(
        fooQuery,
        newDocuments,
        oldDocuments,
        documentChanges,
        /*isFromCache:*/
        false,
        /*hasPendingWrites:*/
        false,
        /*didSyncStateChange:*/
        true);

    final QuerySnapshot snapshot =
        QuerySnapshot(Query(fooQuery, firestore), viewSnapshot, firestore);

    final QueryDocumentSnapshot doc1Snap = QueryDocumentSnapshot.fromDocument(
        firestore, doc1New, /*fromCache:*/ false);
    final QueryDocumentSnapshot doc2Snap = QueryDocumentSnapshot.fromDocument(
        firestore, doc2New, /*fromCache:*/ false);

    expect(snapshot.documentChanges.length, 1);
    final List<DocumentChange> changesWithoutMetadata = <DocumentChange>[
      DocumentChange(
          doc2Snap,
          DocumentChangeType.modified,
          /*oldIndex:*/
          1,
          /*newIndex:*/ 1)
    ];
    expect(snapshot.documentChanges, changesWithoutMetadata);

    final List<DocumentChange> changesWithMetadata = <DocumentChange>[
      DocumentChange(
          doc1Snap,
          DocumentChangeType.modified,
          /*oldIndex:*/
          0,
          /*newIndex:*/ 0),
      DocumentChange(
          doc2Snap,
          DocumentChangeType.modified,
          /*oldIndex:*/
          1,
          /*newIndex:*/ 1)
    ];
    expect(snapshot.getDocumentChanges(MetadataChanges.include),
        changesWithMetadata);
  });
}

// ignore: always_specify_types
const doc = util.TestUtil.docForValue;
// ignore: always_specify_types
const wrapList = util.TestUtil.wrapList;
// ignore: always_specify_types
const map = util.TestUtil.map;
// ignore: always_specify_types
const docSet = util.TestUtil.docSet;
// ignore: always_specify_types
const query = util.TestUtil.query;
