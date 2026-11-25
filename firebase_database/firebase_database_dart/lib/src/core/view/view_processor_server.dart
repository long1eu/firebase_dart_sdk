// JS: core/view/ViewProcessor.ts (server operations); Android: core/view/ViewProcessor.java.
part of 'view_processor.dart';

/// The server-side operations of [ViewProcessor]: server overwrite and merge, ack, listen
/// complete, and the event cache they lead to. JS: `core/view/ViewProcessor.ts`.
extension _ServerOperations on ViewProcessor {
  /// JS `viewProcessorGenerateEventCacheAfterServerEvent`.
  ViewCache _generateEventCacheAfterServerEvent(
    ViewCache viewCache,
    Path changePath,
    WriteTreeRef writesCache,
    CompleteChildSource source,
    ChildChangeAccumulator accumulator,
  ) {
    final CacheNode oldEventSnap = viewCache.eventCache;
    if (writesCache.shadowingWrite(changePath) != null) {
      // A shadowing write: ignore the change.
      return viewCache;
    }
    final Node newEventCache;
    final ChildKey? childKey = changePath.front;
    if (childKey == null || _staleEventLeafAbove(viewCache, changePath)) {
      assert(
        viewCache.serverCache.fullyInitialized,
        'If change path is empty, we must have complete server data',
      );
      if (viewCache.serverCache.filtered) {
        // Only apply writes to complete children, or we might raise events for incomplete
        // children: with filtered server data, deep writes cannot be known to be complete.
        final Node? serverCache = viewCache.completeServerSnap;
        final Node completeChildren = serverCache is ChildrenNode
            ? serverCache
            : ChildrenNode.empty;
        final Node completeEventChildren = writesCache
            .calcCompleteEventChildren(completeChildren);
        newEventCache = filter.updateFullNode(
          viewCache.eventCache.node,
          completeEventChildren,
          accumulator,
        );
      } else {
        final Node completeNode = writesCache.calcCompleteEventCache(
          viewCache.completeServerSnap,
        )!;
        newEventCache = filter.updateFullNode(
          viewCache.eventCache.node,
          completeNode,
          accumulator,
        );
      }
    } else if (childKey.isPriorityKey) {
      assert(
        changePath.length == 1,
        "Can't have a priority with additional path components",
      );
      final Node oldEventNode = oldEventSnap.node;
      // We might have overwrites for this priority.
      final Node? updatedPriority = writesCache
          .calcEventCacheAfterServerOverwrite(
            changePath,
            oldEventNode,
            viewCache.serverCache.node,
          );
      final Node? completeServer = viewCache.completeServerSnap;
      if (updatedPriority != null &&
          ViewProcessor._ignoresPriority(oldEventNode) &&
          completeServer != null) {
        // The node is empty here only because of a pending write below it; the server node took
        // the priority and keeps it when that write empties it. Rebuild from the writes over the
        // server node.
        newEventCache = filter.updateFullNode(
          oldEventNode,
          writesCache.calcCompleteEventCache(completeServer)!,
          accumulator,
        );
      } else {
        newEventCache = updatedPriority != null
            ? filter.updatePriority(oldEventNode, updatedPriority)
            : oldEventNode;
      }
    } else {
      final Path childChangePath = changePath.popFront();
      final Node? newEventChild;
      if (oldEventSnap.isCompleteForChild(childKey)) {
        final Node? eventChildUpdate = writesCache
            .calcEventCacheAfterServerOverwrite(
              changePath,
              oldEventSnap.node,
              viewCache.serverCache.node,
            );
        final Node oldChild = oldEventSnap.node.getImmediateChild(childKey);
        if (eventChildUpdate != null &&
            (childChangePath.back?.isPriorityKey ?? false) &&
            ViewProcessor._ignoresPriority(
              oldChild.getChild(childChangePath.parent!),
            )) {
          // As for the view's own priority above: the owner is empty only because of a pending
          // write; rebuild the child from the writes over the server cache.
          newEventChild =
              writesCache.calcCompleteChild(childKey, viewCache.serverCache) ??
              oldChild;
        } else {
          newEventChild = eventChildUpdate != null
              ? oldChild.updateChild(childChangePath, eventChildUpdate)
              : oldChild;
        }
      } else {
        newEventChild = writesCache.calcCompleteChild(
          childKey,
          viewCache.serverCache,
        );
      }
      newEventCache = newEventChild != null
          ? filter.updateChild(
              oldEventSnap.node,
              childKey,
              newEventChild,
              childChangePath,
              source,
              accumulator,
            )
          // No complete child available, or no change.
          : oldEventSnap.node;
    }
    return viewCache.updateEventSnap(
      newEventCache,
      complete: oldEventSnap.fullyInitialized || changePath.isEmpty,
      filtered: filter.filtersNodes,
    );
  }

  /// Whether the event cache of [viewCache] holds a leaf above [changePath] while the server
  /// cache is complete: a change below a leaf cannot be applied child by child, because the
  /// writes that made the leaf may no longer shadow the server data (a write at `b/c` replaced
  /// by a later one there, over a server leaf). The event cache is then built again from the
  /// server cache. No JS or Android counterpart.
  bool _staleEventLeafAbove(ViewCache viewCache, Path changePath) {
    if (!viewCache.serverCache.fullyInitialized ||
        viewCache.serverCache.filtered) {
      return false;
    }
    Node node = viewCache.eventCache.node;
    for (final ChildKey key in changePath.segments) {
      if (key.isPriorityKey) {
        return false;
      }
      if (node.isLeafNode) {
        return true;
      }
      node = node.getImmediateChild(key);
    }
    return false;
  }

  /// JS `viewProcessorApplyServerOverwrite`.
  ViewCache _applyServerOverwrite(
    ViewCache oldViewCache,
    Path changePath,
    Node changedSnap,
    WriteTreeRef writesCache,
    Node? completeCache,
    bool filterServerNode,
    ChildChangeAccumulator accumulator,
  ) {
    final CacheNode oldServerSnap = oldViewCache.serverCache;
    final Node newServerCache;
    final NodeFilter serverFilter = filterServerNode
        ? filter
        : filter.indexedFilter;
    final ChildKey? childKey = changePath.front;
    if (childKey == null) {
      newServerCache = serverFilter.updateFullNode(
        oldServerSnap.node,
        changedSnap,
        null,
      );
    } else if (serverFilter.filtersNodes && !oldServerSnap.filtered) {
      // We want to filter the server node but have not yet: simulate a full update.
      final Node newServerNode = oldServerSnap.node.updateChild(
        changePath,
        changedSnap,
      );
      newServerCache = serverFilter.updateFullNode(
        oldServerSnap.node,
        newServerNode,
        null,
      );
    } else {
      if (!oldServerSnap.isCompleteForPath(changePath) &&
          changePath.length > 1) {
        // We don't update incomplete nodes with updates intended for other listeners.
        return oldViewCache;
      }
      final Path childChangePath = changePath.popFront();
      final Node childNode = oldServerSnap.node.getImmediateChild(childKey);
      final Node newChildNode = childNode.updateChild(
        childChangePath,
        changedSnap,
      );
      if (childKey.isPriorityKey) {
        newServerCache = serverFilter.updatePriority(
          oldServerSnap.node,
          newChildNode,
        );
      } else {
        newServerCache = serverFilter.updateChild(
          oldServerSnap.node,
          childKey,
          newChildNode,
          childChangePath,
          noCompleteChildSource,
          null,
        );
      }
    }
    final ViewCache newViewCache = oldViewCache.updateServerSnap(
      newServerCache,
      complete: oldServerSnap.fullyInitialized || changePath.isEmpty,
      filtered: serverFilter.filtersNodes,
    );
    final WriteTreeCompleteChildSource source = WriteTreeCompleteChildSource(
      writesCache,
      newViewCache,
      completeCache,
    );
    return _generateEventCacheAfterServerEvent(
      newViewCache,
      changePath,
      writesCache,
      source,
      accumulator,
    );
  }

  /// JS `viewProcessorApplyServerMerge` (Android `applyServerMerge` for the [CompoundWrite]):
  /// the children the server cache has first (a limit window may make room), then the others.
  ViewCache _applyServerMerge(
    ViewCache viewCache,
    Path path,
    CompoundWrite changedChildren,
    WriteTreeRef writesCache,
    Node? serverCache,
    bool filterServerNode,
    ChildChangeAccumulator accumulator,
  ) {
    // Without a cache yet, this merge was meant for an earlier listen at this location: ignore
    // it and wait for the complete data coming soon.
    if (viewCache.serverCache.node.isEmpty &&
        !viewCache.serverCache.fullyInitialized) {
      return viewCache;
    }
    assert(
      changedChildren.rootWrite() == null,
      "Can't have a merge that is an overwrite",
    );
    ViewCache curViewCache = viewCache;
    final CompoundWrite actualMerge = path.isEmpty
        ? changedChildren
        : CompoundWrite.empty.addWrites(path, changedChildren);
    final Node serverNode = viewCache.serverCache.node;
    final Map<ChildKey, CompoundWrite> childCompoundWrites = actualMerge
        .childCompoundWrites();
    void apply(ChildKey childKey, CompoundWrite childMerge) {
      final Node serverChild = serverNode.getImmediateChild(childKey);
      curViewCache = _applyServerOverwrite(
        curViewCache,
        Path.fromKeys(<ChildKey>[childKey]),
        childMerge.apply(serverChild),
        writesCache,
        serverCache,
        filterServerNode,
        accumulator,
      );
    }

    // The node's own priority as the server applies one update: before the children when the
    // node takes a priority now (emptying it then keeps it), else after them.
    final CompoundWrite? priority = childCompoundWrites[ChildKey.priority];
    final bool priorityFirst =
        !serverNode.isEmpty || ChildrenNode.keepsPriority(serverNode);
    if (priority != null && priorityFirst) {
      apply(ChildKey.priority, priority);
    }
    for (final MapEntry<ChildKey, CompoundWrite> childMerge
        in childCompoundWrites.entries) {
      if (serverNode.hasChild(childMerge.key)) {
        apply(childMerge.key, childMerge.value);
      }
    }
    for (final MapEntry<ChildKey, CompoundWrite> childMerge
        in childCompoundWrites.entries) {
      final ChildKey childKey = childMerge.key;
      final bool isUnknownDeepMerge =
          !viewCache.serverCache.isCompleteForChild(childKey) &&
          childMerge.value.rootWrite() == null;
      if (!childKey.isPriorityKey &&
          !serverNode.hasChild(childKey) &&
          !isUnknownDeepMerge) {
        apply(childKey, childMerge.value);
      }
    }
    if (priority != null && !priorityFirst) {
      apply(ChildKey.priority, priority);
    }
    return curViewCache;
  }

  /// JS `viewProcessorAckUserWrite` (`ViewProcessor.ts:670-704`): the write is no longer
  /// shadowing, so the server cache of the affected paths is applied again as a server update.
  ViewCache _ackUserWrite(
    ViewCache viewCache,
    Path ackPath,
    ImmutableTree<bool> affectedTree,
    WriteTreeRef writesCache,
    Node? completeCache,
    ChildChangeAccumulator accumulator,
  ) {
    if (writesCache.shadowingWrite(ackPath) != null) {
      return viewCache;
    }
    // Only filter the server node if it is currently filtered.
    final bool filterServerNode = viewCache.serverCache.filtered;
    final CacheNode serverCache = viewCache.serverCache;
    final Path? leafPath = _serverLeafAbove(serverCache, ackPath);
    if (leafPath != null) {
      // The server turned an ancestor of the write into a leaf: apply that leaf. Applying the
      // empty child below it, as JS and Android do, would remove the leaf from the event cache.
      return _applyServerOverwrite(
        viewCache,
        leafPath,
        serverCache.node.getChild(leafPath),
        writesCache,
        completeCache,
        filterServerNode,
        accumulator,
      );
    }
    if (affectedTree.value != null) {
      // An overwrite.
      if ((ackPath.isEmpty && serverCache.fullyInitialized) ||
          serverCache.isCompleteForPath(ackPath)) {
        return _applyServerOverwrite(
          viewCache,
          ackPath,
          ChildrenNode.storedChild(serverCache.node, ackPath),
          writesCache,
          completeCache,
          filterServerNode,
          accumulator,
        );
      } else if (ackPath.isEmpty) {
        // Acking data at this location without full data: apply what the cache has as a merge.
        CompoundWrite changedChildren = CompoundWrite.empty;
        serverCache.node.forEachChild(keyIndex, (ChildKey name, Node node) {
          changedChildren = changedChildren.addChildWrite(name, node);
          return false;
        });
        return _applyServerMerge(
          viewCache,
          ackPath,
          changedChildren,
          writesCache,
          completeCache,
          filterServerNode,
          accumulator,
        );
      } else {
        return viewCache;
      }
    }
    // A merge.
    CompoundWrite changedChildren = CompoundWrite.empty;
    affectedTree.forEach((Path mergePath, bool value) {
      final Path serverCachePath = ackPath.childPath(mergePath);
      if (serverCache.isCompleteForPath(serverCachePath)) {
        changedChildren = changedChildren.addWrite(
          mergePath,
          ChildrenNode.storedChild(serverCache.node, serverCachePath),
        );
      }
    });
    return _applyServerMerge(
      viewCache,
      ackPath,
      changedChildren,
      writesCache,
      completeCache,
      filterServerNode,
      accumulator,
    );
  }

  /// The shortest path from the root of [serverCache] to [ackPath] (inclusive) at which the
  /// complete server data is a leaf, or null. No JS or Android counterpart.
  Path? _serverLeafAbove(CacheNode serverCache, Path ackPath) {
    Node node = serverCache.node;
    final List<ChildKey> prefix = <ChildKey>[];
    for (int i = 0; i <= ackPath.length; i++) {
      final Path at = Path.fromKeys(List<ChildKey>.of(prefix));
      if (node.isLeafNode) {
        return serverCache.isCompleteForPath(at) ? at : null;
      }
      if (i == ackPath.length) {
        return null;
      }
      final ChildKey key = ackPath.segments[i];
      if (key.isPriorityKey) {
        return null;
      }
      prefix.add(key);
      node = node.getImmediateChild(key);
    }
    return null;
  }

  /// JS `viewProcessorListenComplete`: the server cache is complete at [path].
  ViewCache _listenComplete(
    ViewCache viewCache,
    Path path,
    WriteTreeRef writesCache,
    ChildChangeAccumulator accumulator,
  ) {
    final CacheNode oldServerNode = viewCache.serverCache;
    final ViewCache newViewCache = viewCache.updateServerSnap(
      oldServerNode.node,
      complete: oldServerNode.fullyInitialized || path.isEmpty,
      filtered: oldServerNode.filtered,
    );
    return _generateEventCacheAfterServerEvent(
      newViewCache,
      path,
      writesCache,
      noCompleteChildSource,
      accumulator,
    );
  }
}
