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
///
/// A name that occurs many times in [json] (the field names of a list of records) gets one
/// [ChildKey] and one string for the whole call. The table lives for this call only: it cannot
/// grow without bound and nothing is shared between two messages or two databases.
Node nodeFromJson(Object? json, [Object? priority]) =>
    _nodeFromJson(json, priority, null, keepHidden: false);

/// The node of server data [json]: as [nodeFromJson], except that an object holding only
/// `.priority` (or only such objects) is kept as hidden state, as the server sends a node emptied
/// by a write below it (`{".priority": p}`, also inside its parent's data). See [ChildrenNode].
///
/// For data the server sent, never for a user's value.
Node nodeFromServerJson(Object? json) =>
    _nodeFromJson(json, null, null, keepHidden: true);

Node _nodeFromJson(
  Object? json,
  Object? priority,
  Map<String, ChildKey>? keys, {
  required bool keepHidden,
}) {
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
    return LeafNode(data!, _priorityNode(priorityValue, keys));
  }

  final Map<String, ChildKey> keyTable = keys ?? <String, ChildKey>{};
  final List<NamedNode> children = <NamedNode>[];
  List<NamedNode>? hidden;
  bool childrenHavePriority = false;
  void addChild(String key, Object? childData) {
    // Ignore metadata nodes.
    if (key.startsWith('.')) {
      return;
    }
    final Node childNode = _nodeFromJson(
      childData,
      null,
      keyTable,
      keepHidden: keepHidden,
    );
    if (!childNode.isEmpty) {
      childrenHavePriority =
          childrenHavePriority || !childNode.priority.isEmpty;
      children.add(NamedNode(keyTable[key] ??= ChildKey(key), childNode));
    } else if (childNode is ChildrenNode && childNode.holdsHiddenState) {
      (hidden ??= <NamedNode>[]).add(
        NamedNode(keyTable[key] ??= ChildKey(key), childNode),
      );
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

  final SortedMap<ChildKey, Node>? hiddenSet = hidden == null
      ? null
      : _childSet(hidden!);
  if (children.isEmpty) {
    if (keepHidden && (priorityValue != null || hiddenSet != null)) {
      return ChildrenNode.withHidden(
        _childSet(children),
        _priorityNode(priorityValue, keyTable),
        IndexMap.defaultMap,
        hiddenSet,
      );
    }
    return ChildrenNode.empty;
  }

  final SortedMap<ChildKey, Node> childSet = _childSet(children);
  final Node priorityNode = _priorityNode(priorityValue, keyTable);
  if (childrenHavePriority) {
    final SortedMap<NamedNode, Node> sortedChildSet =
        buildChildSet<NamedNode, Node>(
          children,
          priorityIndex.comparator,
          keyOf: (NamedNode n) => n,
          valueOf: (NamedNode n) => n.node,
        );
    return ChildrenNode.withHidden(
      childSet,
      priorityNode,
      IndexMap(
        <String, SortedMap<NamedNode, Node>?>{'.priority': sortedChildSet},
        const <String, Index>{'.priority': priorityIndex},
      ),
      hiddenSet,
    );
  }
  return ChildrenNode.withHidden(
    childSet,
    priorityNode,
    IndexMap.defaultMap,
    hiddenSet,
  );
}

SortedMap<ChildKey, Node> _childSet(List<NamedNode> children) =>
    buildChildSet<ChildKey, Node>(
      children,
      nameOnlyComparator,
      keyOf: (NamedNode n) => n.name,
      valueOf: (NamedNode n) => n.node,
      keyCompare: nameComparator,
    );

Node _priorityNode(Object? priority, Map<String, ChildKey>? keys) =>
    priority == null
    ? ChildrenNode.empty
    : _nodeFromJson(priority, null, keys, keepHidden: false);
