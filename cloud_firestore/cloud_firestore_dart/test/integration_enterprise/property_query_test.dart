// Property: the SDK evaluates a query to the documents the Enterprise
// edition backend returns (see test/util/property_backend.dart and
// test/integration/firebase/firestore/property_query_test.dart).
//
//     FIRESTORE_ENTERPRISE_EMULATOR_HOST=127.0.0.1:8181 \
//         dart test test/integration_enterprise/property_query_test.dart

import 'package:test/test.dart';

import '../util/integration_test_util.dart';
import '../util/property.dart';
import '../util/property_backend.dart';

void main() {
  IntegrationTestUtil.currentDatabasePath =
      'integration_enterprise/property_query';

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  test('local query evaluation agrees with the backend',
      skip: IntegrationTestUtil.enterpriseEmulatorSkipReason, () async {
    final QueryPropertyStats stats = QueryPropertyStats();
    for (int i = 0; i < cases(4); i++) {
      await checkQueriesAgainstBackend(
          IntegrationTestUtil.testEnterpriseFirestore,
          seed: caseSeed(i),
          documentCount: 40,
          queryCount: 100,
          stats: stats,
          // See checkQueriesAgainstBackend.
          limits: false,
          nullAndNaNOperands: true);
    }
    print('query property: $stats');
    if (stats.failures.isNotEmpty) {
      fail('${stats.failures.length} failure(s):\n\n'
          '${stats.failures.join('\n')}');
    }
    expect(stats.compared, greaterThan(cases(4) * 100 ~/ 2), reason: '$stats');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
