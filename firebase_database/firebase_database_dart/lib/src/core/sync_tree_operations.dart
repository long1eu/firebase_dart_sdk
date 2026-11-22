// Android: core/SyncTree.java (applyOperationToSyncPoints and helpers); JS: core/SyncTree.ts.
part of 'sync_tree.dart';

/// How [SyncTree] applies an operation to its sync points (Android
/// `SyncTree.applyOperationToSyncPoints` and helpers).
extension _SyncTreeOperations on SyncTree {
  /// Android `SyncTree.applyTaggedOperation`.
  List<Event> _applyTaggedOperation(QuerySpec query, Operation operation) {
    final Path queryPath = query.path;
    final SyncPoint? syncPoint = _syncPointTree.get(queryPath);
    if (syncPoint == null) {
      throw StateError("Missing sync point for query tag that we're tracking");
    }
    return syncPoint.applyOperation(
      operation,
      _pendingWriteTree.childWrites(queryPath),
      null,
    );
  }

  /// Android `SyncTree.applyOperationToSyncPoints`: descendants first (events depth first).
  List<Event> _applyOperationToSyncPoints(Operation operation) =>
      _applyOperationHelper(
        operation,
        _syncPointTree,
        null,
        _pendingWriteTree.childWrites(Path.empty),
      );

  /// Android `SyncTree.applyOperationHelper`.
  List<Event> _applyOperationHelper(
    Operation operation,
    ImmutableTree<SyncPoint> syncPointTree,
    Node? serverCache,
    WriteTreeRef writesCache,
  ) {
    final ChildKey? childKey = operation.path.front;
    if (childKey == null) {
      return _applyOperationDescendantsHelper(
        operation,
        syncPointTree,
        serverCache,
        writesCache,
      );
    }
    final SyncPoint? syncPoint = syncPointTree.value;
    // Without cached server data, see if this sync point has it.
    Node? resolvedServerCache = serverCache;
    if (resolvedServerCache == null && syncPoint != null) {
      resolvedServerCache = syncPoint.completeServerCache(Path.empty);
    }
    final List<Event> events = <Event>[];
    final Operation? childOperation = operation.operationForChild(childKey);
    final ImmutableTree<SyncPoint>? childTree =
        syncPointTree.children[childKey];
    if (childTree != null && childOperation != null) {
      events.addAll(
        _applyOperationHelper(
          childOperation,
          childTree,
          resolvedServerCache?.getImmediateChild(childKey),
          writesCache.child(childKey),
        ),
      );
    }
    if (syncPoint != null) {
      events.addAll(
        syncPoint.applyOperation(operation, writesCache, resolvedServerCache),
      );
    }
    return events;
  }

  /// Android `SyncTree.applyOperationDescendantsHelper`.
  List<Event> _applyOperationDescendantsHelper(
    Operation operation,
    ImmutableTree<SyncPoint> syncPointTree,
    Node? serverCache,
    WriteTreeRef writesCache,
  ) {
    final SyncPoint? syncPoint = syncPointTree.value;
    Node? resolvedServerCache = serverCache;
    if (resolvedServerCache == null && syncPoint != null) {
      resolvedServerCache = syncPoint.completeServerCache(Path.empty);
    }
    final List<Event> events = <Event>[];
    for (final MapEntry<ChildKey, ImmutableTree<SyncPoint>> entry
        in syncPointTree.children.entries) {
      final ChildKey key = entry.key;
      final Operation? childOperation = operation.operationForChild(key);
      if (childOperation != null) {
        events.addAll(
          _applyOperationDescendantsHelper(
            childOperation,
            entry.value,
            resolvedServerCache?.getImmediateChild(key),
            writesCache.child(key),
          ),
        );
      }
    }
    if (syncPoint != null) {
      events.addAll(
        syncPoint.applyOperation(operation, writesCache, resolvedServerCache),
      );
    }
    return events;
  }
}
