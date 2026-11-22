/// Orders children by key. JS: `core/snap/indexes/KeyIndex.ts`; Android: `snapshot/KeyIndex.java`.
library;

import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/index.dart';
import 'package:firebase_database_dart/src/core/snap/named_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';

/// Orders children by key.
final class KeyIndex extends Index {
  /// Use [keyIndex].
  const KeyIndex();

  @override
  int compare(NamedNode a, NamedNode b) => throw UnimplementedError();

  @override
  bool isDefinedOn(Node node) => throw UnimplementedError();

  @override
  bool indexedValueChanged(Node oldNode, Node newNode) =>
      throw UnimplementedError();

  @override
  NamedNode get minPost => throw UnimplementedError();

  @override
  NamedNode get maxPost => throw UnimplementedError();

  @override
  NamedNode makePost(Node indexValue, ChildKey name) =>
      throw UnimplementedError();

  @override
  String get queryDefinition => throw UnimplementedError();

  @override
  String toString() => throw UnimplementedError();
}

/// The single instance.
const KeyIndex keyIndex = KeyIndex();
