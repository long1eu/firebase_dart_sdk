// Copyright 2026 Google LLC
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
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart'
    as core;
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/expression.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/pipeline.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/pipeline_source.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:meta/meta.dart';

BooleanExpression _and(List<BooleanExpression> conditions) {
  return conditions.length == 1
      ? conditions.first
      : conditions.first.and(conditions[1], conditions.sublist(2));
}

BooleanExpression _or(List<BooleanExpression> conditions) {
  return conditions.length == 1
      ? conditions.first
      : conditions.first.or(conditions[1], conditions.sublist(2));
}

List<Constant> _elements(FieldValue value) {
  return value is ArrayValue
      ? value.internalValue.map(Constant.fromModel).toList(growable: false)
      : const <Constant>[];
}

/// Converts a filter of a classic query to a pipeline condition.
///
/// A classic filter never matches a document that lacks the field, so most
/// conditions are combined with an `exists` check.
@internal
BooleanExpression filterToCondition(Filter filter) {
  if (filter is FieldFilter) {
    final Field field = Field(filter.field);
    final Constant value = Constant.fromModel(filter.value);
    final FilterOperator op = filter.operator;
    if (op == FilterOperator.lessThan) {
      return field.exists().and(field.lessThan(value));
    } else if (op == FilterOperator.lessThanOrEqual) {
      return field.exists().and(field.lessThanOrEqual(value));
    } else if (op == FilterOperator.graterThan) {
      return field.exists().and(field.greaterThan(value));
    } else if (op == FilterOperator.graterThanOrEqual) {
      return field.exists().and(field.greaterThanOrEqual(value));
    } else if (op == FilterOperator.equal) {
      return field.exists().and(field.equal(value));
    } else if (op == FilterOperator.notEqual) {
      return field.notEqual(value);
    } else if (op == FilterOperator.arrayContains) {
      return field.exists().and(field.arrayContains(value));
    } else if (op == FilterOperator.IN) {
      final List<Constant> values = _elements(filter.value);
      return field.exists().and(values.length == 1
          ? field.equal(values.first)
          : field.equalAny(values));
    } else if (op == FilterOperator.arrayContainsAny) {
      return field
          .exists()
          .and(field.arrayContainsAny(_elements(filter.value)));
    } else if (op == FilterOperator.NOT_IN) {
      final List<Constant> values = _elements(filter.value);
      return values.length == 1
          ? field.notEqual(values.first)
          : field.notEqualAny(values);
    }
    throw fail('Unexpected filter operator: $op');
  } else if (filter is CompositeFilter) {
    final List<BooleanExpression> conditions =
        filter.filters.map(filterToCondition).toList(growable: false);
    hardAssert(conditions.isNotEmpty, 'A composite filter must have filters.');
    switch (filter.operator) {
      case CompositeFilterOperator.and:
        return _and(conditions);
      case CompositeFilterOperator.or:
        return _or(conditions);
    }
  }
  throw fail('Failed to convert filter to a pipeline condition: $filter');
}

/// The condition "comes after [bound]" (or "comes before" when [after] is
/// false) in the order given by [orderings].
///
/// PORTING NOTE: the JS and Android SDKs always use `greater_than` for start
/// bounds and `less_than` for end bounds, which is wrong for descending
/// orderings; here the comparison follows the direction of each ordering.
BooleanExpression _cursorCondition(Bound bound, List<Ordering> orderings,
    {required bool after, required bool inclusive}) {
  BooleanExpression compare(int i) {
    final Expression field = orderings[i].expression;
    final Constant value = Constant.fromModel(bound.position[i]);
    final bool ascending =
        orderings[i].direction == OrderingDirection.ascending;
    return ascending == after
        ? field.greaterThan(value)
        : field.lessThan(value);
  }

  BooleanExpression same(int i) =>
      orderings[i].expression.equal(Constant.fromModel(bound.position[i]));

  final int size = bound.position.length;
  hardAssert(size > 0 && size <= orderings.length,
      'Bound positions must not exceed order fields.');
  BooleanExpression condition = compare(size - 1);
  if (inclusive) {
    condition = condition.or(same(size - 1));
  }
  for (int i = size - 2; i >= 0; i--) {
    condition = compare(i).or(same(i).and(condition));
  }
  return condition;
}

/// Converts a classic [query] to the equivalent pipeline.
@internal
Pipeline queryToPipeline(Firestore firestore, core.Query query) {
  final PipelineSource source = PipelineSource(firestore);
  Pipeline pipeline;
  if (query.isCollectionGroupQuery) {
    pipeline = source.collectionGroup(query.collectionGroup!);
  } else if (query.isDocumentQuery) {
    pipeline = source.documents(<Object>[query.path.canonicalString]);
  } else {
    pipeline = source.collection(query.path.canonicalString);
  }

  for (final Filter filter in query.filters) {
    pipeline = pipeline.where(filterToCondition(filter));
  }

  // Like a classic query, only return documents that have every field that
  // is ordered by (this includes the document key, which always exists).
  final List<OrderBy> orders = query.orderByConstraints;
  pipeline = pipeline.where(_and(orders
      .map((OrderBy order) => Field(order.field).exists())
      .toList(growable: false)));

  final List<Ordering> orderings = orders
      .map((OrderBy order) => order.direction == OrderByDirection.ascending
          ? Field(order.field).ascending()
          : Field(order.field).descending())
      .toList(growable: false);

  Pipeline applyCursors(Pipeline pipeline) {
    final Bound? startAt = query.getStartAt();
    if (startAt != null) {
      pipeline = pipeline.where(_cursorCondition(startAt, orderings,
          after: true, inclusive: startAt.before));
    }
    final Bound? endAt = query.getEndAt();
    if (endAt != null) {
      pipeline = pipeline.where(_cursorCondition(endAt, orderings,
          after: false, inclusive: !endAt.before));
    }
    return pipeline;
  }

  if (query.hasLimitToLast) {
    if (query.explicitSortOrder.isEmpty) {
      throw StateError(
          'limitToLast() queries require specifying at least one orderBy() clause');
    }
    final List<Ordering> reversed = orderings
        .map((Ordering o) => o.direction == OrderingDirection.ascending
            ? o.expression.descending()
            : o.expression.ascending())
        .toList(growable: false);
    pipeline = applyCursors(pipeline.sort(reversed))
        .limit(query.getLimit())
        .sort(orderings);
  } else {
    pipeline = applyCursors(pipeline.sort(orderings));
    if (query.hasLimit) {
      pipeline = pipeline.limit(query.getLimit());
    }
  }
  return pipeline;
}
