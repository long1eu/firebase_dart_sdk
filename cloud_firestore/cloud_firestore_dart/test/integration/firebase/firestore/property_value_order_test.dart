// Property: the backend sorts values like the SDK (see
// test/util/property_backend.dart). BSON values are covered by
// test/integration_enterprise/property_value_order_test.dart.

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:test/test.dart';

import '../../../util/integration_test_util.dart';
import '../../../util/property.dart';
import '../../../util/property_backend.dart';

/// Property tests write many documents and compare with the emulator: they
/// never run against a real project.
final String? needsEmulator = IntegrationTestUtil.emulatorHost == null
    ? 'Runs against the emulator only: set FIRESTORE_EMULATOR_HOST.'
    : null;

void main() {
  configureGeneratorsForBackend();
  IntegrationTestUtil.currentDatabasePath = 'integration/property_value_order';

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  test(
    'orderBy on the backend agrees with the local order of values',
    skip: needsEmulator,
    () async {
      final Firestore firestore = await IntegrationTestUtil.testFirestore();
      for (int i = 0; i < cases(3); i++) {
        await checkValueOrderAgainstBackend(
          firestore,
          seed: caseSeed(i),
          count: 150,
          bson: false,
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
