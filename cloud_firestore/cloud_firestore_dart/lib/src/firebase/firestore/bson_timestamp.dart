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

/// Represents a BSON Timestamp type in Firestore documents.
///
/// Only databases of the Enterprise edition store this type.
class BsonTimestamp {
  /// Creates a BSON timestamp.
  ///
  /// Throws an [ArgumentError] if [seconds] or [increment] is not in the range
  /// of an unsigned 32-bit integer.
  BsonTimestamp(this.seconds, this.increment) {
    if (seconds < 0 || seconds > maxValue) {
      throw ArgumentError.value(seconds, 'seconds',
          "The field 'seconds' does not represent an unsigned 32-bit integer");
    }
    if (increment < 0 || increment > maxValue) {
      throw ArgumentError.value(increment, 'increment',
          "The field 'increment' does not represent an unsigned 32-bit integer");
    }
  }

  /// The largest value [seconds] and [increment] can hold.
  static const int maxValue = 4294967295;

  /// The seconds since the Unix epoch, an unsigned 32-bit integer.
  final int seconds;

  /// The ordinal of the operation within [seconds], an unsigned 32-bit
  /// integer.
  final int increment;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BsonTimestamp &&
          seconds == other.seconds &&
          increment == other.increment;

  @override
  int get hashCode => Object.hash(seconds, increment);

  @override
  String toString() => 'BsonTimestamp{seconds=$seconds, increment=$increment}';
}
