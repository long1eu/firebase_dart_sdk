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
  /// Creates a reference. Android: `WriteTreeRef(Path, WriteTree)`.
  const WriteTreeRef(this.treePath, this.writeTree);

  /// The path.
  final Path treePath;

  /// The tree.
  final WriteTree writeTree;

  /// See [WriteTree.calcCompleteEventCache]. Android: `WriteTreeRef.calcCompleteEventCache`.
  Node? calcCompleteEventCache(
    Node? completeServerCache, {
    List<WriteId> writeIdsToExclude = const <WriteId>[],
    bool includeHiddenWrites = false,
  }) => writeTree.calcCompleteEventCache(
    treePath,
    completeServerCache,
    writeIdsToExclude: writeIdsToExclude,
    includeHiddenWrites: includeHiddenWrites,
  );

  /// See [WriteTree.calcCompleteEventChildren]. Android:
  /// `WriteTreeRef.calcCompleteEventChildren`.
  Node calcCompleteEventChildren(Node completeServerChildren) =>
      writeTree.calcCompleteEventChildren(treePath, completeServerChildren);

  /// See [WriteTree.calcEventCacheAfterServerOverwrite]. Android:
  /// `WriteTreeRef.calcEventCacheAfterServerOverwrite`.
  Node? calcEventCacheAfterServerOverwrite(
    Path path,
    Node? existingEventSnap,
    Node? existingServerSnap,
  ) => writeTree.calcEventCacheAfterServerOverwrite(
    treePath,
    path,
    existingEventSnap,
    existingServerSnap,
  );

  /// See [WriteTree.shadowingWrite]; [path] is relative to [treePath]. Android:
  /// `WriteTreeRef.shadowingWrite`.
  Node? shadowingWrite(Path path) =>
      writeTree.shadowingWrite(treePath.childPath(path));

  /// See [WriteTree.calcNextNodeAfterPost]. Android: `WriteTreeRef.calcNextNodeAfterPost`.
  NamedNode? calcNextNodeAfterPost(
    Node completeServerData,
    NamedNode startPost,
    Index index, {
    required bool reverse,
  }) => writeTree.calcNextNodeAfterPost(
    treePath,
    completeServerData,
    startPost,
    index,
    reverse: reverse,
  );

  /// See [WriteTree.calcCompleteChild]. Android: `WriteTreeRef.calcCompleteChild`.
  Node? calcCompleteChild(ChildKey childKey, CacheNode existingServerCache) =>
      writeTree.calcCompleteChild(treePath, childKey, existingServerCache);

  /// The reference at child [childKey]. Android: `WriteTreeRef.child`.
  WriteTreeRef child(ChildKey childKey) =>
      WriteTreeRef(treePath.child(childKey), writeTree);
}
