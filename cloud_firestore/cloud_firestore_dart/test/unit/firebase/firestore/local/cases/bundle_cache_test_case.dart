// Copyright 2021 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_metadata.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundled_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/named_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/bound.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/bundle_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../../../util/test_util.dart';

/// Defines the tests for any implementation of the [BundleCache] interface (port of the Android
/// `BundleCacheTestCase`).
///
/// [createPersistence] creates and starts the [Persistence] under test. It is called once per test.
void defineBundleCacheTests(Future<Persistence> Function() createPersistence) {
  late Persistence persistence;
  late BundleCache bundleCache;

  setUp(() async {
    persistence = await createPersistence();
    bundleCache = persistence.bundleCache;
  });

  tearDown(() => persistence.shutdown());

  Future<T> inTransaction<T>(Future<T> Function() action) =>
      persistence.runTransactionAndReturn<T>('bundle cache test', action);

  Future<void> expectRoundTrip(
      Query query, BundledQueryLimitType limitType) async {
    final NamedQuery expectedQuery = NamedQuery('query-1',
        BundledQuery(query, limitType), SnapshotVersion(Timestamp.now()));
    await inTransaction(() => bundleCache.saveNamedQuery(expectedQuery));

    final NamedQuery? actualQuery =
        await inTransaction(() => bundleCache.getNamedQuery('query-1'));
    expect(actualQuery, expectedQuery);
  }

  test('testReturnsNullWhenBundleIdNotFound', () async {
    expect(await inTransaction(() => bundleCache.getBundleMetadata('bundle-1')),
        isNull);
  });

  test('testReturnsSavedBundle', () async {
    BundleMetadata expectedBundleMetadata =
        BundleMetadata('bundle-1', 1, SnapshotVersion(Timestamp.now()), 1, 10);
    await inTransaction(
        () => bundleCache.saveBundleMetadata(expectedBundleMetadata));
    BundleMetadata? actualBundleMetadata =
        await inTransaction(() => bundleCache.getBundleMetadata('bundle-1'));

    expect(actualBundleMetadata, expectedBundleMetadata);

    // Overwrite
    expectedBundleMetadata =
        BundleMetadata('bundle-1', 2, SnapshotVersion(Timestamp.now()), 1, 10);
    await inTransaction(
        () => bundleCache.saveBundleMetadata(expectedBundleMetadata));
    actualBundleMetadata =
        await inTransaction(() => bundleCache.getBundleMetadata('bundle-1'));

    expect(actualBundleMetadata, expectedBundleMetadata);
  });

  test('testReturnsNullWhenQueryNameIsNotFound', () async {
    expect(await inTransaction(() => bundleCache.getNamedQuery('query-1')),
        isNull);
  });

  test('testReturnsSavedCollectionQueries', () async {
    await expectRoundTrip(Query(path('room')), BundledQueryLimitType.first);
  });

  test('testReturnsSavedLimitToFirstQueries', () async {
    await expectRoundTrip(
        Query(path('room'), limit: 1), BundledQueryLimitType.first);
  });

  test('testReturnsSavedLimitToLastQueries', () async {
    await expectRoundTrip(
        Query(path('room'), limit: 1), BundledQueryLimitType.last);
  });

  test('testReturnsSavedCollectionGroupQueries', () async {
    await expectRoundTrip(
        Query(ResourcePath.empty, collectionGroup: 'collectionGroup', limit: 1),
        BundledQueryLimitType.first);
  });

  test('testReturnsSavedQueriesWithFiltersOrdersAndBounds', () async {
    await expectRoundTrip(
        query('room')
            .filter(filter('a', '==', 'x'))
            .filter(filter('b', '>', 3))
            .orderBy(orderBy('b', 'desc'))
            .startAt(Bound(position: <FieldValue>[wrap(4)], before: true))
            .endAt(Bound(position: <FieldValue>[wrap(9)], before: false))
            .limit(10),
        BundledQueryLimitType.first);
  });

  test('testOverwritesNamedQueriesWithTheSameName', () async {
    final NamedQuery first = NamedQuery(
        'query-1',
        BundledQuery(Query(path('room')), BundledQueryLimitType.first),
        const SnapshotVersion(Timestamp(1, 0)));
    final NamedQuery second = NamedQuery(
        'query-1',
        BundledQuery(Query(path('rooms')), BundledQueryLimitType.last),
        const SnapshotVersion(Timestamp(2, 0)));
    await inTransaction(() => bundleCache.saveNamedQuery(first));
    await inTransaction(() => bundleCache.saveNamedQuery(second));

    expect(await inTransaction(() => bundleCache.getNamedQuery('query-1')),
        second);
  });
}
