// File created by
// Lung Razvan <long1eu>
// on 28/09/2018
import 'dart:math';
import 'dart:typed_data';

import 'package:firebase_database_collection/firebase_database_collection.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart'
    as core;
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/view.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/view_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/document_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore.dart';
import 'package:firebase_firestore/src/firebase/firestore/metadata_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/no_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/target_change.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../../../util/test_util.dart';

void main() {
  void validatePositions(
      core.Query query,
      List<Document> initialDocsList,
      List<Document> addedList,
      List<Document> modifiedList,
      List<NoDocument> removedList) {
    final ImmutableSortedMap<DocumentKey, MaybeDocument> initialDocs =
        docUpdates(initialDocsList);

    ImmutableSortedMap<DocumentKey, MaybeDocument> updates =
        ImmutableSortedMap<DocumentKey, MaybeDocument>.emptyMap(
            DocumentKey.comparator);
    for (Document doc in addedList) {
      updates = updates.insert(doc.key, doc);
    }
    for (Document doc in modifiedList) {
      updates = updates.insert(doc.key, doc);
    }
    for (NoDocument doc in removedList) {
      updates = updates.insert(doc.key, doc);
    }

    final View view = View(query, DocumentKey.emptyKeySet);
    final ViewDocumentChanges initialChanges =
        view.computeDocChanges(initialDocs);
    final TargetChange initialTargetChange = ackTarget(initialDocsList);
    final ViewSnapshot initialSnapshot =
        view.applyChanges(initialChanges, initialTargetChange).snapshot;

    final ViewDocumentChanges updateChanges = view.computeDocChanges(updates);
    final TargetChange updateTargetChange = targetChange(
        Uint8List.fromList(<int>[]),
        true,
        addedList,
        modifiedList,
        removedList);
    final ViewSnapshot updatedSnapshot =
        view.applyChanges(updateChanges, updateTargetChange).snapshot;

    if (updatedSnapshot == null) {
      // Nothing changed, no positions to verify
      return;
    }

    final List<Document> expected = updatedSnapshot.documents.toList();
    final List<Document> actual = initialSnapshot.documents.toList();

    final FirebaseFirestore firestore = FirebaseFirestoreMock();
    final List<DocumentChange> changes = DocumentChange.changesFromSnapshot(
        firestore, MetadataChanges.exclude, updatedSnapshot);

    for (DocumentChange change in changes) {
      if (change.type != DocumentChangeType.added) {
        actual.removeAt(change.oldIndex);
      }

      if (change.type != DocumentChangeType.removed) {
        actual.insert(change.newIndex, change.document.document);
      }
    }

    expect(actual, expected);
  }

  test('testAdditions', () {
    final Query query = Query.atPath(path('c'));
    final List<Document> initialDocs = <Document>[
      doc('c/a', 1, map()),
      doc('c/c', 1, map()),
      doc('c/e', 1, map())
    ];
    final List<Document> adds = <Document>[
      doc('c/d', 2, map()),
      doc('c/b', 2, map())
    ];

    validatePositions(query, initialDocs, adds, <Document>[], <NoDocument>[]);
  });

  test('testDeletions', () {
    final Query query = Query.atPath(path('c'));
    final List<Document> initialDocs = <Document>[
      doc('c/a', 1, map()),
      doc('c/b', 1, map()),
      doc('c/c', 1, map())
    ];
    final List<NoDocument> deletes = <NoDocument>[
      deletedDoc('c/a', 2),
      deletedDoc('c/c', 2)
    ];
    validatePositions(query, initialDocs, <Document>[], <Document>[], deletes);
  });

  test('testModifications', () {
    final Query query = Query.atPath(path('c'));
    final List<Document> initialDocs = <Document>[
      doc('c/a', 1, map(<String>['value', 'a-1'])),
      doc('c/b', 1, map(<String>['value', 'b-1'])),
      doc('c/c', 1, map(<String>['value', 'c-1']))
    ];
    final List<Document> updates = <Document>[
      doc('c/a', 2, map(<String>['value', 'a-2'])),
      doc('c/c', 2, map(<String>['value', 'c-2']))
    ];
    validatePositions(
        query, initialDocs, <Document>[], updates, <NoDocument>[]);
  });

  test('testChangesWithSortOrderChange', () {
    final Query query = Query.atPath(path('c')).orderBy(orderBy('sort'));
    final List<Document> initialDocs = <Document>[
      doc('c/a', 1, map(<dynamic>['sort', 10])),
      doc('c/b', 1, map(<dynamic>['sort', 20])),
      doc('c/c', 1, map(<dynamic>['sort', 30]))
    ];
    final List<Document> adds = <Document>[
      doc('c/new-a', 2, map(<dynamic>['sort', 0])),
      doc('c/e', 2, map(<dynamic>['sort', 25]))
    ];
    final List<Document> updates = <Document>[
      doc('c/new-a', 2, map(<dynamic>['sort', 0])),
      doc('c/b', 2, map(<dynamic>['sort', 5])),
      doc('c/e', 2, map(<dynamic>['sort', 25])),
      doc('c/a', 2, map(<dynamic>['sort', 35]))
    ];
    final List<NoDocument> deletes = <NoDocument>[deletedDoc('c/c', 2)];
    validatePositions(query, initialDocs, adds, updates, deletes);
  });

  test('randomTests', () {
    for (int run = 0; run < 100; run++) {
      final Query query = Query.atPath(path('c')).orderBy(orderBy('sort'));
      final Map<DocumentKey, Document> initialDocs = <DocumentKey, Document>{};
      final List<Document> adds = <Document>[];
      final List<Document> updates = <Document>[];
      final List<NoDocument> deletes = <NoDocument>[];
      const int numDocs = 100;
      final Random random = Random();
      for (int i = 0; i < numDocs; i++) {
        final String docKey = 'c/test-doc-$i';
        // Skip 20% of the docs
        if (random.nextDouble() > 0.8) {
          initialDocs[key(docKey)] =
              doc(docKey, 1, map(<dynamic>['sort', random.nextDouble()]));
        }
      }
      for (int i = 0; i < numDocs; i++) {
        final String docKey = 'c/test-doc-$i';
        // Only update 20% of the docs
        if (random.nextDouble() < 0.2) {
          // 30% deletes, rest updates and/or additions
          if (random.nextDouble() < 0.3) {
            deletes.add(deletedDoc(docKey, 2));
          } else {
            if (initialDocs.containsKey(key(docKey))) {
              updates.add(
                  doc(docKey, 2, map(<dynamic>['sort', random.nextDouble()])));
            } else {
              adds.add(
                  doc(docKey, 2, map(<dynamic>['sort', random.nextDouble()])));
            }
          }
        }
      }

      validatePositions(
          query, initialDocs.values.toList(), adds, updates, deletes);
    }
  });
}

class FirebaseFirestoreMock extends Mock implements FirebaseFirestore {}

// ignore: always_specify_types
const ackTarget = TestUtil.ackTarget;
// ignore: always_specify_types
const targetChange = TestUtil.targetChange;
// ignore: always_specify_types
const docUpdates = TestUtil.docUpdates;
// ignore: always_specify_types
const map = TestUtil.map;
// ignore: always_specify_types
const deletedDoc = TestUtil.deletedDoc;
// ignore: always_specify_types
const path = TestUtil.path;
// ignore: always_specify_types
const orderBy = TestUtil.orderBy;
// ignore: always_specify_types
const key = TestUtil.key;
// ignore: always_specify_types
const doc = TestUtil.doc;
