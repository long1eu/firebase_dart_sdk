/// A range merge (`rm` push) applied to a cached node. JS: none; Android:
/// `snapshot/RangeMerge.java`.
library;

import 'package:firebase_database_dart/src/core/connection/wire_range_merge.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/comparators.dart';
import 'package:firebase_database_dart/src/core/snap/index_map.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/key_index.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/util/sorted_map.dart';

/// Replaces every leaf after [exclusiveStart] and up to [inclusiveEnd] with the leaves of [snap]
/// in that range; a null bound is unbounded.
final class RangeMerge {
  /// Creates a range merge.
  const RangeMerge(this.exclusiveStart, this.inclusiveEnd, this.snap);

  /// Converts the wire form.
  factory RangeMerge.fromWire(WireRangeMerge merge) {
    final String? start = merge.exclusiveStart;
    final String? end = merge.inclusiveEnd;
    return RangeMerge(
      start == null ? null : Path(start),
      end == null ? null : Path(end),
      nodeFromServerJson(merge.data),
    );
  }

  /// The exclusive start, or null for minus infinity.
  final Path? exclusiveStart;

  /// The inclusive end, or null for plus infinity.
  final Path? inclusiveEnd;

  /// The new data of the range.
  final Node snap;

  /// [node] with this merge applied.
  Node applyTo(Node node) => _updateRangeInNode(Path.empty, node, snap);

  Node _updateRangeInNode(Path currentPath, Node node, Node updateNode) {
    final Path? start = exclusiveStart;
    final Path? end = inclusiveEnd;
    final int startComparison = start == null
        ? 1
        : currentPath.compareTo(start);
    final int endComparison = end == null ? -1 : currentPath.compareTo(end);
    final bool startInNode = start != null && currentPath.contains(start);
    final bool endInNode = end != null && currentPath.contains(end);
    if (startComparison > 0 && endComparison < 0 && !endInNode) {
      // The child is completely contained.
      return updateNode;
    } else if (startComparison > 0 && endInNode && updateNode.isLeafNode) {
      return updateNode;
    } else if (startComparison > 0 && endComparison == 0) {
      assert(endInNode);
      assert(!updateNode.isLeafNode);
      // The update node is not a leaf, so a leaf here is deleted; anything else is unaffected.
      return node.isLeafNode ? ChildrenNode.empty : node;
    } else if (startInNode || endInNode) {
      // A partial update: visit every child of both nodes.
      final Set<ChildKey> allChildren = <ChildKey>{};
      bool collect(ChildKey key, Node child) {
        allChildren.add(key);
        return false;
      }

      node.forEachChild(keyIndex, collect);
      updateNode.forEachChild(keyIndex, collect);
      // Hidden children (nodes emptied below that keep a priority) are in the range too.
      for (final Node n in <Node>[node, updateNode]) {
        if (n is ChildrenNode) {
          allChildren.addAll(n.hiddenKeys);
        }
      }
      final List<ChildKey> inOrder = allChildren.toList();
      // The priority goes last, so the node is not empty when it is applied; an emptied node's
      // kept priority counts, on both sides.
      if (!_priorityOf(updateNode).isEmpty || !_priorityOf(node).isEmpty) {
        inOrder.add(ChildKey.priority);
      }
      Node newNode = node;
      for (final ChildKey key in inOrder) {
        if (key.isPriorityKey) {
          final Node currentPriority = _priorityOf(node);
          final Node updatedPriority = _updateRangeInNode(
            currentPath.child(key),
            currentPriority,
            _priorityOf(updateNode),
          );
          // Priorities are leaves (or empty): compared by value.
          if (updatedPriority != currentPriority) {
            newNode = _withPriority(newNode, updatedPriority);
          }
          continue;
        }
        final Node currentChild = node.getImmediateChild(key);
        final Node updatedChild = _updateRangeInNode(
          currentPath.child(key),
          currentChild,
          updateNode.getImmediateChild(key),
        );
        // Only update when the child changed.
        if (!identical(updatedChild, currentChild)) {
          newNode = newNode.updateImmediateChild(key, updatedChild);
        }
      }
      return newNode;
    } else {
      // Unaffected by this range.
      assert(endComparison > 0 || startComparison <= 0);
      return node;
    }
  }

  /// The priority the server holds for [node]: for an emptied node, the priority it kept.
  static Node _priorityOf(Node node) =>
      node is ChildrenNode ? node.keptPriority : node.priority;

  /// [node] with [priority]. An empty node that holds no hidden state ignores a priority written
  /// on it, so a non-empty [priority] there makes an emptied node that keeps it: the range data
  /// came from the server, which holds that priority for a node with no children in the range.
  static Node _withPriority(Node node, Node priority) {
    if (node.isEmpty &&
        !priority.isEmpty &&
        !(node is ChildrenNode && node.holdsHiddenState)) {
      return ChildrenNode(
        SortedMap<ChildKey, Node>(nameComparator),
        priority,
        IndexMap.defaultMap,
      );
    }
    return node.updateImmediateChild(ChildKey.priority, priority);
  }

  @override
  String toString() =>
      'RangeMerge{optExclusiveStart=$exclusiveStart, optInclusiveEnd=$inclusiveEnd, '
      'snap=$snap}';
}
