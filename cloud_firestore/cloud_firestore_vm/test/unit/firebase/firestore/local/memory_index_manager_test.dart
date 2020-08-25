// File created by
// Lung Razvan <long1eu>
// on 02/10/2018

import 'dart:async';

import 'package:cloud_firestore_vm/src/firebase/firestore/local/memory/memory_persistence.dart';
import 'package:test/test.dart';

import 'cases/index_manager_test_case.dart';
import 'persistence_test_helpers.dart';

void main() {
  IndexManagerTestCase testCase;

  setUp(() async {
    print('setUp');
    final MemoryPersistence persistence =
        await createEagerGCMemoryPersistence();
    testCase = IndexManagerTestCase(persistence)..setUp();
    print('setUpDone');
  });

  tearDown(() => Future<void>.delayed(
      const Duration(milliseconds: 250), () => testCase.tearDown()));

  test('testCanAddAndReadCollectionParentIndexEntries',
      () => testCase.testCanAddAndReadCollectionParentIndexEntries());
}
