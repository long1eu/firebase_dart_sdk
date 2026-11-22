/// Orders children by their value. JS: `core/snap/indexes/ValueIndex.ts`; Android: `snapshot/ValueIndex.java`.
library;

import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/index.dart';
import 'package:firebase_database_dart/src/core/snap/named_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';

/// Orders children by their value.
final class ValueIndex extends Index {
  /// Use [valueIndex].
  const ValueIndex();

  @override
  int compare(NamedNode a, NamedNode b) {
    final int indexCmp = a.node.compareTo(b.node);
    return indexCmp == 0 ? a.name.compareTo(b.name) : indexCmp;
  }

  @override
  bool isDefinedOn(Node node) => true;

  @override
  bool indexedValueChanged(Node oldNode, Node newNode) => oldNode != newNode;

  @override
  NamedNode get minPost => NamedNode.min;

  @override
  NamedNode get maxPost => NamedNode.max;

  @override
  NamedNode makePost(Node indexValue, ChildKey name) =>
      NamedNode(name, indexValue);

  @override
  String get queryDefinition => '.value';

  @override
  String toString() => queryDefinition;
}

/// The single instance.
const ValueIndex valueIndex = ValueIndex();
