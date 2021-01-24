// File created by
// Lung Razvan <long1eu>
// on 16/03/2020

part of filter;

// ignore_for_file: constant_identifier_names
class FilterOperator {
  const FilterOperator._(this._value);

  final String _value;

  static const FilterOperator lessThan = FilterOperator._('<');
  static const FilterOperator lessThanOrEqual = FilterOperator._('<=');
  static const FilterOperator equal = FilterOperator._('==');
  static const FilterOperator notEqual = FilterOperator._('!=');
  static const FilterOperator graterThan = FilterOperator._('>');
  static const FilterOperator graterThanOrEqual = FilterOperator._('>=');
  static const FilterOperator arrayContains = FilterOperator._('array_contains');
  static const FilterOperator arrayContainsAny = FilterOperator._('array_contains_any');
  static const FilterOperator IN = FilterOperator._('in');
  static const FilterOperator notIn = FilterOperator._('not_in');

  static const List<FilterOperator> arrayOperators = <FilterOperator>[arrayContains, arrayContainsAny];

  static const List<FilterOperator> disjunctiveOperators = <FilterOperator>[arrayContainsAny, IN];

  static const List<FilterOperator> inequalityOperators = <FilterOperator>[
    lessThan,
    lessThanOrEqual,
    graterThan,
    graterThanOrEqual,
    notEqual,
    notIn
  ];

  @override
  String toString() => _value;
}
