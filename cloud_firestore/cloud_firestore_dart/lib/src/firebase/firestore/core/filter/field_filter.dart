// File created by
// Lung Razvan <long1eu>
// on 16/03/2020

part of 'filter.dart';

/// Represents a filter to be applied to query.
class FieldFilter extends Filter {
  factory FieldFilter(
    FieldPath path,
    FilterOperator operator,
    FieldValue value,
  ) {
    if (path.isKeyField) {
      if (operator == FilterOperator.IN) {
        hardAssert(
          value is ArrayValue,
          'Comparing on key with IN, but an array value was not a RefValue',
        );
        return KeyFieldInFilter(path, value);
      } else if (operator == FilterOperator.NOT_IN) {
        hardAssert(
          value is ArrayValue,
          'Comparing on key with NOT_IN, but an array value was not a RefValue',
        );
        return KeyFieldNotInFilter(path, value);
      } else {
        hardAssert(
          value is ReferenceValue,
          'Comparing on key, but filter value not a ReferenceValue',
        );
        hardAssertLazy(
          operator != FilterOperator.arrayContains &&
              operator != FilterOperator.arrayContainsAny,
          () => '$operator queries don\'t make sense on document keys',
        );
        return KeyFieldFilter(path, operator, value);
      }
    } else if (operator == FilterOperator.arrayContains) {
      return ArrayContainsFilter(path, value);
    } else if (operator == FilterOperator.IN) {
      hardAssertLazy(
        value is ArrayValue,
        () => 'IN filter has invalid value: $value',
      );
      return InFilter(path, value);
    } else if (operator == FilterOperator.arrayContainsAny) {
      hardAssertLazy(
        value is ArrayValue,
        () => 'ARRAY_CONTAINS_ANY filter has invalid value: $value',
      );
      return ArrayContainsAnyFilter(path, value);
    } else if (operator == FilterOperator.NOT_IN) {
      hardAssertLazy(
        value is ArrayValue,
        () => 'NOT_IN filter has invalid value: $value',
      );
      return NotInFilter(path, value);
    } else {
      return FieldFilter._(path, operator, value);
    }
  }

  /// Creates a new filter that compares fields and values. Only intended to be
  /// called from [Filter.create].
  const FieldFilter._(this.field, this.operator, this.value) : super._();

  final FilterOperator operator;
  final FieldValue value;
  final FieldPath field;

  @override
  List<Filter> get filters => <Filter>[this];

  @override
  List<FieldFilter> get flattenedFilters => <FieldFilter>[this];

  @override
  bool matches(Document doc) {
    final FieldValue? other = doc.getField(field);
    // Types do not have to match in NOT_EQUAL filters. Documents where the
    // field is missing or null are excluded.
    if (operator == FilterOperator.notEqual) {
      return other != null &&
          other is! NullValue &&
          _matchesComparison(other.compareTo(value));
    }
    // Null and NaN have a place in the order of values (null before
    // everything, NaN before the other numbers), but the backend does not
    // order by them in a filter: `a < 1` does not match a NaN, `a > null`
    // matches nothing, and `a >= NaN` matches no number.
    //
    // PORTING NOTE: the JS and Android SDKs evaluate these with the order of
    // values, and then match documents that the backend does not return.
    final bool special =
        _isNaN(other) ||
        _isNaN(value) ||
        other is NullValue ||
        value is NullValue;
    if (special && operator != FilterOperator.equal) {
      // `<=` and `>=` hold for a null with null and for a NaN with NaN, as in
      // the other SDKs and in an Enterprise edition database (a Standard
      // edition database matches nothing here either).
      final bool same =
          other is NullValue && value is NullValue ||
          _isNaN(other) && _isNaN(value);
      return same &&
          (operator == FilterOperator.lessThanOrEqual ||
              operator == FilterOperator.graterThanOrEqual);
    }
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
      case FilterOperator.notEqual:
        return comp != 0;
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
  String get canonicalId =>
      // TODO(b/29183165): Technically, this won't be unique if two values have the same description, such as the int
      //  3 and the string "3". So we should add the types in here somehow, too.
      '${field.canonicalString}${operator.canonicalName}${canonifyValue(value)}';

  @override
  // For messages (the JS `stringifyFilter`); the canonical id does not use it.
  String toString() =>
      '${field.canonicalString} ${operator.canonicalName} ${canonifyValue(value)}';

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
