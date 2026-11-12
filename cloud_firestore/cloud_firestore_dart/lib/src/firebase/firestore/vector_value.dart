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

  /// Builds a vector from a JSON map created by [toJson].
  ///
  /// Throws an [ArgumentError] if [json] does not have that shape. This is the JS SDK `VectorValue.fromJSON()`.
  factory VectorValue.fromJson(Map<String, Object?> json) {
    final Object? values = json['vectorValues'];
    if (json['type'] != jsonType ||
        values is! List<Object?> ||
        values.any((Object? value) => value is! num)) {
      throw ArgumentError.value(
          json, 'json', 'Not a JSON representation of a VectorValue');
    }
    return VectorValue(<double>[
      for (final Object? value in values) (value! as num).toDouble(),
    ]);
  }

  /// The value of the `type` field written by [toJson].
  static const String jsonType = 'firestore/vectorValue/1.0';

  final List<double> _values;

  /// A JSON-serializable representation of this vector, in the same shape as the JS SDK's `VectorValue.toJSON()`: its
  /// `type` ([jsonType]) and `vectorValues`. Read it back with [VectorValue.fromJson].
  ///
  /// Like in the JS SDK, a vector with a NaN or infinite component cannot be encoded as JSON.
  Map<String, Object> toJson() {
    return <String, Object>{
      'type': jsonType,
      'vectorValues': List<double>.of(_values),
    };
  }

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
