// Copyright 2024 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Upstream (main) MutationTest and NumericMinimum/MaximumTransformOperationTest
// cases that exercise features the port does not have yet. They are listed
// here as skipped tests so they show up in the test report and can be ported
// when the features arrive.

import 'package:test/test.dart';

void main() {
  const String noMinMax =
      'FieldValue.minimum/maximum (NumericMinimum/MaximumTransformOperation) '
      'are not implemented in the port';
  const String noInt32 = 'Int32Value / Decimal128Value are not implemented in '
      'the port';
  const String noOverlays = 'Mutation.calculateOverlayMutation (document '
      'overlays) is not implemented in the port';

  group('numeric minimum/maximum transforms', () {
    for (final String name in <String>[
      'testAppliesMinimumTransformToDocument',
      'testAppliesMaximumTransformToDocument',
      'testAppliesMinimumTransformToUnexpectedType',
      'testAppliesMaximumTransformToUnexpectedType',
      'testAppliesMinimumTransformToMissingField',
      'testAppliesMaximumTransformToMissingField',
      'testAppliesNumericTransformsToStandardIntegerAndDoubleFields',
      'testAppliesNumericTransformsToMissingAndNonNumericFields',
      'testAppliesConsecutiveNumericTransformsOnDocument',
      'testNumericMinimumBaseValue',
      'testNumericMaximumBaseValue',
      'NumericMinimumTransformOperationTest (all cases)',
      'NumericMaximumTransformOperationTest (all cases)',
    ]) {
      test(name, skip: noMinMax, () {});
    }
  });

  group('int32 / decimal128 numeric transforms', () {
    for (final String name in <String>[
      'testModelIncrementInt32AndInt32',
      'testModelIncrementDecimal128AndDecimal128',
      'testAppliesIncrementWithIntegerToInt32Base',
      'testAppliesNumericTransformsToInt32Fields',
      'testAppliesNumericTransformsToDecimal128Fields',
      'testModelMinimum/Maximum Int32 and Decimal128 variants',
    ]) {
      test(name, skip: noInt32, () {});
    }
  });

  group('overlays', () {
    for (final String name in <String>[
      'testOverlayWithNoMutation',
      'testOverlayWithMutationsFailByPreconditions',
      'testOverlayWithPatchOnInvalidDocument',
      'testOverlayWithOneSetMutation',
      'testOverlayWithOnePatchMutation',
      'testOverlayWithPatchThenMerge',
      'testOverlayWithDeleteThenPatch',
      'testOverlayWithDeleteThenMerge',
      'testOverlayWithPatchThenPatchToDeleteField',
      'testOverlayWithPatchThenMergeWithArrayUnion',
      'testOverlayWithArrayUnionThenRemove',
      'testOverlayWithSetThenIncrement',
      'testOverlayWithSetThenPatchOnDeletedDoc',
      'testOverlayWithFieldDeletionOfNestedField',
      'testOverlayCreatedFromSetToEmptyWithMerge',
      'testOverlayWithMutationWithMultipleDeletes',
      'testOverlayByCombinationsAndPermutations',
      'testOverlayByCombinationsAndPermutations_ArrayTransforms',
      'testOverlayByCombinationsAndPermutations_Increments',
    ]) {
      test(name, skip: noOverlays, () {});
    }
  });
}
