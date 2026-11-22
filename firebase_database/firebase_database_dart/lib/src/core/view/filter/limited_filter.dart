/// Keeps at most the limit of children within the range, from the anchored side. JS: `core/view/filter/LimitedFilter.ts`; Android: `core/view/filter/LimitedFilter.java`.
library;

import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/index.dart';
import 'package:firebase_database_dart/src/core/snap/named_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/view/change.dart';
import 'package:firebase_database_dart/src/core/view/complete_child_source.dart';
import 'package:firebase_database_dart/src/core/view/filter/child_change_accumulator.dart';
import 'package:firebase_database_dart/src/core/view/filter/node_filter.dart';
import 'package:firebase_database_dart/src/core/view/filter/ranged_filter.dart';
import 'package:firebase_database_dart/src/core/view/query_params.dart';

/// Keeps at most the limit of children within the range, from the anchored side.
final class LimitedFilter implements NodeFilter {
  /// Creates the filter.
  factory LimitedFilter(QueryParams params) => LimitedFilter._(
    RangedFilter(params),
    params.index,
    params.limit,
    reverse: !params.isViewFromLeft,
    startInclusive: params.startInclusive,
    endInclusive: params.endInclusive,
  );

  LimitedFilter._(
    this._rangedFilter,
    this._index,
    this._limit, {
    required bool reverse,
    required bool startInclusive,
    required bool endInclusive,
  }) : _reverse = reverse,
       _startInclusive = startInclusive,
       _endInclusive = endInclusive;

  final RangedFilter _rangedFilter;
  final Index _index;
  final int _limit;
  final bool _reverse;
  final bool _startInclusive;
  final bool _endInclusive;

  /// JS `LimitedFilter.updateChild`: below the limit as the indexed filter, else the window
  /// update.
  @override
  Node updateChild(
    Node snap,
    ChildKey key,
    Node newChild,
    Path affectedPath,
    CompleteChildSource source,
    ChildChangeAccumulator? accumulator,
  ) {
    final Node child = _rangedFilter.matches(NamedNode(key, newChild))
        ? newChild
        : ChildrenNode.empty;
    if (snap.getImmediateChild(key) == child) {
      // No change.
      return snap;
    } else if (snap.numChildren < _limit) {
      return _rangedFilter.indexedFilter.updateChild(
        snap,
        key,
        child,
        affectedPath,
        source,
        accumulator,
      );
    } else {
      return _fullLimitUpdateChild(snap, key, child, source, accumulator);
    }
  }

  /// JS `LimitedFilter.updateFullNode`: keeps the first [QueryParams.limit] children within the
  /// range from the anchored side.
  @override
  Node updateFullNode(
    Node oldSnap,
    Node newSnap,
    ChildChangeAccumulator? accumulator,
  ) {
    Node filtered;
    if (newSnap.isLeafNode || newSnap.isEmpty) {
      // Make sure we have a children node with the correct index, not a leaf node.
      filtered = ChildrenNode.empty.withIndex(_index);
    } else if (_limit * 2 < newSnap.numChildren && newSnap.isIndexed(_index)) {
      // Easier to build up a snapshot, since what we're given has more than twice the elements
      // we want. Anchor to the start post, the end post, or the last element as appropriate.
      filtered = ChildrenNode.empty.withIndex(_index);
      final ChildrenNode children = newSnap as ChildrenNode;
      final Iterable<NamedNode> iterator = _reverse
          ? children.reverseChildrenFrom(_rangedFilter.endPost, _index)
          : children.childrenFrom(_rangedFilter.startPost, _index);
      int count = 0;
      for (final NamedNode next in iterator) {
        if (count >= _limit) {
          break;
        }
        if (!_withinDirectionalStart(next)) {
          // We have not reached the start: skip to the next element.
          continue;
        } else if (!_withinDirectionalEnd(next)) {
          // We have reached the end: stop adding elements.
          break;
        } else {
          filtered = filtered.updateImmediateChild(next.name, next.node);
          count++;
        }
      }
    } else {
      // The snap has less than twice the limit: faster to delete from it than to build a new one.
      // Don't support priorities on queries.
      filtered = newSnap.withIndex(_index).updatePriority(ChildrenNode.empty);
      final ChildrenNode children = filtered as ChildrenNode;
      final Iterable<NamedNode> iterator = _reverse
          ? children.reverseChildren(_index)
          : children.childrenInOrder(_index);
      int count = 0;
      for (final NamedNode next in iterator) {
        final bool inRange =
            count < _limit &&
            _withinDirectionalStart(next) &&
            _withinDirectionalEnd(next);
        if (inRange) {
          count++;
        } else {
          filtered = filtered.updateImmediateChild(
            next.name,
            ChildrenNode.empty,
          );
        }
      }
    }
    return _rangedFilter.indexedFilter.updateFullNode(
      oldSnap,
      filtered,
      accumulator,
    );
  }

  /// Unchanged: queries do not support priorities (JS `LimitedFilter.updatePriority`).
  @override
  Node updatePriority(Node oldSnap, Node newPriority) => oldSnap;

  /// True (JS `LimitedFilter.filtersNodes`).
  @override
  bool get filtersNodes => true;

  /// The indexed filter of the range (JS `LimitedFilter.getIndexedFilter`).
  @override
  NodeFilter get indexedFilter => _rangedFilter.indexedFilter;

  /// The index (JS `LimitedFilter.getIndex`).
  @override
  Index get index => _index;

  /// JS `LimitedFilter.fullLimitUpdateChild_`: the window is full; [childKey] changes to
  /// [childSnap], which may push the boundary child out or pull the next one in.
  Node _fullLimitUpdateChild(
    Node snap,
    ChildKey childKey,
    Node childSnap,
    CompleteChildSource source,
    ChildChangeAccumulator? accumulator,
  ) {
    int cmp(NamedNode a, NamedNode b) =>
        _reverse ? _index.compare(b, a) : _index.compare(a, b);
    final ChildrenNode oldEventCache = snap as ChildrenNode;
    assert(oldEventCache.numChildren == _limit, '');
    final NamedNode newChildNamedNode = NamedNode(childKey, childSnap);
    final NamedNode windowBoundary = _reverse
        ? oldEventCache.firstChild(_index)!
        : oldEventCache.lastChild(_index)!;
    final bool inRange = _rangedFilter.matches(newChildNamedNode);
    if (oldEventCache.hasChild(childKey)) {
      final Node oldChildSnap = oldEventCache.getImmediateChild(childKey);
      NamedNode? nextChild = source.getChildAfterChild(
        _index,
        windowBoundary,
        reverse: _reverse,
      );
      while (nextChild != null &&
          (nextChild.name == childKey ||
              oldEventCache.hasChild(nextChild.name))) {
        // A node updated as part of a merge in the write tree but not yet applied to this
        // filter: skip it, it is updated later.
        nextChild = source.getChildAfterChild(
          _index,
          nextChild,
          reverse: _reverse,
        );
      }
      final int compareNext = nextChild == null
          ? 1
          : cmp(nextChild, newChildNamedNode);
      final bool remainsInWindow =
          inRange && !childSnap.isEmpty && compareNext >= 0;
      if (remainsInWindow) {
        accumulator?.trackChildChange(
          Change.childChanged(childKey, childSnap, oldChildSnap),
        );
        return oldEventCache.updateImmediateChild(childKey, childSnap);
      }
      accumulator?.trackChildChange(
        Change.childRemoved(childKey, oldChildSnap),
      );
      final Node newEventCache = oldEventCache.updateImmediateChild(
        childKey,
        ChildrenNode.empty,
      );
      final bool nextChildInRange =
          nextChild != null && _rangedFilter.matches(nextChild);
      if (nextChildInRange) {
        accumulator?.trackChildChange(
          Change.childAdded(nextChild.name, nextChild.node),
        );
        return newEventCache.updateImmediateChild(
          nextChild.name,
          nextChild.node,
        );
      }
      return newEventCache;
    } else if (childSnap.isEmpty) {
      // We're deleting a node, but it was not in the window, so ignore it.
      return snap;
    } else if (inRange) {
      if (cmp(windowBoundary, newChildNamedNode) >= 0) {
        if (accumulator != null) {
          accumulator
            ..trackChildChange(
              Change.childRemoved(windowBoundary.name, windowBoundary.node),
            )
            ..trackChildChange(Change.childAdded(childKey, childSnap));
        }
        return oldEventCache
            .updateImmediateChild(childKey, childSnap)
            .updateImmediateChild(windowBoundary.name, ChildrenNode.empty);
      }
      return snap;
    }
    return snap;
  }

  bool _withinDirectionalStart(NamedNode node) =>
      _reverse ? _withinEndPost(node) : _withinStartPost(node);

  bool _withinDirectionalEnd(NamedNode node) =>
      _reverse ? _withinStartPost(node) : _withinEndPost(node);

  bool _withinStartPost(NamedNode node) {
    final int compareRes = _index.compare(_rangedFilter.startPost, node);
    return _startInclusive ? compareRes <= 0 : compareRes < 0;
  }

  bool _withinEndPost(NamedNode node) {
    final int compareRes = _index.compare(node, _rangedFilter.endPost);
    return _endInclusive ? compareRes <= 0 : compareRes < 0;
  }
}
