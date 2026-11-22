/// A set of writes at paths, used for merges. JS: `core/CompoundWrite.ts`; Android:
/// `core/CompoundWrite.java`.
library;

import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/named_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/util/immutable_tree.dart';

/// An immutable tree of complete writes (nodes) at paths; a write shadows writes below it.
final class CompoundWrite {
  /// Wraps [writeTree].
  const CompoundWrite(this.writeTree);

  /// The empty write.
  static CompoundWrite get empty => throw UnimplementedError();

  /// A write of a JSON `update` map whose keys are relative paths.
  factory CompoundWrite.fromValue(Map<String, Object?> merge) => throw UnimplementedError();

  /// A write of one node per child key.
  factory CompoundWrite.fromChildMerge(Map<ChildKey, Node> merge) => throw UnimplementedError();

  /// A write of one node per relative path.
  factory CompoundWrite.fromPathMerge(Map<Path, Node> merge) => throw UnimplementedError();

  /// The tree of written nodes.
  final ImmutableTree<Node> writeTree;

  /// This write with [node] written at [path].
  CompoundWrite addWrite(Path path, Node node) => throw UnimplementedError();

  /// This write with [node] written at child [key].
  CompoundWrite addChildWrite(ChildKey key, Node node) => throw UnimplementedError();

  /// This write with every write of [updates] added below [path].
  CompoundWrite addWrites(Path path, CompoundWrite updates) => throw UnimplementedError();

  /// This write without the writes at and below [path].
  CompoundWrite removeWrite(Path path) => throw UnimplementedError();

  /// Whether [path] is covered by a complete write.
  bool hasCompleteWrite(Path path) => throw UnimplementedError();

  /// The write at the root, or null.
  Node? rootWrite() => throw UnimplementedError();

  /// The complete node at [path] if a write covers it, or null.
  Node? getCompleteNode(Path path) => throw UnimplementedError();

  /// The complete children written directly at the root.
  List<NamedNode> getCompleteChildren() => throw UnimplementedError();

  /// The part of this write below [path], relative to it.
  CompoundWrite childCompoundWrite(Path path) => throw UnimplementedError();

  /// The writes per immediate child.
  Map<ChildKey, CompoundWrite> childCompoundWrites() => throw UnimplementedError();

  /// Whether nothing is written.
  bool get isEmpty => throw UnimplementedError();

  /// [node] with every write applied.
  Node apply(Node node) => throw UnimplementedError();

  /// The writes as a JSON map from path strings to values (export form when [exportFormat]).
  Map<String, Object?> toJson({bool exportFormat = false}) => throw UnimplementedError();

  /// Every write with its path.
  Iterable<MapEntry<Path, Node>> get entries => throw UnimplementedError();

  @override
  bool operator ==(Object other) => throw UnimplementedError();

  @override
  int get hashCode => throw UnimplementedError();

  @override
  String toString() => throw UnimplementedError();
}
