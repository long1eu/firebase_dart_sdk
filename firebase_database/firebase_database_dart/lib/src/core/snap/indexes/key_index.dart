/// Orders children by key. JS: `core/snap/indexes/KeyIndex.ts`; Android: `snapshot/KeyIndex.java`.
library;

import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/index.dart';
import 'package:firebase_database_dart/src/core/snap/leaf_node.dart';
import 'package:firebase_database_dart/src/core/snap/named_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';

/// Orders children by key.
final class KeyIndex extends Index {
  /// Use [keyIndex].
  const KeyIndex();

  @override
  int compare(NamedNode a, NamedNode b) => a.name.compareTo(b.name);

  @override
  bool isDefinedOn(Node node) =>
      throw StateError('KeyIndex.isDefinedOn not expected to be called.');

  @override
  bool indexedValueChanged(Node oldNode, Node newNode) => false;

  @override
  NamedNode get minPost => NamedNode.min;

  @override
  NamedNode get maxPost => NamedNode(ChildKey.max, ChildrenNode.empty);

  @override
  NamedNode makePost(Node indexValue, ChildKey name) {
    if (indexValue is! LeafNode || indexValue.value is! String) {
      throw ArgumentError('KeyIndex indexValue must always be a string.');
    }
    // The node is never compared: the comparator only looks at the name.
    return NamedNode(ChildKey(indexValue.value as String), ChildrenNode.empty);
  }

  @override
  String get queryDefinition => '.key';

  @override
  String toString() => queryDefinition;
}

/// The single instance.
const KeyIndex keyIndex = KeyIndex();
