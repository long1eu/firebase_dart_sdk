/// Orders children by the value at a child path. JS: `core/snap/indexes/PathIndex.ts`; Android:
/// `snapshot/PathIndex.java`.
library;

import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/index.dart';
import 'package:firebase_database_dart/src/core/snap/named_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';

/// Orders children by the value at [indexPath] below each child (`orderByChild`).
final class PathIndex extends Index {
  /// Creates the index; [indexPath] must not be empty or `.priority`.
  const PathIndex(this.indexPath);

  /// The child path.
  final Path indexPath;

  @override
  int compare(NamedNode a, NamedNode b) {
    final int indexCmp = a.node
        .getChild(indexPath)
        .compareTo(b.node.getChild(indexPath));
    return indexCmp == 0 ? a.name.compareTo(b.name) : indexCmp;
  }

  @override
  bool isDefinedOn(Node node) => !node.getChild(indexPath).isEmpty;

  @override
  NamedNode makePost(Node indexValue, ChildKey name) =>
      NamedNode(name, ChildrenNode.empty.updateChild(indexPath, indexValue));

  @override
  NamedNode get maxPost => NamedNode(
    ChildKey.max,
    ChildrenNode.empty.updateChild(indexPath, MaxNode.instance),
  );

  @override
  String get queryDefinition => indexPath.toStringList().join('/');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PathIndex && indexPath == other.indexPath;

  @override
  int get hashCode => indexPath.hashCode;

  @override
  String toString() => queryDefinition;
}
