/// A cached node with completeness flags. JS: `core/view/CacheNode.ts`; Android:
/// `core/view/CacheNode.java`.
library;

import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';

/// A [node] (indexed for its view) and whether it is [fullyInitialized] and [filtered].
final class CacheNode {
  /// Creates a cache node.
  const CacheNode(
    this.node, {
    required this.fullyInitialized,
    required this.filtered,
  });

  /// The data.
  final Node node;

  /// Whether [node] is the complete data (else partial).
  final bool fullyInitialized;

  /// Whether a query filter dropped children.
  final bool filtered;

  /// Whether the data at [path] is complete (Android `CacheNode.isCompleteForPath`).
  bool isCompleteForPath(Path path) {
    final ChildKey? front = path.front;
    if (front == null) {
      return fullyInitialized && !filtered;
    }
    return isCompleteForChild(front);
  }

  /// Whether child [key] is complete (Android `CacheNode.isCompleteForChild`).
  bool isCompleteForChild(ChildKey key) =>
      (fullyInitialized && !filtered) || node.hasChild(key);
}
