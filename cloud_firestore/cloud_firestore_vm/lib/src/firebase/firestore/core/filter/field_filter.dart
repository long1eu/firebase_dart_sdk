// File created by
// Lung Razvan <long1eu>
// on 16/03/2020

part of filter;

/// Represents a filter to be applied to query.
class FieldFilter extends Filter {
  /// Note that if the relation operator is EQUAL and the value is null or NaN, this will return
  /// the appropriate NullFilter or NaNFilter class instead of a FieldFilter.
  factory FieldFilter(FieldPath path, FilterOperator operator, Value value) {
    if (path.isKeyField) {
      if (operator == FilterOperator.IN) {
        return KeyFieldInFilter(path, value);
      } else if (operator == FilterOperator.notIn) {
        return KeyFieldNotInFilter(path, value);
      } else {
        hardAssert(
          operator != FilterOperator.arrayContains && operator != FilterOperator.arrayContainsAny,
          "$operator queries don't make sense on document keys",
        );
        return KeyFieldFilter(path, operator, value);
      }
    } else if (operator == FilterOperator.arrayContains) {
      return ArrayContainsFilter(path, value);
    } else if (operator == FilterOperator.IN) {
      return InFilter(path, value);
    } else if (operator == FilterOperator.arrayContainsAny) {
      return ArrayContainsAnyFilter(path, value);
    } else if (operator == FilterOperator.notIn) {
      return NotInFilter(path, value);
    } else {
      return FieldFilter._(path, operator, value);
    }
  }

  /// Creates a new filter that compares fields and values. Only intended to be
  /// called from [Filter.create].
  const FieldFilter._(this.field, this.operator, this.value) : super._();

  final FilterOperator operator;
  final Value value;
  @override
  final FieldPath field;

  @override
  bool matches(Document doc) {
    final Value other = doc.getField(field);
    // Types do not have to match in NOT_EQUAL filters.
    if (operator == FilterOperator.notEqual) {
      return other != null && _matchesComparison(compare(other, value));
    }
    // Only compare types with matching backend order (such as double and int).
    return other != null && typeOrder(other) == typeOrder(value) && _matchesComparison(compare(other, value));
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

  bool get isInequality {
    return FilterOperator.inequalityOperators.contains(operator);
  }

  @override
  String get canonicalId {
    // TODO(long1eu): Technically, this won't be unique if two values have the
    //  same description, such as the int 3 and the string '3'. So we should add
    //  the types in here somehow, too.
    return '${field.canonicalString} $operator ${values.canonicalId(value)}';
  }

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
