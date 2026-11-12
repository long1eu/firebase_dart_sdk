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

import 'package:cloud_firestore_vm/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';
import 'package:meta/meta.dart';

/// Provides utility functions that help with boolean logic transformations
/// needed for handling complex filters used in queries.
///
/// NOTE: the Dart port has no client-side index engine, so the local store
/// never plans a query as a union of disjunction terms; the backend evaluates
/// OR queries natively and the client matches documents with
/// [Filter.matches]. These transformations are provided for parity with the
/// other SDKs (and for a future index engine).
class LogicUtils {
  const LogicUtils._();

  /// Asserts that the given filter is a [FieldFilter] or [CompositeFilter].
  static void _assertFieldFilterOrCompositeFilter(Filter filter) {
    hardAssert(filter is FieldFilter || filter is CompositeFilter,
        'Only field filters and composite filters are accepted.');
  }

  /// Returns true if the given filter is a single field filter. For example,
  /// (a == 10).
  static bool _isSingleFieldFilter(Filter filter) => filter is FieldFilter;

  /// Returns true if the given filter is the conjunction of one or more field
  /// filters. For example, (a == 10 && b == 20).
  static bool _isFlatConjunction(Filter filter) =>
      filter is CompositeFilter && filter.isFlatConjunction;

  /// Returns true if the given filter is the disjunction of one or more "flat
  /// conjunctions" and field filters. For example, (a == 10) || (b==20 &&
  /// c==30).
  static bool _isDisjunctionOfFieldFiltersAndFlatConjunctions(Filter filter) {
    if (filter is CompositeFilter && filter.isDisjunction) {
      for (Filter subfilter in filter.filters) {
        if (!_isSingleFieldFilter(subfilter) && !_isFlatConjunction(subfilter)) {
          return false;
        }
      }
      return true;
    }
    return false;
  }

  /// Returns whether or not the given filter is in disjunctive normal form
  /// (DNF): a disjunction of conjunctions (an OR of ANDs).
  ///
  /// For more info, visit: https://en.wikipedia.org/wiki/Disjunctive_normal_form
  static bool isDisjunctiveNormalForm(Filter filter) {
    // A single field filter is always in DNF form.
    // An AND of several field filters ("Flat AND") is in DNF form. Example:
    // (A && B).
    // An OR of field filters and "Flat AND"s is in DNF form. Example:
    // A || (B && C) || (D && F).
    // Everything else is not in DNF form.
    return _isSingleFieldFilter(filter) ||
        _isFlatConjunction(filter) ||
        _isDisjunctionOfFieldFiltersAndFlatConjunctions(filter);
  }

  /// Applies the associativity property to the given filter and returns the
  /// resulting filter.
  ///
  ///  * A | (B | C) == (A | B) | C == (A | B | C)
  ///  * A & (B & C) == (A & B) & C == (A & B & C)
  @visibleForTesting
  static Filter applyAssociation(Filter filter) {
    _assertFieldFilterOrCompositeFilter(filter);

    if (_isSingleFieldFilter(filter)) {
      return filter;
    }

    final CompositeFilter compositeFilter = filter as CompositeFilter;

    // Example: (A | (((B)) | (C | D) | (E & F & (G | H))) -->
    // (A | B | C | D | (E & F & (G | H)))
    final List<Filter> filters = compositeFilter.filters;

    // If the composite filter only contains 1 filter, apply associativity to
    // it.
    if (filters.length == 1) {
      return applyAssociation(filters[0]);
    }

    // Associativity applied to a flat composite filter results in itself.
    if (compositeFilter.isFlat) {
      return compositeFilter;
    }

    // First apply associativity to all subfilters. This will in turn
    // recursively apply associativity to all nested composite filters and
    // field filters.
    final List<Filter> updatedFilters =
        filters.map(applyAssociation).toList(growable: false);

    // For composite subfilters that perform the same kind of logical operation
    // as `compositeFilter` take out their filters and add them to
    // `compositeFilter`. For example:
    // compositeFilter = (A | (B | C | D))
    // compositeSubfilter = (B | C | D)
    // Result: (A | B | C | D)
    final List<Filter> newSubfilters = <Filter>[];
    for (Filter subfilter in updatedFilters) {
      if (subfilter is FieldFilter) {
        newSubfilters.add(subfilter);
      } else if (subfilter is CompositeFilter) {
        if (subfilter.operator == compositeFilter.operator) {
          // compositeFilter: (A | (B | C)), compositeSubfilter: (B | C)
          // Result: (A | B | C)
          newSubfilters.addAll(subfilter.filters);
        } else {
          // compositeFilter: (A | (B & C)), compositeSubfilter: (B & C)
          // Result: (A | (B & C))
          newSubfilters.add(subfilter);
        }
      }
    }
    if (newSubfilters.length == 1) {
      return newSubfilters[0];
    }
    return CompositeFilter(newSubfilters, compositeFilter.operator);
  }

  /// Performs conjunction distribution for the given filters.
  ///
  /// There are generally four types of distributions:
  ///
  ///  * Distribution of conjunction over disjunction: P & (Q | R) == (P & Q) | (P & R)
  ///  * Distribution of disjunction over conjunction: P | (Q & R) == (P | Q) & (P | R)
  ///  * Distribution of conjunction over conjunction: P & (Q & R) == (P & Q) & (P & R)
  ///  * Distribution of disjunction over disjunction: P | (Q | R) == (P | Q) | (P | R)
  ///
  /// This function ONLY performs the first type (distributing conjunction over
  /// disjunction) as it is meant to be used towards arriving at a DNF form.
  @visibleForTesting
  static Filter applyDistribution(Filter lhs, Filter rhs) {
    _assertFieldFilterOrCompositeFilter(lhs);
    _assertFieldFilterOrCompositeFilter(rhs);

    final Filter result;
    if (lhs is FieldFilter && rhs is FieldFilter) {
      result = _distributeFieldFieldFilter(lhs, rhs);
    } else if (lhs is FieldFilter && rhs is CompositeFilter) {
      result = _distributeFieldCompositeFilter(lhs, rhs);
    } else if (lhs is CompositeFilter && rhs is FieldFilter) {
      result = _distributeFieldCompositeFilter(rhs, lhs);
    } else {
      result = _distributeCompositeComposite(
          lhs as CompositeFilter, rhs as CompositeFilter);
    }

    // Since `applyDistribution` is recursive, we must apply association at the
    // end of each distribution in order to ensure the result is as flat as
    // possible for the next round of distributions.
    return applyAssociation(result);
  }

  static Filter _distributeFieldFieldFilter(FieldFilter lhs, FieldFilter rhs) {
    // Conjunction distribution for two field filters is the conjunction of
    // them.
    return CompositeFilter(<Filter>[lhs, rhs], CompositeFilterOperator.and);
  }

  static Filter _distributeFieldCompositeFilter(
      FieldFilter fieldFilter, CompositeFilter compositeFilter) {
    // There are two cases:
    // A & (B & C) --> (A & B & C)
    // A & (B | C) --> (A & B) | (A & C)
    if (compositeFilter.isConjunction) {
      // Case 1
      return compositeFilter.withAddedFilters(<Filter>[fieldFilter]);
    } else {
      // Case 2
      final List<Filter> newFilters = <Filter>[
        for (Filter subfilter in compositeFilter.filters)
          applyDistribution(fieldFilter, subfilter),
      ];
      return CompositeFilter(newFilters, CompositeFilterOperator.or);
    }
  }

  static Filter _distributeCompositeComposite(
      CompositeFilter lhs, CompositeFilter rhs) {
    hardAssert(lhs.filters.isNotEmpty && rhs.filters.isNotEmpty,
        'Found an empty composite filter');

    // There are four cases:
    // (A & B) & (C & D) --> (A & B & C & D)
    // (A & B) & (C | D) --> (A & B & C) | (A & B & D)
    // (A | B) & (C & D) --> (C & D & A) | (C & D & B)
    // (A | B) & (C | D) --> (A & C) | (A & D) | (B & C) | (B & D)

    // Case 1 is a merge.
    if (lhs.isConjunction && rhs.isConjunction) {
      return lhs.withAddedFilters(rhs.filters);
    }

    // Case 2,3,4 all have at least one side (lhs or rhs) that is a
    // disjunction. In all three cases we should take each element of the
    // disjunction and distribute it over the other side, and return the
    // disjunction of the distribution results.
    final CompositeFilter disjunctionSide = lhs.isDisjunction ? lhs : rhs;
    final CompositeFilter otherSide = lhs.isDisjunction ? rhs : lhs;
    final List<Filter> results = <Filter>[
      for (Filter subfilter in disjunctionSide.filters)
        applyDistribution(subfilter, otherSide),
    ];
    return CompositeFilter(results, CompositeFilterOperator.or);
  }

  /// Computes the disjunctive normal form of [filter].
  @visibleForTesting
  static Filter computeDistributedNormalForm(Filter filter) {
    _assertFieldFilterOrCompositeFilter(filter);

    if (filter is FieldFilter) {
      return filter;
    }

    final CompositeFilter compositeFilter = filter as CompositeFilter;

    if (compositeFilter.filters.length == 1) {
      return computeDistributedNormalForm(compositeFilter.filters[0]);
    }

    // Compute the DNF for each of the subfilters first.
    final List<Filter> result = compositeFilter.filters
        .map(computeDistributedNormalForm)
        .toList(growable: false);

    Filter newFilter = CompositeFilter(result, compositeFilter.operator);
    newFilter = applyAssociation(newFilter);

    if (isDisjunctiveNormalForm(newFilter)) {
      return newFilter;
    }

    hardAssert(newFilter is CompositeFilter,
        'field filters are already in DNF form.');
    final CompositeFilter newCompositeFilter = newFilter as CompositeFilter;
    hardAssert(newCompositeFilter.isConjunction,
        'Disjunction of filters all of which are already in DNF form is itself in DNF form.');
    hardAssert(newCompositeFilter.filters.length > 1,
        'Single-filter composite filters are already in DNF form.');

    Filter runningResult = newCompositeFilter.filters[0];
    for (int i = 1; i < newCompositeFilter.filters.length; ++i) {
      runningResult =
          applyDistribution(runningResult, newCompositeFilter.filters[i]);
    }
    return runningResult;
  }

  /// The `in` filter is only a syntactic sugar over a disjunction of
  /// equalities. For instance: `a in [1,2,3]` is in fact `a==1 || a==2 ||
  /// a==3`. This method expands any `in` filter in the given input into a
  /// disjunction of equality filters and returns the expanded filter.
  @visibleForTesting
  static Filter computeInExpansion(Filter filter) {
    _assertFieldFilterOrCompositeFilter(filter);

    if (filter is FieldFilter) {
      if (filter is InFilter) {
        // We have reached a field filter with `in` operator.
        final List<FieldValue> values = (filter.value as ArrayValue).internalValue;
        return CompositeFilter(
          <Filter>[
            for (FieldValue value in values)
              FieldFilter(filter.field, FilterOperator.equal, value),
          ],
          CompositeFilterOperator.or,
        );
      } else {
        // We have reached other kinds of field filters.
        return filter;
      }
    }

    // We have a composite filter.
    final CompositeFilter compositeFilter = filter as CompositeFilter;
    return CompositeFilter(
      compositeFilter.filters.map(computeInExpansion).toList(growable: false),
      compositeFilter.operator,
    );
  }

  /// Given a composite filter, returns the list of terms in its disjunctive
  /// normal form.
  ///
  /// Each element in the return value is one term of the resulting DNF. For
  /// instance: for the input (A || B) && C, the DNF form is (A && C) || (B &&
  /// C), and the return value is a list with two elements: a composite filter
  /// that performs (A && C), and a composite filter that performs (B && C).
  static List<Filter> getDnfTerms(CompositeFilter filter) {
    if (filter.filters.isEmpty) {
      return const <Filter>[];
    }

    // The `in` operator is a syntactic sugar over a disjunction of equalities.
    // We should first replace such filters with equality filters before
    // running the DNF transform.
    final Filter result =
        computeDistributedNormalForm(computeInExpansion(filter));

    hardAssert(isDisjunctiveNormalForm(result),
        'computeDistributedNormalForm did not result in disjunctive normal form');

    if (_isSingleFieldFilter(result) || _isFlatConjunction(result)) {
      return <Filter>[result];
    }

    return result.filters;
  }
}
