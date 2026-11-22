/// The index interface. JS: `core/snap/indexes/Index.ts`; Android: `snapshot/Index.java`.
library;

import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/named_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';

/// An ordering of children: by priority (default), key, value, or a child path.
abstract base class Index {
  /// Const constructor for subclasses.
  const Index();

  /// Compares two children; ties are broken by key.
  int compare(NamedNode a, NamedNode b);

  /// [compare] as a [Comparator], for sorted maps.
  Comparator<NamedNode> get comparator => throw UnimplementedError();

  /// Whether [node] has a value under this index (for example a priority).
  bool isDefinedOn(Node node);

  /// Whether the indexed value differs between [oldNode] and [newNode].
  bool indexedValueChanged(Node oldNode, Node newNode) => throw UnimplementedError();

  /// The post before every child.
  NamedNode get minPost => throw UnimplementedError();

  /// The post after every child.
  NamedNode get maxPost;

  /// The post for a query bound: [indexValue] under [name].
  NamedNode makePost(Node indexValue, ChildKey name);

  /// The wire name of the index: `.priority`, `.key`, `.value` or the child path (`a/b`).
  String get queryDefinition;
}
