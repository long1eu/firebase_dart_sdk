/// Size estimate of a node's JSON. JS: none; Android: `core/utilities/NodeSizeEstimator.java`.
library;

import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/key_index.dart';
import 'package:firebase_database_dart/src/core/snap/leaf_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';

/// Overhead of the extra JSON object, the `.value` and `.priority` keys, colons and comma.
const int _leafPriorityOverhead = 2 + 8 + 11 + 2 + 1;

int _estimateLeafNodeSize(LeafNode node) {
  // Rough values: performance matters more than exactness.
  final int valueSize = switch (node.leafType) {
    LeafType.number => 8,
    LeafType.boolean => 4,
    LeafType.string => 2 + (node.value as String).length,
    LeafType.deferredValue => throw ArgumentError(
      'Unknown leaf node type: ${node.leafType}',
    ),
  };
  final Node priority = node.priority;
  if (priority.isEmpty) {
    return valueSize;
  }
  return _leafPriorityOverhead +
      valueSize +
      _estimateLeafNodeSize(priority as LeafNode);
}

/// The estimated size in bytes of [node] serialised as JSON (decides whether a listen sends a
/// compound hash).
int estimateSerializedNodeSize(Node node) {
  if (node.isEmpty) {
    return 4; // null
  }
  if (node.isLeafNode) {
    return _estimateLeafNodeSize(node as LeafNode);
  }
  int sum = 1; // opening bracket
  node.forEachChild(keyIndex, (ChildKey key, Node child) {
    sum += key.name.length; // key
    sum += 4; // quotes around the key, colon, and comma or closing bracket
    sum += estimateSerializedNodeSize(child);
    return false;
  });
  final Node priority = node.priority;
  if (!priority.isEmpty) {
    sum += 12; // ".priority" key, colon and comma
    sum += _estimateLeafNodeSize(priority as LeafNode);
  }
  return sum;
}

/// The number of leaves of [node].
int nodeCount(Node node) {
  if (node.isEmpty) {
    return 0;
  }
  if (node.isLeafNode) {
    return 1;
  }
  int sum = 0;
  node.forEachChild(keyIndex, (ChildKey key, Node child) {
    sum += nodeCount(child);
    return false;
  });
  return sum;
}
