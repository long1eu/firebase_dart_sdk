// Checks that a test cleaned up after itself. A test that leaves a running
// Firestore instance or an operation in flight behind does not fail by
// itself: the instance keeps its streams open, and the operation fails later,
// as an unhandled error in whichever test runs then.

import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_multi_db_component.dart';
import 'package:test/test.dart';

/// The instances created with `Firestore.instanceFor` that are still running,
/// as `app/database` keys.
List<String> runningFirestoreInstances() {
  return <String>[
    for (final MapEntry<String, Firestore> entry
        in FirestoreMultiDbComponent.instances.entries)
      if (!entry.value.client.isTerminated) entry.key
  ];
}

/// Fails the current test when it left a Firestore instance running, or when
/// one of [instances] (instances created outside the instance registry, as
/// the integration tests do) was not terminated.
///
/// It first lets the event queue drain, so that an asynchronous error of an
/// operation the test did not wait for is reported for this test (the test
/// runner fails a test for an unhandled error) and not for a later one.
Future<void> expectTestLeftNothingBehind(
    {Iterable<Firestore> instances = const <Firestore>[]}) async {
  await pumpEventQueue();
  expect(runningFirestoreInstances(), isEmpty,
      reason: 'The test left Firestore instances running: terminate() them, '
          'for example with addTearDown(firestore.terminate)');
  expect(
      instances.where((Firestore firestore) => !firestore.client.isTerminated),
      isEmpty,
      reason: 'The test left Firestore instances running');
}

/// Registers [expectTestLeftNothingBehind] for every test of the file. Call
/// it first in `main()`: tear-downs run in reverse order, so the check runs
/// after the cleanup the file registers itself.
void checkTestsLeaveNothingBehind() {
  tearDown(expectTestLeftNothingBehind);
}
