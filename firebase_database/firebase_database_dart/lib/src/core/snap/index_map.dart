/// The lazily built indexes of a children node. JS: `core/snap/IndexMap.ts`; Android: the role of
/// `snapshot/IndexedNode.java`.
library;

import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/index.dart';
import 'package:firebase_database_dart/src/core/snap/named_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/util/sorted_map.dart';

/// The indexes of a children node: for each index key, the children sorted by that index.
final class IndexMap {
  /// Creates a map of [indexes] (null value: not built yet) and their [indexSet].
  const IndexMap(this.indexes, this.indexSet);

  /// The map holding only the priority index.
  static IndexMap get defaultMap => throw UnimplementedError();

  /// The sorted children per index key; null while not built.
  final Map<String, SortedMap<NamedNode, Node>?> indexes;

  /// The index definitions per index key.
  final Map<String, Index> indexSet;

  /// The sorted children of index [indexKey], or null.
  SortedMap<NamedNode, Node>? get(String indexKey) =>
      throw UnimplementedError();

  /// Whether [index] is present.
  bool hasIndex(Index index) => throw UnimplementedError();

  /// A map with [index] added, built from [existingChildren].
  IndexMap addIndex(Index index, SortedMap<ChildKey, Node> existingChildren) =>
      throw UnimplementedError();

  /// A map with [namedNode] added to every index; [existingChildren] are the old children.
  IndexMap addToIndexes(
    NamedNode namedNode,
    SortedMap<ChildKey, Node> existingChildren,
  ) => throw UnimplementedError();

  /// A map with [namedNode] removed from every index.
  IndexMap removeFromIndexes(
    NamedNode namedNode,
    SortedMap<ChildKey, Node> existingChildren,
  ) => throw UnimplementedError();
}
