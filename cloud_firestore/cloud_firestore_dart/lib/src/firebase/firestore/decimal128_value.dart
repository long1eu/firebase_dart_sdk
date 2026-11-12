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
  /// Throws a [FormatException] if [stringValue] is not a decimal number.
  Decimal128Value(this.stringValue) : _number = ExactNumber.parse(stringValue);

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
