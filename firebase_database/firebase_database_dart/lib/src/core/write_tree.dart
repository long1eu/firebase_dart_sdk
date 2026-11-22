/// The tree of pending user writes. JS: `core/WriteTree.ts` (`WriteTree`, `writeTree*`); Android:
/// `core/WriteTree.java`.
library;

import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/index.dart';
import 'package:firebase_database_dart/src/core/snap/named_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/user_write_record.dart';
import 'package:firebase_database_dart/src/core/view/cache_node.dart';
import 'package:firebase_database_dart/src/core/write_id.dart';
import 'package:firebase_database_dart/src/core/write_tree_ref.dart';

/// All pending writes in order, with the visible ones layered into a [CompoundWrite].
final class WriteTree {
  /// Creates an empty tree.
  factory WriteTree() => throw UnimplementedError();

  /// A reference to the writes at [path].
  WriteTreeRef childWrites(Path path) => throw UnimplementedError();

  /// Records an overwrite; ids must increase.
  void addOverwrite(Path path, Node snap, WriteId writeId, {required bool visible}) =>
      throw UnimplementedError();

  /// Records a merge; ids must increase.
  void addMerge(Path path, CompoundWrite changedChildren, WriteId writeId) =>
      throw UnimplementedError();

  /// The write [writeId], or null.
  UserWriteRecord? getWrite(WriteId writeId) => throw UnimplementedError();

  /// Removes and returns every write (Repo's purge).
  List<UserWriteRecord> purgeAllWrites() => throw UnimplementedError();

  /// Removes write [writeId]; returns whether it was visible and may need events.
  bool removeWrite(WriteId writeId) => throw UnimplementedError();

  /// The complete write data at [path], or null.
  Node? getCompleteWriteData(Path path) => throw UnimplementedError();

  /// The event cache at [treePath]: [completeServerCache] with the writes applied, skipping
  /// [writeIdsToExclude] and, unless [includeHiddenWrites], invisible writes.
  Node? calcCompleteEventCache(
    Path treePath,
    Node? completeServerCache, {
    List<WriteId> writeIdsToExclude = const <WriteId>[],
    bool includeHiddenWrites = false,
  }) => throw UnimplementedError();

  /// The children at [treePath] with writes over [completeServerChildren].
  Node calcCompleteEventChildren(Path treePath, Node completeServerChildren) =>
      throw UnimplementedError();

  /// The event cache at [childPath] below [treePath] after a server overwrite, or null when
  /// writes shadow it.
  Node? calcEventCacheAfterServerOverwrite(
    Path treePath,
    Path childPath,
    Node? existingEventSnap,
    Node? existingServerSnap,
  ) => throw UnimplementedError();

  /// The complete child [childKey] at [treePath], or null.
  Node? calcCompleteChild(Path treePath, ChildKey childKey, CacheNode existingServerSnap) =>
      throw UnimplementedError();

  /// The write shadowing [path] entirely, or null.
  Node? shadowingWrite(Path path) => throw UnimplementedError();

  /// The next child after [post] in [index] order with writes applied, or null.
  NamedNode? calcNextNodeAfterPost(
    Path treePath,
    Node completeServerData,
    NamedNode post,
    Index index, {
    required bool reverse,
  }) => throw UnimplementedError();
}
