// Copyright 2018 Google LLC
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

// The NaN equality group of upstream FieldValueTest.testValueEquality, which is
// commented out in field_value_test.dart.

import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:test/test.dart';

import '../../../../util/equals_tester.dart';
import '../../../../util/test_util.dart';

void main() {
  test('testValueEquality (NaN group)', () {
    final ByteData bits = ByteData(8)..setUint64(0, 0x7ff8000000000000);
    final double canonicalNan = bits.getFloat64(0);
    // NaNs with other bits: the one `0.0 / 0.0` is on x64 (sign bit set) and
    // one with a payload. On arm64 `0.0 / 0.0` is the canonical NaN, so
    // without these the test only fails on x64.
    final double negativeNan =
        (ByteData(8)..setUint64(0, 0xfff8000000000000)).getFloat64(0);
    final double payloadNan =
        (ByteData(8)..setUint64(0, 0x7ff8000000000123)).getFloat64(0);
    expect(negativeNan.isNaN && payloadNan.isNaN, isTrue);

    EqualsTester()
        .addEqualityGroup(<FieldValue>[
          wrap(0.0 / 0.0),
          wrap(canonicalNan),
          wrap(negativeNan),
          wrap(payloadNan),
          DoubleValue.nan,
        ])
        // -0.0 and 0.0 compareTo the same but are not equal.
        .addItem(wrap(-0.0))
        .addItem(wrap(0.0))
        .testEquals();
  });
}
