/// Orders children by priority (the default index). JS: `core/snap/indexes/PriorityIndex.ts`; Android: `snapshot/PriorityIndex.java`.
library;

import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/index.dart';
import 'package:firebase_database_dart/src/core/snap/leaf_node.dart';
import 'package:firebase_database_dart/src/core/snap/named_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';

/// Orders children by priority (the default index).
final class PriorityIndex extends Index {
  /// Use [priorityIndex].
  const PriorityIndex();

  @override
  int compare(NamedNode a, NamedNode b) {
    final int indexCmp = a.node.priority.compareTo(b.node.priority);
    return indexCmp == 0 ? a.name.compareTo(b.name) : indexCmp;
  }

  @override
  bool isDefinedOn(Node node) => !node.priority.isEmpty;

  @override
  bool indexedValueChanged(Node oldNode, Node newNode) =>
      oldNode.priority != newNode.priority;

  @override
  NamedNode get minPost => NamedNode.min;

  @override
  NamedNode get maxPost =>
      NamedNode(ChildKey.max, LeafNode('[PRIORITY-POST]', MaxNode.instance));

  @override
  NamedNode makePost(Node indexValue, ChildKey name) =>
      NamedNode(name, LeafNode('[PRIORITY-POST]', indexValue));

  @override
  String get queryDefinition => '.priority';

  @override
  String toString() => queryDefinition;
}

/// The single instance.
const PriorityIndex priorityIndex = PriorityIndex();
