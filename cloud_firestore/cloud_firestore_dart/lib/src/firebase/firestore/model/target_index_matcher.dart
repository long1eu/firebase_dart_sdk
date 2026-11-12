import 'package:cloud_firestore_dart/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/order_by.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/target.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';

/// A light query planner for Firestore. Port of `TargetIndexMatcher` of the
/// Android SDK.
///
/// This class matches a [FieldIndex] against a Firestore Query [Target]. It
/// determines whether a given index can be used to serve the specified target.
///
/// The following table showcases some possible index configurations:
///
/// | Query                                               | Index                    |
/// |-----------------------------------------------------|--------------------------|
/// | where("a", "==", "a").where("b", "==", "b")         | a ASCENDING, b DESCENDING|
/// | where("a", "==", "a").where("b", "==", "b")         | a ASCENDING              |
/// | where("a", "==", "a").where("b", "==", "b")         | b DESCENDING             |
/// | where("a", ">=", "a").orderBy("a")                  | a ASCENDING              |
/// | where("a", ">=", "a").orderBy("a", "descending")    | a DESCENDING             |
/// | where("a", ">=", "a").orderBy("a").orderBy("b")     | a ASCENDING, b ASCENDING |
/// | where("a", ">=", "a").orderBy("a").orderBy("b")     | a ASCENDING              |
/// | where("a", "array-contains", "a").orderBy("b")      | a CONTAINS, b ASCENDING  |
/// | where("a", "array-contains", "a").orderBy("b")      | a CONTAINS               |
class TargetIndexMatcher {
  /// [target] must only have field filters (a target with composite filters
  /// is matched through its sub targets in disjunctive normal form).
  TargetIndexMatcher(Target target)
      : _collectionId = target.collectionGroup ?? target.path.getLastSegment(),
        _orderBys = target.orderBy {
    for (final Filter filter in target.filters) {
      final FieldFilter fieldFilter = filter as FieldFilter;
      if (_isInequality(fieldFilter)) {
        // One filter per field: only the first inequality of a field is kept,
        // like the TreeSet with a field comparator upstream.
        _inequalityFilters.putIfAbsent(fieldFilter.field, () => fieldFilter);
      } else {
        _equalityFilters.add(fieldFilter);
      }
    }
  }

  /// The collection ID (or collection group) of the query target.
  final String _collectionId;

  /// The inequality filters of the target (if they exist), one per field.
  final Map<FieldPath, FieldFilter> _inequalityFilters =
      <FieldPath, FieldFilter>{};

  final List<FieldFilter> _equalityFilters = <FieldFilter>[];
  final List<OrderBy> _orderBys;

  static bool _isInequality(FieldFilter filter) =>
      FilterOperator.inequalityOperators.contains(filter.operator);

  static bool _isArrayOperator(FieldFilter filter) =>
      filter.operator == FilterOperator.arrayContains ||
      filter.operator == FilterOperator.arrayContainsAny;

  bool get hasMultipleInequality => _inequalityFilters.length > 1;

  /// Returns whether the index can be used to serve the TargetIndexMatcher's
  /// target.
  ///
  /// An index is considered capable of serving the target when:
  ///
  ///   * The target uses all index segments for its filters and orderBy
  ///     clauses. The target can have additional filter and orderBy clauses,
  ///     but not fewer.
  ///   * If an ArrayContains/ArrayContainsAny filter is used, the index must
  ///     also have a corresponding [SegmentKind.contains] segment.
  ///   * All directional index segments can be mapped to the target as a
  ///     series of equality filters, a single inequality filter and a series
  ///     of orderBy clauses.
  ///   * The segments that represent the equality filters may appear out of
  ///     order.
  ///   * The optional segment for the inequality filter must appear after all
  ///     equality segments.
  ///   * The segments that represent that orderBy clause of the target must
  ///     appear in order after all equality and inequality segments. Single
  ///     orderBy clauses cannot be skipped, but a continuous orderBy suffix may
  ///     be omitted.
  ///
  /// Throws an [AssertionError] if the index is for a different collection.
  bool servedByIndex(FieldIndex index) {
    hardAssert(
        index.collectionGroup == _collectionId, 'Collection IDs do not match');

    if (hasMultipleInequality) {
      // Only single inequality is supported for now.
      // TODO(Add support for multiple inequality query): b/298441043
      return false;
    }

    // If there is an array element, find a matching filter.
    final IndexSegment? arraySegment = index.arraySegment;
    if (arraySegment != null && !_hasMatchingEqualityFilter(arraySegment)) {
      return false;
    }

    final Iterator<OrderBy> orderBys = _orderBys.iterator;
    final List<IndexSegment> segments = index.directionalSegments;
    int segmentIndex = 0;

    final Set<String> equalitySegments = <String>{};

    // Process all equalities first. Equalities can appear out of order.
    for (; segmentIndex < segments.length; ++segmentIndex) {
      // We attempt to greedily match all segments to equality filters. If a
      // filter matches an index segment, we can mark the segment as used.
      if (_hasMatchingEqualityFilter(segments[segmentIndex])) {
        equalitySegments.add(segments[segmentIndex].fieldPath.canonicalString);
      } else {
        // If we cannot find a matching filter, we need to verify whether the
        // remaining segments map to the target's inequality and its orderBy
        // clauses.
        break;
      }
    }

    // If we already have processed all segments, all segments are used to
    // serve the equality filters and we do not need to map any segments to the
    // target's inequality and orderBy clauses.
    if (segmentIndex == segments.length) {
      return true;
    }

    if (_inequalityFilters.isNotEmpty) {
      // Only a single inequality is currently supported. Get the only entry in
      // the set.
      final FieldFilter inequalityFilter = _inequalityFilters.values.first;

      // If there is an inequality filter and the field was not in one of the
      // equality filters above, the next segment must match both the filter
      // and the first orderBy clause.
      if (!equalitySegments.contains(inequalityFilter.field.canonicalString)) {
        final IndexSegment segment = segments[segmentIndex];

        if (!_matchesFilter(inequalityFilter, segment) ||
            !orderBys.moveNext() ||
            !_matchesOrderBy(orderBys.current, segment)) {
          return false;
        }
      }

      ++segmentIndex;
    }

    // All remaining segments need to represent the prefix of the target's
    // orderBy.
    for (; segmentIndex < segments.length; ++segmentIndex) {
      final IndexSegment segment = segments[segmentIndex];
      if (!orderBys.moveNext() || !_matchesOrderBy(orderBys.current, segment)) {
        return false;
      }
    }

    return true;
  }

  /// Returns a full matched field index for this target. Currently multiple
  /// inequality query is not supported so function returns null.
  FieldIndex? buildTargetIndex() {
    if (hasMultipleInequality) {
      return null;
    }

    // We want to make sure only one segment created for one field. For
    // example, in case like a == 3 and a > 2, Index: {a ASCENDING} will only be
    // created once.
    final Set<FieldPath> uniqueFields = <FieldPath>{};
    final List<IndexSegment> segments = <IndexSegment>[];

    for (final FieldFilter filter in _equalityFilters) {
      if (filter.field.isKeyField) {
        continue;
      }
      if (_isArrayOperator(filter)) {
        segments.add(IndexSegment(filter.field, SegmentKind.contains));
      } else {
        if (uniqueFields.contains(filter.field)) {
          continue;
        }
        uniqueFields.add(filter.field);
        segments.add(IndexSegment(filter.field, SegmentKind.ascending));
      }
    }

    // Note: We do not explicitly check `inequalityFilter` but rather rely on
    // the target defining an appropriate `orderBys` to ensure that the required
    // index segment is added. The query engine would reject a query with an
    // inequality filter that lacks the required order-by clause.
    for (final OrderBy orderBy in _orderBys) {
      // Stop adding more segments if we see a order-by on key. Typically this
      // is the default implicit order-by which is covered in the index_entry
      // table as a separate column. If it is not the default order-by, the
      // generated index will be missing some segments optimized for order-bys,
      // which is probably fine.
      if (orderBy.field.isKeyField) {
        continue;
      }

      if (uniqueFields.contains(orderBy.field)) {
        continue;
      }
      uniqueFields.add(orderBy.field);

      segments.add(IndexSegment(
          orderBy.field,
          orderBy.direction == OrderByDirection.ascending
              ? SegmentKind.ascending
              : SegmentKind.descending));
    }

    return FieldIndex(
        FieldIndex.unknownId, _collectionId, segments, FieldIndex.initialState);
  }

  bool _hasMatchingEqualityFilter(IndexSegment segment) {
    for (final FieldFilter filter in _equalityFilters) {
      if (_matchesFilter(filter, segment)) {
        return true;
      }
    }
    return false;
  }

  bool _matchesFilter(FieldFilter filter, IndexSegment segment) {
    if (filter.field != segment.fieldPath) {
      return false;
    }
    return (segment.kind == SegmentKind.contains) == _isArrayOperator(filter);
  }

  bool _matchesOrderBy(OrderBy orderBy, IndexSegment segment) {
    if (orderBy.field != segment.fieldPath) {
      return false;
    }
    return (segment.kind == SegmentKind.ascending &&
            orderBy.direction == OrderByDirection.ascending) ||
        (segment.kind == SegmentKind.descending &&
            orderBy.direction == OrderByDirection.descending);
  }
}
