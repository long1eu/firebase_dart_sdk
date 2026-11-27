/// A set of writes at paths, used for merges. JS: `core/CompoundWrite.ts`; Android:
/// `core/CompoundWrite.java`.
library;

import 'package:collection/collection.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/key_index.dart';
import 'package:firebase_database_dart/src/core/snap/named_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/util/immutable_tree.dart';

const DeepCollectionEquality _deepEquality = DeepCollectionEquality();

/// An immutable tree of complete writes (nodes) at paths; a write shadows writes below it.
final class CompoundWrite {
  /// Wraps [writeTree].
  const CompoundWrite(this.writeTree);

  static final CompoundWrite _empty = CompoundWrite(
    ImmutableTree<Node>.empty(),
  );

  /// The empty write.
  static CompoundWrite get empty => _empty;

  /// A write of a JSON `update` map whose keys are relative paths.
  factory CompoundWrite.fromValue(Map<String, Object?> merge) {
    ImmutableTree<Node> writeTree = ImmutableTree<Node>.empty();
    for (final MapEntry<String, Object?> entry in merge.entries) {
      writeTree = writeTree.setTree(
        Path(entry.key),
        ImmutableTree<Node>(nodeFromJson(entry.value)),
      );
    }
    return CompoundWrite(writeTree);
  }

  /// A write of one node per child key.
  factory CompoundWrite.fromChildMerge(Map<ChildKey, Node> merge) {
    ImmutableTree<Node> writeTree = ImmutableTree<Node>.empty();
    for (final MapEntry<ChildKey, Node> entry in merge.entries) {
      writeTree = writeTree.setTree(
        Path.fromKeys(<ChildKey>[entry.key]),
        ImmutableTree<Node>(entry.value),
      );
    }
    return CompoundWrite(writeTree);
  }

  /// A write of one node per relative path.
  factory CompoundWrite.fromPathMerge(Map<Path, Node> merge) {
    ImmutableTree<Node> writeTree = ImmutableTree<Node>.empty();
    for (final MapEntry<Path, Node> entry in merge.entries) {
      writeTree = writeTree.setTree(
        entry.key,
        ImmutableTree<Node>(entry.value),
      );
    }
    return CompoundWrite(writeTree);
  }

  /// The tree of written nodes.
  final ImmutableTree<Node> writeTree;

  /// This write with [node] written at [path].
  CompoundWrite addWrite(Path path, Node node) {
    if (path.isEmpty) {
      return CompoundWrite(ImmutableTree<Node>(node));
    }
    final PathAndValue<Node>? rootMost = writeTree.findRootMostValueAndPath(
      path,
    );
    if (rootMost != null) {
      final Path relativePath = Path.relative(rootMost.path, path);
      Node value = rootMost.value;
      final ChildKey? back = relativePath.back;
      if (back != null && back.isPriorityKey) {
        final Node target = value.getChild(relativePath.parent!);
        if (!ChildrenNode.takesPriority(target)) {
          // Ignore priority updates on empty nodes, except one that holds hidden state.
          return this;
        }
      }
      value = value.updateChild(relativePath, node);
      return CompoundWrite(writeTree.set(rootMost.path, value));
    }
    return CompoundWrite(writeTree.setTree(path, ImmutableTree<Node>(node)));
  }

  /// This write with [node] written at child [key].
  CompoundWrite addChildWrite(ChildKey key, Node node) =>
      addWrite(Path.fromKeys(<ChildKey>[key]), node);

  /// This write with every write of [updates] (one update) added below [path], in the server's
  /// two passes (see [apply]): the values first, then the priorities, parents first.
  CompoundWrite addWrites(Path path, CompoundWrite updates) {
    CompoundWrite result = this;
    for (final MapEntry<Path, Node> write in writesInServerOrder(updates)) {
      result = result.addWrite(path.childPath(write.key), write.value);
    }
    return result;
  }

  /// This write without the writes at and below [path].
  CompoundWrite removeWrite(Path path) {
    if (path.isEmpty) {
      return empty;
    }
    return CompoundWrite(writeTree.setTree(path, ImmutableTree<Node>.empty()));
  }

  /// Whether [path] is covered by a complete write.
  bool hasCompleteWrite(Path path) => getCompleteNode(path) != null;

  /// The write at the root, or null.
  Node? rootWrite() => writeTree.value;

  /// The complete node at [path] if a write covers it, or null.
  Node? getCompleteNode(Path path) {
    final PathAndValue<Node>? rootMost = writeTree.findRootMostValueAndPath(
      path,
    );
    if (rootMost == null) {
      return null;
    }
    return ChildrenNode.storedChild(
      rootMost.value,
      Path.relative(rootMost.path, path),
    );
  }

  /// The complete children written directly at the root.
  List<NamedNode> getCompleteChildren() {
    final List<NamedNode> children = <NamedNode>[];
    final Node? root = writeTree.value;
    if (root != null) {
      if (!root.isLeafNode) {
        root.forEachChild(keyIndex, (ChildKey key, Node child) {
          children.add(NamedNode(key, child));
          return false;
        });
      }
    } else {
      writeTree.forEachChild(
        (ChildKey key, Node value) => children.add(NamedNode(key, value)),
      );
    }
    return children;
  }

  /// The part of this write below [path], relative to it.
  CompoundWrite childCompoundWrite(Path path) {
    if (path.isEmpty) {
      return this;
    }
    final Node? shadowingNode = getCompleteNode(path);
    if (shadowingNode != null) {
      return CompoundWrite(ImmutableTree<Node>(shadowingNode));
    }
    return CompoundWrite(writeTree.subtree(path));
  }

  /// The writes per immediate child.
  Map<ChildKey, CompoundWrite> childCompoundWrites() =>
      <ChildKey, CompoundWrite>{
        for (final MapEntry<ChildKey, ImmutableTree<Node>> entry
            in writeTree.children.entries)
          entry.key: CompoundWrite(entry.value),
      };

  /// Whether nothing is written.
  bool get isEmpty => writeTree.isEmpty;

  /// [node] with every write applied, as the server applies one update (production check 39,
  /// Q1, Q6, Q10 and F1 to F9, both key orders): pass 1 writes every value, at any depth (a node
  /// whose last child goes keeps its priority as an emptied node); pass 2 writes every priority,
  /// parents before children, each landing only on a node that then has a value or holds
  /// hidden state ([ChildrenNode.takesPriority]); a null priority removes a kept one.
  Node apply(Node node) {
    Node result = node;
    for (final MapEntry<Path, Node> write in writesInServerOrder(this)) {
      final ChildKey? back = write.key.back;
      if (back != null &&
          back.isPriorityKey &&
          !ChildrenNode.takesPriority(result.getChild(write.key.parent!))) {
        continue;
      }
      result = result.updateChild(write.key, write.value);
    }
    return result;
  }

  /// The writes as a JSON map from path strings to values (export form when [exportFormat]).
  ///
  /// Keys are `Path.toString()` (`/a/b`, `/` for the root); [CompoundWrite.fromValue] reads them
  /// back.
  Map<String, Object?> toJson({bool exportFormat = false}) {
    final Map<String, Object?> writes = <String, Object?>{};
    writeTree.forEach((Path path, Node value) {
      writes[path.toString()] = value.toJson(exportFormat: exportFormat);
    });
    return writes;
  }

  /// Every write with its path.
  Iterable<MapEntry<Path, Node>> get entries => writeTree.entries;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CompoundWrite &&
          _deepEquality.equals(
            other.toJson(exportFormat: true),
            toJson(exportFormat: true),
          );

  @override
  int get hashCode => _deepEquality.hash(toJson(exportFormat: true));

  @override
  String toString() => 'CompoundWrite{${toJson(exportFormat: true)}}';
}

/// The writes in the order the server applies one update: every value write, then every
/// priority write by depth, parents first (production check 39 Q10, F1 to F9).
List<MapEntry<Path, Node>> writesInServerOrder(CompoundWrite write) {
  final List<MapEntry<Path, Node>> values = <MapEntry<Path, Node>>[];
  final List<MapEntry<Path, Node>> priorities = <MapEntry<Path, Node>>[];
  for (final MapEntry<Path, Node> entry in write.writeTree.entries) {
    ((entry.key.back?.isPriorityKey ?? false) ? priorities : values).add(entry);
  }
  // Parents first; a stable sort, and writes of one depth never meet.
  mergeSort(
    priorities,
    compare: (MapEntry<Path, Node> a, MapEntry<Path, Node> b) =>
        a.key.length - b.key.length,
  );
  return <MapEntry<Path, Node>>[...values, ...priorities];
}
