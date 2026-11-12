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
/// NOTE: the Java-like API of this port expresses the filter with static
/// factories and `Query.where(Filter)`. A FlutterFire-style `where(field,
/// isEqualTo: ...)` extension with named parameters can be layered on top of
/// these (it would only need to build the same filters) and is intentionally
/// left for a later change.
///
/// **Subclassing Note**: Firestore classes are not meant to be subclassed.
class Filter {
  const Filter._();

  /// Creates a new filter for checking that the given field is equal to the
  /// given value.
  static Filter equalTo(String field, Object? value) =>
      equalToField(FieldPath.fromDotSeparatedPath(field), value);

  /// Creates a new filter for checking that the given field path is equal to
  /// the given value.
  static Filter equalToField(FieldPath fieldPath, Object? value) =>
      UnaryFilter(fieldPath, core.FilterOperator.equal, value);

  /// Creates a new filter for checking that the given field is not equal to
  /// the given value.
  static Filter notEqualTo(String field, Object? value) =>
      notEqualToField(FieldPath.fromDotSeparatedPath(field), value);

  /// Creates a new filter for checking that the given field path is not equal
  /// to the given value.
  static Filter notEqualToField(FieldPath fieldPath, Object? value) =>
      UnaryFilter(fieldPath, core.FilterOperator.notEqual, value);

  /// Creates a new filter for checking that the given field is greater than
  /// the given value.
  static Filter greaterThan(String field, Object? value) =>
      greaterThanField(FieldPath.fromDotSeparatedPath(field), value);

  /// Creates a new filter for checking that the given field path is greater
  /// than the given value.
  static Filter greaterThanField(FieldPath fieldPath, Object? value) =>
      UnaryFilter(fieldPath, core.FilterOperator.graterThan, value);

  /// Creates a new filter for checking that the given field is greater than or
  /// equal to the given value.
  static Filter greaterThanOrEqualTo(String field, Object? value) =>
      greaterThanOrEqualToField(FieldPath.fromDotSeparatedPath(field), value);

  /// Creates a new filter for checking that the given field path is greater
  /// than or equal to the given value.
  static Filter greaterThanOrEqualToField(FieldPath fieldPath, Object? value) =>
      UnaryFilter(fieldPath, core.FilterOperator.graterThanOrEqual, value);

  /// Creates a new filter for checking that the given field is less than the
  /// given value.
  static Filter lessThan(String field, Object? value) =>
      lessThanField(FieldPath.fromDotSeparatedPath(field), value);

  /// Creates a new filter for checking that the given field path is less than
  /// the given value.
  static Filter lessThanField(FieldPath fieldPath, Object? value) =>
      UnaryFilter(fieldPath, core.FilterOperator.lessThan, value);

  /// Creates a new filter for checking that the given field is less than or
  /// equal to the given value.
  static Filter lessThanOrEqualTo(String field, Object? value) =>
      lessThanOrEqualToField(FieldPath.fromDotSeparatedPath(field), value);

  /// Creates a new filter for checking that the given field path is less than
  /// or equal to the given value.
  static Filter lessThanOrEqualToField(FieldPath fieldPath, Object? value) =>
      UnaryFilter(fieldPath, core.FilterOperator.lessThanOrEqual, value);

  /// Creates a new filter for checking that the given array field contains the
  /// given value.
  static Filter arrayContains(String field, Object? value) =>
      arrayContainsField(FieldPath.fromDotSeparatedPath(field), value);

  /// Creates a new filter for checking that the given array field path
  /// contains the given value.
  static Filter arrayContainsField(FieldPath fieldPath, Object? value) =>
      UnaryFilter(fieldPath, core.FilterOperator.arrayContains, value);

  /// Creates a new filter for checking that the given array field contains any
  /// of the given values.
  static Filter arrayContainsAny(String field, List<Object?> values) =>
      arrayContainsAnyField(FieldPath.fromDotSeparatedPath(field), values);

  /// Creates a new filter for checking that the given array field path
  /// contains any of the given values.
  static Filter arrayContainsAnyField(
          FieldPath fieldPath, List<Object?> values) =>
      UnaryFilter(fieldPath, core.FilterOperator.arrayContainsAny, values);

  /// Creates a new filter for checking that the given field equals any of the
  /// given values.
  static Filter inArray(String field, List<Object?> values) =>
      inArrayField(FieldPath.fromDotSeparatedPath(field), values);

  /// Creates a new filter for checking that the given field path equals any of
  /// the given values.
  static Filter inArrayField(FieldPath fieldPath, List<Object?> values) =>
      UnaryFilter(fieldPath, core.FilterOperator.IN, values);

  /// Creates a new filter for checking that the given field does not equal any
  /// of the given values.
  static Filter notInArray(String field, List<Object?> values) =>
      notInArrayField(FieldPath.fromDotSeparatedPath(field), values);

  /// Creates a new filter for checking that the given field path does not
  /// equal any of the given values.
  static Filter notInArrayField(FieldPath fieldPath, List<Object?> values) =>
      UnaryFilter(fieldPath, core.FilterOperator.NOT_IN, values);

  /// Creates a new filter that is a disjunction of the given filters. A
  /// disjunction filter includes a document if it satisfies *any* of the given
  /// filters.
  static Filter or(List<Filter> filters) =>
      CompositeFilter._(filters, core.CompositeFilterOperator.or);

  /// Creates a new filter that is a conjunction of the given filters. A
  /// conjunction filter includes a document if it satisfies *all* of the given
  /// filters.
  static Filter and(List<Filter> filters) =>
      CompositeFilter._(filters, core.CompositeFilterOperator.and);
}

/// A filter on a single field, as created by the [Filter] factories. The value
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
  int get hashCode => Object.hash(operator, const ListEquality<Filter>().hash(filters));

  @override
  String toString() => 'Filter.$operator($filters)';
}
