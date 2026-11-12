// Copyright 2022 Google LLC
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

import 'package:cloud_firestore_dart/src/firebase/firestore/field_path.dart';

/// Represents an aggregation that can be performed by Firestore.
///
/// Create instances with [AggregateField.count], [AggregateField.sum] and
/// [AggregateField.average] and pass them to `Query.aggregate`.
abstract class AggregateField {
  AggregateField._(this._fieldPath, this.operator)
      : alias = _fieldPath == null ? operator : '${operator}_$_fieldPath';

  final FieldPath? _fieldPath;

  /// The name of the aggregation operator: `count`, `sum` or `average`.
  final String operator;

  /// The client-side alias under which the result is stored in an
  /// [AggregateQuerySnapshot]. The alias sent to the server is different.
  final String alias;

  /// The canonical string of the field this aggregation operates on, or the
  /// empty string for aggregations without a field (count).
  String get fieldPath => _fieldPath?.toString() ?? '';

  /// Creates an [AggregateField] that counts the documents in the result set.
  static CountAggregateField count() => CountAggregateField._();

  /// Creates an [AggregateField] that sums the values of [field] over the
  /// documents in the result set.
  ///
  /// Non-numeric values are ignored. The result is an integer unless a double
  /// value takes part in the sum or the integer sum overflows, in which case it
  /// is a double.
  static SumAggregateField sum(String field) =>
      SumAggregateField._(FieldPath.fromDotSeparatedPath(field));

  /// Same as [sum] but takes a [FieldPath].
  static SumAggregateField sumField(FieldPath fieldPath) =>
      SumAggregateField._(fieldPath);

  /// Creates an [AggregateField] that averages the values of [field] over the
  /// documents in the result set. The result is a double, or null if no
  /// document has a numeric value for the field.
  static AverageAggregateField average(String field) =>
      AverageAggregateField._(FieldPath.fromDotSeparatedPath(field));

  /// Same as [average] but takes a [FieldPath].
  static AverageAggregateField averageField(FieldPath fieldPath) =>
      AverageAggregateField._(fieldPath);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! AggregateField) {
      return false;
    }
    if (_fieldPath == null || other._fieldPath == null) {
      return _fieldPath == null && other._fieldPath == null;
    }
    return operator == other.operator && fieldPath == other.fieldPath;
  }

  @override
  int get hashCode => Object.hash(operator, fieldPath);

  @override
  String toString() => '$operator($fieldPath)';
}

/// Counts the documents in the result set.
class CountAggregateField extends AggregateField {
  CountAggregateField._() : super._(null, 'count');
}

/// Sums the values of a field over the result set.
class SumAggregateField extends AggregateField {
  SumAggregateField._(FieldPath fieldPath) : super._(fieldPath, 'sum');
}

/// Averages the values of a field over the result set.
class AverageAggregateField extends AggregateField {
  AverageAggregateField._(FieldPath fieldPath) : super._(fieldPath, 'average');
}
