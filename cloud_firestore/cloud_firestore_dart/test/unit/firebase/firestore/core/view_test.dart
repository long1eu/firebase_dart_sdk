// File created by
// Lung Razvan <long1eu>
// on 27/09/2018

import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/document_view_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/limbo_document_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/no_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/target_change.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

void main() {
  Query messageQuery() {
    return Query(ResourcePath.fromString('rooms/eros/messages'));
  }

  ViewChange applyChanges(
    View view, [
    List<MaybeDocument> docs = const <MaybeDocument>[],
  ]) {
    return view.applyChanges(view.computeDocChanges(docUpdates(docs)));
  }

  test('testAddsDocumentsBasedOnQuery', () {
    final Query query = messageQuery();
    final View view = View(query, DocumentKey.emptyKeySet);

    final Document doc1 = doc(
      'rooms/eros/messages/1',
      0,
      map(<String>['text', 'msg1']),
    );
    final Document doc2 = doc(
      'rooms/eros/messages/2',
      0,
      map(<String>['text', 'msg2']),
    );
    final Document doc3 = doc(
      'rooms/other/messages/1',
      0,
      map(<String>['text', 'msg3']),
    );

    final ImmutableSortedMap<DocumentKey, Document> updates = docUpdates(
      <Document>[doc1, doc2, doc3],
    );
    final ViewDocumentChanges docViewChanges = view.computeDocChanges(updates);
    final TargetChange targetChange = ackTarget(<Document>[doc1, doc2, doc3]);
    final ViewSnapshot snapshot = view
        .applyChanges(docViewChanges, targetChange)
        .snapshot!;
    expect(snapshot!.query, query);
    expect(snapshot!.documents.toList(), <Document>[doc1, doc2]);
    expect(snapshot!.changes, <DocumentViewChange>[
      DocumentViewChange(DocumentViewChangeType.added, doc1),
      DocumentViewChange(DocumentViewChangeType.added, doc2),
    ]);
    expect(snapshot!.isFromCache, isFalse);
    expect(snapshot!.didSyncStateChange, isTrue);
    expect(snapshot!.hasPendingWrites, isFalse);
  });

  test('testRemovesDocument', () {
    final Query query = messageQuery();
    final View view = View(query, DocumentKey.emptyKeySet);

    final Document doc1 = doc(
      'rooms/eros/messages/1',
      0,
      map(<String>['text', 'msg1']),
    );
    final Document doc2 = doc(
      'rooms/eros/messages/2',
      0,
      map(<String>['text', 'msg2']),
    );
    final Document doc3 = doc(
      'rooms/eros/messages/3',
      0,
      map(<String>['text', 'msg3']),
    );

    // initial state
    applyChanges(view, <Document>[doc1, doc2]);

    // delete doc2, add doc3
    final ViewSnapshot snapshot = view
        .applyChanges(
          view.computeDocChanges(
            docUpdates(<MaybeDocument>[
              deletedDoc('rooms/eros/messages/2', 0),
              doc3,
            ]),
          ),
          ackTarget(<Document>[doc1, doc3]),
        )
        .snapshot!;

    expect(snapshot!.query, query);
    expect(snapshot!.documents.toList(), <Document>[doc1, doc3]);
    expect(snapshot!.changes, <DocumentViewChange>[
      DocumentViewChange(DocumentViewChangeType.removed, doc2),
      DocumentViewChange(DocumentViewChangeType.added, doc3),
    ]);
    expect(snapshot!.isFromCache, isFalse);
    expect(snapshot!.didSyncStateChange, isTrue);
  });

  test('testReturnsNilIfNoChange', () {
    final Query query = messageQuery();
    final View view = View(query, DocumentKey.emptyKeySet);

    final Document doc1 = doc(
      'rooms/eros/messages/1',
      0,
      map(<String>['text', 'msg1']),
    );
    final Document doc2 = doc(
      'rooms/eros/messages/2',
      0,
      map(<String>['text', 'msg2']),
    );

    // initial state
    applyChanges(view, <Document>[doc1, doc2]);

    final ViewSnapshot? snapshot = applyChanges(view, <Document>[
      doc1,
      doc2,
    ]).snapshot;
    expect(snapshot, isNull);
  });

  test('testReturnsNotNilForFirstChanges', () {
    final Query query = messageQuery();
    final View view = View(query, DocumentKey.emptyKeySet);

    // initial state
    expect(applyChanges(view).snapshot, isNotNull);
  });

  test('testFiltersDocumentsBasedOnQueryWithFilters', () {
    final Query query = messageQuery().filter(filter('sort', '<=', 2));
    final View view = View(query, DocumentKey.emptyKeySet);

    final Document doc1 = doc(
      'rooms/eros/messages/1',
      0,
      map(<dynamic>['sort', 1]),
    );
    final Document doc2 = doc(
      'rooms/eros/messages/2',
      0,
      map(<dynamic>['sort', 2]),
    );
    final Document doc3 = doc(
      'rooms/eros/messages/3',
      0,
      map(<dynamic>['sort', 3]),
    );
    final Document doc4 = doc(
      'rooms/eros/messages/4',
      0,
      map(),
    ); // no sort, no match
    final Document doc5 = doc(
      'rooms/eros/messages/5',
      0,
      map(<dynamic>['sort', 1]),
    );

    final ViewSnapshot snapshot = applyChanges(view, <Document>[
      doc1,
      doc2,
      doc3,
      doc4,
      doc5,
    ]).snapshot!;

    expect(snapshot!.query, query);
    expect(snapshot!.documents.toList(), <Document>[doc1, doc5, doc2]);
    expect(snapshot!.changes, <DocumentViewChange>[
      DocumentViewChange(DocumentViewChangeType.added, doc1),
      DocumentViewChange(DocumentViewChangeType.added, doc5),
      DocumentViewChange(DocumentViewChangeType.added, doc2),
    ]);
    expect(snapshot!.isFromCache, isTrue);
    expect(snapshot!.didSyncStateChange, isTrue);
  });

  test('testUpdatesDocumentsBasedOnQueryWithFilters', () {
    final Query query = messageQuery().filter(filter('sort', '<=', 2));
    final View view = View(query, DocumentKey.emptyKeySet);

    final Document doc1 = doc(
      'rooms/eros/messages/1',
      0,
      map(<dynamic>['sort', 1]),
    );
    final Document doc2 = doc(
      'rooms/eros/messages/2',
      0,
      map(<dynamic>['sort', 3]),
    );
    final Document doc3 = doc(
      'rooms/eros/messages/3',
      0,
      map(<dynamic>['sort', 2]),
    );
    final Document doc4 = doc('rooms/eros/messages/4', 0, map());

    ViewSnapshot snapshot = applyChanges(view, <Document>[
      doc1,
      doc2,
      doc3,
      doc4,
    ]).snapshot!;

    expect(snapshot!.query, query);
    expect(snapshot!.documents.toList(), <Document>[doc1, doc3]);

    final Document newDoc2 = doc(
      'rooms/eros/messages/2',
      1,
      map(<dynamic>['sort', 2]),
    );
    final Document newDoc3 = doc(
      'rooms/eros/messages/3',
      1,
      map(<dynamic>['sort', 3]),
    );
    final Document newDoc4 = doc(
      'rooms/eros/messages/4',
      1,
      map(<dynamic>['sort', 0]),
    );

    snapshot = applyChanges(view, <Document>[
      newDoc2,
      newDoc3,
      newDoc4,
    ]).snapshot!;

    expect(snapshot!.query, query);
    expect(snapshot!.documents.toList(), <Document>[newDoc4, doc1, newDoc2]);

    expect(snapshot!.changes, <DocumentViewChange>[
      DocumentViewChange(DocumentViewChangeType.removed, doc3),
      DocumentViewChange(DocumentViewChangeType.added, newDoc4),
      DocumentViewChange(DocumentViewChangeType.added, newDoc2),
    ]);
    expect(snapshot!.isFromCache, isTrue);
    expect(snapshot!.didSyncStateChange, isFalse);
  });

  test('testRemovesDocumentsForQueryWithLimit', () {
    final Query query = messageQuery().limit(2);
    final View view = View(query, DocumentKey.emptyKeySet);

    final Document doc1 = doc(
      'rooms/eros/messages/1',
      0,
      map(<String>['text', 'msg1']),
    );
    final Document doc2 = doc(
      'rooms/eros/messages/2',
      0,
      map(<String>['text', 'msg2']),
    );
    final Document doc3 = doc(
      'rooms/eros/messages/3',
      0,
      map(<String>['text', 'msg3']),
    );

    // initial state
    applyChanges(view, <Document>[doc1, doc3]);

    final ViewSnapshot snapshot = view
        .applyChanges(
          view.computeDocChanges(docUpdates(<Document>[doc2])),
          ackTarget(<Document>[doc1, doc2, doc3]),
        )
        .snapshot!;
    expect(snapshot!.query, query);
    expect(snapshot!.documents.toList(), <Document>[doc1, doc2]);

    expect(snapshot!.changes, <DocumentViewChange>[
      DocumentViewChange(DocumentViewChangeType.removed, doc3),
      DocumentViewChange(DocumentViewChangeType.added, doc2),
    ]);
    expect(snapshot!.isFromCache, isFalse);
    expect(snapshot!.didSyncStateChange, isTrue);
  });

  test('testDoesNotReportChangesForDocumentBeyondLimit', () {
    final Query query = messageQuery().orderBy(orderBy('num')).limit(2);
    final View view = View(query, DocumentKey.emptyKeySet);

    final Document doc1 = doc(
      'rooms/eros/messages/1',
      0,
      map(<dynamic>['num', 1]),
    );
    Document doc2 = doc('rooms/eros/messages/2', 0, map(<dynamic>['num', 2]));
    final Document doc3 = doc(
      'rooms/eros/messages/3',
      0,
      map(<dynamic>['num', 3]),
    );
    final Document doc4 = doc(
      'rooms/eros/messages/4',
      0,
      map(<dynamic>['num', 4]),
    );

    applyChanges(view, <Document>[doc1, doc2]);

    // change doc2 to 5, and add doc3 and doc4.
    // doc2 will be modified + removed = removed
    // doc3 will be added
    // doc4 will be added + removed = nothing
    doc2 = doc('rooms/eros/messages/2', 1, map(<dynamic>['num', 5]));
    ViewDocumentChanges viewDocChanges = view.computeDocChanges(
      docUpdates(<Document>[doc2, doc3, doc4]),
    );
    expect(viewDocChanges.needsRefill, isTrue);
    // Verify that all the docs still match.
    viewDocChanges = view.computeDocChanges(
      docUpdates(<Document>[doc1, doc2, doc3, doc4]),
      viewDocChanges,
    );
    final ViewSnapshot snapshot = view
        .applyChanges(
          viewDocChanges,
          ackTarget(<Document>[doc1, doc2, doc3, doc4]),
        )
        .snapshot!;

    expect(snapshot!.query, query);
    expect(snapshot!.documents.toList(), <Document>[doc1, doc3]);

    expect(snapshot!.changes, <DocumentViewChange>[
      DocumentViewChange(DocumentViewChangeType.removed, doc2),
      DocumentViewChange(DocumentViewChangeType.added, doc3),
    ]);
    expect(snapshot!.isFromCache, isFalse);
    expect(snapshot!.didSyncStateChange, isTrue);
  });

  test('testKeepsTrackOfLimboDocuments', () {
    final Query query = messageQuery();
    final View view = View(query, DocumentKey.emptyKeySet);
    final Document doc1 = doc('rooms/eros/messages/0', 0, map());
    final Document doc2 = doc('rooms/eros/messages/1', 0, map());
    final Document doc3 = doc('rooms/eros/messages/2', 0, map());

    ViewChange change = applyChanges(view, <Document>[doc1]);
    expect(change.limboChanges.isEmpty, isTrue);

    ViewDocumentChanges viewDocChanges = view.computeDocChanges(docUpdates());
    change = view.applyChanges(viewDocChanges, ackTarget());
    expect(change.limboChanges, <LimboDocumentChange>[
      LimboDocumentChange(LimboDocumentChangeType.added, doc1.key),
    ]);

    viewDocChanges = view.computeDocChanges(docUpdates());
    change = view.applyChanges(
      viewDocChanges,
      targetChange(
        Uint8List.fromList(<int>[]),
        <Document>[doc1],
        null,
        null,
        current: true,
      ),
    );
    expect(change.limboChanges, <LimboDocumentChange>[
      LimboDocumentChange(LimboDocumentChangeType.removed, doc1.key),
    ]);

    viewDocChanges = view.computeDocChanges(docUpdates(<Document>[doc2]));
    change = view.applyChanges(
      viewDocChanges,
      targetChange(
        Uint8List.fromList(<int>[]),
        <Document>[doc2],
        null,
        null,
        current: true,
      ),
    );
    expect(change.limboChanges, isEmpty);

    change = applyChanges(view, <Document>[doc3]);
    expect(change.limboChanges, <LimboDocumentChange>[
      LimboDocumentChange(LimboDocumentChangeType.added, doc3.key),
    ]);

    change = applyChanges(view, <NoDocument>[
      deletedDoc('rooms/eros/messages/2', 1),
    ]);
    expect(change.limboChanges, <LimboDocumentChange>[
      LimboDocumentChange(LimboDocumentChangeType.removed, doc3.key),
    ]);
  });

  test('testViewsWithLimboDocumentsAreMarkedFromCache', () {
    final Query query = messageQuery();
    final View view = View(query, DocumentKey.emptyKeySet);
    final Document doc1 = doc('rooms/eros/messages/0', 0, map());
    final Document doc2 = doc('rooms/eros/messages/1', 0, map());

    // Doc1 is contained in the local view, but we are not yet CURRENT so it is
    // expected that the backend hasn't told us about all documents yet.
    ViewChange change = view.applyChanges(
      view.computeDocChanges(docUpdates(<Document>[doc1])),
    );
    expect(change.snapshot!.isFromCache, isTrue);

    // Add doc2 to generate a snapshot. Doc1 is still missing.
    final ViewDocumentChanges viewDocChanges = view.computeDocChanges(
      docUpdates(<Document>[doc2]),
    );
    change = view.applyChanges(
      viewDocChanges,
      targetChange(Uint8List(0), <Document>[doc2], null, null, current: true),
    );
    // We are CURRENT but doc1 is in limbo.
    expect(change.snapshot!.isFromCache, isTrue);

    // Add doc1 to the backend's result set.
    change = view.applyChanges(
      viewDocChanges,
      targetChange(Uint8List(0), <Document>[doc1], null, null, current: true),
    );
    expect(change.snapshot!.isFromCache, isFalse);
  });

  test('testResumingQueryCreatesNoLimbos', () {
    final Query query = messageQuery();
    final Document doc1 = doc('rooms/eros/messages/0', 0, map());
    final Document doc2 = doc('rooms/eros/messages/1', 0, map());

    // Unlike other cases, here the view is initialized with a set of previously synced documents which happens when
    // listening to a previously listened-to query.
    final View view = View(query, keySet(<DocumentKey>[doc1.key, doc2.key]));

    final TargetChange markCurrent = ackTarget();
    final ViewDocumentChanges changes = view.computeDocChanges(docUpdates());
    final ViewChange change = view.applyChanges(changes, markCurrent);
    expect(change.limboChanges, isEmpty);
  });

  test('testPendingResetCreatesNoLimbosAndIsNotSynced', () {
    final Query query = messageQuery();
    final Document doc1 = doc('rooms/eros/messages/0', 0, map());

    // doc1 is only in the local cache: once the target is current it would be treated as a limbo document. While the
    // target is pending a reset (existence filter mismatch) that must not happen and the view must not be synced.
    final View view = View(query, DocumentKey.emptyKeySet);
    final ViewChange change = view.applyChanges(
      view.computeDocChanges(docUpdates(<Document>[doc1])),
      ackTarget(),
      true,
    );

    expect(change.limboChanges, isEmpty);
    expect(change.snapshot!.isFromCache, isTrue);

    // Without the pending reset the same state does resolve doc1 as limbo.
    final ViewChange next = view.applyChanges(
      view.computeDocChanges(docUpdates()),
      ackTarget(),
    );
    expect(next.limboChanges, <LimboDocumentChange>[
      LimboDocumentChange(LimboDocumentChangeType.added, doc1.key),
    ]);
  });

  test('testReturnsNeedsRefillOnDeleteInLimitQuery', () {
    final Query query = messageQuery().limit(2);
    final Document doc1 = doc('rooms/eros/messages/0', 0, map());
    final Document doc2 = doc('rooms/eros/messages/1', 0, map());
    final View view = View(query, DocumentKey.emptyKeySet);

    // Start with a full view.
    ViewDocumentChanges changes = view.computeDocChanges(
      docUpdates(<Document>[doc1, doc2]),
    );
    expect(changes.documentSet.length, 2);
    expect(changes.needsRefill, isFalse);
    expect(changes.changeSet.changes.length, 2);
    view.applyChanges(changes);

    // Remove one of the docs.
    changes = view.computeDocChanges(
      docUpdates(<NoDocument>[deletedDoc('rooms/eros/messages/0', 0)]),
    );
    expect(changes.documentSet.length, 1);
    expect(changes.needsRefill, isTrue);
    expect(changes.changeSet.changes.length, 1);
    // Refill it with just the one doc remaining.
    changes = view.computeDocChanges(docUpdates(<Document>[doc2]), changes);
    expect(changes.documentSet.length, 1);
    expect(changes.needsRefill, isFalse);
    expect(changes.changeSet.changes.length, 1);
    view.applyChanges(changes);
  });

  test('testReturnsNeedsRefillOnReorderInLimitQuery', () {
    final Query query = messageQuery().orderBy(orderBy('order')).limit(2);
    final Document doc1 = doc(
      'rooms/eros/messages/0',
      0,
      map(<dynamic>['order', 1]),
    );
    Document doc2 = doc('rooms/eros/messages/1', 0, map(<dynamic>['order', 2]));
    final Document doc3 = doc(
      'rooms/eros/messages/2',
      0,
      map(<dynamic>['order', 3]),
    );
    final View view = View(query, DocumentKey.emptyKeySet);

    // Start with a full view.
    ViewDocumentChanges changes = view.computeDocChanges(
      docUpdates(<Document>[doc1, doc2, doc3]),
    );
    expect(changes.documentSet.length, 2);
    expect(changes.needsRefill, isFalse);
    expect(changes.changeSet.changes.length, 2);
    view.applyChanges(changes);

    // Move one of the docs.
    doc2 = doc('rooms/eros/messages/1', 1, map(<dynamic>['order', 2000]));
    changes = view.computeDocChanges(docUpdates(<Document>[doc2]));
    expect(changes.documentSet.length, 2);
    expect(changes.needsRefill, isTrue);
    expect(changes.changeSet.changes.length, 1);
    // Refill it with all three current docs.
    changes = view.computeDocChanges(
      docUpdates(<Document>[doc1, doc2, doc3]),
      changes,
    );
    expect(changes.documentSet.length, 2);
    expect(changes.needsRefill, isFalse);
    expect(changes.changeSet.changes.length, 2);
    view.applyChanges(changes);
  });

  test('testDoesNotNeedRefillOnReorderWithinLimit', () {
    final Query query = messageQuery().orderBy(orderBy('order')).limit(3);
    Document doc1 = doc('rooms/eros/messages/0', 0, map(<dynamic>['order', 1]));
    final Document doc2 = doc(
      'rooms/eros/messages/1',
      0,
      map(<dynamic>['order', 2]),
    );
    final Document doc3 = doc(
      'rooms/eros/messages/2',
      0,
      map(<dynamic>['order', 3]),
    );
    final Document doc4 = doc(
      'rooms/eros/messages/3',
      0,
      map(<dynamic>['order', 4]),
    );
    final Document doc5 = doc(
      'rooms/eros/messages/4',
      0,
      map(<dynamic>['order', 5]),
    );
    final View view = View(query, DocumentKey.emptyKeySet);

    // Start with a full view.
    ViewDocumentChanges changes = view.computeDocChanges(
      docUpdates(<Document>[doc1, doc2, doc3, doc4, doc5]),
    );
    expect(changes.documentSet.length, 3);
    expect(changes.needsRefill, isFalse);
    expect(changes.changeSet.changes.length, 3);
    view.applyChanges(changes);

    // Move one of the docs.
    doc1 = doc('rooms/eros/messages/0', 1, map(<dynamic>['order', 3]));
    changes = view.computeDocChanges(docUpdates(<Document>[doc1]));
    expect(changes.documentSet.length, 3);
    expect(changes.needsRefill, isFalse);
    expect(changes.changeSet.changes.length, 1);
    view.applyChanges(changes);
  });

  test('testDoesNotNeedRefillOnReorderAfterLimitQuery', () {
    final Query query = messageQuery().orderBy(orderBy('order')).limit(3);
    final Document doc1 = doc(
      'rooms/eros/messages/0',
      0,
      map(<dynamic>['order', 1]),
    );
    final Document doc2 = doc(
      'rooms/eros/messages/1',
      0,
      map(<dynamic>['order', 2]),
    );
    final Document doc3 = doc(
      'rooms/eros/messages/2',
      0,
      map(<dynamic>['order', 3]),
    );
    Document doc4 = doc('rooms/eros/messages/3', 0, map(<dynamic>['order', 4]));
    final Document doc5 = doc(
      'rooms/eros/messages/4',
      0,
      map(<dynamic>['order', 5]),
    );
    final View view = View(query, DocumentKey.emptyKeySet);

    // Start with a full view.
    ViewDocumentChanges changes = view.computeDocChanges(
      docUpdates(<Document>[doc1, doc2, doc3, doc4, doc5]),
    );
    expect(changes.documentSet.length, 3);
    expect(changes.needsRefill, isFalse);
    expect(changes.changeSet.changes.length, 3);
    view.applyChanges(changes);

    // Move one of the docs.
    doc4 = doc('rooms/eros/messages/3', 1, map(<dynamic>['order', 6]));
    changes = view.computeDocChanges(docUpdates(<Document>[doc4]));
    expect(changes.documentSet.length, 3);
    expect(changes.needsRefill, isFalse);
    expect(changes.changeSet.changes, isEmpty);
    view.applyChanges(changes);
  });

  test('testDoesNotNeedRefillForAdditionAfterTheLimit', () {
    final Query query = messageQuery().limit(2);
    final Document doc1 = doc('rooms/eros/messages/0', 0, map());
    final Document doc2 = doc('rooms/eros/messages/1', 0, map());
    final View view = View(query, DocumentKey.emptyKeySet);

    // Start with a full view.
    ViewDocumentChanges changes = view.computeDocChanges(
      docUpdates(<Document>[doc1, doc2]),
    );
    expect(changes.documentSet.length, 2);
    expect(changes.needsRefill, isFalse);
    expect(changes.changeSet.changes.length, 2);
    view.applyChanges(changes);

    // Add a doc that is past the limit.
    changes = view.computeDocChanges(
      docUpdates(<NoDocument>[deletedDoc('rooms/eros/messages/2', 0)]),
    );
    expect(changes.documentSet.length, 2);
    expect(changes.needsRefill, isFalse);
    expect(changes.changeSet.changes, isEmpty);
    view.applyChanges(changes);
  });

  test('testDoesNotNeedRefillForDeletionsWhenNotNearTheLimit', () {
    final Query query = messageQuery().limit(20);
    final Document doc1 = doc('rooms/eros/messages/0', 0, map());
    final Document doc2 = doc('rooms/eros/messages/1', 0, map());
    final View view = View(query, DocumentKey.emptyKeySet);

    ViewDocumentChanges changes = view.computeDocChanges(
      docUpdates(<Document>[doc1, doc2]),
    );
    expect(changes.documentSet.length, 2);
    expect(changes.needsRefill, isFalse);
    expect(changes.changeSet.changes.length, 2);
    view.applyChanges(changes);

    // Remove one of the docs.
    changes = view.computeDocChanges(
      docUpdates(<NoDocument>[deletedDoc('rooms/eros/messages/1', 0)]),
    );
    expect(changes.documentSet.length, 1);
    expect(changes.needsRefill, isFalse);
    expect(changes.changeSet.changes.length, 1);
    view.applyChanges(changes);
  });

  test('testHandlesApplyingIrrelevantDocs', () {
    final Query query = messageQuery().limit(2);
    final Document doc1 = doc('rooms/eros/messages/0', 0, map());
    final Document doc2 = doc('rooms/eros/messages/1', 0, map());
    final View view = View(query, DocumentKey.emptyKeySet);

    // Start with a full view.
    ViewDocumentChanges changes = view.computeDocChanges(
      docUpdates(<Document>[doc1, doc2]),
    );
    expect(changes.documentSet.length, 2);
    expect(changes.needsRefill, isFalse);
    expect(changes.changeSet.changes.length, 2);
    view.applyChanges(changes);

    // Remove a doc that isn't even in the results.
    changes = view.computeDocChanges(
      docUpdates(<NoDocument>[deletedDoc('rooms/eros/messages/2', 0)]),
    );
    expect(changes.documentSet.length, 2);
    expect(changes.needsRefill, isFalse);
    expect(changes.changeSet.changes.length, 0);
    view.applyChanges(changes);
  });

  test('testComputesMutatedDocumentKeys', () {
    final Query query = messageQuery();
    final Document doc1 = doc('rooms/eros/messages/0', 0, map());
    final Document doc2 = doc('rooms/eros/messages/1', 0, map());
    final View view = View(query, DocumentKey.emptyKeySet);

    // Start with a full view.
    ViewDocumentChanges changes = view.computeDocChanges(
      docUpdates(<Document>[doc1, doc2]),
    );
    view.applyChanges(changes);
    expect(changes.mutatedKeys, keySet());

    final Document doc3 = doc(
      'rooms/eros/messages/2',
      0,
      map(),
      DocumentState.localMutations,
    );
    changes = view.computeDocChanges(docUpdates(<Document>[doc3]));
    view.applyChanges(changes);
    expect(changes.mutatedKeys, keySet(<DocumentKey>[doc3.key]));
  });

  test(
    'testRemovesKeysFromMutatedDocumentKeysWhenNewDocDoesNotHaveChanges',
    () {
      final Query query = messageQuery().limit(2);
      final Document doc1 = doc('rooms/eros/messages/0', 0, map());
      final Document doc2 = doc(
        'rooms/eros/messages/1',
        0,
        map(),
        DocumentState.localMutations,
      );
      final View view = View(query, DocumentKey.emptyKeySet);

      // Start with a full view.
      ViewDocumentChanges changes = view.computeDocChanges(
        docUpdates(<Document>[doc1, doc2]),
      );
      view.applyChanges(changes);
      expect(changes.mutatedKeys, keySet(<DocumentKey>[doc2.key]));

      final Document doc2Prime = doc('rooms/eros/messages/1', 0, map());

      changes = view.computeDocChanges(docUpdates(<Document>[doc2Prime]));
      view.applyChanges(changes);
      expect(changes.mutatedKeys, keySet());
    },
  );

  test('testRemembersLocalMutationsFromPreviousSnapshot', () {
    final Query query = messageQuery().limit(2);
    final Document doc1 = doc('rooms/eros/messages/0', 0, map());
    final Document doc2 = doc(
      'rooms/eros/messages/1',
      0,
      map(),
      DocumentState.localMutations,
    );
    final View view = View(query, DocumentKey.emptyKeySet);

    // Start with a full view.
    ViewDocumentChanges changes = view.computeDocChanges(
      docUpdates(<Document>[doc1, doc2]),
    );
    view.applyChanges(changes);
    expect(changes.mutatedKeys, keySet(<DocumentKey>[doc2.key]));

    final Document doc3 = doc('rooms/eros/messages/2', 0, map());
    changes = view.computeDocChanges(docUpdates(<Document>[doc3]));
    expect(changes.mutatedKeys, keySet(<DocumentKey>[doc2.key]));
  });

  test('testRemembersLocalMutationsFromPreviousCallToComputeChanges', () {
    final Query query = messageQuery().limit(2);
    final Document doc1 = doc('rooms/eros/messages/0', 0, map());
    final Document doc2 = doc(
      'rooms/eros/messages/1',
      0,
      map(),
      DocumentState.localMutations,
    );
    final View view = View(query, DocumentKey.emptyKeySet);

    // Start with a full view.
    ViewDocumentChanges changes = view.computeDocChanges(
      docUpdates(<Document>[doc1, doc2]),
    );
    expect(changes.mutatedKeys, keySet(<DocumentKey>[doc2.key]));

    final Document doc3 = doc('rooms/eros/messages/2', 0, map());
    changes = view.computeDocChanges(docUpdates(<Document>[doc3]), changes);
    expect(changes.mutatedKeys, keySet(<DocumentKey>[doc2.key]));
  });

  test('testRaisesHasPendingWritesForPendingMutationsInInitialSnapshot', () {
    final Query query = messageQuery();
    final Document doc1 = doc(
      'rooms/eros/messages/1',
      0,
      map(),
      DocumentState.localMutations,
    );
    final View view = View(query, DocumentKey.emptyKeySet);

    final ViewDocumentChanges changes = view.computeDocChanges(
      docUpdates(<MaybeDocument>[doc1]),
    );
    final ViewChange viewChange = view.applyChanges(changes);

    expect(viewChange.snapshot!.hasPendingWrites, isTrue);
  });

  test(
    'testDoesntRaiseHasPendingWritesForCommittedMutationsInInitialSnapshot',
    () {
      final Query query = messageQuery();
      final Document doc1 = doc(
        'rooms/eros/messages/1',
        0,
        map(),
        DocumentState.committedMutations,
      );
      final View view = View(query, DocumentKey.emptyKeySet);

      final ViewDocumentChanges changes = view.computeDocChanges(
        docUpdates(<MaybeDocument>[doc1]),
      );
      final ViewChange viewChange = view.applyChanges(changes);

      expect(viewChange.snapshot!.hasPendingWrites, isFalse);
    },
  );

  test('testSuppressesWriteAcknowledgementIfWatchHasNotCaughtUp', () {
    // This test verifies that we don't get three events for a ServerTimestamp
    // mutation. We suppress the event generated by the write acknowledgement
    // and instead wait for Watch to catch up.
    final Query query = messageQuery();

    final Document doc1 = doc(
      'rooms/eros/messages/1',
      1,
      map(<dynamic>['time', 1]),
      DocumentState.localMutations,
    );
    final Document doc1Committed = doc(
      'rooms/eros/messages/1',
      2,
      map(<dynamic>['time', 2]),
      DocumentState.committedMutations,
    );
    final Document doc1Acknowledged = doc(
      'rooms/eros/messages/1',
      2,
      map(<dynamic>['time', 2]),
      DocumentState.synced,
    );

    final Document doc2 = doc(
      'rooms/eros/messages/2',
      1,
      map(<dynamic>['time', 1]),
      DocumentState.localMutations,
    );
    final Document doc2Modified = doc(
      'rooms/eros/messages/2',
      2,
      map(<dynamic>['time', 3]),
      DocumentState.localMutations,
    );
    final Document doc2Acknowledged = doc(
      'rooms/eros/messages/2',
      2,
      map(<dynamic>['time', 3]),
      DocumentState.synced,
    );

    final View view = View(query, DocumentKey.emptyKeySet);

    ViewDocumentChanges changes = view.computeDocChanges(
      docUpdates(<Document>[doc1, doc2]),
    );
    ViewChange snap = view.applyChanges(changes);

    expect(snap.snapshot!.changes, <DocumentViewChange>[
      DocumentViewChange(DocumentViewChangeType.added, doc1),
      DocumentViewChange(DocumentViewChangeType.added, doc2),
    ]);

    changes = view.computeDocChanges(
      docUpdates(<Document>[doc1Committed, doc2Modified]),
    );
    snap = view.applyChanges(changes);

    // The 'doc1Committed' update is suppressed
    expect(snap.snapshot!.changes, <DocumentViewChange>[
      DocumentViewChange(DocumentViewChangeType.modified, doc2Modified),
    ]);

    changes = view.computeDocChanges(
      docUpdates(<Document>[doc1Acknowledged, doc2Acknowledged]),
    );
    snap = view.applyChanges(changes);

    expect(snap.snapshot!.changes, <DocumentViewChange>[
      DocumentViewChange(DocumentViewChangeType.modified, doc1Acknowledged),
      DocumentViewChange(DocumentViewChangeType.metadata, doc2Acknowledged),
    ]);
  });

  group('limitToLast', () {
    Document numDoc(int id, int num, [int version = 0]) =>
        doc('rooms/eros/messages/$id', version, map(<dynamic>['num', num]));

    Query lastQuery(int limit) =>
        messageQuery().orderBy(orderBy('num')).limitToLast(limit);

    test('keeps the last documents of the query ordering', () {
      final Query query = lastQuery(2);
      final View view = View(query, DocumentKey.emptyKeySet);

      final Document doc1 = numDoc(1, 1);
      final Document doc2 = numDoc(2, 2);
      final Document doc3 = numDoc(3, 3);

      final ViewSnapshot snapshot = view
          .applyChanges(
            view.computeDocChanges(docUpdates(<Document>[doc1, doc2, doc3])),
            ackTarget(<Document>[doc1, doc2, doc3]),
          )
          .snapshot!;

      expect(snapshot.query, query);
      // The results stay in the order of the query (ascending), the first
      // document is the one that was dropped.
      expect(snapshot.documents.toList(), <Document>[doc2, doc3]);
      expect(snapshot.changes, <DocumentViewChange>[
        DocumentViewChange(DocumentViewChangeType.added, doc2),
        DocumentViewChange(DocumentViewChangeType.added, doc3),
      ]);
      expect(snapshot.isFromCache, isFalse);
      expect(snapshot.didSyncStateChange, isTrue);
      expect(view.syncState, ViewSnapshotSyncState.synced);
    });

    test('keeps the order of a descending limitToLast query', () {
      final Query query = messageQuery()
          .orderBy(orderBy('num', 'desc'))
          .limitToLast(2);
      final View view = View(query, DocumentKey.emptyKeySet);

      final Document doc1 = numDoc(1, 1);
      final Document doc2 = numDoc(2, 2);
      final Document doc3 = numDoc(3, 3);

      final ViewSnapshot snapshot = view
          .applyChanges(
            view.computeDocChanges(docUpdates(<Document>[doc1, doc2, doc3])),
          )
          .snapshot!;

      // Descending order: doc3, doc2, doc1. The last two are doc2 and doc1.
      expect(snapshot.documents.toList(), <Document>[doc2, doc1]);
    });

    test('replaces the first document when a document is added before it', () {
      final View view = View(lastQuery(2), DocumentKey.emptyKeySet);

      final Document doc2 = numDoc(2, 2);
      final Document doc3 = numDoc(3, 3);
      final Document doc4 = numDoc(4, 4);
      applyChanges(view, <Document>[doc2, doc3]);

      final ViewSnapshot snapshot = view
          .applyChanges(view.computeDocChanges(docUpdates(<Document>[doc4])))
          .snapshot!;

      expect(snapshot.documents.toList(), <Document>[doc3, doc4]);
      expect(snapshot.changes, <DocumentViewChange>[
        DocumentViewChange(DocumentViewChangeType.removed, doc2),
        DocumentViewChange(DocumentViewChangeType.added, doc4),
      ]);
    });

    test('does not report documents that sort before the limit', () {
      final View view = View(lastQuery(2), DocumentKey.emptyKeySet);

      final Document doc2 = numDoc(2, 2);
      final Document doc3 = numDoc(3, 3);
      applyChanges(view, <Document>[doc2, doc3]);

      final ViewDocumentChanges changes = view.computeDocChanges(
        docUpdates(<Document>[numDoc(1, 1)]),
      );
      expect(changes.needsRefill, isFalse);
      expect(changes.changeSet.changes, isEmpty);
      expect(changes.documentSet.toList(), <Document>[doc2, doc3]);
    });

    test('returns needsRefill on delete in a limitToLast query', () {
      final View view = View(lastQuery(2), DocumentKey.emptyKeySet);
      final Document doc1 = numDoc(0, 1);
      final Document doc2 = numDoc(1, 2);

      // Start with a full view.
      ViewDocumentChanges changes = view.computeDocChanges(
        docUpdates(<Document>[doc1, doc2]),
      );
      expect(changes.documentSet.length, 2);
      expect(changes.needsRefill, isFalse);
      view.applyChanges(changes);

      // Remove one of the docs.
      changes = view.computeDocChanges(
        docUpdates(<NoDocument>[deletedDoc('rooms/eros/messages/1', 0)]),
      );
      expect(changes.documentSet.length, 1);
      expect(changes.needsRefill, isTrue);
      expect(changes.changeSet.changes.length, 1);

      // Refill it with just the one doc remaining.
      changes = view.computeDocChanges(docUpdates(<Document>[doc1]), changes);
      expect(changes.documentSet.length, 1);
      expect(changes.needsRefill, isFalse);
      view.applyChanges(changes);
    });

    test('returns needsRefill when a document moves before the limit', () {
      final Document doc1 = numDoc(0, 1);
      Document doc2 = numDoc(1, 2);
      final Document doc3 = numDoc(2, 3);
      final View view = View(lastQuery(2), DocumentKey.emptyKeySet);

      // Start with a full view holding doc2 and doc3.
      ViewDocumentChanges changes = view.computeDocChanges(
        docUpdates(<Document>[doc1, doc2, doc3]),
      );
      expect(changes.documentSet.toList(), <Document>[doc2, doc3]);
      expect(changes.needsRefill, isFalse);
      view.applyChanges(changes);

      // Move the first document of the view in front of the limit.
      doc2 = numDoc(1, 0, 1);
      changes = view.computeDocChanges(docUpdates(<Document>[doc2]));
      expect(changes.needsRefill, isTrue);

      // Refill it with all three current docs.
      changes = view.computeDocChanges(
        docUpdates(<Document>[doc1, doc2, doc3]),
        changes,
      );
      expect(changes.needsRefill, isFalse);
      expect(changes.documentSet.toList(), <Document>[doc1, doc3]);
      view.applyChanges(changes);
    });

    test('does not need a refill when a document moves within the limit', () {
      final Document doc1 = numDoc(0, 1);
      Document doc2 = numDoc(1, 2);
      final Document doc3 = numDoc(2, 3);
      final View view = View(lastQuery(3), DocumentKey.emptyKeySet);

      view.applyChanges(
        view.computeDocChanges(docUpdates(<Document>[doc1, doc2, doc3])),
      );

      doc2 = numDoc(1, 2000, 1);
      final ViewDocumentChanges changes = view.computeDocChanges(
        docUpdates(<Document>[doc2]),
      );
      expect(changes.needsRefill, isFalse);
      expect(changes.documentSet.toList(), <Document>[doc1, doc3, doc2]);
    });

    test('does not need a refill when a document moves after the first', () {
      final Document doc1 = numDoc(0, 1);
      final Document doc2 = numDoc(1, 2);
      Document doc3 = numDoc(2, 3);
      final View view = View(lastQuery(2), DocumentKey.emptyKeySet);

      view.applyChanges(
        view.computeDocChanges(docUpdates(<Document>[doc1, doc2, doc3])),
      );

      // Still sorts after the first document of the view (doc2).
      doc3 = numDoc(2, 2500, 1);
      final ViewDocumentChanges changes = view.computeDocChanges(
        docUpdates(<Document>[doc3]),
      );
      expect(changes.needsRefill, isFalse);
      expect(changes.documentSet.toList(), <Document>[doc2, doc3]);
    });

    test('does not need a refill when not near the limit', () {
      final Document doc1 = numDoc(0, 1);
      final Document doc2 = numDoc(1, 2);
      final View view = View(lastQuery(20), DocumentKey.emptyKeySet);

      view.applyChanges(
        view.computeDocChanges(docUpdates(<Document>[doc1, doc2])),
      );

      final ViewDocumentChanges changes = view.computeDocChanges(
        docUpdates(<NoDocument>[deletedDoc('rooms/eros/messages/0', 0)]),
      );
      expect(changes.needsRefill, isFalse);
      expect(changes.documentSet.toList(), <Document>[doc2]);
    });

    test('tracks the sync state of the view', () {
      final View view = View(lastQuery(2), DocumentKey.emptyKeySet);
      expect(view.syncState, ViewSnapshotSyncState.none);

      final Document doc1 = numDoc(1, 1);
      applyChanges(view, <Document>[doc1]);
      expect(view.syncState, ViewSnapshotSyncState.local);

      view.applyChanges(
        view.computeDocChanges(docUpdates(<Document>[doc1])),
        ackTarget(<Document>[doc1]),
      );
      expect(view.syncState, ViewSnapshotSyncState.synced);
    });
  });
}

// ignore: always_specify_types, type_annotate_public_apis
final emptyList = <dynamic>[];
