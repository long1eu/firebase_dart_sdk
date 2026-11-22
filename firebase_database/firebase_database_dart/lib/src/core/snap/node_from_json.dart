/// JSON to node. JS: `core/snap/nodeFromJSON.ts`; Android: `snapshot/NodeUtilities.java`
/// (`NodeFromJSON`).
///
/// Node to JSON is [Node.toJson] (plain value and export form).
library;

import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/child_set.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/comparators.dart';
import 'package:firebase_database_dart/src/core/snap/index_map.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/index.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/priority_index.dart';
import 'package:firebase_database_dart/src/core/snap/leaf_node.dart';
import 'package:firebase_database_dart/src/core/snap/named_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/util/sorted_map.dart';

/// The node of [json] (export form accepted: `.priority`, `.value`; other keys starting with `.`
/// ignored), with [priority] when given.
///
/// Numbers are kept as given (server data: `1.0`, `-0.0` and large integers stay as they are).
/// A `List` is read as a map of its indices (null entries skipped), like JS's array branch, but
/// built in linear time like the object branch.
Node nodeFromJson(Object? json, [Object? priority]) {
  if (json == null) {
    return ChildrenNode.empty;
  }

  Object? data = json;
  Object? priorityValue = priority;
  if (data is Map && data.containsKey('.priority')) {
    priorityValue = data['.priority'];
  }

  if (!(priorityValue == null ||
      priorityValue is String ||
      priorityValue is num ||
      (priorityValue is Map && priorityValue.containsKey('.sv')))) {
    throw ArgumentError.value(
      priorityValue,
      'priority',
      'Invalid priority type found: ${priorityValue.runtimeType}',
    );
  }

  if (data is Map && data.containsKey('.value') && data['.value'] != null) {
    data = data['.value'];
  }

  // Valid leaf nodes include non-objects or server-value wrapper objects.
  if (data is! Map && data is! List || data is Map && data.containsKey('.sv')) {
    return LeafNode(data!, _priorityNode(priorityValue));
  }

  final List<NamedNode> children = <NamedNode>[];
  bool childrenHavePriority = false;
  void addChild(String key, Object? childData) {
    // Ignore metadata nodes.
    if (key.startsWith('.')) {
      return;
    }
    final Node childNode = nodeFromJson(childData);
    if (!childNode.isEmpty) {
      childrenHavePriority =
          childrenHavePriority || !childNode.priority.isEmpty;
      children.add(NamedNode(ChildKey(key), childNode));
    }
  }

  if (data is List) {
    for (int i = 0; i < data.length; i++) {
      addChild('$i', data[i]);
    }
  } else {
    for (final MapEntry<Object?, Object?> entry
        in (data as Map<Object?, Object?>).entries) {
      addChild('${entry.key}', entry.value);
    }
  }

  if (children.isEmpty) {
    return ChildrenNode.empty;
  }

  final SortedMap<ChildKey, Node> childSet = buildChildSet<ChildKey, Node>(
    children,
    nameOnlyComparator,
    keyOf: (NamedNode n) => n.name,
    valueOf: (NamedNode n) => n.node,
    keyCompare: nameComparator,
  );
  final Node priorityNode = _priorityNode(priorityValue);
  if (childrenHavePriority) {
    final SortedMap<NamedNode, Node> sortedChildSet =
        buildChildSet<NamedNode, Node>(
          children,
          priorityIndex.comparator,
          keyOf: (NamedNode n) => n,
          valueOf: (NamedNode n) => n.node,
        );
    return ChildrenNode(
      childSet,
      priorityNode,
      IndexMap(
        <String, SortedMap<NamedNode, Node>?>{'.priority': sortedChildSet},
        const <String, Index>{'.priority': priorityIndex},
      ),
    );
  }
  return ChildrenNode(childSet, priorityNode, IndexMap.defaultMap);
}

Node _priorityNode(Object? priority) =>
    priority == null ? ChildrenNode.empty : nodeFromJson(priority);
