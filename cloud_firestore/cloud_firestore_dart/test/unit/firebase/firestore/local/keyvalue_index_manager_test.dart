// File created by
// Lung Razvan <long1eu>
// on 02/10/2018

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/local/keyvalue/cache_store_persistence.dart';
import 'package:test/test.dart';

import 'cases/index_manager_test_case.dart';
import 'persistence_test_helpers.dart';

void main() {
  late IndexManagerTestCase testCase;

  setUp(() async {
    print('setUp');
    final CacheStorePersistence persistence = await createKeyValuePersistence();
    testCase = IndexManagerTestCase(persistence);
    await testCase.setUp();
    print('setUpDone');
  });

  tearDown(
    () => Future<void>.delayed(
      const Duration(milliseconds: 250),
      () => testCase.tearDown(),
    ),
  );

  test(
    'testCanAddAndReadCollectionParentIndexEntries',
    () => testCase.testCanAddAndReadCollectionParentIndexEntries(),
  );
}
