// Terminating an instance while calls are in flight or streams are closing
// must fail the pending operations of that instance (if at all) through their
// own futures, never as an unhandled asynchronous error.

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/aggregate_field.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/aggregate_source.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/collection_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/transaction.dart';
import 'package:test/test.dart';

import '../../../util/integration_test_util.dart';
import '../../../util/test_util.dart';

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/terminate_in_flight';

  test('terminate with calls in flight raises no unhandled error', () async {
    final List<Object> unhandled = <Object>[];
    int failedOperations = 0;

    await runZonedGuarded(() async {
      for (int round = 0; round < 15; round++) {
        final Firestore firestore = await IntegrationTestUtil.testFirestore();
        final CollectionReference collection =
            firestore.collection('terminate${DateTime.now().microsecondsSinceEpoch}');
        final DocumentReference doc = collection.document();
        await doc.set(map(<dynamic>['count', 1]));

        // A listener (listen stream open) that is cancelled right before the
        // shutdown, so its stream is closing.
        final StreamSubscription<QuerySnapshot> listener =
            collection.snapshots.listen((QuerySnapshot _) {}, onError: (Object _) {});
        await Future<void>.delayed(Duration(milliseconds: round * 3));

        // Operations of every kind, in flight at shutdown. Their callers
        // handle the outcome, whatever it is.
        final List<Future<void>> operations = <Future<void>>[
          doc.set(map(<dynamic>['count', 2])),
          firestore.runTransaction<void>((Transaction transaction) async {
            await transaction.get(doc);
            transaction.set(doc, map(<dynamic>['count', 3]));
          }),
          collection
              .aggregate(<AggregateField>[AggregateField.count()])
              .get(AggregateSource.server),
        ].map((Future<void> operation) {
          return operation.catchError((Object _) {
            failedOperations++;
          });
        }).toList();

        unawaited(listener.cancel());
        await firestore.terminate();
        // The write stays pending forever on a terminated instance.
        await Future.wait(operations.skip(1))
            .timeout(const Duration(seconds: 20));
      }
      // Late errors of the closed connections surface here, if any.
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }, (Object error, StackTrace stackTrace) => unhandled.add(error));

    // ignore: avoid_print
    print('operations that failed because of the shutdown: $failedOperations');
    expect(unhandled, isEmpty);
    IntegrationTestUtil.firestoreStatus.clear();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
