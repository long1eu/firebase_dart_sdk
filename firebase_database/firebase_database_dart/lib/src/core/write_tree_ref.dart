/// The pending writes seen from one path. JS: `core/WriteTree.ts` (`WriteTreeRef`,
/// `writeTreeRef*`); Android: `core/WriteTreeRef.java`.
library;

import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/index.dart';
import 'package:firebase_database_dart/src/core/snap/named_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/view/cache_node.dart';
import 'package:firebase_database_dart/src/core/write_id.dart';
import 'package:firebase_database_dart/src/core/write_tree.dart';

/// [writeTree] at [treePath]: each method is the [WriteTree] method with the path filled in.
final class WriteTreeRef {
  /// Creates a reference.
  const WriteTreeRef(this.treePath, this.writeTree);

  /// The path.
  final Path treePath;

  /// The tree.
  final WriteTree writeTree;

  /// See [WriteTree.calcCompleteEventCache].
  Node? calcCompleteEventCache(
    Node? completeServerCache, {
    List<WriteId> writeIdsToExclude = const <WriteId>[],
    bool includeHiddenWrites = false,
  }) => throw UnimplementedError();

  /// See [WriteTree.calcCompleteEventChildren].
  Node calcCompleteEventChildren(Node completeServerChildren) =>
      throw UnimplementedError();

  /// See [WriteTree.calcEventCacheAfterServerOverwrite].
  Node? calcEventCacheAfterServerOverwrite(
    Path path,
    Node? existingEventSnap,
    Node? existingServerSnap,
  ) => throw UnimplementedError();

  /// See [WriteTree.shadowingWrite].
  Node? shadowingWrite(Path path) => throw UnimplementedError();

  /// See [WriteTree.calcNextNodeAfterPost].
  NamedNode? calcNextNodeAfterPost(
    Node completeServerData,
    NamedNode startPost,
    Index index, {
    required bool reverse,
  }) => throw UnimplementedError();

  /// See [WriteTree.calcCompleteChild].
  Node? calcCompleteChild(ChildKey childKey, CacheNode existingServerCache) =>
      throw UnimplementedError();

  /// The reference at child [childKey].
  WriteTreeRef child(ChildKey childKey) => throw UnimplementedError();
}
