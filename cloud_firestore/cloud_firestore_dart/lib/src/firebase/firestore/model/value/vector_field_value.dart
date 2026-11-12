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

part of 'field_value.dart';

/// A wrapper for vector values in Firestore.
///
/// On the wire a vector is a map `{__type__: '__vector__', value: [doubles]}`.
/// Vectors sort after arrays and before maps; they compare first by length and
/// then element by element.
class VectorFieldValue extends FieldValue {
  const VectorFieldValue(this._value);

  factory VectorFieldValue.fromList(List<double> values) =>
      VectorFieldValue(List<double>.unmodifiable(values));

  /// The reserved map key holding the type marker.
  static const String typeKey = '__type__';

  /// The marker stored under [typeKey] for vectors.
  static const String vectorTypeValue = '__vector__';

  /// The reserved map key holding the array of doubles.
  static const String vectorKey = 'value';

  final List<double> _value;

  @override
  int get typeOrder => FieldValue.typeOrderVector;

  @override
  VectorValue get value => VectorValue(_value);

  List<double> get internalValue => _value;

  @override
  int compareTo(FieldValue other) {
    if (other is VectorFieldValue) {
      final int lengthCmp = _value.length.compareTo(other._value.length);
      if (lengthCmp != 0) {
        return lengthCmp;
      }
      for (int i = 0; i < _value.length; i++) {
        final int cmp = DoubleValue(
          _value[i],
        ).compareTo(DoubleValue(other._value[i]));
        if (cmp != 0) {
          return cmp;
        }
      }
      return 0;
    } else {
      return defaultCompareTo(other);
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VectorFieldValue &&
          _value.length == other._value.length &&
          compareTo(other) == 0;

  @override
  int get hashCode => const ListEquality<double>().hash(_value);
}
