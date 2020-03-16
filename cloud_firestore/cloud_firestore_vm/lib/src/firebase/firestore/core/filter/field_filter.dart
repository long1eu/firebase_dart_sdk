// File created by
// Lung Razvan <long1eu>
// on 16/03/2020

part of filter;

/// Represents a filter to be applied to query.
class FieldFilter extends Filter {
  /// Note that if the relation operator is EQUAL and the value is null or NaN, this will return
  /// the appropriate NullFilter or NaNFilter class instead of a FieldFilter.
  factory FieldFilter(
      FieldPath path, FilterOperator operator, FieldValue value) {
    if (path.isKeyField) {
      if (operator == FilterOperator.IN) {
        hardAssert(value is ArrayValue,
            'Comparing on key with IN, but an array value was not a RefValue');
        return KeyFieldInFilter(path, value);
      } else {
        hardAssert(value is ReferenceValue,
            'Comparing on key, but filter value not a ReferenceValue');
        hardAssert(
            operator != FilterOperator.arrayContains &&
                operator != FilterOperator.arrayContainsAny,
            '$operator queries don\'t make sense on document keys');
        return KeyFieldFilter(path, operator, value);
      }
    } else if (value == NullValue.nullValue()) {
      if (operator != FilterOperator.equal) {
        throw ArgumentError(
            'Invalid Query. You can only perform equality comparisons on null (via whereEqualTo()).');
      }
      return FieldFilter._(path, operator, value);
    } else if (value == DoubleValue.nan) {
      if (operator != FilterOperator.equal) {
        throw ArgumentError(
            'Invalid Query. You can only perform equality comparisons on NaN (via whereEqualTo()).');
      }
      return FieldFilter._(path, operator, value);
    } else if (operator == FilterOperator.arrayContains) {
      return ArrayContainsFilter(path, value);
    } else if (operator == FilterOperator.IN) {
      hardAssert(value is ArrayValue, 'IN filter has invalid value: $value');
      return InFilter(path, value);
    } else if (operator == FilterOperator.arrayContainsAny) {
      hardAssert(value is ArrayValue,
          'ARRAY_CONTAINS_ANY filter has invalid value: $value');
      return ArrayContainsAnyFilter(path, value);
    } else {
      return FieldFilter._(path, operator, value);
    }
  }

  /// Creates a new filter that compares fields and values. Only intended to be
  /// called from [Filter.create].
  const FieldFilter._(this.field, this.operator, this.value) : super._();

  final FilterOperator operator;
  final FieldValue value;
  @override
  final FieldPath field;

  @override
  bool matches(Document doc) {
    final FieldValue other = doc.getField(field);
    // Only compare types with matching backend order (such as double and int).
    return other != null &&
        value.typeOrder == other.typeOrder &&
        _matchesComparison(other.compareTo(value));
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
        throw fail('Unknown FieldFilter operator: $operator');
    }
  }

  bool get isInequality =>
      FilterOperator.inequalityOperators.contains(operator);

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
      other is FieldFilter &&
          runtimeType == other.runtimeType &&
          operator == other.operator &&
          value == other.value &&
          field == other.field;

  @override
  int get hashCode => operator.hashCode ^ value.hashCode ^ field.hashCode;
}
