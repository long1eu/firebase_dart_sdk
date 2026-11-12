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

// Ported from upstream FieldValueTest.testNumericTransformsEquals (main).

import 'package:cloud_firestore_dart/src/firebase/firestore/field_value.dart';
import 'package:test/test.dart';

void main() {
  test('testNumericTransformsEquals (increment)', () {
    final FieldValue incInt = FieldValue.increment(5);
    final FieldValue incIntDup = FieldValue.increment(5);
    final FieldValue incDouble = FieldValue.increment(5.0);
    final FieldValue incDoubleDup = FieldValue.increment(5.0);

    expect(incIntDup, incInt);
    expect(incDoubleDup, incDouble);

    expect(incIntDup.hashCode, incInt.hashCode);
    expect(incDoubleDup.hashCode, incDouble.hashCode);

    expect(incInt, isNot(incDouble));
  });

  test('testNumericTransformsEquals (minimum)', () {
    final FieldValue i = FieldValue.minimum(5);
    final FieldValue iDup = FieldValue.minimum(5);
    final FieldValue d = FieldValue.minimum(5.0);
    final FieldValue dDup = FieldValue.minimum(5.0);

    expect(iDup, i);
    expect(dDup, d);
    expect(iDup.hashCode, i.hashCode);
    expect(dDup.hashCode, d.hashCode);
    expect(i, isNot(d));
  });

  test('testNumericTransformsEquals (maximum)', () {
    final FieldValue i = FieldValue.maximum(5);
    final FieldValue iDup = FieldValue.maximum(5);
    final FieldValue d = FieldValue.maximum(5.0);
    final FieldValue dDup = FieldValue.maximum(5.0);

    expect(iDup, i);
    expect(dDup, d);
    expect(iDup.hashCode, i.hashCode);
    expect(dDup.hashCode, d.hashCode);
    expect(i, isNot(d));
  });

  test('testNumericTransformsEquals (different kinds)', () {
    // Only increment exists in the port; compare it against the other
    // transform sentinels that do exist.
    final FieldValue incInt = FieldValue.increment(5);
    expect(incInt, isNot(FieldValue.serverTimestamp()));
    expect(incInt, isNot(FieldValue.delete()));
    expect(incInt, isNot(FieldValue.minimum(5)));
    expect(FieldValue.minimum(5), isNot(FieldValue.maximum(5)));
    expect(incInt, isNot(FieldValue.arrayUnion(<Object?>[5])));
    expect(incInt, isNot(FieldValue.arrayRemove(<Object?>[5])));
  });
}
