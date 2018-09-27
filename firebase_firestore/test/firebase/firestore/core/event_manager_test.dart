// File created by
// Lung Razvan <long1eu>
// on 26/09/2018
import 'package:firebase_firestore/src/firebase/firestore/core/event_manager.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/online_state.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query_listener.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/sync_engine.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/view_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore_error.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../../../util/test_util.dart';

class QueryListenerMock extends Mock implements QueryListener {}

class SyncEngineMock extends Mock implements SyncEngine {}

class ViewSnapshotMock extends Mock implements ViewSnapshot {}

void main() {
  QueryListener queryListener(Query query) {
    return QueryListener(query, ListenOptions(),
        (ViewSnapshot value, FirebaseFirestoreError error) {});
  }

  test('testMultipleListenersPerQuery', () {
    final Query query = Query.atPath(TestUtil.path('foo/bar'));

    final QueryListener listener1 = queryListener(query);
    final QueryListener listener2 = queryListener(query);

    final SyncEngine syncSpy = SyncEngineMock();

    final EventManager manager = EventManager(syncSpy);
    manager.addQueryListener(listener1);
    manager.addQueryListener(listener2);

    manager.removeQueryListener(listener1);
    manager.removeQueryListener(listener2);

    verify(syncSpy.listen(query)).called(1);
    verify(syncSpy.stopListening(query)).called(1);
  });

  test('testUnlistensOnUnknownListeners', () {
    final Query query = Query.atPath(TestUtil.path('foo/bar'));
    final SyncEngine syncSpy = SyncEngineMock();

    final EventManager manager = EventManager(syncSpy);
    manager.removeQueryListener(queryListener(query));
    verifyNever(syncSpy.stopListening(query));
  });

  test('testListenCalledInOrder', () {
    final Query query1 = Query.atPath(TestUtil.path('foo/bar'));
    final Query query2 = Query.atPath(TestUtil.path('bar/baz'));

    final SyncEngine syncSpy = SyncEngineMock();
    final EventManager eventManager = EventManager(syncSpy);

    final QueryListener spy1 = QueryListenerMock();
    when(spy1.query).thenReturn(query1);
    final QueryListener spy2 = QueryListenerMock();
    when(spy2.query).thenReturn(query2);
    final QueryListener spy3 = QueryListenerMock();
    when(spy3.query).thenReturn(query1);
    eventManager.addQueryListener(spy1);
    eventManager.addQueryListener(spy2);
    eventManager.addQueryListener(spy3);

    verify(syncSpy.listen(query1)).called(1);
    verify(syncSpy.listen(query2)).called(1);

    final ViewSnapshot snap1 = ViewSnapshotMock();
    when(snap1.query).thenReturn(query1);

    final ViewSnapshot snap2 = ViewSnapshotMock();
    when(snap2.query).thenReturn(query2);

    eventManager.onViewSnapshots(<ViewSnapshot>[snap1, snap2]);

    verifyInOrder(<void>[
      spy1.onViewSnapshot(snap1),
      spy3.onViewSnapshot(snap1),
      spy2.onViewSnapshot(snap2),
    ]);
  });

  test('testWillForwardOnOnlineStateChangedCalls', () {
    final Query query1 = Query.atPath(TestUtil.path('foo/bar'));

    final SyncEngine syncSpy = SyncEngineMock();
    final EventManager eventManager = EventManager(syncSpy);

    final List<Object> events = <Object>[];

    final QueryListener spy = QueryListenerMock();
    when(spy.query).thenReturn(query1);

    when(spy.onOnlineStateChanged(any)).thenAnswer((Invocation invocation) =>
        events.add(invocation.positionalArguments[0]));

    eventManager.addQueryListener(spy);
    expect(events, <OnlineState>[OnlineState.unknown]);
    eventManager.handleOnlineStateChange(OnlineState.online);
    expect(events, <OnlineState>[OnlineState.unknown, OnlineState.online]);
  });
}
