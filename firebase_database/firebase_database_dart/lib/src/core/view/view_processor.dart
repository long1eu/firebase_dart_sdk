/// Applies operations to a view cache. JS: `core/view/ViewProcessor.ts`; Android:
/// `core/view/ViewProcessor.java`.
///
/// The server-side operations (server overwrite and merge, ack, listen complete) live in the part
/// file `view_processor_server.dart`.
library;

import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/operation/operation.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/key_index.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/util/immutable_tree.dart';
import 'package:firebase_database_dart/src/core/view/cache_node.dart';
import 'package:firebase_database_dart/src/core/view/change.dart';
import 'package:firebase_database_dart/src/core/view/complete_child_source.dart';
import 'package:firebase_database_dart/src/core/view/filter/child_change_accumulator.dart';
import 'package:firebase_database_dart/src/core/view/filter/node_filter.dart';
import 'package:firebase_database_dart/src/core/view/view_cache.dart';
import 'package:firebase_database_dart/src/core/write_tree_ref.dart';

part 'view_processor_server.dart';

/// The new view cache and the changes that led to it.
final class ProcessorResult {
  /// Creates a result.
  const ProcessorResult(this.viewCache, this.changes);

  /// The new cache.
  final ViewCache viewCache;

  /// The child and value changes.
  final List<Change> changes;
}

/// Computes view caches and changes from operations, using [filter] for the query.
final class ViewProcessor {
  /// Creates a processor.
  const ViewProcessor(this.filter);

  /// The query's filter.
  final NodeFilter filter;

  /// Applies [operation] to [oldViewCache] with the pending [writesCache]; [optCompleteCache] is a
  /// complete server cache from a parent view, if any (JS `viewProcessorApplyOperation`).
  ///
  /// The changes end with a value change when the new event cache is complete and anything
  /// changed (JS `viewProcessorMaybeAddValueEvent`); a partial event cache never gets one.
  ProcessorResult applyOperation(
    ViewCache oldViewCache,
    Operation operation,
    WriteTreeRef writesCache,
    Node? optCompleteCache,
  ) {
    final ChildChangeAccumulator accumulator = ChildChangeAccumulator();
    final ViewCache newViewCache;
    switch (operation) {
      case Overwrite():
        if (operation.source.fromUser) {
          newViewCache = _applyUserOverwrite(
            oldViewCache,
            operation.path,
            operation.snapshot,
            writesCache,
            optCompleteCache,
            accumulator,
          );
        } else {
          // Filter the node if it is a tagged update, or if it was filtered before and the update
          // is not at the root (an update at the root may, and must, mark it unfiltered again).
          final bool filterServerNode =
              operation.source.tagged ||
              (oldViewCache.serverCache.filtered && !operation.path.isEmpty);
          newViewCache = _applyServerOverwrite(
            oldViewCache,
            operation.path,
            operation.snapshot,
            writesCache,
            optCompleteCache,
            filterServerNode,
            accumulator,
          );
        }
      case Merge():
        if (operation.source.fromUser) {
          newViewCache = _applyUserMerge(
            oldViewCache,
            operation.path,
            operation.children,
            writesCache,
            optCompleteCache,
            accumulator,
          );
        } else {
          // Filter the node if it is a tagged update or was filtered before.
          final bool filterServerNode =
              operation.source.tagged || oldViewCache.serverCache.filtered;
          newViewCache = _applyServerMerge(
            oldViewCache,
            operation.path,
            operation.children,
            writesCache,
            optCompleteCache,
            filterServerNode,
            accumulator,
          );
        }
      case AckUserWrite():
        newViewCache = !operation.revert
            ? _ackUserWrite(
                oldViewCache,
                operation.path,
                operation.affectedTree,
                writesCache,
                optCompleteCache,
                accumulator,
              )
            : revertUserWrite(
                oldViewCache,
                operation.path,
                writesCache,
                optCompleteCache,
                accumulator,
              );
      case ListenComplete():
        newViewCache = _listenComplete(
          oldViewCache,
          operation.path,
          writesCache,
          accumulator,
        );
    }
    final List<Change> changes = accumulator.changes;
    _maybeAddValueEvent(oldViewCache, newViewCache, changes);
    return ProcessorResult(newViewCache, changes);
  }

  /// JS `viewProcessorMaybeAddValueEvent`.
  static void _maybeAddValueEvent(
    ViewCache oldViewCache,
    ViewCache newViewCache,
    List<Change> changes,
  ) {
    final CacheNode eventSnap = newViewCache.eventCache;
    if (!eventSnap.fullyInitialized) {
      return;
    }
    final Node node = eventSnap.node;
    final bool isLeafOrEmpty = node.isLeafNode || node.isEmpty;
    final Node? oldCompleteSnap = oldViewCache.completeEventSnap;
    if (changes.isNotEmpty ||
        oldCompleteSnap == null ||
        (isLeafOrEmpty && node != oldCompleteSnap) ||
        node.priority != oldCompleteSnap.priority) {
      changes.add(Change.value(node));
    }
  }

  /// JS `viewProcessorApplyUserOverwrite`.
  ViewCache _applyUserOverwrite(
    ViewCache oldViewCache,
    Path changePath,
    Node changedSnap,
    WriteTreeRef writesCache,
    Node? completeCache,
    ChildChangeAccumulator accumulator,
  ) {
    final CacheNode oldEventSnap = oldViewCache.eventCache;
    final WriteTreeCompleteChildSource source = WriteTreeCompleteChildSource(
      writesCache,
      oldViewCache,
      completeCache,
    );
    final ChildKey? childKey = changePath.front;
    if (childKey == null) {
      final Node newEventCache = filter.updateFullNode(
        oldEventSnap.node,
        changedSnap,
        accumulator,
      );
      return oldViewCache.updateEventSnap(
        newEventCache,
        complete: true,
        filtered: filter.filtersNodes,
      );
    }
    if (childKey.isPriorityKey) {
      final Node newEventCache = filter.updatePriority(
        oldEventSnap.node,
        changedSnap,
      );
      return oldViewCache.updateEventSnap(
        newEventCache,
        complete: oldEventSnap.fullyInitialized,
        filtered: oldEventSnap.filtered,
      );
    }
    final Path childChangePath = changePath.popFront();
    final Node oldChild = oldEventSnap.node.getImmediateChild(childKey);
    final Node newChild;
    if (childChangePath.isEmpty) {
      // A child overwrite: replace the child.
      newChild = changedSnap;
    } else {
      final Node? childNode = source.getCompleteChild(childKey);
      if (childNode == null) {
        // There is no complete child node available.
        newChild = ChildrenNode.empty;
      } else if (childChangePath.back!.isPriorityKey &&
          _ignoresPriority(childNode.getChild(childChangePath.parent!))) {
        // A priority update on an empty node: if the node exists on the server, the server
        // sends the priority down with it, so ignore it for now. A node that keeps a priority
        // takes it, as the server does.
        newChild = childNode;
      } else {
        newChild = childNode.updateChild(childChangePath, changedSnap);
      }
    }
    if (oldChild == newChild &&
        ChildrenNode.sameHiddenAlong(oldChild, newChild, childChangePath)) {
      return oldViewCache;
    }
    final Node newEventSnap = filter.updateChild(
      oldEventSnap.node,
      childKey,
      newChild,
      childChangePath,
      source,
      accumulator,
    );
    return oldViewCache.updateEventSnap(
      newEventSnap,
      complete: oldEventSnap.fullyInitialized,
      filtered: filter.filtersNodes,
    );
  }

  /// Whether a priority written on [node] is ignored: it is empty and holds no hidden state.
  static bool _ignoresPriority(Node node) => !ChildrenNode.takesPriority(node);

  /// JS `viewProcessorApplyUserMerge`: the writes to children in view first (a limit window may
  /// make room), then the others; priority writes after every child write, as the server applies
  /// one update (production check 39 Q1, Q6: a priority lands only on a node the children leave
  /// with a value or with hidden state).
  ViewCache _applyUserMerge(
    ViewCache viewCache,
    Path path,
    CompoundWrite changedChildren,
    WriteTreeRef writesCache,
    Node? serverCache,
    ChildChangeAccumulator accumulator,
  ) {
    assert(
      changedChildren.rootWrite() == null,
      "Can't have a merge that is an overwrite",
    );
    ViewCache curViewCache = viewCache;
    final List<MapEntry<Path, Node>> writes = changedChildren.entries.toList();
    for (final bool priorities in <bool>[false, true]) {
      for (final bool inView in <bool>[true, false]) {
        for (final MapEntry<Path, Node> entry in writes) {
          final Path writePath = path.childPath(entry.key);
          if ((writePath.back?.isPriorityKey ?? false) == priorities &&
              viewCache.eventCache.isCompleteForChild(writePath.front!) ==
                  inView) {
            curViewCache = _applyUserOverwrite(
              curViewCache,
              writePath,
              entry.value,
              writesCache,
              serverCache,
              accumulator,
            );
          }
        }
      }
    }
    return curViewCache;
  }

  /// Reverts a rejected user write at [path] (JS `viewProcessorRevertUserWrite`).
  ///
  /// Differs from JS where a remaining write shadows [path]; see the comment in the body.
  ViewCache revertUserWrite(
    ViewCache viewCache,
    Path path,
    WriteTreeRef writesCache,
    Node? optCompleteServerCache,
    ChildChangeAccumulator accumulator,
  ) {
    // JS: `if (writeTreeRefShadowingWrite(writesCache, path) != null) return viewCache;`.
    // That holds for a write made after the reverted one, but then WriteTree.removeWrite
    // returns false and no revert reaches the view. A write made before the reverted one can
    // shadow [path] too (a transaction aborted below an ancestor transaction still in flight),
    // and the view still holds the reverted data. So the view takes what the write tree holds:
    // a write over the whole view replaces the view; otherwise the code below recomputes the
    // touched child as for an unshadowed revert. The incomplete-cache branch below must not
    // see a write over the whole view: it would keep only that node's children (a leaf gives
    // an empty node).
    final Node? viewShadow = writesCache.shadowingWrite(Path.empty);
    if (viewShadow != null) {
      return viewCache.updateEventSnap(
        filter.updateFullNode(
          viewCache.eventCache.node,
          viewShadow,
          accumulator,
        ),
        complete: true,
        filtered: filter.filtersNodes,
      );
    }
    final WriteTreeCompleteChildSource source = WriteTreeCompleteChildSource(
      writesCache,
      viewCache,
      optCompleteServerCache,
    );
    final Node oldEventCache = viewCache.eventCache.node;
    Node newEventCache;
    final ChildKey? front = path.front;
    if (front == null || front.isPriorityKey) {
      final Node newNode;
      if (viewCache.serverCache.fullyInitialized) {
        newNode = writesCache.calcCompleteEventCache(
          viewCache.completeServerSnap,
        )!;
      } else {
        final Node serverChildren = viewCache.serverCache.node;
        assert(
          serverChildren is ChildrenNode,
          'serverChildren would be complete if leaf node',
        );
        newNode = writesCache.calcCompleteEventChildren(serverChildren);
      }
      newEventCache = filter.updateFullNode(
        oldEventCache,
        newNode,
        accumulator,
      );
    } else {
      final ChildKey childKey = front;
      Node? newChild = writesCache.calcCompleteChild(
        childKey,
        viewCache.serverCache,
      );
      if (newChild == null &&
          viewCache.serverCache.isCompleteForChild(childKey)) {
        newChild = oldEventCache.getImmediateChild(childKey);
      }
      if (newChild != null) {
        newEventCache = filter.updateChild(
          oldEventCache,
          childKey,
          newChild,
          path.popFront(),
          source,
          accumulator,
        );
      } else if (viewCache.eventCache.node.hasChild(childKey)) {
        // No complete child available: delete the existing one, if any.
        newEventCache = filter.updateChild(
          oldEventCache,
          childKey,
          ChildrenNode.empty,
          path.popFront(),
          source,
          accumulator,
        );
      } else {
        newEventCache = oldEventCache;
      }
      if (newEventCache.isEmpty && viewCache.serverCache.fullyInitialized) {
        // We might have reverted all child writes. Maybe the old event was a leaf node.
        final Node? complete = writesCache.calcCompleteEventCache(
          viewCache.completeServerSnap,
        );
        if (complete != null && complete.isLeafNode) {
          newEventCache = filter.updateFullNode(
            newEventCache,
            complete,
            accumulator,
          );
        }
      }
    }
    final bool complete =
        viewCache.serverCache.fullyInitialized ||
        writesCache.shadowingWrite(Path.empty) != null;
    return viewCache.updateEventSnap(
      newEventCache,
      complete: complete,
      filtered: filter.filtersNodes,
    );
  }
}
