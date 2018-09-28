// File created by
// Lung Razvan <long1eu>
// on 26/09/2018

import 'package:firebase_firestore/src/firebase/firestore/core/document_view_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/event_manager.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/online_state.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query_listener.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/view.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/view_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore_error.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_set.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/target_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/util.dart';
import 'package:grpc/grpc.dart';
import 'package:test/test.dart';

import '../../../util/test_util.dart';

void main() {
  ViewSnapshot applyChanges(View view, List<MaybeDocument> docs) {
    return view.applyChanges(view.computeDocChanges(docUpdates(docs))).snapshot;
  }

  QueryListener queryListener(
      Query query, ListenOptions options, List<ViewSnapshot> accumulator) {
    return QueryListener(query, options,
        (ViewSnapshot value, FirebaseFirestoreError error) {
      expect(error, isNull);
      accumulator.add(value);
    });
  }

  QueryListener queryListenerDefault(
      Query query, List<ViewSnapshot> accumulator) {
    final ListenOptions options = ListenOptions();
    options.includeDocumentMetadataChanges = true;
    options.includeQueryMetadataChanges = true;
    return queryListener(query, options, accumulator);
  }

  test('testRaisesCollectionEvents', () {
    final List<ViewSnapshot> accum = <ViewSnapshot>[];
    final List<ViewSnapshot> otherAccum = <ViewSnapshot>[];

    final Query query = Query.atPath(path('rooms'));
    final Document doc1 =
        doc('rooms/eros', 1, map(<String>['name', 'eros']), false);
    final Document doc2 =
        doc('rooms/hades', 2, map(<String>['name', 'hades']), false);
    final Document doc2prime = doc('rooms/hades', 3,
        map(<String>['name', 'hades', 'owner', 'Jonny']), false);

    final QueryListener listener = queryListenerDefault(query, accum);
    final QueryListener otherListener = queryListenerDefault(query, otherAccum);

    final View view = View(query, DocumentKey.emptyKeySet);
    final ViewSnapshot snap1 = applyChanges(view, <Document>[doc1, doc2]);
    final ViewSnapshot snap2 = applyChanges(view, <Document>[doc2prime]);

    final DocumentViewChange change1 =
        DocumentViewChange(DocumentViewChangeType.added, doc1);
    final DocumentViewChange change2 =
        DocumentViewChange(DocumentViewChangeType.added, doc2);
    final DocumentViewChange change3 =
        DocumentViewChange(DocumentViewChangeType.modified, doc2prime);
    // Second listener should receive doc2prime as added document not modified.
    final DocumentViewChange change4 =
        DocumentViewChange(DocumentViewChangeType.added, doc2prime);

    listener.onViewSnapshot(snap1);
    listener.onViewSnapshot(snap2);
    otherListener.onViewSnapshot(snap2);
    expect(accum, <ViewSnapshot>[snap1, snap2]);
    expect(accum[0].changes, <DocumentViewChange>[change1, change2]);
    expect(accum[1].changes, <DocumentViewChange>[change3]);

    final ViewSnapshot snap2Prime = ViewSnapshot(
        snap2.query,
        snap2.documents,
        DocumentSet.emptySet(snap2.query.comparator),
        <DocumentViewChange>[change1, change4],
        snap2.isFromCache,
        snap2.hasPendingWrites,
        /*didSyncStateChange:*/
        true);
    expect(otherAccum, <ViewSnapshot>[snap2Prime]);
  });

  test('testRaisesErrorEvent', () {
    final Query query = Query.atPath(path('rooms/eros'));

    bool hadEvent = false;
    final QueryListener listener = QueryListener(query, ListenOptions(),
        (ViewSnapshot value, FirebaseFirestoreError error) {
      expect(value, isNull);
      expect(error, isNotNull);
      hadEvent = true;
    });
    final GrpcError status = GrpcError.alreadyExists('test error');
    final FirebaseFirestoreError error = Util.exceptionFromStatus(status);
    listener.onError(error);
    expect(hadEvent, isTrue);
  });

  test('testRaisesEventForEmptyCollectionsAfterSync', () {
    final List<ViewSnapshot> accum = <ViewSnapshot>[];
    final Query query = Query.atPath(path('rooms'));

    final QueryListener listener = queryListenerDefault(query, accum);

    final View view = View(query, DocumentKey.emptyKeySet);
    final ViewSnapshot snap1 = applyChanges(view, <MaybeDocument>[]);
    final TargetChange ackTarget = TestUtil.ackTarget(<Document>[]);
    final ViewSnapshot snap2 = view
        .applyChanges(
            view.computeDocChanges(docUpdates(<MaybeDocument>[])), ackTarget)
        .snapshot;

    listener.onViewSnapshot(snap1);
    expect(accum, isEmpty);

    listener.onViewSnapshot(snap2);
    expect(accum.first, snap2);
  });

  test('testDoesNotRaiseEventsForMetadataChangesUnlessSpecified', () {
    final List<ViewSnapshot> filteredAccum = <ViewSnapshot>[];
    final List<ViewSnapshot> fullAccum = <ViewSnapshot>[];
    final Query query = Query.atPath(path('rooms'));
    final Document doc1 =
        doc('rooms/eros', 1, map(<String>['name', 'eros']), false);
    final Document doc2 =
        doc('rooms/hades', 2, map(<String>['name', 'hades']), false);
    final ListenOptions options1 = ListenOptions();
    final ListenOptions options2 = ListenOptions();
    options2.includeQueryMetadataChanges = true;
    final QueryListener filteredListener =
        queryListener(query, options1, filteredAccum);
    final QueryListener fullListener =
        queryListener(query, options2, fullAccum);

    final View view = View(query, DocumentKey.emptyKeySet);
    final ViewSnapshot snap1 = applyChanges(view, <Document>[doc1]);

    final TargetChange ackTarget = TestUtil.ackTarget(<Document>[doc1]);
    final ViewSnapshot snap2 = view
        .applyChanges(
            view.computeDocChanges(docUpdates(<MaybeDocument>[])), ackTarget)
        .snapshot;
    final ViewSnapshot snap3 = applyChanges(view, <Document>[doc2]);

    filteredListener.onViewSnapshot(snap1); // local event
    filteredListener.onViewSnapshot(snap2); // no event
    filteredListener.onViewSnapshot(snap3); // doc2 update

    fullListener.onViewSnapshot(snap1); // local event
    fullListener.onViewSnapshot(snap2); // no event
    fullListener.onViewSnapshot(snap3); // doc2 update

    expect(filteredAccum, <ViewSnapshot>[snap1, snap3]);
    expect(fullAccum, <ViewSnapshot>[snap1, snap2, snap3]);
  });

  test('testRaisesDocumentMetadataEventsOnlyWhenSpecified', () {
    final List<ViewSnapshot> filteredAccum = <ViewSnapshot>[];
    final List<ViewSnapshot> fullAccum = <ViewSnapshot>[];
    final Query query = Query.atPath(path('rooms'));
    final Document doc1 =
        doc('rooms/eros', 1, map(<String>['name', 'eros']), false);
    final Document doc1Prime =
        doc('rooms/eros', 1, map(<String>['name', 'eros']), true);
    final Document doc2 =
        doc('rooms/hades', 2, map(<String>['name', 'hades']), false);
    final Document doc3 =
        doc('rooms/other', 3, map(<String>['name', 'other']), false);

    final ListenOptions options1 = ListenOptions();
    final ListenOptions options2 = ListenOptions();
    options2.includeDocumentMetadataChanges = true;
    final QueryListener filteredListener =
        queryListener(query, options1, filteredAccum);
    final QueryListener fullListener =
        queryListener(query, options2, fullAccum);

    final View view = View(query, DocumentKey.emptyKeySet);
    final ViewSnapshot snap1 = applyChanges(view, <Document>[doc1, doc2]);
    final ViewSnapshot snap2 = applyChanges(view, <Document>[doc1Prime]);
    final ViewSnapshot snap3 = applyChanges(view, <Document>[doc3]);

    filteredListener.onViewSnapshot(snap1);
    filteredListener.onViewSnapshot(snap2);
    filteredListener.onViewSnapshot(snap3);

    fullListener.onViewSnapshot(snap1);
    fullListener.onViewSnapshot(snap2);
    fullListener.onViewSnapshot(snap3);

    expect(filteredAccum, <ViewSnapshot>[snap1, snap3]);
    // Second listener should receive doc1prime as added document not modified
    expect(fullAccum, <ViewSnapshot>[snap1, snap2, snap3]);
  });

  test('testRaisesQueryMetadataEventsOnlyWhenHasPendingWritesOnTheQueryChanges',
      () {
    final List<ViewSnapshot> fullAccum = <ViewSnapshot>[];
    final Query query = Query.atPath(path('rooms'));
    final Document doc1 =
        doc('rooms/eros', 1, map(<String>['name', 'eros']), true);
    final Document doc2 =
        doc('rooms/hades', 2, map(<String>['name', 'hades']), true);
    final Document doc1Prime =
        doc('rooms/eros', 1, map(<String>['name', 'eros']), false);
    final Document doc2Prime =
        doc('rooms/hades', 2, map(<String>['name', 'hades']), false);
    final Document doc3 =
        doc('rooms/other', 3, map(<String>['name', 'other']), false);

    final ListenOptions options = ListenOptions();
    options.includeQueryMetadataChanges = true;
    final QueryListener fullListener = queryListener(query, options, fullAccum);

    final View view = View(query, DocumentKey.emptyKeySet);
    final ViewSnapshot snap1 = applyChanges(view, <Document>[doc1, doc2]);
    final ViewSnapshot snap2 = applyChanges(view, <Document>[doc1Prime]);
    final ViewSnapshot snap3 = applyChanges(view, <Document>[doc3]);
    final ViewSnapshot snap4 = applyChanges(view, <Document>[doc2Prime]);

    fullListener.onViewSnapshot(snap1);
    fullListener.onViewSnapshot(snap2); // Emits no events
    fullListener.onViewSnapshot(snap3);
    fullListener.onViewSnapshot(snap4); // Metadata change event

    final ViewSnapshot expectedSnapshot4 = ViewSnapshot(
        snap4.query,
        snap4.documents,
        snap3.documents,
        <DocumentViewChange>[],
        snap4.isFromCache,
        snap4.hasPendingWrites,
        snap4.didSyncStateChange);
    expect(fullAccum, <ViewSnapshot>[snap1, snap3, expectedSnapshot4]);
  });

  test('testMetadataOnlyDocumentChangesAreFilteredOut', () {
    final List<ViewSnapshot> filteredAccum = <ViewSnapshot>[];
    final Query query = Query.atPath(path('rooms'));
    final Document doc1 =
        doc('rooms/eros', 1, map(<String>['name', 'eros']), false);
    final Document doc1Prime =
        doc('rooms/eros', 1, map(<String>['name', 'eros']), true);
    final Document doc2 =
        doc('rooms/hades', 2, map(<String>['name', 'hades']), false);
    final Document doc3 =
        doc('rooms/other', 3, map(<String>['name', 'other']), false);

    final ListenOptions options = ListenOptions();
    options.includeDocumentMetadataChanges = false;
    final QueryListener filteredListener =
        queryListener(query, options, filteredAccum);

    final View view = View(query, DocumentKey.emptyKeySet);
    final ViewSnapshot snap1 = applyChanges(view, <Document>[doc1, doc2]);
    final ViewSnapshot snap2 = applyChanges(view, <Document>[doc1Prime, doc3]);

    filteredListener.onViewSnapshot(snap1);
    filteredListener.onViewSnapshot(snap2);

    final DocumentViewChange change3 =
        DocumentViewChange(DocumentViewChangeType.added, doc3);
    final ViewSnapshot expectedSnapshot2 = ViewSnapshot(
        snap2.query,
        snap2.documents,
        snap1.documents,
        <DocumentViewChange>[change3],
        snap2.isFromCache,
        snap2.hasPendingWrites,
        snap2.didSyncStateChange);
    expect(filteredAccum, <ViewSnapshot>[snap1, expectedSnapshot2]);
  });

  test('testWillWaitForSyncIfOnline', () {
    final List<ViewSnapshot> events = <ViewSnapshot>[];
    final Query query = Query.atPath(path('rooms'));

    final Document doc1 =
        doc('rooms/eros', 1, map(<String>['name', 'eros']), false);
    final Document doc2 =
        doc('rooms/hades', 2, map(<String>['name', 'hades']), false);

    final ListenOptions options = ListenOptions();
    options.waitForSyncWhenOnline = true;
    final QueryListener listener = queryListener(query, options, events);

    final View view = View(query, DocumentKey.emptyKeySet);
    final ViewSnapshot snap1 = applyChanges(view, <Document>[doc1]);
    final ViewSnapshot snap2 = applyChanges(view, <Document>[doc2]);
    final ViewDocumentChanges changes =
        view.computeDocChanges(docUpdates(<MaybeDocument>[]));

    final ViewSnapshot snap3 = view
        .applyChanges(changes, TestUtil.ackTarget(<Document>[doc1, doc2]))
        .snapshot;

    listener.onOnlineStateChanged(OnlineState.online); // no event
    listener.onViewSnapshot(snap1); // no event
    listener.onOnlineStateChanged(OnlineState.unknown); // no event
    listener.onOnlineStateChanged(OnlineState.online); // no event
    listener.onViewSnapshot(snap2); // no event
    listener.onViewSnapshot(snap3); // event because synced

    final DocumentViewChange change1 =
        DocumentViewChange(DocumentViewChangeType.added, doc1);
    final DocumentViewChange change2 =
        DocumentViewChange(DocumentViewChangeType.added, doc2);
    final ViewSnapshot expectedSnapshot = ViewSnapshot(
        snap3.query,
        snap3.documents,
        DocumentSet.emptySet(snap3.query.comparator),
        <DocumentViewChange>[change1, change2],
        /*isFromCache:*/
        false,
        /*hasPendingWrites:*/
        false,
        /*didSyncStateChange:*/
        true);
    expect(events, <ViewSnapshot>[expectedSnapshot]);
  });

  test('testWillRaiseInitialEventWhenGoingOffline', () {
    final List<ViewSnapshot> events = <ViewSnapshot>[];
    final Query query = Query.atPath(path('rooms'));

    final Document doc1 =
        doc('rooms/eros', 1, map(<String>['name', 'eros']), false);
    final Document doc2 =
        doc('rooms/hades', 2, map(<String>['name', 'hades']), false);

    final ListenOptions options = ListenOptions();
    options.waitForSyncWhenOnline = true;
    final QueryListener listener = queryListener(query, options, events);

    final View view = View(query, DocumentKey.emptyKeySet);
    final ViewSnapshot snap1 = applyChanges(view, <Document>[doc1]);
    final ViewSnapshot snap2 = applyChanges(view, <Document>[doc2]);

    listener.onOnlineStateChanged(OnlineState.online); // no event
    listener.onViewSnapshot(snap1); // no event
    listener.onOnlineStateChanged(OnlineState.offline); // event
    listener.onOnlineStateChanged(OnlineState.online); // event
    listener.onOnlineStateChanged(OnlineState.offline); // no event
    listener.onViewSnapshot(snap2); // event

    final DocumentViewChange change1 =
        DocumentViewChange(DocumentViewChangeType.added, doc1);
    final DocumentViewChange change2 =
        DocumentViewChange(DocumentViewChangeType.added, doc2);
    final ViewSnapshot expectedSnapshot1 = ViewSnapshot(
        snap1.query,
        snap1.documents,
        DocumentSet.emptySet(snap1.query.comparator),
        <DocumentViewChange>[change1],
        /* sFromCache:*/
        true,
        /*hasPendingWrites:*/
        false,
        /*didSyncStateChange:*/
        true);
    final ViewSnapshot expectedSnapshot2 = ViewSnapshot(
        snap2.query,
        snap2.documents,
        snap1.documents,
        <DocumentViewChange>[change2],
        /*isFromCache:*/
        true,
        /*hasPendingWrites=:*/
        false,
        /*didSyncStateChange:*/
        false);
    expect(events, <ViewSnapshot>[expectedSnapshot1, expectedSnapshot2]);
  });

  test('testWillRaiseInitialEventWhenGoingOfflineAndThereAreNoDocs', () {
    final List<ViewSnapshot> events = <ViewSnapshot>[];
    final Query query = Query.atPath(path('rooms'));

    final QueryListener listener =
        queryListener(query, ListenOptions(), events);

    final View view = View(query, DocumentKey.emptyKeySet);
    final ViewSnapshot snap1 = applyChanges(view, <MaybeDocument>[]);

    listener.onOnlineStateChanged(OnlineState.online); // no event
    listener.onViewSnapshot(snap1); // no event
    listener.onOnlineStateChanged(OnlineState.offline); // event

    final ViewSnapshot expectedSnapshot = ViewSnapshot(
        snap1.query,
        snap1.documents,
        DocumentSet.emptySet(snap1.query.comparator),
        <DocumentViewChange>[],
        /*isFromCache:*/
        true,
        /*hasPendingWrites:*/
        false,
        /*didSyncStateChange:*/
        true);
    expect(events, <ViewSnapshot>[expectedSnapshot]);
  });

  test('testWillRaiseInitialEventWhenStartingOfflineAndThereAreNoDocs', () {
    final List<ViewSnapshot> events = <ViewSnapshot>[];
    final Query query = Query.atPath(path('rooms'));

    final QueryListener listener =
        queryListener(query, ListenOptions(), events);

    final View view = View(query, DocumentKey.emptyKeySet);
    final ViewSnapshot snap1 = applyChanges(view, <MaybeDocument>[]);

    listener.onOnlineStateChanged(OnlineState.offline);
    listener.onViewSnapshot(snap1);

    final ViewSnapshot expectedSnapshot = ViewSnapshot(
        snap1.query,
        snap1.documents,
        DocumentSet.emptySet(snap1.query.comparator),
        <DocumentViewChange>[],
        /*isFromCache:*/
        true,
        /*hasPendingWrites:*/
        false,
        /*didSyncStateChange:*/
        true);
    expect(events, <ViewSnapshot>[expectedSnapshot]);
  });
}

// ignore: always_specify_types
const map = TestUtil.map;
// ignore: always_specify_types
const doc = TestUtil.doc;
// ignore: always_specify_types
const filter = TestUtil.filter;
// ignore: always_specify_types
const orderBy = TestUtil.orderBy;
// ignore: always_specify_types
const testEquality = TestUtil.testEquality;
// ignore: always_specify_types
const ref = TestUtil.ref;
// ignore: always_specify_types
const path = TestUtil.path;
// ignore: always_specify_types
const docUpdates = TestUtil.docUpdates;
