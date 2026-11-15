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

/// A vector of doubles stored in a document field, for example an embedding
/// for vector search.
///
/// Create one with `VectorValue(values)` or `FieldValue.vector(values)` and
/// store it as a field value; a snapshot returns it for a vector field, also
/// through `DocumentSnapshot.getVectorValue`. Find the documents with the
/// nearest vectors with `Query.findNearest`.
///
/// ```dart
/// await firestore.doc('items/a').set(<String, Object?>{
///   'embedding': VectorValue(<double>[0.1, 0.2, 0.3]),
/// });
/// final DocumentSnapshot<Map<String, Object?>> snapshot =
///     await firestore.doc('items/a').get();
/// final List<double>? values = snapshot.getVectorValue('embedding')?.toArray();
/// ```
///
/// On a real database, vector search needs a vector index on the field,
/// which you create with the Google Cloud tools, not with this SDK.
///
/// A vector is not a list: it is a value of its own type and is not equal to
/// a `List<double>` with the same numbers. In `orderBy`, vectors sort after
/// arrays and before maps, by their length first and then by their values.
class VectorValue {
  /// Creates a vector holding a copy of [values]; later changes to [values]
  /// do not affect the vector.
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
        json,
        'json',
        'Not a JSON representation of a VectorValue',
      );
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
  ///
  /// ```dart
  /// VectorValue(<double>[0.1, 0.2]).length; // 2
  /// ```
  int get length => _values.length;

  /// Returns a copy of the vector as a list of doubles; changing the list does
  /// not change the vector.
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
