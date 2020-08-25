// File created by
// Lung Razvan <long1eu>
// on 26/09/2018
import 'package:cloud_firestore_vm/src/firebase/firestore/core/event_manager.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/online_state.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query_stream.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/sync_engine.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/view_snapshot.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

class QueryListenerMock extends Mock implements QueryStream {}

class SyncEngineMock extends Mock implements SyncEngine {}

class ViewSnapshotMock extends Mock implements ViewSnapshot {}

// ignore_for_file: unawaited_futures, avoid_implementing_value_types
void main() {
  QueryStream queryListener(Query query) {
    return QueryStream(query)..listen(null);
  }

  test('testMultipleListenersPerQuery', () async {
    final Query query = Query(path('foo/bar'));

    final QueryStream listener1 = queryListener(query);
    final QueryStream listener2 = queryListener(query);

    final SyncEngine syncSpy = SyncEngineMock();

    final EventManager manager = EventManager(syncSpy)
      ..addQueryListener(listener1)
      ..addQueryListener(listener2);

    await manager.removeQueryListener(listener1);
    await manager.removeQueryListener(listener2);

    verify(syncSpy.listen(query)).called(1);
    verify(syncSpy.stopListening(query)).called(1);
  });

  test('testUnlistensOnUnknownListeners', () async {
    final Query query = Query(path('foo/bar'));
    final SyncEngine syncSpy = SyncEngineMock();

    final EventManager manager = EventManager(syncSpy);
    await manager.removeQueryListener(queryListener(query));
    verifyNever(syncSpy.stopListening(query));
  });

  test('testListenCalledInOrder', () async {
    final Query query1 = Query(path('foo/bar'));
    final Query query2 = Query(path('bar/baz'));

    final SyncEngine syncSpy = SyncEngineMock();
    final EventManager eventManager = EventManager(syncSpy);

    final QueryStream spy1 = QueryListenerMock();
    when(spy1.query).thenReturn(query1);
    final QueryStream spy2 = QueryListenerMock();
    when(spy2.query).thenReturn(query2);
    final QueryStream spy3 = QueryListenerMock();
    when(spy3.query).thenReturn(query1);
    eventManager
      ..addQueryListener(spy1)
      ..addQueryListener(spy2)
      ..addQueryListener(spy3);

    verify(syncSpy.listen(query1)).called(1);
    verify(syncSpy.listen(query2)).called(1);

    final ViewSnapshot snap1 = ViewSnapshotMock();
    when(snap1.query).thenReturn(query1);

    final ViewSnapshot snap2 = ViewSnapshotMock();
    when(snap2.query).thenReturn(query2);

    await eventManager.onViewSnapshots(<ViewSnapshot>[snap1, snap2]);

    verifyInOrder(<void>[
      await spy1.onViewSnapshot(snap1),
      await spy3.onViewSnapshot(snap1),
      await spy2.onViewSnapshot(snap2),
    ]);
  });

  test('testWillForwardOnOnlineStateChangedCalls', () {
    final Query query1 = Query(path('foo/bar'));

    final SyncEngine syncSpy = SyncEngineMock();
    final EventManager eventManager = EventManager(syncSpy);

    final List<Object> events = <Object>[];

    final QueryStream spy = QueryListenerMock();
    when(spy.query).thenReturn(query1);

    when(spy.onOnlineStateChanged(any)).thenAnswer((Invocation invocation) =>
        events.add(invocation.positionalArguments[0]));

    eventManager.addQueryListener(spy);
    expect(events, <OnlineState>[OnlineState.unknown]);
    eventManager.handleOnlineStateChange(OnlineState.online);
    expect(events, <OnlineState>[OnlineState.unknown, OnlineState.online]);
  });
}
