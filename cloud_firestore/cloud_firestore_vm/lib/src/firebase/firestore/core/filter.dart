// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';

/// Interface used for all query filters.
abstract class Filter {
  const Filter._();

  /// Gets a Filter instance for the provided path, operator, and value.
  ///
  /// Note that if the relation operator is [FilterOperator.equal] and the value
  /// is null or NaN, this will return the appropriate [NullFilter] or
  /// [NaNFilter] class instead of a [RelationFilter].
  factory Filter.create(
    FieldPath path,
    FilterOperator operator,
    FieldValue value,
  ) {
    if (value == NullValue.nullValue()) {
      if (operator != FilterOperator.equal) {
        throw ArgumentError(
            'Invalid Query. You can only perform equality comparisons on null (via whereEqualTo()).');
      }
      return NullFilter(path);
    } else if (value == DoubleValue.nan) {
      if (operator != FilterOperator.equal) {
        throw ArgumentError(
            'Invalid Query. You can only perform equality comparisons on NaN (via whereEqualTo()).');
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

/// Filter that matches NaN (not-a-number) fields.
class NaNFilter extends Filter {
  const NaNFilter(this.fieldPath) : super._();

  final FieldPath fieldPath;

  @override
  FieldPath get field => fieldPath;

  @override
  bool matches(Document doc) {
    final FieldValue fieldValue = doc.getField(fieldPath);
    return fieldValue != null && fieldValue == DoubleValue.nan;
  }

  @override
  String get canonicalId => '${fieldPath.canonicalString} IS NaN';

  @override
  String toString() => canonicalId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NaNFilter &&
          runtimeType == other.runtimeType &&
          fieldPath == other.fieldPath;

  @override
  int get hashCode => fieldPath.hashCode;
}

/// Filter that matches NULL values.
class NullFilter extends Filter {
  const NullFilter(this.fieldPath) : super._();

  final FieldPath fieldPath;

  @override
  FieldPath get field => fieldPath;

  @override
  bool matches(Document doc) {
    final FieldValue fieldValue = doc.getField(fieldPath);
    return fieldValue != null && fieldValue == NullValue.nullValue();
  }

  @override
  String get canonicalId => '${fieldPath.canonicalString} IS NULL';

  @override
  String toString() => canonicalId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NullFilter &&
          runtimeType == other.runtimeType &&
          fieldPath == other.fieldPath;

  @override
  int get hashCode => fieldPath.hashCode;
}

/// Represents a filter to be applied to query.
class RelationFilter extends Filter {
  /// Creates a new filter that compares fields and values. Only intended to be
  /// called from [Filter.create].
  const RelationFilter(this.field, this.operator, this.value) : super._();

  final FilterOperator operator;
  final FieldValue value;
  @override
  final FieldPath field;

  @override
  bool matches(Document doc) {
    if (field.isKeyField) {
      final DocumentKey refValue = value.value;
      hardAssert(refValue is DocumentKey,
          'Comparing on key, but filter value not a DocumentKey');
      hardAssert(operator != FilterOperator.arrayContains,
          'ARRAY_CONTAINS queries don\'t make sense on document keys.');
      final int comparison = doc.key.compareTo(refValue);
      return _matchesComparison(comparison);
    } else {
      final FieldValue value = doc.getField(field);
      return value != null && _matchesValue(value);
    }
  }

  bool _matchesValue(FieldValue other) {
    if (operator == FilterOperator.arrayContains) {
      return other is ArrayValue && other.internalValue.contains(value);
    } else {
      // Only compare types with matching backend order (such as double and int).
      return value.typeOrder == other.typeOrder &&
          _matchesComparison(other.compareTo(value));
    }
  }

  bool _matchesComparison(int comp) {
    switch (operator) {
      case FilterOperator.lessThan:
        return comp < 0;
      case FilterOperator.lessThanOrEqual:
        return comp <= 0;
      case FilterOperator.equal:
        return comp == 0;
      case FilterOperator.graterThan:
        return comp > 0;
      case FilterOperator.graterThanOrEqual:
        return comp >= 0;
      default:
        throw fail('Unknown operator: $operator');
    }
  }

  bool get isInequality =>
      operator != FilterOperator.equal &&
      operator != FilterOperator.arrayContains;

  // TODO(long1eu): Technically, this won't be unique if two values have the
  //  same description, such as the int 3 and the string '3'. So we should add
  //  the types in here somehow, too.
  @override
  String get canonicalId => '${field.canonicalString} $operator $value';

  @override
  String toString() => canonicalId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RelationFilter &&
          runtimeType == other.runtimeType &&
          operator == other.operator &&
          value == other.value &&
          field == other.field;

  @override
  int get hashCode => operator.hashCode ^ value.hashCode ^ field.hashCode;
}
