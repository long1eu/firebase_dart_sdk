// Smoke test of the Enterprise edition emulator (tool/start_enterprise_emulator.sh):
//
//     FIRESTORE_ENTERPRISE_EMULATOR_HOST=127.0.0.1:8181 dart test test/integration_enterprise
//
// Tests in this directory need features of the Enterprise edition; they are
// skipped, with a reason, when the variable is not set. This one only checks
// that the SDK can write to and read from that emulator; it cannot tell the
// edition of the emulator it talks to.

import 'package:cloud_firestore_dart/src/firebase/firestore/collection_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/source.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart';
import 'package:test/test.dart';

import '../util/integration_test_util.dart';

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration_enterprise/smoke';

  final String? skipReason = IntegrationTestUtil.enterpriseEmulatorSkipReason;

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  test('writes and reads documents on the enterprise emulator',
      skip: skipReason, () async {
    final Firestore firestore =
        await IntegrationTestUtil.testEnterpriseFirestore();
    final CollectionReference collection =
        firestore.collection('enterprise-smoke-${autoId()}');
    final DocumentReference doc = collection.document('a');

    await doc.set(<String, Object?>{'value': 1, 'name': 'enterprise'});
    await collection.document('b').set(<String, Object?>{'value': 2});

    final DocumentSnapshot snapshot = await doc.get(Source.server);
    expect(snapshot.exists, isTrue);
    expect(snapshot.data, <String, Object?>{'value': 1, 'name': 'enterprise'});
    expect(snapshot.metadata.isFromCache, isFalse);

    final QuerySnapshot query =
        await collection.where('value', isGreaterThan: 1).get(Source.server);
    expect(query.docs.map((DocumentSnapshot d) => d.id), <String>['b']);
  });

  test('the enterprise emulator is separate from the standard one',
      skip: skipReason ??
          (IntegrationTestUtil.emulatorHost == null
              ? 'FIRESTORE_EMULATOR_HOST is not set: needs both emulators'
              : null), () async {
    final String path = 'enterprise-smoke-${autoId()}/doc';
    final Firestore enterprise =
        await IntegrationTestUtil.testEnterpriseFirestore();
    await enterprise.document(path).set(<String, Object?>{'value': 1});

    final Firestore standard = await IntegrationTestUtil.testFirestore();
    final DocumentSnapshot snapshot =
        await standard.document(path).get(Source.server);
    expect(snapshot.exists, isFalse);
  });
}
