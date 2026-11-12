// Browser tests of the parts of the web transport that deal with imperfect
// networks: long polling and the online/offline events.
//
//   dart test -p chrome -c dart2wasm test/browser

@TestOn('browser')
library;

import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/connectivity_monitor.dart';
import 'package:rxdart/rxdart.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

import 'browser_test_util.dart';

typedef Json = Map<String, Object?>;

void main() {
  test('listens and writes with forced long polling', () async {
    final Firestore firestore = await newClient(forceLongPolling: true);
    final Firestore other = await newClient(forceLongPolling: true);
    final CollectionReference<Json> collection =
        firestore.collection(newCollectionName());

    final EventLog<QuerySnapshot<Json>> log =
        EventLog<QuerySnapshot<Json>>(collection.orderBy('n').snapshots);
    await log.waitFor((QuerySnapshot<Json> s) => s.docs.isEmpty);

    // Several rounds: in this mode every batch of data ends a response and
    // the client has to ask again.
    for (int i = 1; i <= 4; i++) {
      await other.collection(collection.id).doc('d$i').set(<String, Object?>{
        'n': i,
      });
      await log.waitFor((QuerySnapshot<Json> s) => s.docs.length == i);
    }
    expect(
        log.events.last.docs
            .map((QueryDocumentSnapshot<Json> d) => d.data['n'])
            .toList(),
        <int>[1, 2, 3, 4]);
    expect(log.errors, isEmpty);
    expect((await collection.count().get()).getCount(), 4);
  });

  test('the online and offline events of the browser reach the client',
      () async {
    final BehaviorSubject<bool> app = BehaviorSubject<bool>.seeded(true);
    final BehaviorSubject<bool> connectivity = withPlatformConnectivity(app);
    final List<bool> seen = <bool>[];
    final StreamSubscription<bool> sub = connectivity.listen(seen.add);
    await Future<void>.delayed(Duration.zero);
    expect(seen, <bool>[true]);

    web.window.dispatchEvent(web.Event('offline'));
    web.window.dispatchEvent(web.Event('online'));
    // What the app reports itself still counts.
    app.add(false);
    await Future<void>.delayed(Duration.zero);
    expect(seen, <bool>[true, false, true, false]);

    // Without a listener the events are no longer observed.
    await sub.cancel();
    web.window.dispatchEvent(web.Event('offline'));
    await Future<void>.delayed(Duration.zero);
    expect(seen, hasLength(4));
    await app.close();
  });

  test('a listener keeps working after the browser reports online again',
      () async {
    final Firestore firestore = await newClient();
    final Firestore other = await newClient();
    final CollectionReference<Json> collection =
        firestore.collection(newCollectionName());
    final EventLog<QuerySnapshot<Json>> log =
        EventLog<QuerySnapshot<Json>>(collection.snapshots);
    await log.waitFor((QuerySnapshot<Json> s) => s.docs.isEmpty);

    // The client restarts its streams on "online" (after a short debounce).
    web.window.dispatchEvent(web.Event('offline'));
    web.window.dispatchEvent(web.Event('online'));
    await Future<void>.delayed(const Duration(seconds: 2));

    await other.collection(collection.id).doc('a').set(<String, Object?>{
      'a': 1,
    });
    await log.waitFor((QuerySnapshot<Json> s) =>
        s.docs.length == 1 && !s.metadata.isFromCache);
    await firestore.collection(collection.id).doc('b').set(<String, Object?>{
      'b': 1,
    });
    await log.waitFor((QuerySnapshot<Json> s) => s.docs.length == 2);
    expect(log.errors, isEmpty);
  });
}
