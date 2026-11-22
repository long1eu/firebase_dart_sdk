/// A range merge (`rm` push) applied to a cached node. JS: none; Android:
/// `snapshot/RangeMerge.java`.
library;

import 'package:firebase_database_dart/src/core/connection/wire_range_merge.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/key_index.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';

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
      nodeFromJson(merge.data),
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
      final List<ChildKey> inOrder = allChildren.toList();
      // The priority goes last, so the node is not empty when it is applied.
      if (!updateNode.priority.isEmpty || !node.priority.isEmpty) {
        inOrder.add(ChildKey.priority);
      }
      Node newNode = node;
      for (final ChildKey key in inOrder) {
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

  @override
  String toString() =>
      'RangeMerge{optExclusiveStart=$exclusiveStart, optInclusiveEnd=$inclusiveEnd, '
      'snap=$snap}';
}
