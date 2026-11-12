// Property: the SDK evaluates a query to the documents the backend returns
// (see test/util/property_backend.dart): filters including OR, != / not-in,
// null and NaN, array-contains(-any), cursors on fields with values of
// several types, limit and limitToLast.

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart'
    show autoId;
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
  IntegrationTestUtil.currentDatabasePath = 'integration/property_query';

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  test(
    'local query evaluation agrees with the backend',
    skip:
        needsEmulator ??
        IntegrationTestUtil.skipOnEnterprise(
          'limits and null/NaN operands of membership filters behave '
          'differently; test/integration_enterprise/property_query_test.dart '
          'runs the property without them',
        ),
    () async {
      final QueryPropertyStats stats = QueryPropertyStats();
      for (int i = 0; i < cases(4); i++) {
        await checkQueriesAgainstBackend(
          IntegrationTestUtil.testFirestore,
          seed: caseSeed(i),
          documentCount: 40,
          queryCount: 100,
          stats: stats,
        );
      }
      print('query property: $stats');
      if (stats.failures.isNotEmpty) {
        fail(
          '${stats.failures.length} failure(s):\n\n'
          '${stats.failures.join('\n')}',
        );
      }
      // The generator must mostly produce queries that both sides accept.
      expect(
        stats.compared,
        greaterThan(cases(4) * 100 ~/ 2),
        reason: '$stats',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  // The SDK treats null and NaN as the same as themselves in `in`, `not-in`,
  // the array filters, `<=` and `>=`, like the JS and Android SDKs and like an
  // Enterprise edition database. A Standard edition database never matches
  // them there. So when such a document is in the cache, the SDK keeps it in
  // the view of the query while the backend says that it is not a result: it
  // stays in limbo, the listener keeps reporting `isFromCache` and
  // `get(Source.server)` does not complete. The property above leaves these
  // operands out; this test pins the two sides.
  test(
    'known difference: null and NaN operands on a Standard edition backend',
    skip:
        needsEmulator ??
        IntegrationTestUtil.skipOnEnterprise(
          'an Enterprise edition database matches null and NaN like the SDK',
        ),
    () async {
      final Firestore writer = await IntegrationTestUtil.testFirestore();
      final CollectionReference<Map<String, Object?>> written = writer
          .collection('property_query_${autoId()}');
      await written.doc('null').set(<String, Object?>{'v': null});
      await written.doc('nan').set(<String, Object?>{'v': double.nan});
      await written.doc('one').set(<String, Object?>{'v': 1});
      await written.doc('array').set(<String, Object?>{
        'v': <Object?>[null, double.nan],
      });
      final Map<String, Document> documents = <String, Document>{
        for (final QueryDocumentSnapshot<Map<String, Object?>> doc
            in (await written.get(Source.server)).docs)
          doc.id: doc.document!,
      };

      // A second instance has nothing cached, so it returns what the backend
      // returns.
      final CollectionReference<Map<String, Object?>> collection =
          (await IntegrationTestUtil.testFirestore()).collection(written.path);
      Future<void> expectDifference(
        Query<Map<String, Object?>> query, {
        required List<String> backend,
        required List<String> sdk,
      }) async {
        expect(<String>[
          for (final QueryDocumentSnapshot<Map<String, Object?>> doc
              in (await query.get(Source.server)).docs)
            doc.id,
        ], backend);
        expect(<String>[
          for (final MapEntry<String, Document> entry in documents.entries)
            if (query.query.matches(entry.value)) entry.key,
        ], unorderedEquals(sdk));
      }

      await expectDifference(
        collection.where('v', whereIn: <Object?>[null, 1]),
        backend: <String>['one'],
        sdk: <String>['one', 'null'],
      );
      await expectDifference(
        collection.where('v', whereIn: <Object?>[double.nan]),
        backend: <String>[],
        sdk: <String>['nan'],
      );
      await expectDifference(
        collection.where(Filter.arrayContains('v', null)),
        backend: <String>[],
        sdk: <String>['array'],
      );
      await expectDifference(
        collection.where('v', arrayContainsAny: <Object?>[double.nan]),
        backend: <String>[],
        sdk: <String>['array'],
      );
      await expectDifference(
        collection.where(Filter.lessThanOrEqualTo('v', null)),
        backend: <String>[],
        sdk: <String>['null'],
      );
      await expectDifference(
        collection.where('v', isGreaterThanOrEqualTo: double.nan),
        backend: <String>[],
        sdk: <String>['nan'],
      );
      // Where both sides agree: `<` and `>` never hold for them, and a NaN is
      // not smaller than a number.
      await expectDifference(
        collection.where('v', isGreaterThan: double.nan),
        backend: <String>[],
        sdk: <String>[],
      );
      await expectDifference(
        collection.where('v', isLessThan: 2),
        backend: <String>['one'],
        sdk: <String>['one'],
      );
    },
  );
}
