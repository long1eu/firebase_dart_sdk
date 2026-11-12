import 'dart:async';

import 'package:cloud_firestore_vm/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore.dart';
import 'package:test/test.dart';

import '../../../util/integration_test_util.dart';

// Issue #2: there is no process wide queue or scheduler; two instances work independently.
void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/multi';

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  test('two instances have their own scheduler and do not block each other',
      () async {
    final Firestore a = await IntegrationTestUtil.testFirestore();
    final Firestore b = await IntegrationTestUtil.testFirestore();
    expect(identical(a.scheduler, b.scheduler), isFalse);

    final DocumentReference refA = a.collection('multi-instance').document();
    final DocumentReference refB = b.collection('multi-instance').document();

    await Future.wait(<Future<void>>[
      refA.set(<String, Object?>{'who': 'a'}),
      refB.set(<String, Object?>{'who': 'b'}),
    ]).timeout(const Duration(seconds: 30));

    final DocumentSnapshot fromA = await refA.get();
    final DocumentSnapshot fromB = await refB.get();
    expect(fromA.data, <String, Object?>{'who': 'a'});
    expect(fromB.data, <String, Object?>{'who': 'b'});

    // Shutting one instance down leaves the other fully usable.
    await a.shutdown();
    await refB.set(<String, Object?>{'who': 'b2'});
    expect((await refB.get()).data, <String, Object?>{'who': 'b2'});
  });
}
