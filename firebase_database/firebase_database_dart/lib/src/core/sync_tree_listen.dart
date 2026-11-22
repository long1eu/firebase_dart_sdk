// Android: core/SyncTree.java (ListenContainer); JS: core/SyncTree.ts
// (syncTreeCreateListenerForView_).
part of 'sync_tree.dart';

/// The hash and completion of one listen (Android `SyncTree.ListenContainer`, JS
/// `syncTreeCreateListenerForView_`).
final class _ListenContainer implements ListenHashProvider {
  _ListenContainer(this._syncTree, this._view)
    : tag = _syncTree.tagForQuery(_view.query);

  final SyncTree _syncTree;
  final View _view;

  /// The tag of the view's query when the listen started.
  final Tag? tag;

  /// Android `ListenContainer.getCompoundHash`.
  @override
  WireCompoundHash compoundHash() {
    final CompoundHash hash = CompoundHash.fromNode(_view.serverCache);
    return WireCompoundHash(
      posts: <String>[for (final Path path in hash.posts) path.toString()],
      hashes: hash.hashes,
    );
  }

  /// Android `ListenContainer.getSimpleHash`.
  @override
  String simpleHash() => _view.serverCache.hash();

  /// Android `ListenContainer.shouldIncludeCompoundHash`.
  @override
  bool shouldIncludeCompoundHash() =>
      estimateSerializedNodeSize(_view.serverCache) >
      sizeThresholdForCompoundHash;

  /// Android `ListenContainer.onListenComplete`: a listen complete, or on [error] the removal of
  /// every registration of the query (all of them, not just the one that failed).
  List<Event> onListenComplete(DatabaseError? error) {
    if (error == null) {
      final Tag? tag = this.tag;
      return tag != null
          ? _syncTree.applyTaggedListenComplete(tag)
          : _syncTree.applyListenComplete(_view.query.path);
    }
    return _syncTree.removeAllEventRegistrations(_view.query, error);
  }
}

/// Listens and registrations of [SyncTree] (Android `SyncTree.addEventRegistration`,
/// `removeEventRegistration`, `setupListener` and helpers).
extension _SyncTreeListens on SyncTree {
  void _startListening(QuerySpec query, Tag? tag, _ListenContainer container) =>
      _pendingProviderCalls.add(
        () => _listenProvider.startListening(
          query,
          tag,
          container,
          container.onListenComplete,
        ),
      );

  void _stopListening(QuerySpec query, Tag? tag) =>
      _pendingProviderCalls.add(() {
        _listenProvider.stopListening(query, tag);
        return const <Event>[];
      });

  /// The complete server cache on the way from the root to [path], and whether a complete view
  /// is there (the loop at the top of Android `SyncTree.addEventRegistration` and
  /// `getServerValue`); [path]'s own sync point is not included.
  ({Node? serverCache, bool foundAncestorDefaultView}) _ancestorServerCache(
    Path path,
  ) {
    Node? serverCache;
    bool foundAncestorDefaultView = false;
    _syncPointTree.forEachOnPath(path, (Path pathToSyncPoint, SyncPoint sp) {
      serverCache ??= sp.completeServerCache(
        Path.relative(pathToSyncPoint, path),
      );
      foundAncestorDefaultView = foundAncestorDefaultView || sp.hasCompleteView;
    });
    return (
      serverCache: serverCache,
      foundAncestorDefaultView: foundAncestorDefaultView,
    );
  }

  /// The body of Android `SyncTree.addEventRegistration`, inside the transaction.
  List<Event> _addEventRegistration(
    EventRegistration registration, {
    required bool skipListenerSetup,
    required CacheNode? preloadedServerCache,
  }) {
    final QuerySpec query = registration.querySpec;
    final Path path = query.path;

    final ({Node? serverCache, bool foundAncestorDefaultView}) ancestors =
        _ancestorServerCache(path);
    Node? serverCacheNode = ancestors.serverCache;
    bool foundAncestorDefaultView = ancestors.foundAncestorDefaultView;

    SyncPoint? syncPoint = _syncPointTree.get(path);
    if (syncPoint == null) {
      syncPoint = SyncPoint(_persistenceManager);
      _syncPointTree = _syncPointTree.set(path, syncPoint);
    } else {
      foundAncestorDefaultView =
          foundAncestorDefaultView || syncPoint.hasCompleteView;
      serverCacheNode ??= syncPoint.completeServerCache(Path.empty);
    }

    _persistenceManager.setQueryActive(query);

    final CacheNode serverCache;
    if (serverCacheNode != null) {
      serverCache = CacheNode(
        serverCacheNode.withIndex(query.index),
        fullyInitialized: true,
        filtered: false,
      );
    } else {
      final CacheNode persistentServerCache =
          preloadedServerCache ?? _persistenceManager.serverCache(query);
      if (persistentServerCache.fullyInitialized) {
        serverCache = persistentServerCache;
      } else {
        Node node = ChildrenNode.empty;
        _syncPointTree.subtree(path).forEachChild((
          ChildKey key,
          SyncPoint childSyncPoint,
        ) {
          final Node? completeCache = childSyncPoint.completeServerCache(
            Path.empty,
          );
          if (completeCache != null) {
            node = node.updateImmediateChild(key, completeCache);
          }
        });
        // Fill the node with any children persistence has.
        persistentServerCache.node.forEachChild(keyIndex, (
          ChildKey key,
          Node child,
        ) {
          if (!node.hasChild(key)) {
            node = node.updateImmediateChild(key, child);
          }
          return false;
        });
        serverCache = CacheNode(
          node.withIndex(query.index),
          fullyInitialized: false,
          filtered: false,
        );
      }
    }

    final bool viewAlreadyExists = syncPoint.viewExistsForQuery(query);
    if (!viewAlreadyExists && !query.loadsAllData) {
      // A tag for this query.
      assert(
        !_queryToTag.containsKey(query),
        'View does not exist but we have a tag',
      );
      final Tag tag = Tag(_nextQueryTag++);
      _queryToTag[query] = tag;
      _tagToQuery[tag] = query;
    }
    final List<Event> events = syncPoint.addEventRegistration(
      registration,
      _pendingWriteTree.childWrites(path),
      serverCache,
    );
    if (!viewAlreadyExists && !foundAncestorDefaultView && !skipListenerSetup) {
      _setupListener(query, syncPoint.viewForQuery(query)!);
    }
    return events;
  }

  /// The body of Android `SyncTree.removeEventRegistration(QuerySpec, EventRegistration,
  /// DatabaseError, boolean)`, inside the transaction.
  List<Event> _removeEventRegistrationInTransaction(
    QuerySpec query,
    EventRegistration? registration,
    DatabaseError? cancelError, {
    required bool skipDedup,
  }) {
    final Path path = query.path;
    final SyncPoint? maybeSyncPoint = _syncPointTree.get(path);
    // A removal on a default query affects all queries at that location; one on an indexed
    // query, even without other constraints, does not: so this checks isDefault.
    if (maybeSyncPoint == null ||
        !(query.isDefault || maybeSyncPoint.viewExistsForQuery(query))) {
      // Already removed.
      return const <Event>[];
    }
    final SyncPointRemoval removal = maybeSyncPoint.removeEventRegistration(
      query,
      registration,
      cancelError,
    );
    if (maybeSyncPoint.isEmpty) {
      _syncPointTree = _syncPointTree.remove(path);
    }
    final List<QuerySpec> removed = removal.removed;
    // Indexed queries without constraints shadow too: check loadsAllData, not isDefault.
    bool removingDefault = false;
    for (final QuerySpec queryRemoved in removed) {
      _persistenceManager.setQueryInactive(queryRemoved);
      removingDefault = removingDefault || queryRemoved.loadsAllData;
    }

    if (!skipDedup) {
      final bool covered =
          _syncPointTree.findOnPath<bool>(
            path,
            (Path _, SyncPoint sp) => sp.hasCompleteView ? true : null,
          ) ??
          false;
      if (removingDefault && !covered) {
        final ImmutableTree<SyncPoint> subtree = _syncPointTree.subtree(path);
        // Child listeners that the removed default listen shadowed are started now.
        if (!subtree.isEmpty) {
          for (final View view in _collectDistinctViewsForSubTree(subtree)) {
            final QuerySpec newQuery = view.query;
            final _ListenContainer container = _ListenContainer(this, view);
            _startListening(
              _queryForListening(newQuery),
              container.tag,
              container,
            );
          }
        }
      }
      // Not covered by a listen above: stop this one (with a cancel error the provider already
      // dropped it). A removed default was the only listen here.
      if (!covered && removed.isNotEmpty && cancelError == null) {
        if (removingDefault) {
          _stopListening(_queryForListening(query), null);
        } else {
          for (final QuerySpec queryToRemove in removed) {
            final Tag? tag = tagForQuery(queryToRemove);
            assert(tag != null, 'Removed query without a tag');
            _stopListening(_queryForListening(queryToRemove), tag);
          }
        }
      }
    }
    _removeTags(removed);
    return removal.cancelEvents;
  }

  /// JS `syncTreeCollectDistinctViewsForSubTree_` (Android
  /// `SyncTree.collectDistinctViewsForSubTree`): one complete view stands for everything below
  /// it.
  List<View> _collectDistinctViewsForSubTree(
    ImmutableTree<SyncPoint> subtree,
  ) => subtree.fold<List<View>>((
    Path _,
    SyncPoint? maybeChildSyncPoint,
    Map<ChildKey, List<View>> childMap,
  ) {
    final View? completeView = maybeChildSyncPoint?.completeView;
    if (completeView != null) {
      return <View>[completeView];
    }
    return <View>[
      ...?maybeChildSyncPoint?.queryViews,
      for (final List<View> childViews in childMap.values) ...childViews,
    ];
  });

  /// Android `SyncTree.removeTags`.
  void _removeTags(List<QuerySpec> queries) {
    for (final QuerySpec removedQuery in queries) {
      if (!removedQuery.loadsAllData) {
        final Tag? tag = _queryToTag.remove(removedQuery);
        assert(tag != null, 'Removed query without a tag');
        _tagToQuery.remove(tag);
      }
    }
  }

  /// Android `SyncTree.setupListener` (shadowing as JS `syncTreeSetupListener_`).
  void _setupListener(QuerySpec query, View view) {
    final Tag? tag = tagForQuery(query);
    final _ListenContainer container = _ListenContainer(this, view);
    _startListening(_queryForListening(query), tag, container);

    final ImmutableTree<SyncPoint> subtree = _syncPointTree.subtree(query.path);
    if (tag != null) {
      assert(
        !(subtree.value?.hasCompleteView ?? false),
        "If we're adding a query, it shouldn't be shadowed",
      );
      return;
    }
    // A default listen shadows everything at or below this location.
    final List<QuerySpec> queriesToStop = subtree.fold<List<QuerySpec>>((
      Path relativePath,
      SyncPoint? maybeChildSyncPoint,
      Map<ChildKey, List<QuerySpec>> childMap,
    ) {
      final View? completeView = maybeChildSyncPoint?.completeView;
      if (!relativePath.isEmpty && completeView != null) {
        return <QuerySpec>[completeView.query];
      }
      return <QuerySpec>[
        for (final View v in maybeChildSyncPoint?.queryViews ?? const <View>[])
          v.query,
        for (final List<QuerySpec> childQueries in childMap.values)
          ...childQueries,
      ];
    });
    for (final QuerySpec queryToStop in queriesToStop) {
      _stopListening(_queryForListening(queryToStop), tagForQuery(queryToStop));
    }
  }
}

/// Android `SyncTree.queryForListening`: a query that loads all data is listened to as the
/// default query.
QuerySpec _queryForListening(QuerySpec query) =>
    query.loadsAllData && !query.isDefault
    ? QuerySpec.defaultAt(query.path)
    : query;
