// File created by
// Lung Razvan <long1eu>
// on 26/09/2018

import 'dart:async';

import 'package:cloud_firestore_vm/src/firebase/firestore/core/document_view_change.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/event_manager.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/online_state.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query_stream.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/view.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/metadata_change.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_set.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/target_change.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/util.dart';
import 'package:grpc/grpc.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

// ignore_for_file: unawaited_futures
void main() {
  ViewSnapshot applyChanges(View view, List<MaybeDocument> docs) {
    return view.applyChanges(view.computeDocChanges(docUpdates(docs))).snapshot;
  }

  QueryStream queryListener(
      Query query, ListenOptions options, List<ViewSnapshot> accumulator) {
    return QueryStream(query, options)
      ..listen(accumulator.add, onError: (dynamic error) {
        assert(false, 'This should never be called. $error');
      });
  }

  QueryStream queryListenerDefault(
      Query query, List<ViewSnapshot> accumulator) {
    const ListenOptions options = ListenOptions(
        includeDocumentMetadataChanges: true,
        includeQueryMetadataChanges: true);
    return queryListener(query, options, accumulator);
  }

  test('testRaisesCollectionEvents', () async {
    final List<ViewSnapshot> accum = <ViewSnapshot>[];
    final List<ViewSnapshot> otherAccum = <ViewSnapshot>[];

    final Query query = Query(path('rooms'));
    final Document doc1 = doc('rooms/eros', 1, map(<String>['name', 'eros']));
    final Document doc2 = doc('rooms/hades', 2, map(<String>['name', 'hades']));
    final Document doc2prime =
        doc('rooms/hades', 3, map(<String>['name', 'hades', 'owner', 'Jonny']));

    final QueryStream listener = queryListenerDefault(query, accum);
    final QueryStream otherListener = queryListenerDefault(query, otherAccum);

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

    listener..onViewSnapshot(snap1)..onViewSnapshot(snap2);

    otherListener.onViewSnapshot(snap2);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(accum, <ViewSnapshot>[snap1, snap2]);
    expect(accum[0].changes, <DocumentViewChange>[change1, change2]);
    expect(accum[1].changes, <DocumentViewChange>[change3]);

    final ViewSnapshot snap2Prime = ViewSnapshot(
      snap2.query,
      snap2.documents,
      DocumentSet.emptySet(snap2.query.comparator),
      <DocumentViewChange>[change1, change4],
      snap2.mutatedKeys,
      isFromCache: snap2.isFromCache,
      didSyncStateChange: true,
      excludesMetadataChanges: false,
    );
    expect(otherAccum, <ViewSnapshot>[snap2Prime]);
  });

  test('testRaisesErrorEvent', () async {
    final Query query = Query(path('rooms/eros'));

    bool hadEvent = false;
    final QueryStream listener = QueryStream(query)
      ..listen(
        (ViewSnapshot data) {
          assert(false, 'This should never be called.');
        },
        onError: (dynamic e) {
          expect(e, isNotNull);
          hadEvent = true;
        },
      );

    final GrpcError status = GrpcError.alreadyExists('test error');
    final FirestoreError error = exceptionFromStatus(status);
    listener.onError(error);
    await Future<void>.delayed(
        const Duration(milliseconds: 100), () => expect(hadEvent, isTrue));
  });

  test('testRaisesEventForEmptyCollectionsAfterSync', () async {
    final List<ViewSnapshot> accum = <ViewSnapshot>[];
    final Query query = Query(path('rooms'));

    final QueryStream listener = queryListenerDefault(query, accum);

    final View view = View(query, DocumentKey.emptyKeySet);
    final ViewSnapshot snap1 = applyChanges(view, <MaybeDocument>[]);
    final TargetChange _ackTarget = ackTarget(<Document>[]);
    final ViewSnapshot snap2 = view
        .applyChanges(
            view.computeDocChanges(docUpdates(<MaybeDocument>[])), _ackTarget)
        .snapshot;

    listener.onViewSnapshot(snap1);
    expect(accum, isEmpty);

    listener.onViewSnapshot(snap2);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(accum.first, snap2);
  });

  test('testDoesNotRaiseEventsForMetadataChangesUnlessSpecified', () async {
    final List<ViewSnapshot> filteredAccum = <ViewSnapshot>[];
    final List<ViewSnapshot> fullAccum = <ViewSnapshot>[];
    final Query query = Query(path('rooms'));
    final Document doc1 = doc('rooms/eros', 1, map(<String>['name', 'eros']));
    final Document doc2 = doc('rooms/hades', 2, map(<String>['name', 'hades']));
    const ListenOptions options1 = ListenOptions();
    const ListenOptions options2 = ListenOptions(
      includeQueryMetadataChanges: true,
      includeDocumentMetadataChanges: true,
    );
    final QueryStream filteredListener =
        queryListener(query, options1, filteredAccum);
    final QueryStream fullListener = queryListener(query, options2, fullAccum);

    final View view = View(query, DocumentKey.emptyKeySet);
    final ViewSnapshot snap1 = applyChanges(view, <Document>[doc1]);

    final TargetChange _ackTarget = ackTarget(<Document>[doc1]);
    final ViewSnapshot snap2 = view
        .applyChanges(
            view.computeDocChanges(docUpdates(<MaybeDocument>[])), _ackTarget)
        .snapshot;
    final ViewSnapshot snap3 = applyChanges(view, <Document>[doc2]);

    filteredListener
      ..onViewSnapshot(snap1) // local event
      ..onViewSnapshot(snap2) // no event
      ..onViewSnapshot(snap3); // doc2 update

    fullListener
      ..onViewSnapshot(snap1) // local event
      ..onViewSnapshot(snap2) // no event
      ..onViewSnapshot(snap3); // doc2 update
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      filteredAccum,
      <ViewSnapshot>[
        _applyExpectedMetadata(snap1, MetadataChanges.exclude),
        _applyExpectedMetadata(snap3, MetadataChanges.exclude),
      ],
    );
    expect(fullAccum, <ViewSnapshot>[snap1, snap2, snap3]);
  });

  test('testRaisesDocumentMetadataEventsOnlyWhenSpecified', () async {
    final List<ViewSnapshot> filteredAccum = <ViewSnapshot>[];
    final List<ViewSnapshot> fullAccum = <ViewSnapshot>[];
    final Query query = Query(path('rooms'));
    final Document doc1 = doc('rooms/eros', 1, map(<String>['name', 'eros']));
    final Document doc1Prime = doc('rooms/eros', 1,
        map(<String>['name', 'eros']), DocumentState.localMutations);
    final Document doc2 = doc('rooms/hades', 2, map(<String>['name', 'hades']));
    final Document doc3 = doc('rooms/other', 3, map(<String>['name', 'other']));

    const ListenOptions options1 = ListenOptions();
    const ListenOptions options2 =
        ListenOptions(includeDocumentMetadataChanges: true);

    final QueryStream filteredListener =
        queryListener(query, options1, filteredAccum);
    final QueryStream fullListener = queryListener(query, options2, fullAccum);

    final View view = View(query, DocumentKey.emptyKeySet);
    final ViewSnapshot snap1 = applyChanges(view, <Document>[doc1, doc2]);
    final ViewSnapshot snap2 = applyChanges(view, <Document>[doc1Prime]);
    final ViewSnapshot snap3 = applyChanges(view, <Document>[doc3]);

    filteredListener
      ..onViewSnapshot(snap1)
      ..onViewSnapshot(snap2)
      ..onViewSnapshot(snap3);

    fullListener
      ..onViewSnapshot(snap1)
      ..onViewSnapshot(snap2)
      ..onViewSnapshot(snap3);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      filteredAccum,
      <ViewSnapshot>[
        _applyExpectedMetadata(snap1, MetadataChanges.exclude),
        _applyExpectedMetadata(snap3, MetadataChanges.exclude)
      ],
    );
    // Second listener should receive doc1prime as added document not modified
    expect(fullAccum, <ViewSnapshot>[snap1, snap2, snap3]);
  });

  test('testRaisesQueryMetadataEventsOnlyWhenHasPendingWritesOnTheQueryChanges',
      () async {
    final List<ViewSnapshot> fullAccum = <ViewSnapshot>[];
    final Query query = Query(path('rooms'));
    final Document doc1 = doc('rooms/eros', 1, map(<String>['name', 'eros']),
        DocumentState.localMutations);
    final Document doc2 = doc('rooms/hades', 2, map(<String>['name', 'hades']),
        DocumentState.localMutations);
    final Document doc1Prime =
        doc('rooms/eros', 1, map(<String>['name', 'eros']));
    final Document doc2Prime =
        doc('rooms/hades', 2, map(<String>['name', 'hades']));
    final Document doc3 = doc('rooms/other', 3, map(<String>['name', 'other']));

    const ListenOptions options =
        ListenOptions(includeQueryMetadataChanges: true);
    final QueryStream fullListener = queryListener(query, options, fullAccum);

    final View view = View(query, DocumentKey.emptyKeySet);
    final ViewSnapshot snap1 = applyChanges(view, <Document>[doc1, doc2]);
    final ViewSnapshot snap2 = applyChanges(view, <Document>[doc1Prime]);
    final ViewSnapshot snap3 = applyChanges(view, <Document>[doc3]);
    final ViewSnapshot snap4 = applyChanges(view, <Document>[doc2Prime]);

    fullListener
      ..onViewSnapshot(snap1)
      ..onViewSnapshot(snap2) // Emits no events
      ..onViewSnapshot(snap3)
      ..onViewSnapshot(snap4); // Metadata change event
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final ViewSnapshot expectedSnapshot4 = ViewSnapshot(
      snap4.query,
      snap4.documents,
      snap3.documents,
      <DocumentViewChange>[],
      snap4.mutatedKeys,
      isFromCache: snap4.isFromCache,
      didSyncStateChange: snap4.didSyncStateChange,
      excludesMetadataChanges: true,
    );

    expect(
      fullAccum,
      <ViewSnapshot>[
        _applyExpectedMetadata(snap1, MetadataChanges.exclude),
        _applyExpectedMetadata(snap3, MetadataChanges.exclude),
        expectedSnapshot4,
      ],
    );
  });

  test('testMetadataOnlyDocumentChangesAreFilteredOut', () async {
    final List<ViewSnapshot> filteredAccum = <ViewSnapshot>[];
    final Query query = Query(path('rooms'));
    final Document doc1 = doc('rooms/eros', 1, map(<String>['name', 'eros']));
    final Document doc1Prime =
        doc('rooms/eros', 1, map(<String>['name', 'eros']));
    final Document doc2 = doc('rooms/hades', 2, map(<String>['name', 'hades']));
    final Document doc3 = doc('rooms/other', 3, map(<String>['name', 'other']));

    const ListenOptions options = ListenOptions();

    final QueryStream filteredListener =
        queryListener(query, options, filteredAccum);

    final View view = View(query, DocumentKey.emptyKeySet);
    final ViewSnapshot snap1 = applyChanges(view, <Document>[doc1, doc2]);
    final ViewSnapshot snap2 = applyChanges(view, <Document>[doc1Prime, doc3]);

    filteredListener..onViewSnapshot(snap1)..onViewSnapshot(snap2);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final DocumentViewChange change3 =
        DocumentViewChange(DocumentViewChangeType.added, doc3);
    final ViewSnapshot expectedSnapshot2 = ViewSnapshot(
      snap2.query,
      snap2.documents,
      snap1.documents,
      <DocumentViewChange>[change3],
      snap2.mutatedKeys,
      isFromCache: snap2.isFromCache,
      didSyncStateChange: snap2.didSyncStateChange,
      excludesMetadataChanges: true,
    );
    expect(filteredAccum, <ViewSnapshot>[
      _applyExpectedMetadata(snap1, MetadataChanges.exclude),
      expectedSnapshot2,
    ]);
  });

  test('testWillWaitForSyncIfOnline', () async {
    final List<ViewSnapshot> events = <ViewSnapshot>[];
    final Query query = Query(path('rooms'));

    final Document doc1 = doc('rooms/eros', 1, map(<String>['name', 'eros']));
    final Document doc2 = doc('rooms/hades', 2, map(<String>['name', 'hades']));

    const ListenOptions options = ListenOptions(waitForSyncWhenOnline: true);

    final QueryStream listener = queryListener(query, options, events);

    final View view = View(query, DocumentKey.emptyKeySet);
    final ViewSnapshot snap1 = applyChanges(view, <Document>[doc1]);
    final ViewSnapshot snap2 = applyChanges(view, <Document>[doc2]);
    final ViewDocumentChanges changes =
        view.computeDocChanges(docUpdates(<MaybeDocument>[]));

    final ViewSnapshot snap3 =
        view.applyChanges(changes, ackTarget(<Document>[doc1, doc2])).snapshot;

    listener
      ..onOnlineStateChanged(OnlineState.online) // no event
      ..onViewSnapshot(snap1) // no event
      ..onOnlineStateChanged(OnlineState.unknown) // no event
      ..onOnlineStateChanged(OnlineState.online) // no event
      ..onViewSnapshot(snap2) // no event
      ..onViewSnapshot(snap3); // event because synced
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final DocumentViewChange change1 =
        DocumentViewChange(DocumentViewChangeType.added, doc1);
    final DocumentViewChange change2 =
        DocumentViewChange(DocumentViewChangeType.added, doc2);
    final ViewSnapshot expectedSnapshot = ViewSnapshot(
      snap3.query,
      snap3.documents,
      DocumentSet.emptySet(snap3.query.comparator),
      <DocumentViewChange>[change1, change2],
      snap3.mutatedKeys /*hasPendingWrites*/,
      isFromCache: false,
      didSyncStateChange: true,
      excludesMetadataChanges: true,
    );
    expect(events, <ViewSnapshot>[expectedSnapshot]);
  });

  test('testWillRaiseInitialEventWhenGoingOffline', () async {
    final List<ViewSnapshot> events = <ViewSnapshot>[];
    final Query query = Query(path('rooms'));

    final Document doc1 = doc('rooms/eros', 1, map(<String>['name', 'eros']));
    final Document doc2 = doc('rooms/hades', 2, map(<String>['name', 'hades']));

    const ListenOptions options = ListenOptions(waitForSyncWhenOnline: true);

    final QueryStream listener = queryListener(query, options, events);

    final View view = View(query, DocumentKey.emptyKeySet);
    final ViewSnapshot snap1 = applyChanges(view, <Document>[doc1]);
    final ViewSnapshot snap2 = applyChanges(view, <Document>[doc2]);

    listener
      ..onOnlineStateChanged(OnlineState.online) // no event
      ..onViewSnapshot(snap1) // no event
      ..onOnlineStateChanged(OnlineState.offline) // event
      ..onOnlineStateChanged(OnlineState.online) // event
      ..onOnlineStateChanged(OnlineState.offline) // no event
      ..onViewSnapshot(snap2); // event
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final DocumentViewChange change1 =
        DocumentViewChange(DocumentViewChangeType.added, doc1);
    final DocumentViewChange change2 =
        DocumentViewChange(DocumentViewChangeType.added, doc2);
    final ViewSnapshot expectedSnapshot1 = ViewSnapshot(
      snap1.query,
      snap1.documents,
      DocumentSet.emptySet(snap1.query.comparator),
      <DocumentViewChange>[change1],
      snap1.mutatedKeys /*hasPendingWrites*/,
      isFromCache: true,
      didSyncStateChange: true,
      excludesMetadataChanges: true,
    );

    final ViewSnapshot expectedSnapshot2 = ViewSnapshot(
      snap2.query,
      snap2.documents,
      snap1.documents,
      <DocumentViewChange>[change2],
      snap2.mutatedKeys /*hasPendingWrites*/,
      isFromCache: true,
      didSyncStateChange: false,
      excludesMetadataChanges: true,
    );
    expect(events, <ViewSnapshot>[expectedSnapshot1, expectedSnapshot2]);
  });

  test('testWillRaiseInitialEventWhenGoingOfflineAndThereAreNoDocs', () async {
    final List<ViewSnapshot> events = <ViewSnapshot>[];
    final Query query = Query(path('rooms'));

    final QueryStream listener =
        queryListener(query, const ListenOptions(), events);

    final View view = View(query, DocumentKey.emptyKeySet);
    final ViewSnapshot snap1 = applyChanges(view, <MaybeDocument>[]);

    listener
      ..onOnlineStateChanged(OnlineState.online) // no event
      ..onViewSnapshot(snap1) // no even
      ..onOnlineStateChanged(OnlineState.offline); // event
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final ViewSnapshot expectedSnapshot = ViewSnapshot(
      snap1.query,
      snap1.documents,
      DocumentSet.emptySet(snap1.query.comparator),
      <DocumentViewChange>[],
      snap1.mutatedKeys /*hasPendingWrites*/,
      isFromCache: true,
      didSyncStateChange: true,
      excludesMetadataChanges: true,
    );
    expect(events, <ViewSnapshot>[expectedSnapshot]);
  });

  test('testWillRaiseInitialEventWhenStartingOfflineAndThereAreNoDocs',
      () async {
    final List<ViewSnapshot> events = <ViewSnapshot>[];
    final Query query = Query(path('rooms'));

    final QueryStream listener =
        queryListener(query, const ListenOptions(), events);

    final View view = View(query, DocumentKey.emptyKeySet);
    final ViewSnapshot snap1 = applyChanges(view, <MaybeDocument>[]);

    listener
      ..onOnlineStateChanged(OnlineState.offline)
      ..onViewSnapshot(snap1);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final ViewSnapshot expectedSnapshot = ViewSnapshot(
      snap1.query,
      snap1.documents,
      DocumentSet.emptySet(snap1.query.comparator),
      <DocumentViewChange>[],
      snap1.mutatedKeys /*hasPendingWrites*/,
      isFromCache: true,
      didSyncStateChange: true,
      excludesMetadataChanges: true,
    );
    expect(events, <ViewSnapshot>[expectedSnapshot]);
  });
}

ViewSnapshot _applyExpectedMetadata(
    ViewSnapshot snap, MetadataChanges metadata) {
  return ViewSnapshot(
    snap.query,
    snap.documents,
    snap.oldDocuments,
    snap.changes,
    snap.mutatedKeys,
    isFromCache: snap.isFromCache,
    didSyncStateChange: snap.didSyncStateChange,
    excludesMetadataChanges: MetadataChanges.exclude == metadata,
  );
}
