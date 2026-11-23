/// The tree of pending user writes. JS: `core/WriteTree.ts` (`WriteTree`, `writeTree*`); Android:
/// `core/WriteTree.java`.
library;

import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/index.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/key_index.dart';
import 'package:firebase_database_dart/src/core/snap/named_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/user_write_record.dart';
import 'package:firebase_database_dart/src/core/util/immutable_tree.dart';
import 'package:firebase_database_dart/src/core/util/sorted_map.dart';
import 'package:firebase_database_dart/src/core/view/cache_node.dart';
import 'package:firebase_database_dart/src/core/write_id.dart';
import 'package:firebase_database_dart/src/core/write_tree_ref.dart';

/// All pending writes in order, with the visible ones layered into a [CompoundWrite].
final class WriteTree {
  /// Creates an empty tree. Android: `WriteTree()`.
  factory WriteTree() => WriteTree._();

  WriteTree._();

  /// The result of applying all visible writes: no hidden transaction writes, no writes that
  /// later writes shadow completely.
  CompoundWrite _visibleWrites = CompoundWrite.empty;

  /// Every pending write, visible or not, in id order.
  List<UserWriteRecord> _allWrites = <UserWriteRecord>[];

  WriteId _lastWriteId = -1;

  /// A reference to the writes at [path]. Android: `WriteTree.childWrites`.
  WriteTreeRef childWrites(Path path) => WriteTreeRef(path, this);

  /// Records an overwrite; ids must increase. Android: `WriteTree.addOverwrite`.
  void addOverwrite(
    Path path,
    Node snap,
    WriteId writeId, {
    required bool visible,
  }) {
    _checkWriteId(writeId);
    _allWrites.add(
      UserWriteRecord.overwrite(writeId, path, snap, visible: visible),
    );
    if (visible) {
      _visibleWrites = _visibleWrites.addWrite(path, snap);
    }
    _lastWriteId = writeId;
  }

  /// Records a merge; ids must increase. Android: `WriteTree.addMerge`.
  void addMerge(Path path, CompoundWrite changedChildren, WriteId writeId) {
    _checkWriteId(writeId);
    _allWrites.add(UserWriteRecord.merge(writeId, path, changedChildren));
    _visibleWrites = _visibleWrites.addWrites(path, changedChildren);
    _lastWriteId = writeId;
  }

  void _checkWriteId(WriteId writeId) {
    if (writeId <= _lastWriteId) {
      throw StateError('Stacking an older write on top of newer ones');
    }
  }

  /// The write [writeId], or null. Android: `WriteTree.getWrite`.
  UserWriteRecord? getWrite(WriteId writeId) {
    for (final UserWriteRecord record in _allWrites) {
      if (record.writeId == writeId) {
        return record;
      }
    }
    return null;
  }

  /// Removes and returns every write (Repo's purge). Android: `WriteTree.purgeAllWrites`; like
  /// Android, the last write id is kept, so later ids must still increase.
  List<UserWriteRecord> purgeAllWrites() {
    final List<UserWriteRecord> purged = List<UserWriteRecord>.of(_allWrites);
    _visibleWrites = CompoundWrite.empty;
    _allWrites = <UserWriteRecord>[];
    return purged;
  }

  /// Removes write [writeId]; returns whether it was visible and may need events. Throws
  /// [StateError] when there is no such write. Android: `WriteTree.removeWrite`.
  bool removeWrite(WriteId writeId) {
    final int idx = _allWrites.indexWhere(
      (UserWriteRecord record) => record.writeId == writeId,
    );
    if (idx < 0) {
      throw StateError('removeWrite called with nonexistent writeId');
    }
    final UserWriteRecord writeToRemove = _allWrites.removeAt(idx);

    bool removedWriteWasVisible = writeToRemove.visible;
    bool removedWriteOverlapsWithOtherWrites = false;
    // The children of a removed merge (relative paths) that no later write has rewritten yet.
    final List<Path>? unshadowedChildren = writeToRemove.isOverwrite
        ? null
        : <Path>[
            for (final MapEntry<Path, Node> entry
                in writeToRemove.merge!.entries)
              entry.key,
          ];
    // Later writes can shadow the removed one only when it was not folded into the node of an
    // earlier write above it: there it may have changed that node in ways a later rewrite of its
    // paths does not undo (a null child empties the node and drops its priority; a child written
    // under a leaf turns the leaf into children). JS and Android do not check this.
    final bool mayBeShadowed = !_foldedIntoEarlierWrite(writeToRemove, idx);
    int i = _allWrites.length - 1;
    while (removedWriteWasVisible && i >= 0) {
      final UserWriteRecord currentWrite = _allWrites[i];
      // Writes at unrelated paths, and merges at one location with no first key in common,
      // neither shadow nor overlap.
      if (currentWrite.visible &&
          (writeToRemove.path.contains(currentWrite.path) ||
              currentWrite.path.contains(writeToRemove.path)) &&
          !_mergesAtOneLocationApart(writeToRemove, currentWrite)) {
        if (i >= idx &&
            mayBeShadowed &&
            (_recordContainsPath(currentWrite, writeToRemove.path) ||
                (unshadowedChildren != null &&
                    _shadowsRemainingChildren(
                      currentWrite,
                      writeToRemove,
                      unshadowedChildren,
                    )))) {
          // Later writes shadowed the removed one completely.
          removedWriteWasVisible = false;
        } else if (!removedWriteOverlapsWithOtherWrites &&
            _recordsOverlap(writeToRemove, currentWrite)) {
          // Either we cover some writes or they cover part of us. JS and Android count only
          // writes at or below the removed one; a write above it that overlaps it counts too, as
          // the visible writes fold the data of one into the node of the other and removing the
          // removed one's paths would leave its data there or drop the other's.
          removedWriteOverlapsWithOtherWrites = true;
        }
      }
      i--;
    }

    if (!removedWriteWasVisible) {
      return false;
    } else if (removedWriteOverlapsWithOtherWrites) {
      // Some shadowing: rebuild the visible writes from scratch.
      _resetTree();
      return true;
    }
    // No shadowing: remove the write(s) from the visible writes.
    final Node? overwrite = writeToRemove.overwrite;
    if (overwrite != null) {
      _visibleWrites = _visibleWrites.removeWrite(writeToRemove.path);
    } else {
      for (final MapEntry<Path, Node> entry in writeToRemove.merge!.entries) {
        _visibleWrites = _visibleWrites.removeWrite(
          writeToRemove.path.childPath(entry.key),
        );
      }
    }
    return true;
  }

  /// The complete write data at [path], or null; server data is not considered. Android:
  /// `WriteTree.getCompleteWriteData`.
  Node? getCompleteWriteData(Path path) => _visibleWrites.getCompleteNode(path);

  /// The event cache at [treePath]: [completeServerCache] with the writes applied, skipping
  /// [writeIdsToExclude] and, unless [includeHiddenWrites], invisible writes. Android:
  /// `WriteTree.calcCompleteEventCache`.
  Node? calcCompleteEventCache(
    Path treePath,
    Node? completeServerCache, {
    List<WriteId> writeIdsToExclude = const <WriteId>[],
    bool includeHiddenWrites = false,
  }) {
    if (writeIdsToExclude.isEmpty && !includeHiddenWrites) {
      final Node? shadowingNode = _visibleWrites.getCompleteNode(treePath);
      if (shadowingNode != null) {
        return shadowingNode;
      }
      final CompoundWrite subMerge = _visibleWrites.childCompoundWrite(
        treePath,
      );
      if (subMerge.isEmpty) {
        return completeServerCache;
      } else if (completeServerCache == null &&
          !subMerge.hasCompleteWrite(Path.empty)) {
        // No underlying data and no complete shadow: not complete.
        return null;
      }
      return subMerge.apply(completeServerCache ?? ChildrenNode.empty);
    }
    final CompoundWrite merge = _visibleWrites.childCompoundWrite(treePath);
    if (!includeHiddenWrites && merge.isEmpty) {
      return completeServerCache;
    }
    if (!includeHiddenWrites &&
        completeServerCache == null &&
        !merge.hasCompleteWrite(Path.empty)) {
      return null;
    }
    bool filter(UserWriteRecord write) =>
        (write.visible || includeHiddenWrites) &&
        !writeIdsToExclude.contains(write.writeId) &&
        (write.path.contains(treePath) || treePath.contains(write.path));
    final CompoundWrite mergeAtPath = _layerTree(_allWrites, filter, treePath);
    return mergeAtPath.apply(completeServerCache ?? ChildrenNode.empty);
  }

  /// The children at [treePath] with writes over [completeServerChildren]: the children we have
  /// complete data for. Android: `WriteTree.calcCompleteEventChildren`.
  Node calcCompleteEventChildren(Path treePath, Node completeServerChildren) {
    Node completeChildren = ChildrenNode.empty;
    final Node? topLevelSet = _visibleWrites.getCompleteNode(treePath);
    if (topLevelSet != null) {
      if (!topLevelSet.isLeafNode) {
        // We shadow everything: return the children.
        topLevelSet.forEachChild(keyIndex, (ChildKey key, Node child) {
          completeChildren = completeChildren.updateImmediateChild(key, child);
          return false;
        });
      }
      return completeChildren;
    }
    // No top-level set: layer the writes over the existing children, then add the complete
    // children the writes set.
    final CompoundWrite merge = _visibleWrites.childCompoundWrite(treePath);
    completeServerChildren.forEachChild(keyIndex, (ChildKey key, Node child) {
      final Node node = merge
          .childCompoundWrite(Path.fromKeys(<ChildKey>[key]))
          .apply(child);
      completeChildren = completeChildren.updateImmediateChild(key, node);
      return false;
    });
    for (final NamedNode node in merge.getCompleteChildren()) {
      completeChildren = completeChildren.updateImmediateChild(
        node.name,
        node.node,
      );
    }
    return completeChildren;
  }

  /// The event cache at [childPath] below [treePath] after a server overwrite, or null when
  /// writes shadow it: the server data when no write touches it, else the server data with the
  /// writes applied. One of [existingEventSnap] and [existingServerSnap] must be set; like
  /// upstream, [existingServerSnap] is read whenever no write shadows the path. Android:
  /// `WriteTree.calcEventCacheAfterServerOverwrite`.
  Node? calcEventCacheAfterServerOverwrite(
    Path treePath,
    Path childPath,
    Node? existingEventSnap,
    Node? existingServerSnap,
  ) {
    if (existingEventSnap == null && existingServerSnap == null) {
      throw StateError(
        'Either existingEventSnap or existingServerSnap must exist',
      );
    }
    final Path path = treePath.childPath(childPath);
    if (_visibleWrites.hasCompleteWrite(path)) {
      // A write shadows the path completely: no events.
      return null;
    }
    final CompoundWrite childMerge = _visibleWrites.childCompoundWrite(path);
    if (childMerge.isEmpty) {
      // Not shadowed at all.
      return existingServerSnap!.getChild(childPath);
    }
    // Partially shadowed.
    return childMerge.apply(existingServerSnap!.getChild(childPath));
  }

  /// The complete child [childKey] at [treePath] with the writes applied, or null. Android:
  /// `WriteTree.calcCompleteChild`.
  Node? calcCompleteChild(
    Path treePath,
    ChildKey childKey,
    CacheNode existingServerSnap,
  ) {
    final Path path = treePath.child(childKey);
    final Node? shadowingNode = _visibleWrites.getCompleteNode(path);
    if (shadowingNode != null) {
      return shadowingNode;
    }
    if (existingServerSnap.isCompleteForChild(childKey)) {
      final CompoundWrite childMerge = _visibleWrites.childCompoundWrite(path);
      return childMerge.apply(
        existingServerSnap.node.getImmediateChild(childKey),
      );
    }
    return null;
  }

  /// The write shadowing [path] entirely (the child of a higher write when there is one), or
  /// null. Android: `WriteTree.shadowingWrite`.
  Node? shadowingWrite(Path path) => _visibleWrites.getCompleteNode(path);

  /// The next child after [post] in [index] order (reversed with [reverse]) with writes applied,
  /// or null. Used when a child leaves a limited query, to pull in the next one. Android:
  /// `WriteTree.calcNextNodeAfterPost`.
  NamedNode? calcNextNodeAfterPost(
    Path treePath,
    Node completeServerData,
    NamedNode post,
    Index index, {
    required bool reverse,
  }) {
    final CompoundWrite merge = _visibleWrites.childCompoundWrite(treePath);
    final Node toIterate =
        merge.getCompleteNode(Path.empty) ?? merge.apply(completeServerData);
    int compare(NamedNode a, NamedNode b) =>
        reverse ? index.compare(b, a) : index.compare(a, b);
    NamedNode? currentNext;
    toIterate.forEachChild(keyIndex, (ChildKey key, Node child) {
      final NamedNode node = NamedNode(key, child);
      if (compare(node, post) > 0 &&
          (currentNext == null || compare(node, currentNext!) < 0)) {
        currentNext = node;
      }
      return false;
    });
    return currentNext;
  }

  /// Whether a path written by [a] is, contains or lies under a path written by [b].
  ///
  /// JS and Android compare only the paths of the two records, so two merges at one location
  /// always count as overlapping and each acknowledgement rebuilds the visible writes: with n
  /// pending `update` calls at one location that is n rebuilds of n writes. Here a merge counts by
  /// the paths of its children, so merges of different children are removed one by one.
  /// The caller has ruled out [_mergesAtOneLocationApart].
  bool _recordsOverlap(UserWriteRecord a, UserWriteRecord b) {
    if (a.isOverwrite && b.isOverwrite) {
      return true;
    }
    final List<Path> aPaths = _writtenPaths(a);
    final List<Path> bPaths = _writtenPaths(b);
    for (final Path aPath in aPaths) {
      for (final Path bPath in bPaths) {
        if (aPath.contains(bPath) || bPath.contains(aPath)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Whether a visible write before index [idx] of the remaining writes writes a path strictly
  /// above a path [removed] writes, so that [removed] was folded into that write's node.
  bool _foldedIntoEarlierWrite(UserWriteRecord removed, int idx) {
    List<Path>? removedPaths;
    for (int i = 0; i < idx; i++) {
      final UserWriteRecord earlier = _allWrites[i];
      if (!earlier.visible ||
          !(earlier.path.contains(removed.path) ||
              removed.path.contains(earlier.path)) ||
          _mergesAtOneLocationApart(earlier, removed)) {
        continue;
      }
      removedPaths ??= _writtenPaths(removed);
      for (final Path above in _writtenPaths(earlier)) {
        for (final Path path in removedPaths) {
          if (above.length < path.length && above.contains(path)) {
            return true;
          }
        }
      }
    }
    return false;
  }

  /// The paths [record] writes: its path for an overwrite, each child's path for a merge.
  static List<Path> _writtenPaths(UserWriteRecord record) => record.isOverwrite
      ? <Path>[record.path]
      : <Path>[
          for (final MapEntry<Path, Node> entry in record.merge!.entries)
            record.path.childPath(entry.key),
        ];

  /// Whether [a] and [b] are merges at one location with no first key in common, checked without
  /// building paths. This is the common case of many `update` calls at one location; sharing a
  /// first key does not yet mean an overlap (`x/a` and `x/b`).
  bool _mergesAtOneLocationApart(UserWriteRecord a, UserWriteRecord b) {
    if (a.isOverwrite || b.isOverwrite || a.path != b.path) {
      return false;
    }
    final SortedMap<ChildKey, ImmutableTree<Node>> aChildren =
        a.merge!.writeTree.children;
    final bool shared = b.merge!.writeTree.children.inOrderTraversal(
      (ChildKey key, ImmutableTree<Node> _) => aChildren.containsKey(key),
    );
    return !shared;
  }

  /// Drops from [children] (paths relative to the merge [removed]) the ones that [later], a
  /// visible write made after [removed], rewrites; returns whether none is left. The caller has
  /// checked that one of the two paths contains the other and ruled out
  /// [_mergesAtOneLocationApart].
  ///
  /// A later write replaces everything at and below the paths it writes, so a merge whose every
  /// child is rewritten by later writes no longer shows, and removing it changes no visible data.
  /// JS and Android treat a write as shadowed only when one later write contains its whole path;
  /// with n pending `update` calls of the same children each acknowledgement there rebuilds the
  /// visible writes of the n writes, here it stops at the latest one.
  bool _shadowsRemainingChildren(
    UserWriteRecord later,
    UserWriteRecord removed,
    List<Path> children,
  ) {
    final Path path = removed.path;
    final List<Path> written = _writtenPaths(later);
    children.removeWhere((Path child) {
      final Path at = path.childPath(child);
      return written.any((Path w) => w.contains(at));
    });
    return children.isEmpty;
  }

  bool _recordContainsPath(UserWriteRecord writeRecord, Path path) {
    if (writeRecord.isOverwrite) {
      return writeRecord.path.contains(path);
    }
    // A child of the merge can contain [path] only when [path] lies strictly below the merge;
    // this is asked once per pending write on every acknowledgement, so the usual "no" must not
    // walk the merge.
    if (!writeRecord.path.contains(path)) {
      return false;
    }
    final Path relative = Path.relative(writeRecord.path, path);
    if (relative.isEmpty) {
      return false;
    }
    for (final MapEntry<Path, Node> entry in writeRecord.merge!.entries) {
      if (entry.key.contains(relative)) {
        return true;
      }
    }
    return false;
  }

  /// Re-layers the visible writes and merges. Android: `WriteTree.resetTree`.
  void _resetTree() {
    _visibleWrites = _layerTree(
      _allWrites,
      (UserWriteRecord write) => write.visible,
      Path.empty,
    );
    _lastWriteId = _allWrites.isEmpty ? -1 : _allWrites.last.writeId;
  }

  /// The merge at [treeRoot] of the [writes] that pass [filter]. Android:
  /// `WriteTree.layerTree`.
  static CompoundWrite _layerTree(
    List<UserWriteRecord> writes,
    bool Function(UserWriteRecord write) filter,
    Path treeRoot,
  ) {
    CompoundWrite compoundWrite = CompoundWrite.empty;
    for (final UserWriteRecord write in writes) {
      // A later set either aborts a relevant transaction or is on another branch, so it never
      // changes the data computed for that transaction.
      if (!filter(write)) {
        continue;
      }
      final Path writePath = write.path;
      final Node? overwrite = write.overwrite;
      if (overwrite != null) {
        if (treeRoot.contains(writePath)) {
          compoundWrite = compoundWrite.addWrite(
            Path.relative(treeRoot, writePath),
            overwrite,
          );
        } else if (writePath.contains(treeRoot)) {
          compoundWrite = compoundWrite.addWrite(
            Path.empty,
            overwrite.getChild(Path.relative(writePath, treeRoot)),
          );
        }
        // Else no overlap: ignore the write.
      } else {
        final CompoundWrite merge = write.merge!;
        if (treeRoot.contains(writePath)) {
          compoundWrite = compoundWrite.addWrites(
            Path.relative(treeRoot, writePath),
            merge,
          );
        } else if (writePath.contains(treeRoot)) {
          final Path relativePath = Path.relative(writePath, treeRoot);
          if (relativePath.isEmpty) {
            compoundWrite = compoundWrite.addWrites(Path.empty, merge);
          } else {
            final Node? deepNode = merge.getCompleteNode(relativePath);
            if (deepNode != null) {
              compoundWrite = compoundWrite.addWrite(Path.empty, deepNode);
            }
          }
        }
        // Else no overlap: ignore the write.
      }
    }
    return compoundWrite;
  }
}
