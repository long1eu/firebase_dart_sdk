// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_firestore/src/firebase/firestore/core/nan_filter.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/null_filter.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/relation_filter.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/field_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/double_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/null_value.dart';

/// Interface used for all query filters.
abstract class Filter {
  const Filter();

  /// Gets a Filter instance for the provided path, operator, and value.
  ///
  /// * Note that if the relation operator is [FilterOperator.equal] and the
  /// value is null or NaN, this will return the appropriate [NullFilter] or
  /// [NaNFilter] class instead of a [RelationFilter].
  factory Filter.create(
      FieldPath path, FilterOperator operator, FieldValue value) {
    if (value == NullValue.nullValue()) {
      if (operator != FilterOperator.equal) {
        throw ArgumentError('Invalid Query. You can only perform equality '
            'comparisons on null (via whereEqualTo()).');
      }
      return NullFilter(path);
    } else if (value == DoubleValue.nan) {
      if (operator != FilterOperator.equal) {
        throw ArgumentError('Invalid Query. You can only perform equality '
            'comparisons on NaN (via whereEqualTo()).');
      }
      return NaNFilter(path);
    } else {
      return RelationFilter(path, operator, value);
    }
  }

  /// Returns the field the Filter operates over.
  FieldPath get field;

  /// A unique ID identifying the filter; used when serializing queries.
  String get canonicalId;

  /// Returns true if a document matches the filter.
  bool matches(Document doc);
}

class FilterOperator {
  const FilterOperator._(this._value);

  final String _value;

  static const FilterOperator lessThan = FilterOperator._('<');
  static const FilterOperator lessThanOrEqual = FilterOperator._('<=');
  static const FilterOperator equal = FilterOperator._('==');
  static const FilterOperator graterThan = FilterOperator._('>');
  static const FilterOperator graterThanOrEqual = FilterOperator._('>=');
  static const FilterOperator arrayContains =
      FilterOperator._('array_contains');

  @override
  String toString() => _value;
}
