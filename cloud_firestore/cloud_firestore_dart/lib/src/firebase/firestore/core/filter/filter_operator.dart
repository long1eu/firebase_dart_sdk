// File created by
// Lung Razvan <long1eu>
// on 16/03/2020

part of 'filter.dart';

class FilterOperator {
  // The names of the operators in the JS SDK.
  const FilterOperator._(this._value);

  final String _value;

  static const FilterOperator lessThan = FilterOperator._('<');
  static const FilterOperator lessThanOrEqual = FilterOperator._('<=');
  static const FilterOperator equal = FilterOperator._('==');
  static const FilterOperator notEqual = FilterOperator._('!=');
  static const FilterOperator graterThan = FilterOperator._('>');
  static const FilterOperator graterThanOrEqual = FilterOperator._('>=');
  static const FilterOperator arrayContains = FilterOperator._(
    'array-contains',
  );
  static const FilterOperator arrayContainsAny = FilterOperator._(
    'array-contains-any',
  );

  // ignore: constant_identifier_names
  static const FilterOperator IN = FilterOperator._('in');

  // ignore: constant_identifier_names
  static const FilterOperator NOT_IN = FilterOperator._('not-in');

  static const List<FilterOperator> arrayOperators = <FilterOperator>[
    arrayContains,
    arrayContainsAny,
  ];

  static const List<FilterOperator> disjunctiveOperators = <FilterOperator>[
    arrayContainsAny,
    IN,
  ];

  static const List<FilterOperator> inequalityOperators = <FilterOperator>[
    lessThan,
    lessThanOrEqual,
    graterThan,
    graterThanOrEqual,
    notEqual,
    NOT_IN,
  ];

  /// The name of this operator in the canonical id of a query, which is stored in the cache: the name in the JS SDK.
  String get canonicalName => _value;

  /// The name of this operator in the JS SDK (`array-contains`, `not-in`), for messages.
  @override
  String toString() => _value;
}
