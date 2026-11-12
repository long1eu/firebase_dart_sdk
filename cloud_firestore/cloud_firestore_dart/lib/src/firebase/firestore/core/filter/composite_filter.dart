// Copyright 2022 Google LLC
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

part of filter;

/// The logical operation of a [CompositeFilter].
enum CompositeFilterOperator {
  and('and'),
  or('or');

  const CompositeFilterOperator(this._text);

  final String _text;

  @override
  String toString() => _text;
}

/// Represents a filter that is the conjunction or disjunction of other
/// filters.
class CompositeFilter extends Filter {
  CompositeFilter(List<Filter> filters, this.operator)
      : filters = List<Filter>.unmodifiable(filters),
        super._();

  /// A conjunction of [filters].
  CompositeFilter.and(List<Filter> filters)
      : this(filters, CompositeFilterOperator.and);

  /// A disjunction of [filters].
  CompositeFilter.or(List<Filter> filters)
      : this(filters, CompositeFilterOperator.or);

  @override
  final List<Filter> filters;

  final CompositeFilterOperator operator;

  // Memoized list of all field filters that can be found by traversing the
  // tree of filters contained in this composite filter.
  List<FieldFilter>? _memoizedFlattenedFilters;

  @override
  List<FieldFilter> get flattenedFilters {
    return _memoizedFlattenedFilters ??= List<FieldFilter>.unmodifiable(
      <FieldFilter>[
        for (Filter subfilter in filters) ...subfilter.flattenedFilters,
      ],
    );
  }

  bool get isConjunction => operator == CompositeFilterOperator.and;

  bool get isDisjunction => operator == CompositeFilterOperator.or;

  /// Returns true if this filter is a conjunction of field filters only.
  bool get isFlatConjunction => isFlat && isConjunction;

  /// Returns true if this filter does not contain any composite filters.
  bool get isFlat => !filters.any((Filter filter) => filter is CompositeFilter);

  /// Returns the terms of the implicit AND that a list of filters (as held by a
  /// query or a target) represents: a conjunction is replaced by its terms
  /// (recursively), any other filter stands for itself.
  ///
  /// A list of filters is implicitly a conjunction, and a conjunction has the
  /// same wire format and (when flat) canonical id as its terms. Keeping the
  /// top level of a filter list free of conjunctions therefore gives every
  /// query a single representation, which is what lets a target survive being
  /// encoded for the target cache and decoded again.
  static List<Filter> conjunctionTerms(Filter filter) {
    if (filter is CompositeFilter && filter.isConjunction) {
      return <Filter>[
        for (Filter subfilter in filter.filters) ...conjunctionTerms(subfilter),
      ];
    }
    return <Filter>[filter];
  }

  /// Returns a new composite filter that contains all filters from `this` plus
  /// all the given filters.
  CompositeFilter withAddedFilters(List<Filter> otherFilters) {
    return CompositeFilter(<Filter>[...filters, ...otherFilters], operator);
  }

  @override
  bool matches(Document doc) {
    if (isConjunction) {
      // For conjunctions, all filters must match.
      for (Filter filter in filters) {
        if (!filter.matches(doc)) {
          return false;
        }
      }
      return true;
    } else {
      // For disjunctions, at least one filter should match.
      for (Filter filter in filters) {
        if (filter.matches(doc)) {
          return true;
        }
      }
      return false;
    }
  }

  @override
  String get canonicalId {
    // Older SDK versions use an implicit AND operation between their filters.
    // To stay consistent with the old usages, a flat conjunction has the same
    // canonical ID as the plain concatenation of its filters, so that
    // `where(a).where(b)` and `where(Filter.and([a, b]))` agree.
    if (isFlatConjunction) {
      return filters.map((Filter filter) => filter.canonicalId).join();
    }

    return '$operator(${filters.map((Filter f) => f.canonicalId).join(',')})';
  }

  @override
  String toString() => canonicalId;

  @override
  bool operator ==(Object other) {
    // Note: This comparison requires the order of filters in the list to be
    // the same, and it does not remove duplicate subfilters.
    return identical(this, other) ||
        other is CompositeFilter &&
            operator == other.operator &&
            const ListEquality<Filter>().equals(filters, other.filters);
  }

  @override
  int get hashCode =>
      Object.hash(37, operator, const ListEquality<Filter>().hash(filters));
}
