// File created by
// Lung Razvan <long1eu>
// on 16/03/2020

part of filter;

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
  static const FilterOperator arrayContainsAny =
      FilterOperator._('array_contains_any');

  // ignore: constant_identifier_names
  static const FilterOperator IN = FilterOperator._('in');

  static const List<FilterOperator> arrayOperators = <FilterOperator>[
    arrayContains,
    arrayContainsAny
  ];

  static const List<FilterOperator> disjunctiveOperators = <FilterOperator>[
    arrayContainsAny,
    IN
  ];

  static const List<FilterOperator> inequalityOperators = <FilterOperator>[
    lessThan,
    lessThanOrEqual,
    graterThan,
    graterThanOrEqual
  ];

  @override
  String toString() => _value;
}
