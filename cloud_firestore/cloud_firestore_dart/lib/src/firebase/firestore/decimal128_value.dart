// Copyright 2026 Google LLC
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

import 'package:cloud_firestore_dart/src/firebase/firestore/util/exact_number.dart';

/// Represents a 128-bit decimal type in Firestore documents.
///
/// Only databases of the Enterprise edition store this type.
class Decimal128Value {
  /// Creates a 128-bit decimal from its string representation, for example
  /// `1.5`, `-1.2e3`, `NaN`, `Infinity` or `-Infinity`.
  ///
  /// The value must be one that IEEE 754 decimal128 holds exactly, as the
  /// backend only stores such values: at most 34 significant digits (leading
  /// zeros, and trailing zeros that do not carry a digit, do not count, so
  /// `1.` with 40 zeros is fine), and nothing above `9.99...9e6144` (34 nines)
  /// or below `1e-6176` in the last digit. Zeros of any exponent, `NaN` and
  /// the infinities are fine.
  ///
  /// Throws a [FormatException] if [stringValue] is not a decimal number, or
  /// one that decimal128 can not hold exactly (for example
  /// `1.0000000000000000000000000000000001`, `1e6145` or `1e-6177`).
  Decimal128Value(this.stringValue) : _number = _parse(stringValue);

  /// A decimal that is not checked against the decimal128 range: for values
  /// that come from the backend, a bundle or the local cache (always valid in
  /// practice; one that is not is still compared exactly), and for results of
  /// the local pipeline evaluator.
  Decimal128Value._unchecked(this.stringValue)
    : _number = ExactNumber.parse(stringValue);

  static ExactNumber _parse(String stringValue) {
    final ExactNumber number = ExactNumber.parse(stringValue);
    if (!number.isDecimal128) {
      throw FormatException(
        'Decimal128Value: not a value decimal128 can hold exactly (at most 34 '
        'significant digits, between 1e-6176 and 9.99...9e6144)',
        stringValue.length <= 200
            ? stringValue
            : '${stringValue.substring(0, 200)}...',
      );
    }
    return number;
  }

  /// The string representation of the decimal, as it was provided.
  final String stringValue;

  final ExactNumber _number;

  /// Two decimals are equal if they have the same numeric value, so `1.0`
  /// equals `1`, and `-0` equals `0`.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Decimal128Value && _number.compareTo(other._number) == 0;

  @override
  int get hashCode => _number.decimalHashCode;

  @override
  String toString() => 'Decimal128Value{value=$stringValue}';
}

/// Internal members of [Decimal128Value]; not exported.
extension Decimal128ValueInternal on Decimal128Value {
  /// A decimal of [stringValue] without the decimal128 range check: see
  /// [Decimal128Value._unchecked].
  static Decimal128Value unchecked(String stringValue) =>
      Decimal128Value._unchecked(stringValue);
}
