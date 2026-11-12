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

import 'package:test/test.dart';

import 'cases/local_store_bundle_test_case.dart';
import 'persistence_test_helpers.dart';

void main() {
  late LocalStoreBundleTestCase testCase;

  setUp(() async {
    testCase = LocalStoreBundleTestCase(await createEagerGCMemoryPersistence());
    await testCase.setUp();
  });

  tearDown(() => testCase.tearDown());

  test('testHandlesSavingBundledDocuments',
      () => testCase.testHandlesSavingBundledDocuments());
  test(
      'testHandlesSavingBundlesDocumentsWithNewerExistingVersion',
      () =>
          testCase.testHandlesSavingBundlesDocumentsWithNewerExistingVersion());
  test(
      'testHandlesSavingBundledDocumentsWithOlderExistingVersion',
      () =>
          testCase.testHandlesSavingBundledDocumentsWithOlderExistingVersion());
  test(
      'testSavingBundledDocumentsWithSameExistingVersionShouldNotOverwrite',
      () => testCase
          .testSavingBundledDocumentsWithSameExistingVersionShouldNotOverwrite());
  test(
      'testHandlesMergeMutationWithTransformThenBundledDocuments',
      () =>
          testCase.testHandlesMergeMutationWithTransformThenBundledDocuments());
  test(
      'testHandlesPatchMutationWithTransformThenBundledDocuments',
      () =>
          testCase.testHandlesPatchMutationWithTransformThenBundledDocuments());
  test('testHandlesSavingAndCheckingBundleMetadata',
      () => testCase.testHandlesSavingAndCheckingBundleMetadata());
  test('testHandlesSavingAndLoadingNamedQueries',
      () => testCase.testHandlesSavingAndLoadingNamedQueries());
  test(
      'testLoadingNamedQueriesAllocatesTargetsAndUpdatesTargetDocumentMapping',
      () => testCase
          .testLoadingNamedQueriesAllocatesTargetsAndUpdatesTargetDocumentMapping());
  test('testHandlesSavingAndLoadingLimitToLastQueries',
      () => testCase.testHandlesSavingAndLoadingLimitToLastQueries());
  test('testNamedQueryTargetResumesFromTheReadTimeOfTheBundle',
      () => testCase.testNamedQueryTargetResumesFromTheReadTimeOfTheBundle());
  test('testOlderNamedQueryDoesNotOverwriteTheTargetOfANewerOne',
      () => testCase.testOlderNamedQueryDoesNotOverwriteTheTargetOfANewerOne());
  test('testBundleTargetsKeepDocumentsOnceTheQueryIsListenedTo',
      () => testCase.testBundleTargetsKeepDocumentsOnceTheQueryIsListenedTo());
}
