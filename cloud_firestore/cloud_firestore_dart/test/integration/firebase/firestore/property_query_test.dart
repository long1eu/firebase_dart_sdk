// Property: the SDK evaluates a query to the documents the backend returns
// (see test/util/property_backend.dart): filters including OR, != / not-in,
// null and NaN, array-contains(-any), cursors on fields with values of
// several types, limit and limitToLast.

import 'dart:async';

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
  // them there. So the SDK finds such a cached document for the query while
  // the backend says that it is not a result. The document is in limbo until
  // the limbo resolution finds that it exists; then the SDK trusts the
  // backend and takes it out of the result. (The JS and Android SDKs leave
  // it in limbo forever: the listener never leaves `isFromCache` and a get
  // from the server does not complete.)
  test(
    'null and NaN operands on a Standard edition backend: the client '
    'converges to the answer of the backend',
    skip:
        needsEmulator ??
        IntegrationTestUtil.skipOnEnterprise(
          'an Enterprise edition database matches null and NaN like the SDK',
        ),
    () async {
      final Firestore firestore = await IntegrationTestUtil.testFirestore();
      final CollectionReference<Map<String, Object?>> collection = firestore
          .collection('property_query_${autoId()}');
      await collection.doc('null').set(<String, Object?>{'v': null});
      await collection.doc('nan').set(<String, Object?>{'v': double.nan});
      await collection.doc('one').set(<String, Object?>{'v': 1});
      await collection.doc('array').set(<String, Object?>{
        'v': <Object?>[null, double.nan],
      });
      // All documents are in the cache of this client.
      final Map<String, Document> documents = <String, Document>{
        for (final QueryDocumentSnapshot<Map<String, Object?>> doc
            in (await collection.get(Source.server)).docs)
          doc.id: doc.document!,
      };

      Future<void> expectConvergence(
        Query<Map<String, Object?>> query, {
        required List<String> backend,
        required List<String> sdk,
      }) async {
        // What the client's own evaluation says.
        expect(<String>[
          for (final MapEntry<String, Document> entry in documents.entries)
            if (query.query.matches(entry.value)) entry.key,
        ], unorderedEquals(sdk));
        expect(<String>[
          for (final QueryDocumentSnapshot<Map<String, Object?>> doc
              in (await query.get(Source.cache)).docs)
            doc.id,
        ], unorderedEquals(sdk));

        // A get from the server completes with the answer of the backend.
        final QuerySnapshot<Map<String, Object?>> snapshot = await query
            .get(Source.server)
            .timeout(const Duration(seconds: 20));
        expect(<String>[
          for (final QueryDocumentSnapshot<Map<String, Object?>> doc
              in snapshot.docs)
            doc.id,
        ], backend);
        expect(snapshot.metadata.isFromCache, isFalse);

        // A listener sees the cached result first and then the answer of the
        // backend, and nothing after that (the document does not come back).
        final List<QuerySnapshot<Map<String, Object?>>> events =
            <QuerySnapshot<Map<String, Object?>>>[];
        final StreamSubscription<QuerySnapshot<Map<String, Object?>>>
        subscription = query
            .getSnapshots(MetadataChanges.include)
            .listen(events.add);
        await Future<void>.delayed(const Duration(seconds: 2));
        await subscription.cancel();
        expect(events, isNotEmpty);
        expect(events.last.metadata.isFromCache, isFalse);
        expect(<String>[
          for (final QueryDocumentSnapshot<Map<String, Object?>> doc
              in events.last.docs)
            doc.id,
        ], backend);
        expect(
          events.length,
          lessThanOrEqualTo(2),
          reason: 'the listener must not flap',
        );
      }

      await expectConvergence(
        collection.where('v', whereIn: <Object?>[null, 1]),
        backend: <String>['one'],
        sdk: <String>['one', 'null'],
      );
      await expectConvergence(
        collection.where('v', whereIn: <Object?>[double.nan]),
        backend: <String>[],
        sdk: <String>['nan'],
      );
      await expectConvergence(
        collection.where(Filter.arrayContains('v', null)),
        backend: <String>[],
        sdk: <String>['array'],
      );
      await expectConvergence(
        collection.where('v', arrayContainsAny: <Object?>[double.nan]),
        backend: <String>[],
        sdk: <String>['array'],
      );
      await expectConvergence(
        collection.where(Filter.lessThanOrEqualTo('v', null)),
        backend: <String>[],
        sdk: <String>['null'],
      );
      await expectConvergence(
        collection.where('v', isGreaterThanOrEqualTo: double.nan),
        backend: <String>[],
        sdk: <String>['nan'],
      );
      // Where both sides agree: `<` and `>` never hold for them, and a NaN is
      // not smaller than a number.
      await expectConvergence(
        collection.where('v', isGreaterThan: double.nan),
        backend: <String>[],
        sdk: <String>[],
      );
      await expectConvergence(
        collection.where('v', isLessThan: 2),
        backend: <String>['one'],
        sdk: <String>['one'],
      );

      // The documents are still in the cache and still results of other
      // queries.
      expect((await collection.get(Source.server)).docs, hasLength(4));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  // The same for random queries: with null and NaN operands, the client that
  // has all documents cached gets what a client without a cache gets.
  test(
    'queries with null and NaN operands converge to the result of an '
    'uncached client',
    skip:
        needsEmulator ??
        IntegrationTestUtil.skipOnEnterprise(
          'covered by test/integration_enterprise/property_query_test.dart',
        ),
    () async {
      final QueryPropertyStats stats = QueryPropertyStats();
      for (int i = 0; i < cases(2); i++) {
        await checkQueriesAgainstBackend(
          IntegrationTestUtil.testFirestore,
          seed: caseSeed(1000 + i),
          documentCount: 40,
          queryCount: 100,
          stats: stats,
          nullAndNaNOperands: true,
          compareWithUncachedClient: true,
        );
      }
      print('query property (null and NaN operands): $stats');
      if (stats.failures.isNotEmpty) {
        fail(
          '${stats.failures.length} failure(s):\n\n'
          '${stats.failures.join('\n')}',
        );
      }
      expect(
        stats.compared,
        greaterThan(cases(2) * 100 ~/ 2),
        reason: '$stats',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
