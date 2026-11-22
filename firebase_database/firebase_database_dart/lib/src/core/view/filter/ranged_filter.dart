/// Keeps the children between the start and end posts of the query. JS: `core/view/filter/RangedFilter.ts`; Android: `core/view/filter/RangedFilter.java`.
library;

import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/index.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/priority_index.dart';
import 'package:firebase_database_dart/src/core/snap/named_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/view/complete_child_source.dart';
import 'package:firebase_database_dart/src/core/view/filter/child_change_accumulator.dart';
import 'package:firebase_database_dart/src/core/view/filter/indexed_filter.dart';
import 'package:firebase_database_dart/src/core/view/filter/node_filter.dart';
import 'package:firebase_database_dart/src/core/view/query_params.dart';

/// Keeps the children between the start and end posts of the query.
final class RangedFilter implements NodeFilter {
  /// Creates the filter.
  factory RangedFilter(QueryParams params) {
    final Index index = params.index;
    return RangedFilter._(
      IndexedFilter(index),
      index,
      params.hasStart
          ? index.makePost(params.indexStartValue, params.indexStartName)
          : index.minPost,
      params.hasEnd
          ? index.makePost(params.indexEndValue, params.indexEndName)
          : index.maxPost,
      startInclusive: params.startInclusive,
      endInclusive: params.endInclusive,
    );
  }

  RangedFilter._(
    this._indexedFilter,
    this._index,
    this._startPost,
    this._endPost, {
    required bool startInclusive,
    required bool endInclusive,
  }) : _startInclusive = startInclusive,
       _endInclusive = endInclusive;

  final IndexedFilter _indexedFilter;
  final Index _index;
  final NamedNode _startPost;
  final NamedNode _endPost;
  final bool _startInclusive;
  final bool _endInclusive;

  /// The start post (JS `RangedFilter.getStartPost`): the index's min post without a start.
  NamedNode get startPost => _startPost;

  /// The end post (JS `RangedFilter.getEndPost`): the index's max post without an end.
  NamedNode get endPost => _endPost;

  /// Whether [node] is within the range, the start excluded after `startAfter` and the end
  /// after `endBefore` (JS `RangedFilter.matches`).
  bool matches(NamedNode node) {
    final int startCompare = _index.compare(_startPost, node);
    final bool isWithinStart = _startInclusive
        ? startCompare <= 0
        : startCompare < 0;
    final int endCompare = _index.compare(node, _endPost);
    final bool isWithinEnd = _endInclusive ? endCompare <= 0 : endCompare < 0;
    return isWithinStart && isWithinEnd;
  }

  /// A child outside the range becomes empty (JS `RangedFilter.updateChild`).
  @override
  Node updateChild(
    Node snap,
    ChildKey key,
    Node newChild,
    Path affectedPath,
    CompleteChildSource source,
    ChildChangeAccumulator? accumulator,
  ) {
    final Node child = matches(NamedNode(key, newChild))
        ? newChild
        : ChildrenNode.empty;
    return _indexedFilter.updateChild(
      snap,
      key,
      child,
      affectedPath,
      source,
      accumulator,
    );
  }

  /// Drops the children outside the range and the priority (JS `RangedFilter.updateFullNode`).
  @override
  Node updateFullNode(
    Node oldSnap,
    Node newSnap,
    ChildChangeAccumulator? accumulator,
  ) {
    // Make sure we have a children node with the correct index, not a leaf node.
    final Node source = newSnap.isLeafNode ? ChildrenNode.empty : newSnap;
    // Don't support priorities on queries.
    Node filtered = source.withIndex(_index).updatePriority(ChildrenNode.empty);
    source.forEachChild(priorityIndex, (ChildKey key, Node childNode) {
      if (!matches(NamedNode(key, childNode))) {
        filtered = filtered.updateImmediateChild(key, ChildrenNode.empty);
      }
      return false;
    });
    return _indexedFilter.updateFullNode(oldSnap, filtered, accumulator);
  }

  /// Unchanged: queries do not support priorities (JS `RangedFilter.updatePriority`).
  @override
  Node updatePriority(Node oldSnap, Node newPriority) => oldSnap;

  /// True (JS `RangedFilter.filtersNodes`).
  @override
  bool get filtersNodes => true;

  /// The [IndexedFilter] of the index (JS `RangedFilter.getIndexedFilter`).
  @override
  NodeFilter get indexedFilter => _indexedFilter;

  /// The index (JS `RangedFilter.getIndex`).
  @override
  Index get index => _index;
}
