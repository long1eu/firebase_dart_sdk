// Copyright 2024 Google LLC
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

import 'package:collection/collection.dart';

/// Represents a vector type in Firestore documents.
///
/// Create an instance with `FieldValue.vector`.
class VectorValue {
  /// Creates a vector holding a copy of [values].
  VectorValue(List<double> values)
      : _values = List<double>.unmodifiable(values);

  final List<double> _values;

  /// The number of dimensions of the vector.
  int get length => _values.length;

  /// Returns a copy of the vector as a list of doubles.
  List<double> toArray() => List<double>.of(_values);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VectorValue &&
          const ListEquality<double>().equals(_values, other._values);

  @override
  int get hashCode => const ListEquality<double>().hash(_values);

  @override
  String toString() => 'VectorValue($_values)';
}
