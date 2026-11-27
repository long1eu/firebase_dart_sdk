/// The tree of sync points and pending writes. JS: `core/SyncTree.ts`; Android:
/// `core/SyncTree.java` (including its inner `KeepSyncedEventRegistration` and `ListenContainer`).
///
/// Tags start at 1 per [SyncTree] instance (a field counter, not JS's module global): two trees,
/// hence two Repos, each give their first filtered query tag 1. Pinned by the sync tree API
/// contract with two instances.
///
/// Differences from Android, each on purpose:
///
/// * Calls to the [ListenProvider] are made after the persistence transaction of the entry point
///   closes, in the order Android makes them: the `.info` provider applies data to its tree
///   synchronously inside `startListening`, which would nest transactions otherwise.
/// * `setQueryInactive` is called for each removed query (iOS `FSyncTree.m`), not for the
///   query passed in once per removed query.
/// * Shadowing below a new default listen and the views re-listened after a default listen goes
///   use JS's fold, which stops at a complete view (Android's `foreach` also visits below it and
///   stops listens that were never started).
/// * `skipDedup` skips only the listen bookkeeping; tags are still removed and the cancel events
///   returned (JS `syncTreeRemoveEventRegistration`; Android returns null).
/// * `calcCompleteEventCache` looks at the root sync point too (JS `findOnPath`).
/// * `getServerValue` does not leave an empty sync point in the tree.
library;

import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/connection/listen_hash_provider.dart';
import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/core/event_registration.dart';
import 'package:firebase_database_dart/src/core/listen_provider.dart';
import 'package:firebase_database_dart/src/core/operation/operation.dart';
import 'package:firebase_database_dart/src/core/operation/operation_source.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/persistence/noop_persistence_manager.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_manager.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/compound_hash.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/key_index.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/range_merge.dart';
import 'package:firebase_database_dart/src/core/sync_point.dart';
import 'package:firebase_database_dart/src/core/sync_tree_api.dart';
import 'package:firebase_database_dart/src/core/tag.dart';
import 'package:firebase_database_dart/src/core/user_write_record.dart';
import 'package:firebase_database_dart/src/core/util/immutable_tree.dart';
import 'package:firebase_database_dart/src/core/util/node_size_estimator.dart';
import 'package:firebase_database_dart/src/core/util/server_values.dart';
import 'package:firebase_database_dart/src/core/view/cache_node.dart';
import 'package:firebase_database_dart/src/core/view/change.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:firebase_database_dart/src/core/view/view.dart';
import 'package:firebase_database_dart/src/core/view/view_cache.dart';
import 'package:firebase_database_dart/src/core/write_id.dart';
import 'package:firebase_database_dart/src/core/write_tree.dart';
import 'package:firebase_database_dart/src/core/write_tree_ref.dart';

part 'sync_tree_listen.dart';
part 'sync_tree_operations.dart';
part 'sync_tree_registrations.dart';

/// Cached server data larger than this (estimated JSON bytes) makes a listen send a compound
/// hash.
const int sizeThresholdForCompoundHash = 1024;

/// The sync tree: sync points by path, the pending write tree, tags (from a counter of this
/// instance, starting at 1), keep-synced queries, with every entry point wrapped in a
/// [PersistenceManager.runInTransaction].
final class SyncTree implements SyncTreeApi {
  /// Creates a tree listening through [listenProvider] and persisting through
  /// [persistenceManager] (a no-op one by default). Android `SyncTree(Context,
  /// PersistenceManager, ListenProvider)`.
  factory SyncTree({
    required ListenProvider listenProvider,
    PersistenceManager? persistenceManager,
  }) => SyncTree._(
    listenProvider,
    persistenceManager ?? NoopPersistenceManager(),
  );

  SyncTree._(this._listenProvider, this._persistenceManager);

  final ListenProvider _listenProvider;
  final PersistenceManager _persistenceManager;
  ImmutableTree<SyncPoint> _syncPointTree = ImmutableTree<SyncPoint>.empty();
  final WriteTree _pendingWriteTree = WriteTree();
  final Map<Tag, QuerySpec> _tagToQuery = <Tag, QuerySpec>{};
  final Map<QuerySpec, Tag> _queryToTag = <QuerySpec, Tag>{};
  final Set<QuerySpec> _keepSyncedQueries = <QuerySpec>{};
  int _nextQueryTag = 1;

  /// Listen provider calls made during the current entry point, run once its transaction closes.
  final List<List<Event> Function()> _pendingProviderCalls =
      <List<Event> Function()>[];

  /// The sync points (Android `SyncTree.getSyncPointTree`, for tests).
  ImmutableTree<SyncPoint> get syncPointTree => _syncPointTree;

  /// The pending writes (for tests).
  WriteTree get pendingWriteTree => _pendingWriteTree;

  /// Whether no query is registered (Android `SyncTree.isEmpty`).
  @override
  bool get isEmpty => _syncPointTree.isEmpty;

  /// Runs [body] in one persistence transaction, then the listen provider calls it queued, and
  /// returns the events of both.
  List<Event> _run(List<Event> Function() body) {
    final List<Event> events;
    try {
      events = _persistenceManager.runInTransaction(body);
    } on Object {
      _pendingProviderCalls.clear();
      rethrow;
    }
    if (_pendingProviderCalls.isEmpty) {
      return events;
    }
    final List<List<Event> Function()> calls = List<List<Event> Function()>.of(
      _pendingProviderCalls,
    );
    _pendingProviderCalls.clear();
    final List<Event> result = List<Event>.of(events);
    for (final List<Event> Function() call in calls) {
      result.addAll(call());
    }
    return result;
  }

  /// Android `SyncTree.applyUserOverwrite`.
  @override
  List<Event> applyUserOverwrite(
    Path path,
    Node newDataUnresolved,
    Node newData,
    WriteId writeId, {
    required bool visible,
    required bool persist,
  }) {
    assert(
      visible || !persist,
      "We shouldn't be persisting non-visible writes.",
    );
    return _run(() {
      if (persist) {
        _persistenceManager.saveUserOverwrite(path, newDataUnresolved, writeId);
      }
      _pendingWriteTree.addOverwrite(path, newData, writeId, visible: visible);
      if (!visible) {
        return const <Event>[];
      }
      return _applyOperationToSyncPoints(
        Overwrite(OperationSource.user, path, newData),
      );
    });
  }

  /// Android `SyncTree.applyUserMerge`. A merge that writes [path] itself (a root write, key `''`)
  /// is kept and applied as an overwrite of [path], which it is: the write tree's shadowing and the
  /// view processor take a merge to write below its path only. It is persisted as given. The
  /// public API refuses such a key (`validateFirebaseMergeDataArg`); a root merge still comes from
  /// a stored merge replayed from disk and from core tests that call the repo directly.
  @override
  List<Event> applyUserMerge(
    Path path,
    CompoundWrite unresolvedChildren,
    CompoundWrite children,
    WriteId writeId, {
    required bool persist,
  }) => _run(() {
    if (persist) {
      _persistenceManager.saveUserMerge(path, unresolvedChildren, writeId);
    }
    if (children.rootWrite() != null) {
      final Node newData = children.apply(ChildrenNode.empty);
      _pendingWriteTree.addOverwrite(path, newData, writeId, visible: true);
      return _applyOperationToSyncPoints(
        Overwrite(OperationSource.user, path, newData),
      );
    }
    _pendingWriteTree.addMerge(path, children, writeId);
    return _applyOperationToSyncPoints(
      Merge(OperationSource.user, path, children),
    );
  });

  /// Android `SyncTree.ackUserWrite`, with the server values given instead of a clock. The
  /// removal from the write log and the promotion into the server cache share one transaction.
  @override
  List<Event> ackUserWrite(
    WriteId writeId, {
    required bool revert,
    required bool persist,
    required Map<String, Object?> serverValues,
  }) => _run(() {
    if (persist) {
      _persistenceManager.removeUserWrite(writeId);
    }
    final UserWriteRecord? write = _pendingWriteTree.getWrite(writeId);
    if (write == null) {
      // purgeOutstandingWrites removed it: an answer the connection received before the purge is
      // delivered after it. Android drops the answer in the connection; JS asserts here.
      return const <Event>[];
    }
    final bool needToReevaluate = _pendingWriteTree.removeWrite(writeId);
    if (write.visible && !revert) {
      Node? existing(Path p, List<WriteId> exclude) =>
          calcCompleteEventCache(p, writeIdsToExclude: exclude);
      final Node? overwrite = write.overwrite;
      if (overwrite != null) {
        _persistenceManager.applyUserWriteToServerCache(
          write.path,
          resolveDeferredValueTree(
            write.path,
            overwrite,
            existing,
            serverValues,
          ),
        );
      } else {
        _persistenceManager.applyUserMergeToServerCache(
          write.path,
          resolveDeferredValueMerge(
            write.merge!,
            write.path,
            existing,
            serverValues,
          ),
        );
      }
    }
    if (!needToReevaluate) {
      return const <Event>[];
    }
    ImmutableTree<bool> affectedTree = ImmutableTree<bool>.empty();
    if (write.isOverwrite) {
      affectedTree = affectedTree.set(Path.empty, true);
    } else {
      for (final MapEntry<Path, Node> entry in write.merge!.entries) {
        affectedTree = affectedTree.set(entry.key, true);
      }
    }
    return _applyOperationToSyncPoints(
      AckUserWrite(write.path, affectedTree, revert: revert),
    );
  });

  /// Android `SyncTree.removeAllWrites`.
  @override
  List<Event> removeAllWrites() => _run(() {
    _persistenceManager.removeAllUserWrites();
    final List<UserWriteRecord> purgedWrites = _pendingWriteTree
        .purgeAllWrites();
    if (purgedWrites.isEmpty) {
      return const <Event>[];
    }
    return _applyOperationToSyncPoints(
      AckUserWrite(Path.empty, ImmutableTree<bool>(true), revert: true),
    );
  });

  /// The paths under which server data at [path] is persisted: [path] when a sync point is at or
  /// above it, else the top-most sync points below it (none when nothing listens there).
  /// Android persists every push (`SyncTree.java:300-323`); docs/database_decisions.md section 6.
  List<Path> _persistedPathsAt(Path path) {
    if (_syncPointTree.rootMostValue(path) != null) {
      return <Path>[path];
    }
    final List<Path> paths = <Path>[];
    void visit(Path at, ImmutableTree<SyncPoint> tree) {
      if (tree.value != null) {
        paths.add(at);
        return;
      }
      for (final MapEntry<ChildKey, ImmutableTree<SyncPoint>> child
          in tree.children.entries) {
        visit(at.child(child.key), child.value);
      }
    }

    visit(path, _syncPointTree.subtree(path));
    return paths;
  }

  /// Counts a server update that stored nothing towards the persistence manager's prune check,
  /// as Android counts every server update: an empty merge stores nothing.
  void _countUnpersistedServerUpdate(Path path) =>
      _persistenceManager.updateServerCacheWithMerge(path, CompoundWrite.empty);

  /// Android `SyncTree.applyServerOverwrite`. Applying the same data twice raises no events the
  /// second time (overlapping listens push the same data twice). Only the parts of [newData]
  /// under a sync point are persisted.
  @override
  List<Event> applyServerOverwrite(Path path, Node newData) => _run(() {
    final List<Path> persistedPaths = _persistedPathsAt(path);
    for (final Path persisted in persistedPaths) {
      _persistenceManager.updateServerCache(
        QuerySpec.defaultAt(persisted),
        newData.getChild(Path.relative(path, persisted)),
      );
    }
    if (persistedPaths.isEmpty) {
      _countUnpersistedServerUpdate(path);
    }
    return _applyOperationToSyncPoints(
      Overwrite(OperationSource.server, path, newData),
    );
  });

  /// Android `SyncTree.applyServerMerge`. Only the parts of the merge under a sync point are
  /// persisted.
  @override
  List<Event> applyServerMerge(Path path, Map<Path, Node> changedChildren) =>
      _run(() {
        final CompoundWrite merge = CompoundWrite.fromPathMerge(
          changedChildren,
        );
        bool persistedAny = false;
        for (final Path persisted in _persistedPathsAt(path)) {
          final CompoundWrite part = merge.childCompoundWrite(
            Path.relative(path, persisted),
          );
          if (!part.isEmpty) {
            _persistenceManager.updateServerCacheWithMerge(persisted, part);
            persistedAny = true;
          }
        }
        if (!persistedAny) {
          _countUnpersistedServerUpdate(path);
        }
        return _applyOperationToSyncPoints(
          Merge(OperationSource.server, path, merge),
        );
      });

  /// Android `SyncTree.applyServerRangeMerges`: applies the merges to the complete view's server
  /// cache and the result as a server overwrite.
  @override
  List<Event> applyServerRangeMerges(Path path, List<RangeMerge> rangeMerges) {
    final View? view = _syncPointTree.get(path)?.completeView;
    if (view == null) {
      // The view was removed: ignore the update.
      return const <Event>[];
    }
    Node serverNode = view.serverCache;
    for (final RangeMerge merge in rangeMerges) {
      serverNode = merge.applyTo(serverNode);
    }
    return applyServerOverwrite(path, serverNode);
  }

  /// Android `SyncTree.applyTaggedRangeMerges`.
  @override
  List<Event> applyTaggedRangeMerges(
    Path path,
    List<RangeMerge> rangeMerges,
    Tag tag,
  ) {
    final QuerySpec? query = _tagToQuery[tag];
    if (query == null) {
      // The query was removed: ignore the update.
      return const <Event>[];
    }
    assert(path == query.path, 'Range merge for a different path');
    final SyncPoint? syncPoint = _syncPointTree.get(query.path);
    final View? view = syncPoint?.viewForQuery(query);
    if (view == null) {
      throw StateError("Missing view for query tag that we're tracking");
    }
    Node serverNode = view.serverCache;
    for (final RangeMerge merge in rangeMerges) {
      serverNode = merge.applyTo(serverNode);
    }
    return applyTaggedQueryOverwrite(path, serverNode, tag);
  }

  /// Android `SyncTree.applyListenComplete`.
  @override
  List<Event> applyListenComplete(Path path) => _run(() {
    _persistenceManager.setQueryComplete(QuerySpec.defaultAt(path));
    return _applyOperationToSyncPoints(
      ListenComplete(OperationSource.server, path),
    );
  });

  /// Android `SyncTree.applyTaggedListenComplete`.
  @override
  List<Event> applyTaggedListenComplete(Tag tag) => _run(() {
    final QuerySpec? query = _tagToQuery[tag];
    if (query == null) {
      return const <Event>[];
    }
    _persistenceManager.setQueryComplete(query);
    return _applyTaggedOperation(
      query,
      ListenComplete(
        OperationSource.forServerTaggedQuery(query.params),
        Path.empty,
      ),
    );
  });

  /// Android `SyncTree.applyTaggedQueryOverwrite`.
  @override
  List<Event> applyTaggedQueryOverwrite(Path path, Node snap, Tag tag) =>
      _run(() {
        final QuerySpec? query = _tagToQuery[tag];
        if (query == null) {
          return const <Event>[];
        }
        final Path relativePath = Path.relative(query.path, path);
        _persistenceManager.updateServerCache(
          relativePath.isEmpty ? query : QuerySpec.defaultAt(path),
          snap,
        );
        return _applyTaggedOperation(
          query,
          Overwrite(
            OperationSource.forServerTaggedQuery(query.params),
            relativePath,
            snap,
          ),
        );
      });

  /// Android `SyncTree.applyTaggedQueryMerge`.
  @override
  List<Event> applyTaggedQueryMerge(
    Path path,
    Map<Path, Node> changedChildren,
    Tag tag,
  ) => _run(() {
    final QuerySpec? query = _tagToQuery[tag];
    if (query == null) {
      return const <Event>[];
    }
    final Path relativePath = Path.relative(query.path, path);
    final CompoundWrite merge = CompoundWrite.fromPathMerge(changedChildren);
    _persistenceManager.updateServerCacheWithMerge(path, merge);
    return _applyTaggedOperation(
      query,
      Merge(
        OperationSource.forServerTaggedQuery(query.params),
        relativePath,
        merge,
      ),
    );
  });

  /// Android `SyncTree.setQueryActive`.
  @override
  void setQueryActive(QuerySpec query) => _persistenceManager
      .runInTransaction<void>(() => _persistenceManager.setQueryActive(query));

  /// Android `SyncTree.setQueryInactive`.
  @override
  void setQueryInactive(QuerySpec query) =>
      _persistenceManager.runInTransaction<void>(
        () => _persistenceManager.setQueryInactive(query),
      );

  /// Marks [query] inactive unless a view at its path serves it. Android: none (its `getValue`
  /// leaves the query active after a failed or offline get).
  @override
  void releaseQuery(QuerySpec query) {
    if (_syncPointTree.get(query.path)?.viewExistsForQuery(query) ?? false) {
      return;
    }
    setQueryInactive(query);
  }

  /// Android `SyncTree.persistenceServerCache`: the persisted server data of [query] through the
  /// query's filter, or null. Differences from Android, which answers whatever is stored when it
  /// is not empty: only a cache persistence knows complete answers, so a partly known location
  /// (children cached by other queries) gives null and a location known empty gives an empty
  /// node; the limit and range of [query] apply.
  @override
  Node? persistenceServerCache(QuerySpec query) {
    final CacheNode cache = _persistenceManager.serverCache(query);
    if (!cache.fullyInitialized) {
      return null;
    }
    return View(query, ViewCache(cache, cache)).completeNode;
  }

  /// Android `SyncTree.getServerValue`: the complete data of [query] from the tree, pending
  /// writes included (a write not yet acknowledged that covers the query counts, JS
  /// `SyncTree.ts:646-657`), or null.
  @override
  Node? getServerValue(QuerySpec query) =>
      _persistenceManager.runInTransaction(() {
        final Path path = query.path;
        Node? serverCacheNode = _ancestorServerCache(path).serverCache;
        final SyncPoint syncPoint =
            _syncPointTree.get(path) ?? SyncPoint(_persistenceManager);
        serverCacheNode ??= syncPoint.completeServerCache(Path.empty);
        final CacheNode serverCache = CacheNode(
          (serverCacheNode ?? ChildrenNode.empty).withIndex(query.index),
          fullyInitialized: serverCacheNode != null,
          filtered: false,
        );
        return syncPoint
            .getView(query, _pendingWriteTree.childWrites(path), serverCache)
            .completeNode;
      });

  /// Android `SyncTree.addEventRegistration`; [preloadedServerCache] replaces the persistence
  /// lookup. The events [ListenProvider.startListening] returns come last.
  @override
  List<Event> addEventRegistration(
    EventRegistration registration, {
    bool skipListenerSetup = false,
    CacheNode? preloadedServerCache,
  }) => _run(
    () => _addEventRegistration(
      registration,
      skipListenerSetup: skipListenerSetup,
      preloadedServerCache: preloadedServerCache,
    ),
  );

  /// Android `SyncTree.removeEventRegistration(EventRegistration, boolean)`.
  @override
  List<Event> removeEventRegistration(
    EventRegistration registration, {
    bool skipDedup = false,
  }) => _removeEventRegistration(
    registration.querySpec,
    registration,
    null,
    skipDedup: skipDedup,
  );

  /// Android `SyncTree.removeAllEventRegistrations`.
  @override
  List<Event> removeAllEventRegistrations(
    QuerySpec query,
    DatabaseError error,
  ) => _removeEventRegistration(query, null, error, skipDedup: false);

  /// Android `SyncTree.removeEventRegistration(QuerySpec, EventRegistration, DatabaseError,
  /// boolean)`.
  List<Event> _removeEventRegistration(
    QuerySpec query,
    EventRegistration? registration,
    DatabaseError? cancelError, {
    required bool skipDedup,
  }) => _run(
    () => _removeEventRegistrationInTransaction(
      query,
      registration,
      cancelError,
      skipDedup: skipDedup,
    ),
  );

  /// Android `SyncTree.keepSynced(QuerySpec, boolean, boolean)`.
  @override
  void keepSynced(
    QuerySpec query, {
    required bool keep,
    bool skipDedup = false,
  }) {
    if (keep && !_keepSyncedQueries.contains(query)) {
      addEventRegistration(
        KeepSyncedEventRegistration(query),
        skipListenerSetup: skipDedup,
      );
      _keepSyncedQueries.add(query);
    } else if (!keep && _keepSyncedQueries.contains(query)) {
      removeEventRegistration(
        KeepSyncedEventRegistration(query),
        skipDedup: skipDedup,
      );
      _keepSyncedQueries.remove(query);
    }
  }

  /// The tag of [query], or null (Android `SyncTree.tagForQuery`).
  @override
  Tag? tagForQuery(QuerySpec query) => _queryToTag[query];

  /// Android `SyncTree.calcCompleteEventCacheFromRoot`.
  @override
  Node? calcCompleteEventCacheFromRoot(
    Path path, {
    List<WriteId> writeIdsToExclude = const <WriteId>[],
  }) {
    final Node? serverCache = _syncPointTree.value?.completeServerCache(
      Path.empty,
    );
    if (serverCache != null) {
      return _pendingWriteTree.calcCompleteEventCache(
        path,
        serverCache,
        writeIdsToExclude: writeIdsToExclude,
        includeHiddenWrites: true,
      );
    }
    return calcCompleteEventCache(path, writeIdsToExclude: writeIdsToExclude);
  }

  /// Android `SyncTree.calcCompleteEventCache`, with JS's lookup of the server cache on the path
  /// (`syncTreeCalcCompleteEventCache`, which includes the root). Hidden writes count.
  @override
  Node? calcCompleteEventCache(
    Path path, {
    List<WriteId> writeIdsToExclude = const <WriteId>[],
  }) {
    final Node? serverCache = _syncPointTree.findOnPath<Node>(
      path,
      (Path pathSoFar, SyncPoint syncPoint) =>
          syncPoint.completeServerCache(Path.relative(pathSoFar, path)),
    );
    return _pendingWriteTree.calcCompleteEventCache(
      path,
      serverCache,
      writeIdsToExclude: writeIdsToExclude,
      includeHiddenWrites: true,
    );
  }
}
