// Property: the Enterprise edition backend sorts values, including the BSON
// types, like the SDK (see test/util/property_backend.dart). Needs the
// Enterprise edition emulator (tool/start_enterprise_emulator.sh):
//
//     FIRESTORE_ENTERPRISE_EMULATOR_HOST=127.0.0.1:8181 \
//         dart test test/integration_enterprise/property_value_order_test.dart

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:test/test.dart';

import '../util/integration_test_util.dart';
import '../util/property.dart';
import '../util/property_backend.dart';

void main() {
  IntegrationTestUtil.currentDatabasePath =
      'integration_enterprise/property_value_order';

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  test('orderBy on the backend agrees with the local order of BSON values',
      skip: IntegrationTestUtil.enterpriseEmulatorSkipReason, () async {
    final Firestore firestore =
        await IntegrationTestUtil.testEnterpriseFirestore();
    for (int i = 0; i < cases(3); i++) {
      await checkValueOrderAgainstBackend(firestore,
          seed: caseSeed(i), count: 150, bson: true);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
