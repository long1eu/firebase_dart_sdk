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

/// Represents a 32-bit integer type in Firestore documents.
///
/// Only databases of the Enterprise edition store this type.
class Int32Value {
  /// Creates a 32-bit integer value.
  ///
  /// Throws an [ArgumentError] if [value] is not in the range of a signed
  /// 32-bit integer.
  Int32Value(this.value) {
    if (value < minValue || value > maxValue) {
      throw ArgumentError.value(
          value, 'value', 'Int32Value must be a signed 32-bit integer');
    }
  }

  /// The smallest value an [Int32Value] can hold.
  static const int minValue = -2147483648;

  /// The largest value an [Int32Value] can hold.
  static const int maxValue = 2147483647;

  /// The 32-bit integer.
  final int value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Int32Value && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Int32Value{value=$value}';
}
