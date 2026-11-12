import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_snapshot.dart';
import 'package:test/test.dart';

import '../../../util/integration_test_util.dart';
import '../../../util/test_util.dart';

const testFirestore = IntegrationTestUtil.testFirestore;
const testCollection = IntegrationTestUtil.testCollection;

void main() {
  IntegrationTestUtil.currentDatabasePath =
      'integration/document_snapshot_test';

  setUp(() => testFirestore());

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  test('snapshots of the same document are equal', () async {
    final DocumentReference documentReference =
        (await testCollection('rooms')).document('eros');
    final Map<String, Object?> initialValue = map(<dynamic>[
      'desc',
      'Description',
      'owner',
      map<String>(<String>['name', 'Jonny', 'email', 'abc@xyz.com'])
    ]);
    await documentReference.set(initialValue);

    final DocumentSnapshot snapshot1 = await documentReference.get();
    final DocumentSnapshot snapshot2 = await documentReference.get();
    final DocumentSnapshot snapshot3 = await documentReference.get();
    expect(snapshot1.metadata, snapshot2.metadata);
    expect(snapshot2.metadata, snapshot3.metadata);

    expect(snapshot1.id, snapshot2.id);
    expect(snapshot2.id, snapshot3.id);

    expect(snapshot1.exists, snapshot2.exists);
    expect(snapshot2.exists, snapshot3.exists);

    expect(snapshot1.reference, snapshot2.reference);
    expect(snapshot2.reference, snapshot3.reference);

    expect(snapshot1.data, snapshot2.data);
    expect(snapshot2.data, snapshot3.data);

    expect(snapshot1, snapshot2);
    expect(snapshot2, snapshot3);
  });
}
