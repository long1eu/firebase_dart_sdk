// Pins the behaviour differences between the Standard and the Enterprise
// edition that the standard integration suite runs into (the tests it skips
// with `IntegrationTestUtil.skipOnEnterprise`). They are listed in the
// "Enterprise edition" section of the package README.
//
//     FIRESTORE_ENTERPRISE_EMULATOR_HOST=127.0.0.1:8181 dart test test/integration_enterprise
//
// These were observed with the Firestore emulator v1.22.0 in Enterprise
// edition, not with a production Enterprise database. If one of them starts
// to fail, the emulator changed: update the README and the matching skip.

import 'package:cloud_firestore_dart/src/firebase/firestore/aggregate_field.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/aggregate_query_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/aggregate_source.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/collection_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/source.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart';
import 'package:test/test.dart';

import '../util/integration_test_util.dart';

const int maxLong = 9223372036854775807;

void main() {
  IntegrationTestUtil.currentDatabasePath =
      'integration_enterprise/edition_differences';

  final String? skipReason = IntegrationTestUtil.enterpriseEmulatorSkipReason;

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  Future<CollectionReference> collectionWithDocs(
      Map<String, Map<String, Object?>> docs) async {
    final Firestore firestore =
        await IntegrationTestUtil.testEnterpriseFirestore();
    final CollectionReference collection =
        firestore.collection('edition-differences-${autoId()}');
    await IntegrationTestUtil.writeAllDocs(collection, docs);
    return collection;
  }

  Future<List<String>> ids(Query query) async {
    final QuerySnapshot snapshot = await query.get(Source.server);
    return IntegrationTestUtil.querySnapshotToIds(snapshot)..sort();
  }

  test('equality filters match null and NaN', skip: skipReason, () async {
    final CollectionReference collection =
        await collectionWithDocs(<String, Map<String, Object?>>{
      'number': <String, Object?>{
        'value': 1,
        'array': <Object?>[1]
      },
      'null': <String, Object?>{
        'value': null,
        'array': <Object?>[null]
      },
      'nan': <String, Object?>{
        'value': double.nan,
        'array': <Object?>[double.nan]
      },
    });

    // The Standard edition returns no document for any of these.
    expect(await ids(collection.whereArrayContains('array', null)),
        <String>['null']);
    expect(await ids(collection.whereArrayContains('array', double.nan)),
        <String>['nan']);
    expect(
        await ids(collection.whereArrayContainsAny('array', <Object?>[null])),
        <String>['null']);
    expect(
        await ids(
            collection.whereArrayContainsAny('array', <Object?>[double.nan])),
        <String>['nan']);
    expect(await ids(collection.whereIn('value', <Object?>[null])),
        <String>['null']);
    expect(await ids(collection.whereIn('value', <Object?>[double.nan])),
        <String>['nan']);
  });

  test('the sum over no documents is null', skip: skipReason, () async {
    final CollectionReference collection =
        await collectionWithDocs(<String, Map<String, Object?>>{
      'a': <String, Object?>{'pages': 100},
    });

    final AggregateQuerySnapshot snapshot = await collection
        .where('pages', isGreaterThan: 1000)
        .aggregateWithAliases(<String, AggregateField>{
      'count': AggregateField.count(),
      'sum': AggregateField.sum('pages'),
      'average': AggregateField.average('pages'),
    }).get(AggregateSource.server);

    // The Standard edition returns 0 for the sum.
    expect(snapshot.data(),
        <String, Object?>{'count': 0, 'sum': null, 'average': null});
  });

  test('an aggregation covers documents without the aggregated fields',
      skip: skipReason, () async {
    final CollectionReference collection =
        await collectionWithDocs(<String, Map<String, Object?>>{
      'a': <String, Object?>{'pages': 100, 'year': 1980},
      'b': <String, Object?>{'pages': 50, 'year': 2020},
      'c': <String, Object?>{'pages': 150},
    });

    final AggregateQuerySnapshot snapshot =
        await collection.aggregateWithAliases(<String, AggregateField>{
      'count': AggregateField.count(),
      'totalPages': AggregateField.sum('pages'),
      'averageYear': AggregateField.average('year'),
    }).get(AggregateSource.server);

    // The Standard edition only aggregates over the documents that have
    // every aggregated field ('a' and 'b'): count 2, totalPages 150.
    expect(snapshot.data(), <String, Object?>{
      'count': 3,
      'totalPages': 300,
      'averageYear': 2000.0,
    });
  });

  test('more than 5 aggregations are allowed in one query', skip: skipReason,
      () async {
    final CollectionReference collection =
        await collectionWithDocs(<String, Map<String, Object?>>{
      'a': <String, Object?>{'a': 1, 'b': 2, 'c': 3},
      'b': <String, Object?>{'a': 3, 'b': 4, 'c': 5},
    });

    // The Standard edition rejects this with invalid-argument ("The maximum
    // number of aggregations allowed in an aggregation query is 5").
    final AggregateQuerySnapshot snapshot =
        await collection.aggregateWithAliases(<String, AggregateField>{
      'count': AggregateField.count(),
      'sumA': AggregateField.sum('a'),
      'sumB': AggregateField.sum('b'),
      'sumC': AggregateField.sum('c'),
      'averageA': AggregateField.average('a'),
      'averageB': AggregateField.average('b'),
    }).get(AggregateSource.server);

    expect(snapshot.data(), <String, Object?>{
      'count': 2,
      'sumA': 4,
      'sumB': 6,
      'sumC': 8,
      'averageA': 2.0,
      'averageB': 3.0,
    });
  });

  test('an integer sum that overflows fails instead of becoming a double',
      skip: skipReason, () async {
    final CollectionReference collection =
        await collectionWithDocs(<String, Map<String, Object?>>{
      'a': <String, Object?>{'rating': maxLong},
      'b': <String, Object?>{'rating': maxLong},
    });

    // The Standard edition returns the double 1.8446744073709552e19.
    await expectLater(
        collection
            .aggregate(<AggregateField>[AggregateField.sum('rating')]).get(
                AggregateSource.server),
        throwsA(isA<FirestoreError>()
            .having((FirestoreError e) => e.code, 'code',
                FirestoreErrorCode.invalidArgument)
            .having((FirestoreError e) => e.message, 'message',
                contains('Long overflow'))));
  });
}
