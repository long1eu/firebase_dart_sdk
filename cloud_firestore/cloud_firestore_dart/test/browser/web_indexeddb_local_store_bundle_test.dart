// The shared local store bundle suite of test/unit/firebase/firestore/local (the list of keyvalue_local_store_bundle_test.dart) on the
// IndexedDB engine, in a browser.
//
//   dart test -p chrome -c dart2wasm test/browser/web_indexeddb_local_store_bundle_test.dart

@TestOn('browser')
library;

import 'package:test/test.dart';

import 'indexeddb_test_persistence.dart';

import '../unit/firebase/firestore/local/cases/local_store_bundle_test_case.dart';

void main() {
  late LocalStoreBundleTestCase testCase;

  setUp(() async {
    testCase = LocalStoreBundleTestCase(await newIndexedDbTestPersistence());
    await testCase.setUp();
  });

  tearDown(() => testCase.tearDown());

  test(
    'testHandlesSavingBundledDocuments',
    () => testCase.testHandlesSavingBundledDocuments(),
  );
  test(
    'testHandlesSavingBundlesDocumentsWithNewerExistingVersion',
    () => testCase.testHandlesSavingBundlesDocumentsWithNewerExistingVersion(),
  );
  test(
    'testHandlesSavingBundledDocumentsWithOlderExistingVersion',
    () => testCase.testHandlesSavingBundledDocumentsWithOlderExistingVersion(),
  );
  test(
    'testSavingBundledDocumentsWithSameExistingVersionShouldNotOverwrite',
    () => testCase
        .testSavingBundledDocumentsWithSameExistingVersionShouldNotOverwrite(),
  );
  test(
    'testHandlesMergeMutationWithTransformThenBundledDocuments',
    () => testCase.testHandlesMergeMutationWithTransformThenBundledDocuments(),
  );
  test(
    'testHandlesPatchMutationWithTransformThenBundledDocuments',
    () => testCase.testHandlesPatchMutationWithTransformThenBundledDocuments(),
  );
  test(
    'testHandlesSavingAndCheckingBundleMetadata',
    () => testCase.testHandlesSavingAndCheckingBundleMetadata(),
  );
  test(
    'testHandlesSavingAndLoadingNamedQueries',
    () => testCase.testHandlesSavingAndLoadingNamedQueries(),
  );
  test(
    'testLoadingNamedQueriesAllocatesTargetsAndUpdatesTargetDocumentMapping',
    () => testCase
        .testLoadingNamedQueriesAllocatesTargetsAndUpdatesTargetDocumentMapping(),
  );
  test(
    'testHandlesSavingAndLoadingLimitToLastQueries',
    () => testCase.testHandlesSavingAndLoadingLimitToLastQueries(),
  );
  test(
    'testNamedQueryTargetResumesFromTheReadTimeOfTheBundle',
    () => testCase.testNamedQueryTargetResumesFromTheReadTimeOfTheBundle(),
  );
  test(
    'testOlderNamedQueryDoesNotOverwriteTheTargetOfANewerOne',
    () => testCase.testOlderNamedQueryDoesNotOverwriteTheTargetOfANewerOne(),
  );
  test(
    'testBundleTargetsKeepDocumentsOnceTheQueryIsListenedTo',
    () => testCase.testBundleTargetsKeepDocumentsOnceTheQueryIsListenedTo(),
  );
}
