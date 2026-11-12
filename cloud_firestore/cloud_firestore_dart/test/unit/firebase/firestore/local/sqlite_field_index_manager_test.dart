import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart'
    show
        Blob,
        BsonObjectId,
        BsonTimestamp,
        Decimal128Value,
        GeoPoint,
        Int32Value,
        MaxKey,
        MinKey,
        RegexValue,
        Timestamp,
        VectorValue;
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/target.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/index_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../../../util/core_helpers.dart';
import '../../../../util/index_helpers.dart';
import '../../../../util/test_util.dart';
import 'persistence_test_helpers.dart';

/// `Values.canonicalId` of the Android SDK for the plain values used as
/// document ids by testAdvancedQueries: map keys sorted, no spaces.
String canonicalId(Object? value) {
  if (value is Map<String, Object?>) {
    final List<String> keys = value.keys.toList()..sort();
    return '{${keys.map((String k) => '$k:${canonicalId(value[k])}').join(',')}}';
  } else if (value is List<Object?>) {
    return '[${value.map(canonicalId).join(',')}]';
  }
  return '$value';
}

/// Port of SQLiteIndexManagerTest of the Android SDK.
void main() {
  late SQLitePersistence persistence;
  late IndexManager indexManager;

  setUp(() async {
    persistence = await createSQLitePersistence(
        'firebase/firestore/local/sqlite_field_index_manager_test-${const Uuid().v4()}.db');
    indexManager = persistence.getIndexManager(User.unauthenticated);
    await indexManager.start();
  });

  tearDown(() => persistence.shutdown());

  void validateIndexType(Query query, IndexType expected) {
    final IndexType indexType = indexManager.getIndexType(query.toTarget());
    expect(indexType, expected);
  }

  void verifySequenceNumber(IndexManager indexManager, String collectionGroup,
      int expectedSequenceNumber) {
    expect(
        indexManager
            .getFieldIndexes(collectionGroup)
            .first
            .indexState
            .sequenceNumber,
        expectedSequenceNumber);
  }

  Future<void> addDocs(List<MaybeDocument> docs) {
    return indexManager.updateIndexEntries(<DocumentKey, MaybeDocument?>{
      for (final MaybeDocument doc in docs) doc.key: doc,
    });
  }

  Future<void> addDoc(String key, Map<String, Object?> data) {
    return addDocs(<MaybeDocument>[doc(key, 1, data)]);
  }

  Future<void> verifyResults(Query query, List<String> documents) async {
    final Target target = query.toTarget();
    final List<DocumentKey>? results =
        await indexManager.getDocumentsMatchingTarget(target);
    expect(results, isNotNull, reason: 'Target cannot be served from index.');
    final List<DocumentKey> keys = documents.map(key).toList();
    expect(results, keys, reason: 'Result for $query');
  }

  /// Validates the row count in the SQLite tables that are used for indexing.
  Future<void> validateRowCount(int expectedRows) async {
    final Map<String, dynamic> row = (await persistence.query('SELECT '
            '(SELECT COUNT(*) FROM index_state) AS index_state_count, '
            '(SELECT COUNT(*) FROM index_entries) AS index_entries_count, '
            '(SELECT COUNT(*) FROM index_configuration) AS index_configuration_count'))
        .single;
    expect(row['index_state_count'], expectedRows);
    expect(row['index_entries_count'], expectedRows);
    expect(row['index_configuration_count'], expectedRows);
  }

  Future<void> setUpSingleValueFilter() async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['count', SegmentKind.ascending]));
    await addDoc('coll/val1', map(<dynamic>['count', 1]));
    await addDoc('coll/val2', map(<dynamic>['count', 2]));
    await addDoc('coll/val3', map(<dynamic>['count', 3]));
  }

  Future<void> setUpArrayValueFilter() async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['values', SegmentKind.contains]));
    await addDoc(
        'coll/arr1',
        map(<dynamic>[
          'values',
          <Object?>[1, 2, 3]
        ]));
    await addDoc(
        'coll/arr2',
        map(<dynamic>[
          'values',
          <Object?>[4, 5, 6]
        ]));
    await addDoc(
        'coll/arr3',
        map(<dynamic>[
          'values',
          <Object?>[7, 8, 9]
        ]));
  }

  Future<void> setUpMultipleOrderBys() async {
    await indexManager
        .addFieldIndex(fieldIndex('coll', fieldsAndKinds: <Object>[
      'a',
      SegmentKind.ascending,
      'b',
      SegmentKind.descending,
      'c',
      SegmentKind.ascending
    ]));
    await indexManager
        .addFieldIndex(fieldIndex('coll', fieldsAndKinds: <Object>[
      'a',
      SegmentKind.descending,
      'b',
      SegmentKind.ascending,
      'c',
      SegmentKind.descending
    ]));
    await addDoc('coll/val1', map(<dynamic>['a', 1, 'b', 1, 'c', 3]));
    await addDoc('coll/val2', map(<dynamic>['a', 2, 'b', 2, 'c', 2]));
    await addDoc('coll/val3', map(<dynamic>['a', 2, 'b', 2, 'c', 3]));
    await addDoc('coll/val4', map(<dynamic>['a', 2, 'b', 2, 'c', 4]));
    await addDoc('coll/val5', map(<dynamic>['a', 2, 'b', 2, 'c', 5]));
    await addDoc('coll/val6', map(<dynamic>['a', 3, 'b', 3, 'c', 6]));
  }

  test('testAddsDocuments', () async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['exists', SegmentKind.ascending]));
    await addDoc('coll/doc1', map(<dynamic>['exists', 1]));
    await addDoc('coll/doc2', map());
  });

  test('testOrderByFilter', () async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['count', SegmentKind.ascending]));
    await addDoc('coll/val1', map(<dynamic>['count', 1]));
    await addDoc('coll/val2', map(<dynamic>['not-count', 2]));
    await addDoc('coll/val3', map(<dynamic>['count', 3]));
    Query qry = query('coll').orderBy(orderBy('count'));
    await verifyResults(qry, <String>['coll/val1', 'coll/val3']);
  });

  test('testOrderByKeyFilter', () async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['count', SegmentKind.ascending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['count', SegmentKind.descending]));
    await addDoc('coll/val1', map(<dynamic>['count', 1]));
    await addDoc('coll/val2', map(<dynamic>['count', 1]));
    await addDoc('coll/val3', map(<dynamic>['count', 3]));

    Query qry = query('coll').orderBy(orderBy('count'));
    await verifyResults(qry, <String>['coll/val1', 'coll/val2', 'coll/val3']);

    qry = query('coll').orderBy(orderBy('count', 'desc'));
    await verifyResults(qry, <String>['coll/val3', 'coll/val2', 'coll/val1']);
  });

  test('testAscendingOrderWithLessThanFilter', () async {
    await setUpMultipleOrderBys();

    Query originalQuery = query('coll')
        .filter(filter('a', '==', 2))
        .filter(filter('b', '==', 2))
        .filter(filter('c', '<', 5))
        .orderBy(orderBy('c', 'asc'));
    Query queryWithNonRestrictedBound = originalQuery
        .startAt(bound(false, <Object?>[1]))
        .endAt(bound(false, <Object?>[6]));
    Query queryWithRestrictedBound = originalQuery
        .startAt(bound(false, <Object?>[2]))
        .endAt(bound(false, <Object?>[4]));

    await verifyResults(
        originalQuery, <String>['coll/val2', 'coll/val3', 'coll/val4']);
    await verifyResults(queryWithNonRestrictedBound,
        <String>['coll/val2', 'coll/val3', 'coll/val4']);
    await verifyResults(queryWithRestrictedBound, <String>['coll/val3']);
  });

  test('testDescendingOrderWithLessThanFilter', () async {
    await setUpMultipleOrderBys();

    Query originalQuery = query('coll')
        .filter(filter('a', '==', 2))
        .filter(filter('b', '==', 2))
        .filter(filter('c', '<', 5))
        .orderBy(orderBy('c', 'desc'));
    Query queryWithNonRestrictedBound = originalQuery
        .startAt(bound(false, <Object?>[6]))
        .endAt(bound(false, <Object?>[1]));
    Query queryWithRestrictedBound = originalQuery
        .startAt(bound(false, <Object?>[4]))
        .endAt(bound(false, <Object?>[2]));

    await verifyResults(
        originalQuery, <String>['coll/val4', 'coll/val3', 'coll/val2']);
    await verifyResults(queryWithNonRestrictedBound,
        <String>['coll/val4', 'coll/val3', 'coll/val2']);
    await verifyResults(queryWithRestrictedBound, <String>['coll/val3']);
  });

  test('testAscendingOrderWithGreaterThanFilter', () async {
    await setUpMultipleOrderBys();

    Query originalQuery = query('coll')
        .filter(filter('a', '==', 2))
        .filter(filter('b', '==', 2))
        .filter(filter('c', '>', 2))
        .orderBy(orderBy('c', 'asc'));
    Query queryWithNonRestrictedBound = originalQuery
        .startAt(bound(false, <Object?>[2]))
        .endAt(bound(false, <Object?>[6]));
    Query queryWithRestrictedBound = originalQuery
        .startAt(bound(false, <Object?>[3]))
        .endAt(bound(false, <Object?>[5]));

    await verifyResults(
        originalQuery, <String>['coll/val3', 'coll/val4', 'coll/val5']);
    await verifyResults(queryWithNonRestrictedBound,
        <String>['coll/val3', 'coll/val4', 'coll/val5']);
    await verifyResults(queryWithRestrictedBound, <String>['coll/val4']);
  });

  test('testDescendingOrderWithGreaterThanFilter', () async {
    await setUpMultipleOrderBys();

    Query originalQuery = query('coll')
        .filter(filter('a', '==', 2))
        .filter(filter('b', '==', 2))
        .filter(filter('c', '>', 2))
        .orderBy(orderBy('c', 'desc'));
    Query queryWithNonRestrictedBound = originalQuery
        .startAt(bound(false, <Object?>[6]))
        .endAt(bound(false, <Object?>[2]));
    Query queryWithRestrictedBound = originalQuery
        .startAt(bound(false, <Object?>[5]))
        .endAt(bound(false, <Object?>[3]));

    await verifyResults(
        originalQuery, <String>['coll/val5', 'coll/val4', 'coll/val3']);
    await verifyResults(queryWithNonRestrictedBound,
        <String>['coll/val5', 'coll/val4', 'coll/val3']);
    await verifyResults(queryWithRestrictedBound, <String>['coll/val4']);
  });

  test('testEqualityFilter', () async {
    await setUpSingleValueFilter();
    Query qry = query('coll').filter(filter('count', '==', 2));
    await verifyResults(qry, <String>['coll/val2']);
  });

  test('testOrderByWithNotEqualsFilter', () async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['count', SegmentKind.ascending]));
    await addDoc('coll/val1', map(<dynamic>['count', 1]));
    await addDoc('coll/val2', map(<dynamic>['count', 2]));

    Query qry = query('coll')
        .filter(filter('count', '!=', 2))
        .orderBy(orderBy('count'));
    await verifyResults(qry, <String>['coll/val1']);
  });

  test('testNestedFieldEqualityFilter', () async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['a.b', SegmentKind.ascending]));
    await addDoc(
        'coll/doc1',
        map(<dynamic>[
          'a',
          map(<dynamic>['b', 1])
        ]));
    await addDoc(
        'coll/doc2',
        map(<dynamic>[
          'a',
          map(<dynamic>['b', 2])
        ]));
    Query qry = query('coll').filter(filter('a.b', '==', 2));
    await verifyResults(qry, <String>['coll/doc2']);
  });

  test('testNotEqualsFilter', () async {
    await setUpSingleValueFilter();
    Query qry = query('coll').filter(filter('count', '!=', 2));
    await verifyResults(qry, <String>['coll/val1', 'coll/val3']);
  });

  test('testEqualsWithNotEqualsFilter', () async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>[
          'a',
          SegmentKind.ascending,
          'b',
          SegmentKind.ascending
        ]));
    await addDoc('coll/val1', map(<dynamic>['a', 1, 'b', 1]));
    await addDoc('coll/val2', map(<dynamic>['a', 1, 'b', 2]));
    await addDoc('coll/val3', map(<dynamic>['a', 2, 'b', 1]));
    await addDoc('coll/val4', map(<dynamic>['a', 2, 'b', 2]));

    // Verifies that we apply the filter in the order of the field index
    Query qry =
        query('coll').filter(filter('a', '==', 1)).filter(filter('b', '!=', 1));
    await verifyResults(qry, <String>['coll/val2']);

    qry =
        query('coll').filter(filter('b', '!=', 1)).filter(filter('a', '==', 1));
    await verifyResults(qry, <String>['coll/val2']);
  });

  test('testEqualsWithNotEqualsFilterSameField', () async {
    await setUpSingleValueFilter();
    Query qry = query('coll')
        .filter(filter('count', '>', 1))
        .filter(filter('count', '!=', 2));
    await verifyResults(qry, <String>['coll/val3']);

    qry = query('coll')
        .filter(filter('count', '==', 1))
        .filter(filter('count', '!=', 2));
    await verifyResults(qry, <String>['coll/val1']);

    qry = query('coll')
        .filter(filter('count', '==', 1))
        .filter(filter('count', '!=', 1));
    await verifyResults(qry, <String>[]);
  });

  test('testLessThanFilter', () async {
    await setUpSingleValueFilter();
    Query qry = query('coll').filter(filter('count', '<', 2));
    await verifyResults(qry, <String>['coll/val1']);
  });

  test('testLessThanOrEqualsFilter', () async {
    await setUpSingleValueFilter();
    Query qry = query('coll').filter(filter('count', '<=', 2));
    await verifyResults(qry, <String>['coll/val1', 'coll/val2']);
  });

  test('testGreaterThanOrEqualsFilter', () async {
    await setUpSingleValueFilter();
    Query qry = query('coll').filter(filter('count', '>=', 2));
    await verifyResults(qry, <String>['coll/val2', 'coll/val3']);
  });

  test('testGreaterThanFilter', () async {
    await setUpSingleValueFilter();
    Query qry = query('coll').filter(filter('count', '>', 2));
    await verifyResults(qry, <String>['coll/val3']);
  });

  test('testRangeFilter', () async {
    await setUpSingleValueFilter();
    Query qry = query('coll')
        .filter(filter('count', '>', 1))
        .filter(filter('count', '<', 3));
    await verifyResults(qry, <String>['coll/val2']);
  });

  test('testStartAtFilter', () async {
    await setUpSingleValueFilter();
    Query qry = query('coll')
        .orderBy(orderBy('count'))
        .startAt(bound(true, <Object?>[2]));
    await verifyResults(qry, <String>['coll/val2', 'coll/val3']);
  });

  test('testAppliesStartAtFilterWithNotIn', () async {
    await setUpSingleValueFilter();
    Query qry = query('coll')
        .filter(filter('count', '!=', 2))
        .orderBy(orderBy('count'))
        .startAt(bound(true, <Object?>[2]));
    await verifyResults(qry, <String>['coll/val3']);
  });

  test('testStartAfterFilter', () async {
    await setUpSingleValueFilter();
    Query qry = query('coll')
        .orderBy(orderBy('count'))
        .startAt(bound(false, <Object?>[2]));
    await verifyResults(qry, <String>['coll/val3']);
  });

  test('testEndAtFilter', () async {
    await setUpSingleValueFilter();
    Query qry = query('coll')
        .orderBy(orderBy('count'))
        .endAt(bound(true, <Object?>[2]));
    await verifyResults(qry, <String>['coll/val1', 'coll/val2']);
  });

  test('testEndBeforeFilter', () async {
    await setUpSingleValueFilter();
    Query qry = query('coll')
        .orderBy(orderBy('count'))
        .endAt(bound(false, <Object?>[2]));
    await verifyResults(qry, <String>['coll/val1']);
  });

  test('testRangeWithBoundFilter', () async {
    await setUpSingleValueFilter();
    Query startAt = query('coll')
        .filter(filter('count', '>=', 1))
        .filter(filter('count', '<=', 3))
        .orderBy(orderBy('count'))
        .startAt(bound(false, <Object?>[1]))
        .endAt(bound(true, <Object?>[2]));
    await verifyResults(startAt, <String>['coll/val2']);
  });

  test('testInFilter', () async {
    await setUpSingleValueFilter();
    Query qry = query('coll').filter(filter('count', 'in', <Object?>[1, 3]));
    await verifyResults(qry, <String>['coll/val1', 'coll/val3']);
  });

  test('testNotInFilter', () async {
    await setUpSingleValueFilter();
    Query qry =
        query('coll').filter(filter('count', 'not-in', <Object?>[1, 2]));
    await verifyResults(qry, <String>['coll/val3']);
  });

  test('testNotInWithGreaterThanFilter', () async {
    await setUpSingleValueFilter();
    Query qry = query('coll')
        .filter(filter('count', '>', 1))
        .filter(filter('count', 'not-in', <Object?>[2]));
    await verifyResults(qry, <String>['coll/val3']);
  });

  test('testOutOfBoundsNotInWithGreaterThanFilter', () async {
    await setUpSingleValueFilter();
    Query qry = query('coll')
        .filter(filter('count', '>', 2))
        .filter(filter('count', 'not-in', <Object?>[1]));
    await verifyResults(qry, <String>['coll/val3']);
  });

  test('testArrayContainsFilter', () async {
    await setUpArrayValueFilter();
    Query qry = query('coll').filter(filter('values', 'array-contains', 1));
    await verifyResults(qry, <String>['coll/arr1']);
  });

  test('testArrayContainsWithNotEqualsFilter', () async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>[
          'a',
          SegmentKind.contains,
          'b',
          SegmentKind.ascending
        ]));
    await addDoc(
        'coll/val1',
        map(<dynamic>[
          'a',
          <Object?>[1],
          'b',
          1
        ]));
    await addDoc(
        'coll/val2',
        map(<dynamic>[
          'a',
          <Object?>[1],
          'b',
          2
        ]));
    await addDoc(
        'coll/val3',
        map(<dynamic>[
          'a',
          <Object?>[2],
          'b',
          1
        ]));
    await addDoc(
        'coll/val4',
        map(<dynamic>[
          'a',
          <Object?>[2],
          'b',
          2
        ]));

    Query qry = query('coll')
        .filter(filter('a', 'array-contains', 1))
        .filter(filter('b', '!=', 1));
    await verifyResults(qry, <String>['coll/val2']);
  });

  test('testArrayContainsWithNotEqualsFilterOnSameField', () async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>[
          'a',
          SegmentKind.contains,
          'a',
          SegmentKind.ascending
        ]));
    await addDoc(
        'coll/val1',
        map(<dynamic>[
          'a',
          <Object?>[1, 1]
        ]));
    await addDoc(
        'coll/val2',
        map(<dynamic>[
          'a',
          <Object?>[1, 2]
        ]));
    await addDoc(
        'coll/val3',
        map(<dynamic>[
          'a',
          <Object?>[2, 1]
        ]));
    await addDoc(
        'coll/val4',
        map(<dynamic>[
          'a',
          <Object?>[2, 2]
        ]));

    Query qry = query('coll')
        .filter(filter('a', 'array-contains', 1))
        .filter(filter('a', '!=', <Object?>[1, 2]));
    await verifyResults(qry, <String>['coll/val1', 'coll/val3']);
  });

  test('testEqualsWithNotEqualsOnSameField', () async {
    await setUpSingleValueFilter();

    final List<List<Object>> filtersAndResults = <List<Object>>[
      <Filter>[filter('count', '>', 1), filter('count', '!=', 2)],
      <String>['coll/val3'],
      <Filter>[filter('count', '==', 1), filter('count', '!=', 2)],
      <String>['coll/val1'],
      <Filter>[filter('count', '==', 1), filter('count', '!=', 1)],
      <String>[],
      <Filter>[filter('count', '>', 2), filter('count', '!=', 2)],
      <String>['coll/val3'],
      <Filter>[filter('count', '>=', 2), filter('count', '!=', 2)],
      <String>['coll/val3'],
      <Filter>[filter('count', '<=', 2), filter('count', '!=', 2)],
      <String>['coll/val1'],
      <Filter>[filter('count', '<=', 2), filter('count', '!=', 1)],
      <String>['coll/val2'],
      <Filter>[filter('count', '<', 2), filter('count', '!=', 2)],
      <String>['coll/val1'],
      <Filter>[filter('count', '<', 2), filter('count', '!=', 1)],
      <String>[],
      <Filter>[
        filter('count', '>', 2),
        filter('count', 'not-in', <Object?>[3])
      ],
      <String>[],
      <Filter>[
        filter('count', '>=', 2),
        filter('count', 'not-in', <Object?>[3])
      ],
      <String>['coll/val2'],
      <Filter>[
        filter('count', '>=', 2),
        filter('count', 'not-in', <Object?>[3, 3])
      ],
      <String>['coll/val2'],
      <Filter>[
        filter('count', '>', 1),
        filter('count', '<', 3),
        filter('count', '!=', 2)
      ],
      <String>[],
      <Filter>[
        filter('count', '>=', 1),
        filter('count', '<', 3),
        filter('count', '!=', 2)
      ],
      <String>['coll/val1'],
      <Filter>[
        filter('count', '>=', 1),
        filter('count', '<=', 3),
        filter('count', '!=', 2)
      ],
      <String>['coll/val1', 'coll/val3'],
      <Filter>[
        filter('count', '>', 1),
        filter('count', '<=', 3),
        filter('count', '!=', 2)
      ],
      <String>['coll/val3']
    ];

    for (int i = 0; i < filtersAndResults.length; i += 2) {
      Query qry = query('coll');
      for (final Filter f in filtersAndResults[i].cast<Filter>()) {
        qry = qry.filter(f);
      }
      await verifyResults(qry, filtersAndResults[i + 1].cast<String>());
    }
  });

  test('testArrayContainsAnyFilter', () async {
    await setUpArrayValueFilter();
    Query qry = query('coll')
        .filter(filter('values', 'array-contains-any', <Object?>[1, 2, 4]));
    await verifyResults(qry, <String>['coll/arr1', 'coll/arr2']);
  });

  test('testArrayContainsDoesNotMatchNonArray', () async {
    // Set up two field indices. This causes two index entries to be written, but our qry should
    // only use one index.
    await setUpArrayValueFilter();
    await setUpSingleValueFilter();
    await addDoc('coll/nonmatching', map(<dynamic>['values', 1]));
    Query qry = query('coll')
        .filter(filter('values', 'array-contains-any', <Object?>[1]));
    await verifyResults(qry, <String>['coll/arr1']);
  });

  test('testNoMatchingFilter', () async {
    await setUpSingleValueFilter();
    Query qry = query('coll').filter(filter('unknown', '==', true));
    expect(indexManager.getIndexType(qry.toTarget()), IndexType.none);
    expect(
        await indexManager.getDocumentsMatchingTarget(qry.toTarget()), isNull);
  });

  test('testNoMatchingDocs', () async {
    await setUpSingleValueFilter();
    Query qry = query('coll').filter(filter('count', '==', -1));
    await verifyResults(qry, <String>[]);
  });

  test('testEqualityFilterWithNonMatchingType', () async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['value', SegmentKind.ascending]));
    await addDoc('coll/boolean', map(<dynamic>['value', true]));
    await addDoc('coll/string', map(<dynamic>['value', 'true']));
    await addDoc('coll/number', map(<dynamic>['value', 1]));
    Query qry = query('coll').filter(filter('value', '==', true));
    await verifyResults(qry, <String>['coll/boolean']);
  });

  test('testCollectionGroup', () async {
    await indexManager.addFieldIndex(fieldIndex('coll1',
        fieldsAndKinds: <Object>['value', SegmentKind.ascending]));
    await addDoc('coll1/doc1', map(<dynamic>['value', true]));
    await addDoc('coll2/doc2/coll1/doc1', map(<dynamic>['value', true]));
    await addDoc('coll2/doc2', map(<dynamic>['value', true]));
    Query qry = Query(ResourcePath.empty, collectionGroup: 'coll1')
        .filter(filter('value', '==', true));
    await verifyResults(qry, <String>['coll1/doc1', 'coll2/doc2/coll1/doc1']);
  });

  test('testLimitFilter', () async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['value', SegmentKind.ascending]));
    await addDoc('coll/doc1', map(<dynamic>['value', 1]));
    await addDoc('coll/doc2', map(<dynamic>['value', 1]));
    await addDoc('coll/doc3', map(<dynamic>['value', 1]));
    Query qry = query('coll').filter(filter('value', '==', 1)).limitToFirst(2);
    await verifyResults(qry, <String>['coll/doc1', 'coll/doc2']);
  });

  test('testLimitAppliesOrdering', () async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>[
          'value',
          SegmentKind.contains,
          'value',
          SegmentKind.ascending
        ]));
    await addDoc(
        'coll/doc1',
        map(<dynamic>[
          'value',
          <Object?>[1, 'foo']
        ]));
    await addDoc(
        'coll/doc2',
        map(<dynamic>[
          'value',
          <Object?>[3, 'foo']
        ]));
    await addDoc(
        'coll/doc3',
        map(<dynamic>[
          'value',
          <Object?>[2, 'foo']
        ]));
    Query qry = query('coll')
        .filter(filter('value', 'array-contains', 'foo'))
        .orderBy(orderBy('value'))
        .limitToFirst(2);
    await verifyResults(qry, <String>['coll/doc1', 'coll/doc3']);
  });

  test('testIndexEntriesAreUpdated', () async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['value', SegmentKind.ascending]));
    Query qry = query('coll').orderBy(orderBy('value'));

    await addDoc('coll/doc1', map(<dynamic>['value', true]));
    await verifyResults(qry, <String>['coll/doc1']);

    await addDocs(<MaybeDocument>[
      doc('coll/doc1', 1, map()),
      doc('coll/doc2', 1, map(<dynamic>['value', true]))
    ]);
    await verifyResults(qry, <String>['coll/doc2']);
  });

  test('testIndexEntriesAreUpdatedWithDeletedDoc', () async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['value', SegmentKind.ascending]));
    Query qry = query('coll').orderBy(orderBy('value'));

    await addDoc('coll/doc1', map(<dynamic>['value', true]));
    await verifyResults(qry, <String>['coll/doc1']);

    await addDocs(<MaybeDocument>[deletedDoc('coll/doc1', 1)]);
    await verifyResults(qry, <String>[]);
  });

  test('testCursorsDoNoExpandResultSet', () async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['c', SegmentKind.ascending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['c', SegmentKind.descending]));

    await addDoc('coll/val1', map(<dynamic>['a', 1, 'b', 1, 'c', 3]));
    await addDoc('coll/val2', map(<dynamic>['a', 2, 'b', 2, 'c', 2]));

    Query qry = query('coll')
        .filter(filter('c', '>', 2))
        .orderBy(orderBy('c'))
        .startAt(bound(true, <Object?>[2]));
    await verifyResults(qry, <String>['coll/val1']);

    qry = query('coll')
        .filter(filter('c', '<', 3))
        .orderBy(orderBy('c', 'desc'))
        .startAt(bound(true, <Object?>[3]));
    await verifyResults(qry, <String>['coll/val2']);
  });

  test('testFiltersOnTheSameField', () async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['a', SegmentKind.ascending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>[
          'a',
          SegmentKind.ascending,
          'b',
          SegmentKind.ascending
        ]));

    await addDoc('coll/val1', map(<dynamic>['a', 1, 'b', 1]));
    await addDoc('coll/val2', map(<dynamic>['a', 2, 'b', 2]));
    await addDoc('coll/val3', map(<dynamic>['a', 3, 'b', 3]));
    await addDoc('coll/val4', map(<dynamic>['a', 4, 'b', 4]));

    Query qry =
        query('coll').filter(filter('a', '>', 1)).filter(filter('a', '==', 2));
    await verifyResults(qry, <String>['coll/val2']);

    qry =
        query('coll').filter(filter('a', '<=', 1)).filter(filter('a', '==', 2));
    await verifyResults(qry, <String>[]);

    qry = query('coll')
        .filter(filter('a', '>', 1))
        .filter(filter('a', '==', 2))
        .orderBy(orderBy('a'))
        .orderBy(orderBy(DocumentKey.keyFieldName));
    await verifyResults(qry, <String>['coll/val2']);

    qry = query('coll')
        .filter(filter('a', '>', 1))
        .filter(filter('a', '==', 2))
        .orderBy(orderBy('a'))
        .orderBy(orderBy(DocumentKey.keyFieldName, 'desc'));
    await verifyResults(qry, <String>['coll/val2']);

    qry = query('coll')
        .filter(filter('a', '>', 1))
        .filter(filter('a', '==', 3))
        .orderBy(orderBy('a'))
        .orderBy(orderBy('b'));
    await verifyResults(qry, <String>['coll/val3']);
  });

  test('testAdvancedQueries', () async {
    // This test compares local qry results with those received from the Java Server SDK.

    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['null', SegmentKind.ascending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['int', SegmentKind.ascending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['float', SegmentKind.ascending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['string', SegmentKind.ascending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['multi', SegmentKind.ascending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['array', SegmentKind.ascending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['array', SegmentKind.descending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['array', SegmentKind.contains]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['map', SegmentKind.ascending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['map.field', SegmentKind.ascending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['prefix', SegmentKind.ascending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>[
          'prefix',
          SegmentKind.ascending,
          'suffix',
          SegmentKind.ascending
        ]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['a', SegmentKind.ascending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>[
          'a',
          SegmentKind.ascending,
          'b',
          SegmentKind.ascending
        ]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>[
          'a',
          SegmentKind.descending,
          'b',
          SegmentKind.ascending
        ]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>[
          'a',
          SegmentKind.ascending,
          'b',
          SegmentKind.descending
        ]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>[
          'a',
          SegmentKind.descending,
          'b',
          SegmentKind.descending
        ]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>[
          'b',
          SegmentKind.ascending,
          'a',
          SegmentKind.ascending
        ]));

    final List<Map<String, Object?>> data = <Map<String, Object?>>[
      map(),
      map(<dynamic>[
        'int',
        1,
        'array',
        <Object?>[1, 'foo']
      ]),
      map(<dynamic>[
        'array',
        <Object?>[2, 'foo']
      ]),
      map(<dynamic>[
        'int',
        3,
        'array',
        <Object?>[3, 'foo']
      ]),
      map(<dynamic>['array', 'foo']),
      map(<dynamic>[
        'array',
        <Object?>[1]
      ]),
      map(<dynamic>['float', -0.0, 'string', 'a']),
      map(<dynamic>['float', 0, 'string', 'ab']),
      map(<dynamic>['float', 0.0, 'string', 'b']),
      map(<dynamic>['float', double.nan]),
      map(<dynamic>['multi', true]),
      map(<dynamic>['multi', 1]),
      map(<dynamic>['multi', 'string']),
      map(<dynamic>['multi', <Object?>[]]),
      map(<dynamic>['null', null]),
      map(<dynamic>[
        'prefix',
        <Object?>[1, 2],
        'suffix',
        null
      ]),
      map(<dynamic>[
        'prefix',
        <Object?>[1],
        'suffix',
        2
      ]),
      map(<dynamic>['map', map()]),
      map(<dynamic>[
        'map',
        map(<dynamic>['field', true])
      ]),
      map(<dynamic>[
        'map',
        map(<dynamic>['field', false])
      ]),
      map(<dynamic>['a', 0, 'b', 0]),
      map(<dynamic>['a', 0, 'b', 1]),
      map(<dynamic>['a', 1, 'b', 0]),
      map(<dynamic>['a', 1, 'b', 1]),
      map(<dynamic>['a', 2, 'b', 0]),
      map(<dynamic>['a', 2, 'b', 1]),
    ];

    for (int i = 0; i < data.length; ++i) {
      await addDoc('coll/${canonicalId(data[i])}', data[i]);
    }

    Query q = query('coll');

    await verifyResults(q.orderBy(orderBy('int')),
        <String>['coll/{array:[1,foo],int:1}', 'coll/{array:[3,foo],int:3}']);
    await verifyResults(q.filter(filter('float', '==', double.nan)),
        <String>['coll/{float:NaN}']);
    await verifyResults(q.filter(filter('float', '==', -0.0)), <String>[
      'coll/{float:-0.0,string:a}',
      'coll/{float:0,string:ab}',
      'coll/{float:0.0,string:b}'
    ]);
    await verifyResults(q.filter(filter('float', '==', 0)), <String>[
      'coll/{float:-0.0,string:a}',
      'coll/{float:0,string:ab}',
      'coll/{float:0.0,string:b}'
    ]);
    await verifyResults(q.filter(filter('float', '==', 0.0)), <String>[
      'coll/{float:-0.0,string:a}',
      'coll/{float:0,string:ab}',
      'coll/{float:0.0,string:b}'
    ]);
    await verifyResults(q.filter(filter('string', '==', 'a')),
        <String>['coll/{float:-0.0,string:a}']);
    await verifyResults(q.filter(filter('string', '>', 'a')),
        <String>['coll/{float:0,string:ab}', 'coll/{float:0.0,string:b}']);
    await verifyResults(q.filter(filter('string', '>=', 'a')), <String>[
      'coll/{float:-0.0,string:a}',
      'coll/{float:0,string:ab}',
      'coll/{float:0.0,string:b}'
    ]);
    await verifyResults(q.filter(filter('string', '<', 'b')),
        <String>['coll/{float:-0.0,string:a}', 'coll/{float:0,string:ab}']);
    await verifyResults(q.filter(filter('string', '<', 'coll')), <String>[
      'coll/{float:-0.0,string:a}',
      'coll/{float:0,string:ab}',
      'coll/{float:0.0,string:b}'
    ]);
    await verifyResults(
        q.filter(filter('string', '>', 'a')).filter(filter('string', '<', 'b')),
        <String>['coll/{float:0,string:ab}']);
    await verifyResults(
        q.filter(filter('array', 'array-contains', 'foo')), <String>[
      'coll/{array:[1,foo],int:1}',
      'coll/{array:[2,foo]}',
      'coll/{array:[3,foo],int:3}'
    ]);
    await verifyResults(
        q.filter(filter('array', 'array-contains-any', <Object?>[1, 'foo'])),
        <String>[
          'coll/{array:[1,foo],int:1}',
          'coll/{array:[1]}',
          'coll/{array:[2,foo]}',
          'coll/{array:[3,foo],int:3}'
        ]);
    await verifyResults(
        q.filter(filter('multi', '>=', true)), <String>['coll/{multi:true}']);
    await verifyResults(
        q.filter(filter('multi', '>=', 0)), <String>['coll/{multi:1}']);
    await verifyResults(
        q.filter(filter('multi', '>=', '')), <String>['coll/{multi:string}']);
    await verifyResults(q.filter(filter('multi', '>=', <Object?>[])),
        <String>['coll/{multi:[]}']);
    await verifyResults(q.filter(filter('multi', '!=', true)),
        <String>['coll/{multi:1}', 'coll/{multi:string}', 'coll/{multi:[]}']);
    await verifyResults(q.filter(filter('multi', 'in', <Object?>[true, 1])),
        <String>['coll/{multi:true}', 'coll/{multi:1}']);
    await verifyResults(q.filter(filter('multi', 'not-in', <Object?>[true, 1])),
        <String>['coll/{multi:string}', 'coll/{multi:[]}']);
    await verifyResults(
        q.orderBy(orderBy('array')).startAt(bound(true, <Object?>[
              <Object?>[2]
            ])),
        <String>['coll/{array:[2,foo]}', 'coll/{array:[3,foo],int:3}']);
    await verifyResults(
        q.orderBy(orderBy('array', 'desc')).startAt(bound(true, <Object?>[
              <Object?>[2]
            ])),
        <String>[
          'coll/{array:[1,foo],int:1}',
          'coll/{array:[1]}',
          'coll/{array:foo}'
        ]);
    await verifyResults(
        q
            .orderBy(orderBy('array', 'desc'))
            .startAt(bound(true, <Object?>[
              <Object?>[2]
            ]))
            .limitToFirst(2),
        <String>['coll/{array:[1,foo],int:1}', 'coll/{array:[1]}']);
    await verifyResults(
        q.orderBy(orderBy('array')).startAt(bound(false, <Object?>[
              <Object?>[2]
            ])),
        <String>['coll/{array:[2,foo]}', 'coll/{array:[3,foo],int:3}']);
    await verifyResults(
        q.orderBy(orderBy('array', 'desc')).startAt(bound(false, <Object?>[
              <Object?>[2]
            ])),
        <String>[
          'coll/{array:[1,foo],int:1}',
          'coll/{array:[1]}',
          'coll/{array:foo}'
        ]);
    await verifyResults(
        q
            .orderBy(orderBy('array', 'desc'))
            .startAt(bound(false, <Object?>[
              <Object?>[2]
            ]))
            .limitToFirst(2),
        <String>['coll/{array:[1,foo],int:1}', 'coll/{array:[1]}']);
    await verifyResults(
        q.orderBy(orderBy('array')).startAt(bound(false, <Object?>[
              <Object?>[2, 'foo']
            ])),
        <String>['coll/{array:[3,foo],int:3}']);
    await verifyResults(
        q.orderBy(orderBy('array', 'desc')).startAt(bound(false, <Object?>[
              <Object?>[2, 'foo']
            ])),
        <String>[
          'coll/{array:[1,foo],int:1}',
          'coll/{array:[1]}',
          'coll/{array:foo}'
        ]);
    await verifyResults(
        q
            .orderBy(orderBy('array', 'desc'))
            .startAt(bound(false, <Object?>[
              <Object?>[2, 'foo']
            ]))
            .limitToFirst(2),
        <String>['coll/{array:[1,foo],int:1}', 'coll/{array:[1]}']);
    await verifyResults(
        q.orderBy(orderBy('array')).endAt(bound(true, <Object?>[
              <Object?>[2]
            ])),
        <String>[
          'coll/{array:foo}',
          'coll/{array:[1]}',
          'coll/{array:[1,foo],int:1}'
        ]);
    await verifyResults(
        q.orderBy(orderBy('array', 'desc')).endAt(bound(true, <Object?>[
              <Object?>[2]
            ])),
        <String>['coll/{array:[3,foo],int:3}', 'coll/{array:[2,foo]}']);
    await verifyResults(
        q.orderBy(orderBy('array')).endAt(bound(false, <Object?>[
              <Object?>[2]
            ])),
        <String>[
          'coll/{array:foo}',
          'coll/{array:[1]}',
          'coll/{array:[1,foo],int:1}'
        ]);
    await verifyResults(
        q
            .orderBy(orderBy('array'))
            .endAt(bound(false, <Object?>[
              <Object?>[2]
            ]))
            .limitToFirst(2),
        <String>['coll/{array:foo}', 'coll/{array:[1]}']);
    await verifyResults(
        q.orderBy(orderBy('array', 'desc')).endAt(bound(false, <Object?>[
              <Object?>[2]
            ])),
        <String>['coll/{array:[3,foo],int:3}', 'coll/{array:[2,foo]}']);
    await verifyResults(
        q.orderBy(orderBy('array')).endAt(bound(false, <Object?>[
              <Object?>[2, 'foo']
            ])),
        <String>[
          'coll/{array:foo}',
          'coll/{array:[1]}',
          'coll/{array:[1,foo],int:1}'
        ]);
    await verifyResults(
        q
            .orderBy(orderBy('array'))
            .endAt(bound(false, <Object?>[
              <Object?>[2, 'foo']
            ]))
            .limitToFirst(2),
        <String>['coll/{array:foo}', 'coll/{array:[1]}']);
    await verifyResults(
        q.orderBy(orderBy('array', 'desc')).endAt(bound(false, <Object?>[
              <Object?>[2, 'foo']
            ])),
        <String>['coll/{array:[3,foo],int:3}']);
    await verifyResults(
        q.orderBy(orderBy('a')).orderBy(orderBy('b')).limitToFirst(1),
        <String>['coll/{a:0,b:0}']);
    await verifyResults(
        q.orderBy(orderBy('a', 'desc')).orderBy(orderBy('b')).limitToFirst(1),
        <String>['coll/{a:2,b:0}']);
    await verifyResults(
        q.orderBy(orderBy('a')).orderBy(orderBy('b', 'desc')).limitToFirst(1),
        <String>['coll/{a:0,b:1}']);
    await verifyResults(
        q
            .orderBy(orderBy('a', 'desc'))
            .orderBy(orderBy('b', 'desc'))
            .limitToFirst(1),
        <String>['coll/{a:2,b:1}']);
    await verifyResults(
        q.filter(filter('a', '>', 0)).filter(filter('b', '==', 1)),
        <String>['coll/{a:1,b:1}', 'coll/{a:2,b:1}']);
    await verifyResults(
        q.filter(filter('a', '==', 1)).filter(filter('b', '==', 1)),
        <String>['coll/{a:1,b:1}']);
    await verifyResults(
        q.filter(filter('a', '!=', 0)).filter(filter('b', '==', 1)),
        <String>['coll/{a:1,b:1}', 'coll/{a:2,b:1}']);
    await verifyResults(
        q.filter(filter('b', '==', 1)).filter(filter('a', '!=', 0)),
        <String>['coll/{a:1,b:1}', 'coll/{a:2,b:1}']);
    await verifyResults(q.filter(filter('a', 'not-in', <Object?>[0, 1])),
        <String>['coll/{a:2,b:0}', 'coll/{a:2,b:1}']);
    await verifyResults(
        q
            .filter(filter('a', 'not-in', <Object?>[0, 1]))
            .filter(filter('b', '==', 1)),
        <String>['coll/{a:2,b:1}']);
    await verifyResults(
        q
            .filter(filter('b', '==', 1))
            .filter(filter('a', 'not-in', <Object?>[0, 1])),
        <String>['coll/{a:2,b:1}']);
    await verifyResults(
        q.filter(filter('null', '==', null)), <String>['coll/{null:null}']);
    await verifyResults(
        q.orderBy(orderBy('null')), <String>['coll/{null:null}']);
    await verifyResults(q.filter(filter('prefix', '==', <Object?>[1, 2])),
        <String>['coll/{prefix:[1,2],suffix:null}']);
    await verifyResults(
        q
            .filter(filter('prefix', '==', <Object?>[1]))
            .filter(filter('suffix', '==', 2)),
        <String>['coll/{prefix:[1],suffix:2}']);
    await verifyResults(
        q.filter(filter('map', '==', map())), <String>['coll/{map:{}}']);
    await verifyResults(
        q.filter(filter('map', '==', map(<dynamic>['field', true]))),
        <String>['coll/{map:{field:true}}']);
    await verifyResults(q.filter(filter('map.field', '==', true)),
        <String>['coll/{map:{field:true}}']);
    await verifyResults(q.orderBy(orderBy('map')), <String>[
      'coll/{map:{}}',
      'coll/{map:{field:false}}',
      'coll/{map:{field:true}}'
    ]);
    await verifyResults(q.orderBy(orderBy('map.field')),
        <String>['coll/{map:{field:false}}', 'coll/{map:{field:true}}']);
  });

  test('testPersistsIndexOffset', () async {
    await indexManager.addFieldIndex(fieldIndex('coll1',
        fieldsAndKinds: <Object>['value', SegmentKind.ascending]));
    IndexOffset offset = IndexOffset(version(20), key('coll/doc'), 42);
    await indexManager.updateCollectionGroup('coll1', offset);

    indexManager = persistence.getIndexManager(User.unauthenticated);
    await indexManager.start();

    List<FieldIndex> indexes = indexManager.getFieldIndexes('coll1');
    expect(indexes.length, 1);
    FieldIndex index = indexes.first;
    expect(offset, index.indexState.offset);
  });

  test('testNextCollectionGroupAdvancesWhenCollectionIsUpdated', () async {
    await indexManager.addFieldIndex(fieldIndex('coll1'));
    await indexManager.addFieldIndex(fieldIndex('coll2'));

    String? collectionGroup = indexManager.getNextCollectionGroupToUpdate();
    expect('coll1', collectionGroup);

    await indexManager.updateCollectionGroup('coll1', IndexOffset.none);
    collectionGroup = indexManager.getNextCollectionGroupToUpdate();
    expect('coll2', collectionGroup);

    await indexManager.updateCollectionGroup('coll2', IndexOffset.none);
    collectionGroup = indexManager.getNextCollectionGroupToUpdate();
    expect('coll1', collectionGroup);
  });

  test('testGetFieldIndexes', () async {
    await indexManager.addFieldIndex(fieldIndex('coll1',
        indexId: 1,
        indexState: FieldIndex.initialState,
        fieldsAndKinds: <Object>['value', SegmentKind.ascending]));
    await indexManager.addFieldIndex(fieldIndex('coll2',
        indexId: 2,
        indexState: FieldIndex.initialState,
        fieldsAndKinds: <Object>['value', SegmentKind.contains]));

    List<FieldIndex> indexes = indexManager.getFieldIndexes('coll1');
    expect(indexes.length, 1);
    expect(indexes[0].collectionGroup, 'coll1');
    await indexManager.addFieldIndex(fieldIndex('coll1',
        indexId: 3,
        indexState: FieldIndex.initialState,
        fieldsAndKinds: <Object>['newValue', SegmentKind.contains]));

    indexes = indexManager.getFieldIndexes('coll1');
    expect(indexes.length, 2);
    expect(indexes[0].collectionGroup, 'coll1');
    expect(indexes[1].collectionGroup, 'coll1');
  });

  test('testDeleteFieldIndexRemovesEntryFromCollectionGroup', () async {
    await indexManager.addFieldIndex(fieldIndex('coll1',
        indexId: 1,
        indexState: IndexState(1, IndexOffset.none),
        fieldsAndKinds: <Object>['value', SegmentKind.ascending]));
    await indexManager.addFieldIndex(fieldIndex('coll2',
        indexId: 2,
        indexState: IndexState(2, IndexOffset.none),
        fieldsAndKinds: <Object>['value', SegmentKind.contains]));
    String? collectionGroup = indexManager.getNextCollectionGroupToUpdate();
    expect('coll1', collectionGroup);

    await indexManager
        .deleteFieldIndex(indexManager.getFieldIndexes('coll1').first);
    collectionGroup = indexManager.getNextCollectionGroupToUpdate();
    expect('coll2', collectionGroup);
  });

  test('testDeleteFieldIndexRemovesAllMetadata', () async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        indexId: 1,
        indexState: IndexState(1, IndexOffset.none),
        fieldsAndKinds: <Object>['value', SegmentKind.ascending]));
    await addDoc('coll/doc', map(<dynamic>['value', 1]));
    await indexManager.updateCollectionGroup('coll', IndexOffset.none);

    await validateRowCount(1);

    FieldIndex existingIndex = indexManager.getFieldIndexes('coll').first;
    await indexManager.deleteFieldIndex(existingIndex);

    await validateRowCount(0);
  });

  test('testChangeUser', () async {
    IndexManager indexManager =
        persistence.getIndexManager(User.unauthenticated);
    await indexManager.start();

    // Add two indexes and mark one as updated.
    await indexManager.addFieldIndex(
        fieldIndex('coll1', indexId: 1, indexState: FieldIndex.initialState));
    await indexManager.addFieldIndex(
        fieldIndex('coll2', indexId: 2, indexState: FieldIndex.initialState));

    await indexManager.updateCollectionGroup('coll2', IndexOffset.none);

    verifySequenceNumber(indexManager, 'coll1', 0);
    verifySequenceNumber(indexManager, 'coll2', 1);

    // New user signs it. The user should see all existing field indices.
    // Sequence numbers are set to 0.
    indexManager = persistence.getIndexManager(User('authenticated'));
    await indexManager.start();

    // Add a new index and mark it as updated.
    await indexManager.addFieldIndex(
        fieldIndex('coll3', indexId: 2, indexState: FieldIndex.initialState));
    await indexManager.updateCollectionGroup('coll3', IndexOffset.none);

    verifySequenceNumber(indexManager, 'coll1', 0);
    verifySequenceNumber(indexManager, 'coll2', 0);
    verifySequenceNumber(indexManager, 'coll3', 1);

    // Original user signs it. The user should also see the new index with a zero sequence number.
    indexManager = persistence.getIndexManager(User.unauthenticated);
    await indexManager.start();

    verifySequenceNumber(indexManager, 'coll1', 0);
    verifySequenceNumber(indexManager, 'coll2', 1);
    verifySequenceNumber(indexManager, 'coll3', 0);
  });

  test('testPartialIndexAndFullIndex', () async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['a', SegmentKind.ascending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['b', SegmentKind.ascending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>[
          'c',
          SegmentKind.ascending,
          'd',
          SegmentKind.ascending
        ]));

    Query query1 = query('coll').filter(filter('a', '==', 1));
    validateIndexType(query1, IndexType.full);

    Query query2 = query('coll').filter(filter('b', '==', 1));
    validateIndexType(query2, IndexType.full);

    Query query3 =
        query('coll').filter(filter('a', '==', 1)).orderBy(orderBy('a'));
    validateIndexType(query3, IndexType.full);

    Query query4 =
        query('coll').filter(filter('b', '==', 1)).orderBy(orderBy('b'));
    validateIndexType(query4, IndexType.full);

    Query query5 =
        query('coll').filter(filter('a', '==', 1)).filter(filter('b', '==', 1));
    validateIndexType(query5, IndexType.partial);

    Query query6 =
        query('coll').filter(filter('a', '==', 1)).orderBy(orderBy('b'));
    validateIndexType(query6, IndexType.partial);

    Query query7 =
        query('coll').filter(filter('b', '==', 1)).orderBy(orderBy('a'));
    validateIndexType(query7, IndexType.partial);

    Query query8 =
        query('coll').filter(filter('c', '==', 1)).filter(filter('d', '==', 1));
    validateIndexType(query8, IndexType.full);

    Query query9 = query('coll')
        .filter(filter('c', '==', 1))
        .filter(filter('d', '==', 1))
        .orderBy(orderBy('c'));
    validateIndexType(query9, IndexType.full);

    Query query10 = query('coll')
        .filter(filter('c', '==', 1))
        .filter(filter('d', '==', 1))
        .orderBy(orderBy('d'));
    validateIndexType(query10, IndexType.full);

    Query query11 = query('coll')
        .filter(filter('c', '==', 1))
        .filter(filter('d', '==', 1))
        .orderBy(orderBy('c'))
        .orderBy(orderBy('d'));
    validateIndexType(query11, IndexType.full);

    Query query12 = query('coll')
        .filter(filter('c', '==', 1))
        .filter(filter('d', '==', 1))
        .orderBy(orderBy('d'))
        .orderBy(orderBy('c'));
    validateIndexType(query12, IndexType.full);

    Query query13 = query('coll')
        .filter(filter('c', '==', 1))
        .filter(filter('d', '==', 1))
        .orderBy(orderBy('e'));
    validateIndexType(query13, IndexType.partial);

    Query query14 =
        query('coll').filter(filter('c', '==', 1)).filter(filter('d', '<=', 1));
    validateIndexType(query14, IndexType.full);

    Query query15 = query('coll')
        .filter(filter('c', '==', 1))
        .filter(filter('d', '>', 1))
        .orderBy(orderBy('d'));
    validateIndexType(query15, IndexType.full);
  });

  test('testIndexTypeForOrQueries', () async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['a', SegmentKind.ascending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['a', SegmentKind.descending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['b', SegmentKind.ascending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>[
          'b',
          SegmentKind.ascending,
          'a',
          SegmentKind.ascending
        ]));

    // OR qry without orderBy without limit which has missing sub-target indexes.
    Query query1 = query('coll').filter(
        orFilters(<Filter>[filter('a', '==', 1), filter('c', '==', 1)]));
    validateIndexType(query1, IndexType.none);

    // OR qry with explicit orderBy without limit which has missing sub-target indexes.
    Query query2 = query('coll')
        .filter(orFilters(<Filter>[filter('a', '==', 1), filter('c', '==', 1)]))
        .orderBy(orderBy('c'));
    validateIndexType(query2, IndexType.none);

    // OR qry with implicit orderBy without limit which has missing sub-target indexes.
    Query query3 = query('coll')
        .filter(orFilters(<Filter>[filter('a', '==', 1), filter('c', '>', 1)]));
    validateIndexType(query3, IndexType.none);

    // OR qry with explicit orderBy with limit which has missing sub-target indexes.
    Query query4 = query('coll')
        .filter(orFilters(<Filter>[filter('a', '==', 1), filter('c', '==', 1)]))
        .orderBy(orderBy('c'))
        .limitToFirst(2);
    validateIndexType(query4, IndexType.none);

    // OR qry with implicit orderBy with limit which has missing sub-target indexes.
    Query query5 = query('coll')
        .filter(orFilters(<Filter>[filter('a', '==', 1), filter('c', '>', 1)]))
        .limitToLast(2);
    validateIndexType(query5, IndexType.none);

    // OR qry without orderBy without limit which has all sub-target indexes.
    Query query6 = query('coll').filter(
        orFilters(<Filter>[filter('a', '==', 1), filter('b', '==', 1)]));
    validateIndexType(query6, IndexType.full);

    // OR qry with explicit orderBy without limit which has all sub-target indexes.
    Query query7 = query('coll')
        .filter(orFilters(<Filter>[filter('a', '==', 1), filter('b', '==', 1)]))
        .orderBy(orderBy('a'));
    validateIndexType(query7, IndexType.full);

    // OR qry with implicit orderBy without limit which has all sub-target indexes.
    Query query8 = query('coll')
        .filter(orFilters(<Filter>[filter('a', '>', 1), filter('b', '==', 1)]));
    validateIndexType(query8, IndexType.full);

    // OR qry without orderBy with limit which has all sub-target indexes.
    Query query9 = query('coll')
        .filter(orFilters(<Filter>[filter('a', '==', 1), filter('b', '==', 1)]))
        .limitToFirst(2);
    validateIndexType(query9, IndexType.partial);

    // OR qry with explicit orderBy with limit which has all sub-target indexes.
    Query query10 = query('coll')
        .filter(orFilters(<Filter>[filter('a', '==', 1), filter('b', '==', 1)]))
        .orderBy(orderBy('a'))
        .limitToFirst(2);
    validateIndexType(query10, IndexType.partial);

    // OR qry with implicit orderBy with limit which has all sub-target indexes.
    Query query11 = query('coll')
        .filter(orFilters(<Filter>[filter('a', '>', 1), filter('b', '==', 1)]))
        .limitToLast(2);
    validateIndexType(query11, IndexType.partial);
  });

  test('TestCreateTargetIndexesCreatesFullIndexesForEachSubTarget', () async {
    Query qry = query('coll').filter(orFilters(<Filter>[
      filter('a', '==', 1),
      filter('b', '==', 2),
      filter('c', '==', 3)
    ]));

    Query subQuery1 = query('coll').filter(filter('a', '==', 1));
    Query subQuery2 = query('coll').filter(filter('b', '==', 2));
    Query subQuery3 = query('coll').filter(filter('c', '==', 3));

    validateIndexType(qry, IndexType.none);
    validateIndexType(subQuery1, IndexType.none);
    validateIndexType(subQuery2, IndexType.none);
    validateIndexType(subQuery3, IndexType.none);

    await indexManager.createTargetIndexes(qry.toTarget());

    validateIndexType(qry, IndexType.full);
    validateIndexType(subQuery1, IndexType.full);
    validateIndexType(subQuery2, IndexType.full);
    validateIndexType(subQuery3, IndexType.full);
  });

  test('TestCreateTargetIndexesUpgradesPartialIndexToFullIndex', () async {
    Query qry = query('coll').filter(
        andFilters(<Filter>[filter('a', '==', 1), filter('b', '==', 2)]));

    Query subQuery1 = query('coll').filter(filter('a', '==', 1));
    Query subQuery2 = query('coll').filter(filter('b', '==', 2));

    await indexManager.createTargetIndexes(subQuery1.toTarget());

    validateIndexType(qry, IndexType.partial);
    validateIndexType(subQuery1, IndexType.full);
    validateIndexType(subQuery2, IndexType.none);

    await indexManager.createTargetIndexes(qry.toTarget());

    validateIndexType(qry, IndexType.full);
    validateIndexType(subQuery1, IndexType.full);
    validateIndexType(subQuery2, IndexType.none);
  });

  test('testIndexesBsonObjectId', () async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        indexId: 0,
        indexState: FieldIndex.initialState,
        fieldsAndKinds: <Object>['key', SegmentKind.ascending]));

    await addDoc('coll/doc1',
        map(<dynamic>['key', BsonObjectId('507f191e810c19729de860ea')]));
    await addDoc('coll/doc2',
        map(<dynamic>['key', BsonObjectId('507f191e810c19729de860eb')]));
    await addDoc('coll/doc3',
        map(<dynamic>['key', BsonObjectId('507f191e810c19729de860ec')]));

    Query qry = query('coll').orderBy(orderBy('key', 'asc'));
    await verifyResults(qry, <String>['coll/doc1', 'coll/doc2', 'coll/doc3']);

    qry = query('coll')
        .filter(filter('key', '==', BsonObjectId('507f191e810c19729de860ea')));
    await verifyResults(qry, <String>['coll/doc1']);

    qry = query('coll')
        .filter(filter('key', '!=', BsonObjectId('507f191e810c19729de860ea')));
    await verifyResults(qry, <String>['coll/doc2', 'coll/doc3']);

    qry = query('coll')
        .filter(filter('key', '>=', BsonObjectId('507f191e810c19729de860eb')));
    await verifyResults(qry, <String>['coll/doc2', 'coll/doc3']);

    qry = query('coll')
        .filter(filter('key', '<=', BsonObjectId('507f191e810c19729de860eb')));
    await verifyResults(qry, <String>['coll/doc1', 'coll/doc2']);

    qry = query('coll')
        .filter(filter('key', '>', BsonObjectId('507f191e810c19729de860eb')));
    await verifyResults(qry, <String>['coll/doc3']);

    qry = query('coll')
        .filter(filter('key', '<', BsonObjectId('507f191e810c19729de860eb')));
    await verifyResults(qry, <String>['coll/doc1']);

    qry = query('coll')
        .filter(filter('key', '>', BsonObjectId('507f191e810c19729de860ec')));
    await verifyResults(qry, <String>[]);

    qry = query('coll')
        .filter(filter('key', '<', BsonObjectId('507f191e810c19729de860ea')));
    await verifyResults(qry, <String>[]);
  });

  test('testIndexesBsonBinary', () async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        indexId: 0,
        indexState: FieldIndex.initialState,
        fieldsAndKinds: <Object>['key', SegmentKind.ascending]));

    await addDoc(
        'coll/doc1',
        map(<dynamic>[
          'key',
          Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2, 3]))
        ]));
    await addDoc(
        'coll/doc2',
        map(<dynamic>[
          'key',
          Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2, 4]))
        ]));
    await addDoc(
        'coll/doc3',
        map(<dynamic>[
          'key',
          Blob.bsonBinary(1, Uint8List.fromList(<int>[2, 1, 2]))
        ]));

    Query qry = query('coll').orderBy(orderBy('key', 'asc'));
    await verifyResults(qry, <String>['coll/doc1', 'coll/doc2', 'coll/doc3']);

    qry = query('coll').filter(filter(
        'key', '==', Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2, 3]))));
    await verifyResults(qry, <String>['coll/doc1']);

    qry = query('coll').filter(filter(
        'key', '!=', Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2, 3]))));
    await verifyResults(qry, <String>['coll/doc2', 'coll/doc3']);

    qry = query('coll').filter(filter(
        'key', '>=', Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2, 4]))));
    await verifyResults(qry, <String>['coll/doc2', 'coll/doc3']);

    qry = query('coll').filter(filter(
        'key', '<=', Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2, 4]))));
    await verifyResults(qry, <String>['coll/doc1', 'coll/doc2']);

    qry = query('coll').filter(filter(
        'key', '>', Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2, 4]))));
    await verifyResults(qry, <String>['coll/doc3']);

    qry = query('coll').filter(filter(
        'key', '<', Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2, 4]))));
    await verifyResults(qry, <String>['coll/doc1']);

    qry = query('coll').filter(filter(
        'key', '>', Blob.bsonBinary(1, Uint8List.fromList(<int>[2, 1, 2]))));
    await verifyResults(qry, <String>[]);

    qry = query('coll').filter(filter(
        'key', '<', Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2, 3]))));
    await verifyResults(qry, <String>[]);
  });

  test('testIndexesBlobAndBsonBinaryOrderingAndMatching', () async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        indexId: 0,
        indexState: FieldIndex.initialState,
        fieldsAndKinds: <Object>['key', SegmentKind.ascending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        indexId: 1,
        indexState: FieldIndex.initialState,
        fieldsAndKinds: <Object>['key', SegmentKind.descending]));

    await addDoc(
        'coll/doc_blob',
        map(<dynamic>[
          'key',
          blob(<int>[1, 2, 3])
        ]));
    await addDoc(
        'coll/doc_bson0',
        map(<dynamic>[
          'key',
          Blob.bsonBinary(0, Uint8List.fromList(<int>[1, 2, 3]))
        ]));
    await addDoc(
        'coll/doc_bson1',
        map(<dynamic>[
          'key',
          Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2, 3]))
        ]));

    Query qry = query('coll').orderBy(orderBy('key', 'asc'));
    await verifyResults(
        qry, <String>['coll/doc_blob', 'coll/doc_bson0', 'coll/doc_bson1']);

    qry = query('coll').orderBy(orderBy('key', 'desc'));
    await verifyResults(
        qry, <String>['coll/doc_bson1', 'coll/doc_bson0', 'coll/doc_blob']);

    qry = query('coll').filter(filter('key', '==', blob(<int>[1, 2, 3])));
    await verifyResults(qry, <String>['coll/doc_blob', 'coll/doc_bson0']);

    qry = query('coll').filter(filter(
        'key', '==', Blob.bsonBinary(0, Uint8List.fromList(<int>[1, 2, 3]))));
    await verifyResults(qry, <String>['coll/doc_blob', 'coll/doc_bson0']);

    qry = query('coll').filter(filter(
        'key', '==', Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2, 3]))));
    await verifyResults(qry, <String>['coll/doc_bson1']);
  });

  test('testIndexesBsonTimestamp', () async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        indexId: 0,
        indexState: FieldIndex.initialState,
        fieldsAndKinds: <Object>['key', SegmentKind.ascending]));

    await addDoc('coll/doc1', map(<dynamic>['key', BsonTimestamp(1, 1)]));
    await addDoc('coll/doc2', map(<dynamic>['key', BsonTimestamp(1, 2)]));
    await addDoc('coll/doc3', map(<dynamic>['key', BsonTimestamp(2, 1)]));

    Query qry = query('coll').orderBy(orderBy('key', 'asc'));
    await verifyResults(qry, <String>['coll/doc1', 'coll/doc2', 'coll/doc3']);

    qry = query('coll').filter(filter('key', '==', BsonTimestamp(1, 1)));
    await verifyResults(qry, <String>['coll/doc1']);

    qry = query('coll').filter(filter('key', '!=', BsonTimestamp(1, 1)));
    await verifyResults(qry, <String>['coll/doc2', 'coll/doc3']);

    qry = query('coll').filter(filter('key', '>=', BsonTimestamp(1, 2)));
    await verifyResults(qry, <String>['coll/doc2', 'coll/doc3']);

    qry = query('coll').filter(filter('key', '<=', BsonTimestamp(1, 2)));
    await verifyResults(qry, <String>['coll/doc1', 'coll/doc2']);

    qry = query('coll').filter(filter('key', '>', BsonTimestamp(1, 2)));
    await verifyResults(qry, <String>['coll/doc3']);

    qry = query('coll').filter(filter('key', '<', BsonTimestamp(1, 2)));
    await verifyResults(qry, <String>['coll/doc1']);

    qry = query('coll').filter(filter('key', '>', BsonTimestamp(2, 1)));
    await verifyResults(qry, <String>[]);

    qry = query('coll').filter(filter('key', '<', BsonTimestamp(1, 1)));
    await verifyResults(qry, <String>[]);
  });

  test('testIndexesRegex', () async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        indexId: 0,
        indexState: FieldIndex.initialState,
        fieldsAndKinds: <Object>['key', SegmentKind.ascending]));

    await addDoc('coll/doc1', map(<dynamic>['key', RegexValue('a', 'i')]));
    await addDoc('coll/doc2', map(<dynamic>['key', RegexValue('a', 'm')]));
    await addDoc('coll/doc3', map(<dynamic>['key', RegexValue('b', 'i')]));

    Query qry = query('coll').orderBy(orderBy('key', 'asc'));
    await verifyResults(qry, <String>['coll/doc1', 'coll/doc2', 'coll/doc3']);

    qry = query('coll').filter(filter('key', '==', RegexValue('a', 'i')));
    await verifyResults(qry, <String>['coll/doc1']);

    qry = query('coll').filter(filter('key', '!=', RegexValue('a', 'i')));
    await verifyResults(qry, <String>['coll/doc2', 'coll/doc3']);

    qry = query('coll').filter(filter('key', '>=', RegexValue('a', 'm')));
    await verifyResults(qry, <String>['coll/doc2', 'coll/doc3']);

    qry = query('coll').filter(filter('key', '<=', RegexValue('a', 'm')));
    await verifyResults(qry, <String>['coll/doc1', 'coll/doc2']);

    qry = query('coll').filter(filter('key', '>', RegexValue('a', 'm')));
    await verifyResults(qry, <String>['coll/doc3']);

    qry = query('coll').filter(filter('key', '<', RegexValue('a', 'm')));
    await verifyResults(qry, <String>['coll/doc1']);

    qry = query('coll').filter(filter('key', '>', RegexValue('b', 'i')));
    await verifyResults(qry, <String>[]);

    qry = query('coll').filter(filter('key', '<', RegexValue('a', 'i')));
    await verifyResults(qry, <String>[]);
  });

  test('testIndexesInt32', () async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        indexId: 0,
        indexState: FieldIndex.initialState,
        fieldsAndKinds: <Object>['key', SegmentKind.ascending]));

    await addDoc('coll/doc1', map(<dynamic>['key', Int32Value(1)]));
    await addDoc('coll/doc2', map(<dynamic>['key', Int32Value(2)]));
    await addDoc('coll/doc3', map(<dynamic>['key', Int32Value(3)]));

    Query qry = query('coll').orderBy(orderBy('key', 'asc'));
    await verifyResults(qry, <String>['coll/doc1', 'coll/doc2', 'coll/doc3']);

    qry = query('coll').filter(filter('key', '==', Int32Value(1)));
    await verifyResults(qry, <String>['coll/doc1']);

    qry = query('coll').filter(filter('key', '!=', Int32Value(1)));
    await verifyResults(qry, <String>['coll/doc2', 'coll/doc3']);

    qry = query('coll').filter(filter('key', '>=', Int32Value(2)));
    await verifyResults(qry, <String>['coll/doc2', 'coll/doc3']);

    qry = query('coll').filter(filter('key', '<=', Int32Value(2)));
    await verifyResults(qry, <String>['coll/doc1', 'coll/doc2']);

    qry = query('coll').filter(filter('key', '>', Int32Value(2)));
    await verifyResults(qry, <String>['coll/doc3']);

    qry = query('coll').filter(filter('key', '<', Int32Value(2)));
    await verifyResults(qry, <String>['coll/doc1']);

    qry = query('coll').filter(filter('key', '>', Int32Value(3)));
    await verifyResults(qry, <String>[]);

    qry = query('coll').filter(filter('key', '<', Int32Value(1)));
    await verifyResults(qry, <String>[]);
  });

  test('testIndexesDecimal128Value', () async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        indexId: 0,
        indexState: FieldIndex.initialState,
        fieldsAndKinds: <Object>['key', SegmentKind.ascending]));

    await addDoc('coll/doc1', map(<dynamic>['key', Decimal128Value('-1.2e3')]));
    await addDoc('coll/doc2', map(<dynamic>['key', Decimal128Value('0.0')]));
    await addDoc('coll/doc3', map(<dynamic>['key', Decimal128Value('1.2e3')]));

    Query qry = query('coll').orderBy(orderBy('key', 'asc'));
    await verifyResults(qry, <String>['coll/doc1', 'coll/doc2', 'coll/doc3']);

    qry = query('coll').filter(filter('key', '==', Decimal128Value('-1200')));
    await verifyResults(qry, <String>['coll/doc1']);

    qry = query('coll').filter(filter('key', '!=', Decimal128Value('0')));
    await verifyResults(qry, <String>['coll/doc1', 'coll/doc3']);

    qry = query('coll').filter(filter('key', '>=', Decimal128Value('-0')));
    await verifyResults(qry, <String>['coll/doc2', 'coll/doc3']);

    qry = query('coll').filter(filter('key', '<=', Decimal128Value('-0.0')));
    await verifyResults(qry, <String>['coll/doc1', 'coll/doc2']);

    qry = query('coll').filter(filter('key', '>', Decimal128Value('1.2e-3')));
    await verifyResults(qry, <String>['coll/doc3']);

    qry = query('coll').filter(filter('key', '<', Decimal128Value('-1.2e-3')));
    await verifyResults(qry, <String>['coll/doc1']);

    qry = query('coll').filter(filter('key', '>', Decimal128Value('1.2e3')));
    await verifyResults(qry, <String>[]);

    qry = query('coll').filter(filter('key', '<', Decimal128Value('-1.2e3')));
    await verifyResults(qry, <String>[]);
  });

  test('testIndexesDecimal128ValueWithPrecisionLoss', () async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        indexId: 0,
        indexState: FieldIndex.initialState,
        fieldsAndKinds: <Object>['key', SegmentKind.ascending]));

    await addDoc(
        'coll/doc1',
        map(<dynamic>[
          'key',
          Decimal128Value('-0.1234567890123456789')
        ])); // will be rounded to -0.12345678901234568
    await addDoc('coll/doc2', map(<dynamic>['key', Decimal128Value('0')]));
    await addDoc(
        'coll/doc3',
        map(<dynamic>[
          'key',
          Decimal128Value('0.1234567890123456789')
        ])); // will be rounded to 0.12345678901234568

    Query qry = query('coll').orderBy(orderBy('key', 'asc'));
    await verifyResults(qry, <String>['coll/doc1', 'coll/doc2', 'coll/doc3']);

    qry = query('coll')
        .filter(filter('key', '==', Decimal128Value('0.1234567890123456789')));
    await verifyResults(qry, <String>['coll/doc3']);

    // Mismatch behaviour caused by rounding error. Firestore fetches the doc3 from SQLite DB as
    // doc3 rounds to the same number, even though the actual number in doc3 is different
    // Unlike SQLiteLocalStoreTest, this returns the doc3 as result
    qry = query('coll')
        .filter(filter('key', '==', Decimal128Value('0.12345678901234568')));
    await verifyResults(qry, <String>['coll/doc3']);

    // Operations that doesn't go up to 17 decimal digits of precision wouldn't be affected by
    // this rounding errors.
    qry = query('coll').filter(filter('key', '!=', Decimal128Value('0.0')));
    await verifyResults(qry, <String>['coll/doc1', 'coll/doc3']);

    qry = query('coll').filter(filter('key', '>=', Decimal128Value('1.23e-1')));
    await verifyResults(qry, <String>['coll/doc3']);

    qry =
        query('coll').filter(filter('key', '<=', Decimal128Value('-1.23e-1')));
    await verifyResults(qry, <String>['coll/doc1']);

    qry = query('coll').filter(filter('key', '>', Decimal128Value('1.2e3')));
    await verifyResults(qry, <String>[]);

    qry = query('coll').filter(filter('key', '<', Decimal128Value('-1.2e3')));
    await verifyResults(qry, <String>[]);
  });

  test('testIndexesMinKey', () async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        indexId: 0,
        indexState: FieldIndex.initialState,
        fieldsAndKinds: <Object>['key', SegmentKind.ascending]));
    await addDoc('coll/doc1', map(<dynamic>['key', MinKey.instance]));
    await addDoc('coll/doc2', map(<dynamic>['key', MinKey.instance]));
    await addDoc('coll/doc3', map(<dynamic>['key', null]));
    await addDoc('coll/doc4', map(<dynamic>['key', 1]));
    await addDoc('coll/doc5', map(<dynamic>['key', MaxKey.instance]));

    Query qry = query('coll').orderBy(orderBy('key', 'asc'));
    await verifyResults(qry, <String>[
      'coll/doc3',
      'coll/doc1',
      'coll/doc2',
      'coll/doc4',
      'coll/doc5'
    ]);

    qry = query('coll').filter(filter('key', '==', MinKey.instance));
    await verifyResults(qry, <String>['coll/doc1', 'coll/doc2']);

    qry = query('coll').filter(filter('key', '!=', MinKey.instance));
    await verifyResults(qry, <String>['coll/doc4', 'coll/doc5']);

    qry = query('coll').filter(filter('key', '>=', MinKey.instance));
    await verifyResults(qry, <String>['coll/doc1', 'coll/doc2']);

    qry = query('coll').filter(filter('key', '<=', MinKey.instance));
    await verifyResults(qry, <String>['coll/doc1', 'coll/doc2']);

    qry = query('coll').filter(filter('key', '>', MinKey.instance));
    await verifyResults(qry, <String>[]);

    qry = query('coll').filter(filter('key', '<', MinKey.instance));
    await verifyResults(qry, <String>[]);
  });

  test('testIndexesMaxKey', () async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        indexId: 0,
        indexState: FieldIndex.initialState,
        fieldsAndKinds: <Object>['key', SegmentKind.ascending]));
    await addDoc('coll/doc1', map(<dynamic>['key', MinKey.instance]));
    await addDoc('coll/doc2', map(<dynamic>['key', 1]));
    await addDoc('coll/doc3', map(<dynamic>['key', MaxKey.instance]));
    await addDoc('coll/doc4', map(<dynamic>['key', MaxKey.instance]));
    await addDoc('coll/doc5', map(<dynamic>['key', null]));

    Query qry = query('coll').orderBy(orderBy('key', 'asc'));
    await verifyResults(qry, <String>[
      'coll/doc5',
      'coll/doc1',
      'coll/doc2',
      'coll/doc3',
      'coll/doc4'
    ]);

    qry = query('coll').filter(filter('key', '==', MaxKey.instance));
    await verifyResults(qry, <String>['coll/doc3', 'coll/doc4']);

    qry = query('coll').filter(filter('key', '!=', MaxKey.instance));
    await verifyResults(qry, <String>['coll/doc1', 'coll/doc2']);

    qry = query('coll').filter(filter('key', '>=', MaxKey.instance));
    await verifyResults(qry, <String>['coll/doc3', 'coll/doc4']);

    qry = query('coll').filter(filter('key', '<=', MaxKey.instance));
    await verifyResults(qry, <String>['coll/doc3', 'coll/doc4']);

    qry = query('coll').filter(filter('key', '>', MaxKey.instance));
    await verifyResults(qry, <String>[]);

    qry = query('coll').filter(filter('key', '<', MaxKey.instance));
    await verifyResults(qry, <String>[]);
  });

  test('testIndexFieldsOfBsonTypesTogether', () async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['key', SegmentKind.descending]));

    await addDoc('coll/doc1', map(<dynamic>['key', MinKey.instance]));
    await addDoc('coll/doc2', map(<dynamic>['key', Int32Value(2)]));
    await addDoc('coll/doc3', map(<dynamic>['key', Int32Value(-1)]));
    await addDoc('coll/doc4', map(<dynamic>['key', Decimal128Value('1.2e3')]));
    await addDoc('coll/doc5', map(<dynamic>['key', Decimal128Value('-0.0')]));
    await addDoc('coll/doc6', map(<dynamic>['key', BsonTimestamp(1, 2)]));
    await addDoc('coll/doc7', map(<dynamic>['key', BsonTimestamp(1, 1)]));
    await addDoc(
        'coll/doc8',
        map(<dynamic>[
          'key',
          Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2, 4]))
        ]));
    await addDoc(
        'coll/doc9',
        map(<dynamic>[
          'key',
          Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2, 3]))
        ]));
    await addDoc('coll/doc10',
        map(<dynamic>['key', BsonObjectId('507f191e810c19729de860eb')]));
    await addDoc('coll/doc11',
        map(<dynamic>['key', BsonObjectId('507f191e810c19729de860ea')]));
    await addDoc('coll/doc12', map(<dynamic>['key', RegexValue('a', 'm')]));
    await addDoc('coll/doc13', map(<dynamic>['key', RegexValue('a', 'i')]));
    await addDoc('coll/doc14', map(<dynamic>['key', MaxKey.instance]));

    Query qry = query('coll').orderBy(orderBy('key', 'desc'));
    await verifyResults(qry, <String>[
      'coll/doc14', // maxKey
      'coll/doc12', // regex m
      'coll/doc13', // regex i
      'coll/doc10', // objectId eb
      'coll/doc11', // objectId ea
      'coll/doc8', // binary [1,2,4]
      'coll/doc9', // binary [1,2,3]
      'coll/doc6', // timestamp 1, 2
      'coll/doc7', // timestamp 1, 1
      'coll/doc4', // decimal128 1200
      'coll/doc2', // int32 2
      'coll/doc5', // decimal128 -0.0
      'coll/doc3', // int32 -1
      'coll/doc1' // minKey
    ]);
  });

  test('testIndexFieldsOfAllTypesTogether', () async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['key', SegmentKind.descending]));

    await addDoc('coll/a', map(<dynamic>['key', null]));
    await addDoc('coll/b', map(<dynamic>['key', MinKey.instance]));
    await addDoc('coll/c', map(<dynamic>['key', true]));
    await addDoc('coll/d', map(<dynamic>['key', double.nan]));
    await addDoc('coll/e', map(<dynamic>['key', Int32Value(1)]));
    await addDoc('coll/f', map(<dynamic>['key', 2.0]));
    await addDoc('coll/g', map(<dynamic>['key', 3]));
    await addDoc('coll/h', map(<dynamic>['key', Decimal128Value('1.2e3')]));
    await addDoc('coll/i', map(<dynamic>['key', Timestamp(100, 123456000)]));
    await addDoc('coll/j', map(<dynamic>['key', BsonTimestamp(1, 2)]));
    await addDoc('coll/k', map(<dynamic>['key', 'string']));
    await addDoc(
        'coll/l',
        map(<dynamic>[
          'key',
          blob(<int>[1, 2, 3])
        ]));
    await addDoc(
        'coll/m0',
        map(<dynamic>[
          'key',
          Blob.bsonBinary(0, Uint8List.fromList(<int>[1, 2, 3]))
        ]));
    await addDoc(
        'coll/m',
        map(<dynamic>[
          'key',
          Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2, 3]))
        ]));
    await addDoc('coll/n', map(<dynamic>['key', ref('foo/bar')]));
    await addDoc('coll/o',
        map(<dynamic>['key', BsonObjectId('507f191e810c19729de860ea')]));
    await addDoc('coll/p', map(<dynamic>['key', GeoPoint(0, 1)]));
    await addDoc('coll/q', map(<dynamic>['key', RegexValue('^foo', 'i')]));
    await addDoc(
        'coll/r',
        map(<dynamic>[
          'key',
          <Object?>[1, 2]
        ]));
    await addDoc(
        'coll/s',
        map(<dynamic>[
          'key',
          VectorValue(<double>[1, 2, 3])
        ]));
    await addDoc(
        'coll/t',
        map(<dynamic>[
          'key',
          map(<dynamic>['a', 1])
        ]));
    await addDoc('coll/u', map(<dynamic>['key', MaxKey.instance]));

    Query qry = query('coll').orderBy(orderBy('key', 'desc'));
    await verifyResults(qry, <String>[
      'coll/u', // maxKey
      'coll/t', // map
      'coll/s', // vector
      'coll/r', // array
      'coll/q', // regex
      'coll/p', // geopoint
      'coll/o', // objectId
      'coll/n', // reference
      'coll/m', // bsonBinary
      'coll/m0', // bsonBinary subtype 0
      'coll/l', // bytes
      'coll/k', // string
      'coll/j', // bsonTimestamp
      'coll/i', // timestamp
      'coll/h', // Number decimal128
      'coll/g', // Number long
      'coll/f', // Number double
      'coll/e', // Number int32
      'coll/d', // Number NaN
      'coll/c', // boolean
      'coll/b', // minKey
      'coll/a' // null
    ]);
  });
}
