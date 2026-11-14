// Copyright 2019 Google LLC
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

import 'package:cloud_firestore_dart/src/firebase/firestore/core/bound.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/order_by.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/value_bounds.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:collection/collection.dart';

/// A Target represents the WatchTarget representation of a Query, which is used
/// by the LocalStore and the RemoteStore to keep track of and to execute
/// backend queries. While multiple Queries can map to the same Target, each
/// Target maps to a single WatchTarget in RemoteStore and a single QueryData
/// entry in persistence.
///
/// NOTE: you should always construct a Target from `Query.toTarget` instead of
/// using this constructor, because Query provides an implicit `orderBy`
/// property.
class Target {
  Target(
    this.path, {
    this.collectionGroup,
    this.filters = const <Filter>[],
    this.orderBy = const <OrderBy>[],
    this.limit = noLimit,
    this.startAt,
    this.endAt,
  });

  static const int noLimit = -1;

  /// The base path of the query.
  final ResourcePath path;

  /// An optional collection group within which to query.
  final String? collectionGroup;

  /// The filters on the documents returned by the query.
  final List<Filter> filters;

  /// The full list of orderings (including the implicit key ordering).
  final List<OrderBy> orderBy;

  final int limit;

  /// An optional bound to start the query at.
  final Bound? startAt;

  /// An optional bound to end the query at.
  final Bound? endAt;

  String? _memoizedCanonicalId;

  /// Returns true if this Target is for a specific document.
  bool get isDocumentQuery =>
      DocumentKey.isDocumentKey(path) &&
      collectionGroup == null &&
      filters.isEmpty;

  bool get hasLimit => limit != noLimit;

  /// The maximum number of results to return. If there is no limit on the
  /// query, then this will cause an assertion failure.
  int getLimit() {
    hardAssert(hasLimit, 'Called getLimit when no limit was set');
    return limit;
  }

  /// Returns the field filters that target the given field path.
  ///
  /// Only the top level filters are looked at: the index manager serves a
  /// target with composite filters through its sub targets in disjunctive
  /// normal form, whose filters are all field filters.
  List<FieldFilter> _getFieldFiltersForPath(FieldPath path) {
    return <FieldFilter>[
      for (final Filter filter in filters)
        if (filter is FieldFilter && filter.field == path) filter,
    ];
  }

  /// Returns the values that are used in ARRAY_CONTAINS or ARRAY_CONTAINS_ANY
  /// filters. Returns null if there are no such filters.
  List<FieldValue>? getArrayValues(FieldIndex fieldIndex) {
    final IndexSegment? segment = fieldIndex.arraySegment;
    if (segment == null) {
      return null;
    }

    for (final FieldFilter fieldFilter in _getFieldFiltersForPath(
      segment.fieldPath,
    )) {
      if (fieldFilter.operator == FilterOperator.arrayContainsAny) {
        return (fieldFilter.value as ArrayValue).internalValue;
      } else if (fieldFilter.operator == FilterOperator.arrayContains) {
        return <FieldValue>[fieldFilter.value];
      }
    }

    return null;
  }

  /// Returns the list of values that are used in != or NOT_IN filters.
  /// Returns null if there are no such filters.
  List<FieldValue>? getNotInValues(FieldIndex fieldIndex) {
    // Insertion ordered, one value per field.
    final Map<FieldPath, FieldValue> values = <FieldPath, FieldValue>{};

    for (final IndexSegment segment in fieldIndex.directionalSegments) {
      for (final FieldFilter fieldFilter in _getFieldFiltersForPath(
        segment.fieldPath,
      )) {
        final FilterOperator operator = fieldFilter.operator;
        if (operator == FilterOperator.equal || operator == FilterOperator.IN) {
          // Encode equality prefix, which is encoded in the index value before
          // the inequality (for example `a == 'a' && b != 'b'` is encoded to
          // `value != 'ab'`).
          values[segment.fieldPath] = fieldFilter.value;
        } else if (operator == FilterOperator.NOT_IN ||
            operator == FilterOperator.notEqual) {
          values[segment.fieldPath] = fieldFilter.value;
          // NotIn/NotEqual is always a suffix
          return values.values.toList();
        }
      }
    }

    return null;
  }

  /// Returns a lower bound of field values that can be used as a starting
  /// point to scan the index defined by [fieldIndex]. A segment without lower
  /// bound has [ValueBounds.internalMinValue].
  Bound getLowerBound(FieldIndex fieldIndex) {
    final List<FieldValue> values = <FieldValue>[];
    bool inclusive = true;

    // For each segment, retrieve a lower bound if there is a suitable filter or
    // startAt.
    for (final IndexSegment segment in fieldIndex.directionalSegments) {
      final (
        FieldValue value,
        bool segmentInclusive,
      ) = segment.kind == SegmentKind.ascending
          ? _getAscendingBound(segment, startAt)
          : _getDescendingBound(segment, startAt);

      values.add(value);
      inclusive &= segmentInclusive;
    }

    return Bound(position: values, inclusive: inclusive);
  }

  /// Returns an upper bound of field values that can be used as an ending
  /// point when scanning the index defined by [fieldIndex]. A segment without
  /// upper bound has [ValueBounds.internalMaxValue].
  Bound getUpperBound(FieldIndex fieldIndex) {
    final List<FieldValue> values = <FieldValue>[];
    bool inclusive = true;

    // For each segment, retrieve an upper bound if there is a suitable filter
    // or endAt.
    for (final IndexSegment segment in fieldIndex.directionalSegments) {
      final (
        FieldValue value,
        bool segmentInclusive,
      ) = segment.kind == SegmentKind.ascending
          ? _getDescendingBound(segment, endAt)
          : _getAscendingBound(segment, endAt);

      values.add(value);
      inclusive &= segmentInclusive;
    }

    return Bound(position: values, inclusive: inclusive);
  }

  /// Returns the value for an ascending bound of [segment] and whether the
  /// bound is inclusive. [bound] is a bound to restrict the index range.
  (FieldValue, bool) _getAscendingBound(IndexSegment segment, Bound? bound) {
    FieldValue segmentValue = ValueBounds.internalMinValue;
    bool segmentInclusive = true;

    // Process all filters to find a value for the current field segment
    for (final FieldFilter fieldFilter in _getFieldFiltersForPath(
      segment.fieldPath,
    )) {
      FieldValue filterValue = ValueBounds.internalMinValue;
      bool filterInclusive = true;

      final FilterOperator operator = fieldFilter.operator;
      if (operator == FilterOperator.lessThan ||
          operator == FilterOperator.lessThanOrEqual) {
        filterValue = ValueBounds.getLowerBound(fieldFilter.value);
      } else if (operator == FilterOperator.equal ||
          operator == FilterOperator.IN ||
          operator == FilterOperator.graterThanOrEqual) {
        filterValue = fieldFilter.value;
      } else if (operator == FilterOperator.graterThan) {
        filterValue = fieldFilter.value;
        filterInclusive = false;
      } else if (operator == FilterOperator.notEqual ||
          operator == FilterOperator.NOT_IN) {
        filterValue = MinKeyValue.instance();
      }
      // Remaining filters cannot be used as bound.

      if (ValueBounds.lowerBoundCompare(
            segmentValue,
            segmentInclusive,
            filterValue,
            filterInclusive,
          ) <
          0) {
        segmentValue = filterValue;
        segmentInclusive = filterInclusive;
      }
    }

    // If there is an additional bound, compare the values against the existing
    // range to see if we can narrow the scope.
    if (bound != null) {
      for (int i = 0; i < orderBy.length; ++i) {
        if (orderBy[i].field == segment.fieldPath) {
          final FieldValue cursorValue = bound.position[i];
          if (ValueBounds.lowerBoundCompare(
                segmentValue,
                segmentInclusive,
                cursorValue,
                bound.inclusive,
              ) <
              0) {
            segmentValue = cursorValue;
            segmentInclusive = bound.inclusive;
          }
          break;
        }
      }
    }

    return (segmentValue, segmentInclusive);
  }

  /// Returns the value for a descending bound of [segment] and whether the
  /// bound is inclusive. [bound] is a bound to restrict the index range.
  (FieldValue, bool) _getDescendingBound(IndexSegment segment, Bound? bound) {
    FieldValue segmentValue = ValueBounds.internalMaxValue;
    bool segmentInclusive = true;

    // Process all filters to find a value for the current field segment
    for (final FieldFilter fieldFilter in _getFieldFiltersForPath(
      segment.fieldPath,
    )) {
      FieldValue filterValue = ValueBounds.internalMaxValue;
      bool filterInclusive = true;

      final FilterOperator operator = fieldFilter.operator;
      if (operator == FilterOperator.graterThanOrEqual ||
          operator == FilterOperator.graterThan) {
        filterValue = ValueBounds.getUpperBound(fieldFilter.value);
        filterInclusive = false;
      } else if (operator == FilterOperator.equal ||
          operator == FilterOperator.IN ||
          operator == FilterOperator.lessThanOrEqual) {
        filterValue = fieldFilter.value;
      } else if (operator == FilterOperator.lessThan) {
        filterValue = fieldFilter.value;
        filterInclusive = false;
      } else if (operator == FilterOperator.notEqual ||
          operator == FilterOperator.NOT_IN) {
        filterValue = MaxKeyValue.instance();
      }
      // Remaining filters cannot be used as bound.

      if (ValueBounds.upperBoundCompare(
            segmentValue,
            segmentInclusive,
            filterValue,
            filterInclusive,
          ) >
          0) {
        segmentValue = filterValue;
        segmentInclusive = filterInclusive;
      }
    }

    // If there is an additional bound, compare the values against the existing
    // range to see if we can narrow the scope.
    if (bound != null) {
      for (int i = 0; i < orderBy.length; ++i) {
        if (orderBy[i].field == segment.fieldPath) {
          final FieldValue cursorValue = bound.position[i];
          if (ValueBounds.upperBoundCompare(
                segmentValue,
                segmentInclusive,
                cursorValue,
                bound.inclusive,
              ) >
              0) {
            segmentValue = cursorValue;
            segmentInclusive = bound.inclusive;
          }
          break;
        }
      }
    }

    return (segmentValue, segmentInclusive);
  }

  /// Returns the order of the document key component.
  OrderByDirection get keyOrder => orderBy.last.direction;

  /// Returns the number of segments of a perfect index for this target.
  int get segmentCount {
    final Set<FieldPath> fields = <FieldPath>{};
    bool hasArraySegment = false;
    for (final Filter filter in filters) {
      for (final FieldFilter subFilter in filter.flattenedFilters) {
        // __name__ is not an explicit segment of any index, so we don't need to
        // count it.
        if (subFilter.field.isKeyField) {
          continue;
        }

        // ARRAY_CONTAINS or ARRAY_CONTAINS_ANY filters must be counted
        // separately. For instance, it is possible to have an index for "a
        // ARRAY a ASC". Even though these are on the same field, they should be
        // counted as two separate segments in an index.
        if (subFilter.operator == FilterOperator.arrayContains ||
            subFilter.operator == FilterOperator.arrayContainsAny) {
          hasArraySegment = true;
        } else {
          fields.add(subFilter.field);
        }
      }
    }
    for (final OrderBy order in orderBy) {
      // __name__ is not an explicit segment of any index, so we don't need to
      // count it.
      if (!order.field.isKeyField) {
        fields.add(order.field);
      }
    }
    return fields.length + (hasArraySegment ? 1 : 0);
  }

  /// Returns a canonical string representing this target.
  String get canonicalId {
    final String? memoized = _memoizedCanonicalId;
    if (memoized != null) {
      return memoized;
    }

    final StringBuffer builder = StringBuffer(path.canonicalString);

    if (collectionGroup != null) {
      builder //
        ..write('|cg:')
        ..write(collectionGroup);
    }

    // Add filters.
    builder
      ..write('|f:')
      ..write(filters.map((Filter filter) => filter.canonicalId).join(','))
      // Add order by.
      ..write('|ob:')
      ..write(
        orderBy
            .map(
              (OrderBy orderBy) =>
                  orderBy.field.canonicalString +
                  (orderBy.direction == OrderByDirection.ascending
                      ? 'asc'
                      : 'desc'),
            )
            .join(','),
      );

    // Add limit.
    if (hasLimit) {
      builder //
        ..write('|l:')
        ..write(limit);
    }

    final Bound? startAt = this.startAt;
    if (startAt != null) {
      builder //
        ..write('|lb:')
        ..write(startAt.inclusive ? 'b:' : 'a:')
        ..write(startAt.positionString());
    }

    final Bound? endAt = this.endAt;
    if (endAt != null) {
      builder //
        ..write('|ub:')
        ..write(endAt.inclusive ? 'a:' : 'b:')
        ..write(endAt.positionString());
    }

    return _memoizedCanonicalId = builder.toString();
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Target &&
            runtimeType == other.runtimeType &&
            limit == other.limit &&
            collectionGroup == other.collectionGroup &&
            path == other.path &&
            startAt == other.startAt &&
            endAt == other.endAt &&
            const ListEquality<OrderBy>().equals(orderBy, other.orderBy) &&
            const ListEquality<Filter>().equals(filters, other.filters);
  }

  @override
  int get hashCode =>
      const ListEquality<OrderBy>().hash(orderBy) ^
      collectionGroup.hashCode ^
      const ListEquality<Filter>().hash(filters) ^
      path.hashCode ^
      limit.hashCode ^
      startAt.hashCode ^
      endAt.hashCode;

  @override
  String toString() {
    final StringBuffer builder =
        StringBuffer() //
          ..write('Query(')
          ..write(path.canonicalString);
    if (collectionGroup != null) {
      builder //
        ..write(' collectionGroup=')
        ..write(collectionGroup);
    }
    if (filters.isNotEmpty) {
      builder.write(' where ');
      for (int i = 0; i < filters.length; i++) {
        if (i > 0) {
          builder.write(' and ');
        }
        builder.write(filters[i]);
      }
    }

    if (orderBy.isNotEmpty) {
      builder.write(' order by ');
      for (int i = 0; i < orderBy.length; i++) {
        if (i > 0) {
          builder.write(', ');
        }
        builder.write(orderBy[i]);
      }
    }

    builder.write(')');
    return builder.toString();
  }
}
