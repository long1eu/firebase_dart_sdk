// File created by
// Lung Razvan <long1eu>
// on 10/10/2018

import 'dart:async';

import 'package:firebase_firestore/src/firebase/firestore/collection_reference.dart';
import 'package:firebase_firestore/src/firebase/firestore/document_reference.dart';
import 'package:firebase_firestore/src/firebase/firestore/document_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/query_snapshot.dart';
import 'package:test/test.dart';

import '../../../util/await_helper.dart';
import '../../../util/integration_test_util.dart';
import '../../../util/test_util.dart';

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/stream_subscription';

  setUp(() => testFirestore());

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  test('canBeRemoved', () async {
    final CollectionReference collectionReference = await testCollection();
    final DocumentReference documentReference = collectionReference.document();

    final AwaitHelper<void> events = AwaitHelper<void>(4);
    final StreamSubscription<QuerySnapshot> one =
        collectionReference.snapshots.listen(
      (QuerySnapshot value) => events.completeNext(),
      onError: (dynamic error) {
        assert(false, 'This should not happen.');
      },
    );

    final StreamSubscription<DocumentSnapshot> two =
        documentReference.snapshots.listen(
      (DocumentSnapshot value) => events.completeNext(),
      onError: (dynamic error) {
        assert(false, 'This should not happen.');
      },
    );

    // Initial events
    await events.following(2);

    // Trigger new events
    documentReference.set(map(<String>['foo', 'bar']));

    // Write events should have triggered
    await events.following(2);

    // No more events should occur
    await one.cancel();
    await two.cancel();

    await documentReference.set(map(<String>['foo', 'new-bar']));

    // Assert no events actually occurred
    expect(events.isCompleted, isTrue);
  });

  test('canBeRemovedTwice', () async {
    final CollectionReference reference = await testCollection();
    final StreamSubscription<QuerySnapshot> one =
        reference.snapshots.listen((QuerySnapshot value) {});
    final StreamSubscription<DocumentSnapshot> two =
        reference.document().snapshots.listen((DocumentSnapshot value) {});

    one.cancel();
    one.cancel();

    two.cancel();
    two.cancel();
  });

  test('canBeRemovedIndependently', () async {
    final CollectionReference collectionReference = await testCollection();

    final AwaitHelper<void> eventsOne = AwaitHelper<void>(2);
    final AwaitHelper<void> eventsTwo = AwaitHelper<void>(3);

    final StreamSubscription<QuerySnapshot> one =
        collectionReference.snapshots.listen(
      (QuerySnapshot value) => eventsOne.completeNext(),
      onError: (dynamic error) {
        assert(false, 'This should not happen.');
      },
    );

    final StreamSubscription<QuerySnapshot> two =
        collectionReference.snapshots.listen(
      (QuerySnapshot value) => eventsTwo.completeNext(),
      onError: (dynamic error) {
        assert(false, 'This should not happen.');
      },
    );

    // Initial events
    await eventsOne.next;
    await eventsTwo.next;

    // Trigger new events
    collectionReference.add(map(<String>['foo', 'bar']));

    await eventsOne.next;
    await eventsTwo.next;

    // Should leave 'two' unaffected
    one.cancel();

    collectionReference.add(map(<String>['foo', 'new-bar']));

    // Assert only events for 'two' actually occurred
    expect(eventsOne.isCompleted, isTrue);
    expect(eventsTwo.isCompleted, isFalse);

    await eventsTwo.next;

    // No more events should occur
    two.cancel();
  });
}

// ignore: always_specify_types
const map = TestUtil.map;
// ignore: always_specify_types
const testFirestore = IntegrationTestUtil.testFirestore;
// ignore: always_specify_types
const testCollection = IntegrationTestUtil.testCollection;
