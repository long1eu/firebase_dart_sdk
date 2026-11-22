/// The lazily built indexes of a children node. JS: `core/snap/IndexMap.ts`; Android: the role of
/// `snapshot/IndexedNode.java`.
library;

import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/child_set.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/index.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/key_index.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/priority_index.dart';
import 'package:firebase_database_dart/src/core/snap/named_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/util/sorted_map.dart';

/// The indexes of a children node: for each index key, the children sorted by that index.
///
/// A present index whose sorted map is null is the JS "fallback": no child has a value under the
/// index yet, so the key order is the index order and the children map is used.
final class IndexMap {
  /// Creates a map of [indexes] (null value: not built yet) and their [indexSet].
  const IndexMap(this.indexes, this.indexSet);

  /// The map holding only the priority index.
  static IndexMap get defaultMap => _default;

  static const IndexMap _default = IndexMap(
    <String, SortedMap<NamedNode, Node>?>{'.priority': null},
    <String, Index>{'.priority': priorityIndex},
  );

  /// The sorted children per index key; null while not built.
  final Map<String, SortedMap<NamedNode, Node>?> indexes;

  /// The index definitions per index key.
  final Map<String, Index> indexSet;

  /// The sorted children of index [indexKey], or null when the key order serves; throws a
  /// [StateError] when the index was never added.
  SortedMap<NamedNode, Node>? get(String indexKey) {
    if (!indexes.containsKey(indexKey)) {
      throw StateError('No index defined for $indexKey');
    }
    return indexes[indexKey];
  }

  /// Whether [index] is present.
  bool hasIndex(Index index) => indexSet.containsKey(index.queryDefinition);

  /// A map with [index] added, built from [existingChildren].
  IndexMap addIndex(Index index, SortedMap<ChildKey, Node> existingChildren) {
    assert(
      index != keyIndex,
      "KeyIndex always exists and isn't meant to be added to the IndexMap.",
    );
    final List<NamedNode> childList = <NamedNode>[];
    bool sawIndexedValue = false;
    existingChildren.inOrderTraversal((ChildKey key, Node node) {
      sawIndexedValue = sawIndexedValue || index.isDefinedOn(node);
      childList.add(NamedNode(key, node));
      return false;
    });
    final SortedMap<NamedNode, Node>? newIndex = sawIndexedValue
        ? _build(childList, index)
        : null;
    final String indexName = index.queryDefinition;
    return IndexMap(
      <String, SortedMap<NamedNode, Node>?>{...indexes, indexName: newIndex},
      <String, Index>{...indexSet, indexName: index},
    );
  }

  /// A map with [namedNode] added to every index; [existingChildren] are the old children.
  IndexMap addToIndexes(
    NamedNode namedNode,
    SortedMap<ChildKey, Node> existingChildren,
  ) {
    final Map<String, SortedMap<NamedNode, Node>?> newIndexes =
        <String, SortedMap<NamedNode, Node>?>{};
    for (final MapEntry<String, SortedMap<NamedNode, Node>?> entry
        in indexes.entries) {
      final Index? index = indexSet[entry.key];
      if (index == null) {
        throw StateError('Missing index implementation for ${entry.key}');
      }
      final SortedMap<NamedNode, Node>? indexedChildren = entry.value;
      if (indexedChildren == null) {
        if (index.isDefinedOn(namedNode.node)) {
          // The first child with a value under this index: build it.
          final List<NamedNode> childList = <NamedNode>[];
          existingChildren.inOrderTraversal((ChildKey key, Node node) {
            if (key != namedNode.name) {
              childList.add(NamedNode(key, node));
            }
            return false;
          });
          childList.add(namedNode);
          newIndexes[entry.key] = _build(childList, index);
        } else {
          newIndexes[entry.key] = null;
        }
      } else {
        final Node? existingSnap = existingChildren[namedNode.name];
        SortedMap<NamedNode, Node> newChildren = indexedChildren;
        if (existingSnap != null) {
          newChildren = newChildren.remove(
            NamedNode(namedNode.name, existingSnap),
          );
        }
        newIndexes[entry.key] = newChildren.insert(namedNode, namedNode.node);
      }
    }
    return IndexMap(newIndexes, indexSet);
  }

  /// A map with [namedNode] removed from every index.
  IndexMap removeFromIndexes(
    NamedNode namedNode,
    SortedMap<ChildKey, Node> existingChildren,
  ) {
    final Node? existingSnap = existingChildren[namedNode.name];
    final Map<String, SortedMap<NamedNode, Node>?> newIndexes =
        <String, SortedMap<NamedNode, Node>?>{
          for (final MapEntry<String, SortedMap<NamedNode, Node>?> entry
              in indexes.entries)
            entry.key: entry.value == null || existingSnap == null
                ? entry.value
                : entry.value!.remove(NamedNode(namedNode.name, existingSnap)),
        };
    return IndexMap(newIndexes, indexSet);
  }

  static SortedMap<NamedNode, Node> _build(
    List<NamedNode> childList,
    Index index,
  ) => buildChildSet<NamedNode, Node>(
    childList,
    index.comparator,
    keyOf: (NamedNode n) => n,
    valueOf: (NamedNode n) => n.node,
  );
}
