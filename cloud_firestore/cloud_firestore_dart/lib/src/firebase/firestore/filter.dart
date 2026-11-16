// Copyright 2023 Google LLC
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

import 'package:cloud_firestore_dart/src/firebase/firestore/core/filter/filter.dart'
    as core;
import 'package:cloud_firestore_dart/src/firebase/firestore/field_path.dart';
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// A [Filter] represents a restriction on one or more field values and can be
/// used to refine the results of a `Query` (see `Query.where`).
///
/// Filters can be combined with [Filter.or] and [Filter.and] to build
/// disjunctions (OR queries) and conjunctions.
///
/// [Filter.new] takes the same arguments as `Query.where` (`Filter('age', isGreaterThan: 18)`).
/// A `String` field is split on dots (`'address.city'` is a nested field); a [FieldPath] names a
/// field whose name contains a dot. The value is checked when the filter is added to a query,
/// which throws an [ArgumentError] for a value or a combination of filters that Firestore does
/// not accept (for example an empty list for `whereIn`, or two `whereNotIn` filters).
///
/// ```dart
/// // Cities in California with more than a million people, or any capital.
/// final QuerySnapshot<Map<String, Object?>> snapshot = await firestore
///     .collection('cities')
///     .where(
///       Filter.or([
///         Filter.and([
///           Filter('state', isEqualTo: 'CA'),
///           Filter('population', isGreaterThan: 1000000),
///         ]),
///         Filter('capital', isEqualTo: true),
///       ]),
///     )
///     .get();
/// ```
///
/// **Subclassing Note**: Firestore classes are not meant to be subclassed.
class Filter {
  const Filter._();

  /// A filter on [field], a [String] (dots separate nested fields) or a [FieldPath], with exactly one
  /// of the named arguments: the same arguments as `Query.where`.
  ///
  /// [isNull] `true` keeps the documents whose field is null, `false` those whose field is not null;
  /// a null value of another argument counts as not given, as in FlutterFire.
  ///
  /// Throws an [ArgumentError] if [field] is not a `String` or a `FieldPath`, if its path is invalid,
  /// or if not exactly one of the named arguments is given.
  factory Filter(
    Object field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    Iterable<Object?>? arrayContainsAny,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
    bool? isNull,
  }) {
    final FieldPath fieldPath;
    if (field is FieldPath) {
      fieldPath = field;
    } else if (field is String) {
      fieldPath = FieldPathInternal.fromArgument('Filter', field);
    } else {
      throw ArgumentError.value(
        field,
        'field',
        'Filter() expects a String field or a FieldPath',
      );
    }
    final List<UnaryFilter> filters = unaryFilters(
      fieldPath,
      isEqualTo: isEqualTo,
      isNotEqualTo: isNotEqualTo,
      isLessThan: isLessThan,
      isLessThanOrEqualTo: isLessThanOrEqualTo,
      isGreaterThan: isGreaterThan,
      isGreaterThanOrEqualTo: isGreaterThanOrEqualTo,
      arrayContains: arrayContains,
      arrayContainsAny: arrayContainsAny,
      whereIn: whereIn,
      whereNotIn: whereNotIn,
      isNull: isNull,
    );
    if (filters.length != 1) {
      throw ArgumentError(
        "Invalid filter. Filter('$fieldPath') needs exactly one non-null "
        'named argument. Use isNull to compare with null.',
      );
    }
    return filters.single;
  }

  /// Creates a new filter that is a disjunction of the given filters. A
  /// disjunction filter includes a document if it satisfies *any* of the given
  /// filters.
  ///
  /// An empty list adds no filter to the query. The backend limits the number of disjunctions
  /// in a query and may need an index for it.
  static Filter or(List<Filter> filters) =>
      CompositeFilter._(filters, core.CompositeFilterOperator.or);

  /// Creates a new filter that is a conjunction of the given filters. A
  /// conjunction filter includes a document if it satisfies *all* of the given
  /// filters. An empty list adds no filter to the query.
  static Filter and(List<Filter> filters) =>
      CompositeFilter._(filters, core.CompositeFilterOperator.and);
}

/// The filters of the named arguments of `Query.where` and [Filter.new], in the order of the
/// arguments; empty when none is given.
@internal
List<UnaryFilter> unaryFilters(
  FieldPath fieldPath, {
  Object? isEqualTo,
  Object? isNotEqualTo,
  Object? isLessThan,
  Object? isLessThanOrEqualTo,
  Object? isGreaterThan,
  Object? isGreaterThanOrEqualTo,
  Object? arrayContains,
  Iterable<Object?>? arrayContainsAny,
  Iterable<Object?>? whereIn,
  Iterable<Object?>? whereNotIn,
  bool? isNull,
}) {
  UnaryFilter filter(core.FilterOperator op, Object? value) =>
      UnaryFilter(fieldPath, op, value);
  return <UnaryFilter>[
    if (isEqualTo != null) filter(core.FilterOperator.equal, isEqualTo),
    if (isNotEqualTo != null)
      filter(core.FilterOperator.notEqual, isNotEqualTo),
    if (isLessThan != null) filter(core.FilterOperator.lessThan, isLessThan),
    if (isLessThanOrEqualTo != null)
      filter(core.FilterOperator.lessThanOrEqual, isLessThanOrEqualTo),
    if (isGreaterThan != null)
      filter(core.FilterOperator.graterThan, isGreaterThan),
    if (isGreaterThanOrEqualTo != null)
      filter(core.FilterOperator.graterThanOrEqual, isGreaterThanOrEqualTo),
    if (arrayContains != null)
      filter(core.FilterOperator.arrayContains, arrayContains),
    if (arrayContainsAny != null)
      filter(core.FilterOperator.arrayContainsAny, arrayContainsAny.toList()),
    if (whereIn != null) filter(core.FilterOperator.IN, whereIn.toList()),
    if (whereNotIn != null)
      filter(core.FilterOperator.NOT_IN, whereNotIn.toList()),
    if (isNull != null)
      filter(
        isNull ? core.FilterOperator.equal : core.FilterOperator.notEqual,
        null,
      ),
  ];
}

/// A filter on a single field, as created by [Filter.new]. The value
/// has not been parsed yet; this happens when the filter is added to a query.
@internal
class UnaryFilter extends Filter {
  const UnaryFilter(this.field, this.operator, this.value) : super._();

  final FieldPath field;
  final core.FilterOperator operator;
  final Object? value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnaryFilter &&
          operator == other.operator &&
          field == other.field &&
          const DeepCollectionEquality().equals(value, other.value);

  @override
  int get hashCode =>
      Object.hash(field, operator, const DeepCollectionEquality().hash(value));

  @override
  String toString() => 'Filter($field $operator $value)';
}

/// A conjunction or disjunction of other filters, as created by [Filter.and]
/// and [Filter.or].
@internal
class CompositeFilter extends Filter {
  CompositeFilter._(List<Filter> filters, this.operator)
    : filters = List<Filter>.unmodifiable(filters),
      super._();

  final List<Filter> filters;
  final core.CompositeFilterOperator operator;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CompositeFilter &&
          operator == other.operator &&
          const ListEquality<Filter>().equals(filters, other.filters);

  @override
  int get hashCode =>
      Object.hash(operator, const ListEquality<Filter>().hash(filters));

  @override
  String toString() => 'Filter.$operator($filters)';
}
