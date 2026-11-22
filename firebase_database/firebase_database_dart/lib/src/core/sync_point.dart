/// The views at one path. JS: `core/SyncPoint.ts`; Android: `core/SyncPoint.java`.
library;

import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/core/event_registration.dart';
import 'package:firebase_database_dart/src/core/operation/operation.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_manager.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/key_index.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/view/cache_node.dart';
import 'package:firebase_database_dart/src/core/view/change.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';
import 'package:firebase_database_dart/src/core/view/query_params.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:firebase_database_dart/src/core/view/view.dart';
import 'package:firebase_database_dart/src/core/view/view_cache.dart';
import 'package:firebase_database_dart/src/core/write_tree_ref.dart';

/// The queries removed by a removal and the cancel events it produced.
typedef SyncPointRemoval = ({
  List<QuerySpec> removed,
  List<Event> cancelEvents,
});

/// The views of every query registered at one path; tracks the child keys of filtered queries
/// through [persistenceManager].
final class SyncPoint {
  /// Creates an empty sync point (Android `SyncPoint(PersistenceManager)`).
  factory SyncPoint(PersistenceManager persistenceManager) =>
      SyncPoint._(persistenceManager);

  SyncPoint._(this._persistenceManager);

  final PersistenceManager _persistenceManager;

  /// The views by query parameters, in the order they were added (JS keeps a `Map` in insertion
  /// order; Android a `HashMap`).
  final Map<QueryParams, View> _views = <QueryParams, View>{};

  /// The persistence hooks (Android `SyncPoint.persistenceManager`).
  PersistenceManager get persistenceManager => _persistenceManager;

  /// Whether no view is left (Android `SyncPoint.isEmpty`).
  bool get isEmpty => _views.isEmpty;

  /// Android `SyncPoint.applyOperationToView`: applies [operation] to [view] and, for a filtered
  /// query, reports the children added and removed to persistence.
  List<DataEvent> _applyOperationToView(
    View view,
    Operation operation,
    WriteTreeRef writes,
    Node? optCompleteServerCache,
  ) {
    final ViewOperationResult result = view.applyOperation(
      operation,
      writes,
      optCompleteServerCache,
    );
    if (!view.query.loadsAllData) {
      final Set<ChildKey> removed = <ChildKey>{};
      final Set<ChildKey> added = <ChildKey>{};
      for (final Change change in result.changes) {
        if (change.eventType == EventType.childAdded) {
          added.add(change.childKey!);
        } else if (change.eventType == EventType.childRemoved) {
          removed.add(change.childKey!);
        }
      }
      if (added.isNotEmpty || removed.isNotEmpty) {
        _persistenceManager.updateTrackedQueryKeys(view.query, added, removed);
      }
    }
    return result.events;
  }

  /// Applies [operation] to the view it targets (tagged) or to every view (Android
  /// `SyncPoint.applyOperation`).
  List<DataEvent> applyOperation(
    Operation operation,
    WriteTreeRef writesCache,
    Node? optCompleteServerCache,
  ) {
    final QueryParams? queryParams = operation.source.queryParams;
    if (queryParams != null) {
      final View? view = _views[queryParams];
      if (view == null) {
        throw StateError('SyncTree gave us an op for an invalid query.');
      }
      return _applyOperationToView(
        view,
        operation,
        writesCache,
        optCompleteServerCache,
      );
    }
    final List<DataEvent> events = <DataEvent>[];
    for (final View view in List<View>.of(_views.values)) {
      events.addAll(
        _applyOperationToView(
          view,
          operation,
          writesCache,
          optCompleteServerCache,
        ),
      );
    }
    return events;
  }

  /// The view of [query], creating one from [serverCache] and the writes when missing; a new view
  /// is not added to this point (Android `SyncPoint.getView`).
  ///
  /// A pending write that covers the query makes the new event cache complete (JS
  /// `syncPointGetView`, used by `SyncTree.ts:646-657`).
  View getView(
    QuerySpec query,
    WriteTreeRef writesCache,
    CacheNode serverCache,
  ) {
    final View? view = _views[query.params];
    if (view != null) {
      return view;
    }
    Node? eventCache = writesCache.calcCompleteEventCache(
      serverCache.fullyInitialized ? serverCache.node : null,
    );
    final bool eventCacheComplete;
    if (eventCache != null) {
      eventCacheComplete = true;
    } else {
      eventCache = writesCache.calcCompleteEventChildren(serverCache.node);
      eventCacheComplete = false;
    }
    final ViewCache viewCache = ViewCache(
      CacheNode(
        eventCache.withIndex(query.index),
        fullyInitialized: eventCacheComplete,
        filtered: false,
      ),
      serverCache,
    );
    return View(query, viewCache);
  }

  /// Adds [registration] (creating its view) and returns its initial events (Android
  /// `SyncPoint.addEventRegistration`); for a filtered query, tells persistence the children the
  /// view holds.
  List<DataEvent> addEventRegistration(
    EventRegistration registration,
    WriteTreeRef writesCache,
    CacheNode serverCache,
  ) {
    final QuerySpec query = registration.querySpec;
    final View view = getView(query, writesCache, serverCache);
    if (!query.loadsAllData) {
      final Set<ChildKey> allChildren = <ChildKey>{};
      view.eventCache.forEachChild(keyIndex, (ChildKey key, Node _) {
        allChildren.add(key);
        return false;
      });
      _persistenceManager.setTrackedQueryKeys(query, allChildren);
    }
    _views.putIfAbsent(query.params, () => view);
    view.addEventRegistration(registration);
    return view.initialEvents(registration);
  }

  /// Removes [registration] (all when null) from the views of [query] (all views for the default
  /// query); with [cancelError] returns cancel events (Android
  /// `SyncPoint.removeEventRegistration`). The removed queries are the filtered ones whose view
  /// emptied, then the default query of the path when the last complete view went.
  SyncPointRemoval removeEventRegistration(
    QuerySpec query,
    EventRegistration? registration,
    DatabaseError? cancelError,
  ) {
    final List<QuerySpec> removed = <QuerySpec>[];
    final List<Event> cancelEvents = <Event>[];
    final bool hadCompleteView = hasCompleteView;
    if (query.isDefault) {
      // ref.off(...) searches every view for the registration.
      for (final MapEntry<QueryParams, View> entry
          in List<MapEntry<QueryParams, View>>.of(_views.entries)) {
        final View view = entry.value;
        cancelEvents.addAll(
          view.removeEventRegistration(registration, cancelError),
        );
        if (view.isEmpty) {
          _views.remove(entry.key);
          // Complete views are dealt with below.
          if (!view.query.loadsAllData) {
            removed.add(view.query);
          }
        }
      }
    } else {
      final View? view = _views[query.params];
      if (view != null) {
        cancelEvents.addAll(
          view.removeEventRegistration(registration, cancelError),
        );
        if (view.isEmpty) {
          _views.remove(query.params);
          if (!view.query.loadsAllData) {
            removed.add(view.query);
          }
        }
      }
    }
    if (hadCompleteView && !hasCompleteView) {
      // The last complete view went.
      removed.add(QuerySpec.defaultAt(query.path));
    }
    return (removed: removed, cancelEvents: cancelEvents);
  }

  /// The views of queries that do not load all data (Android `SyncPoint.getQueryViews`).
  List<View> get queryViews => <View>[
    for (final View view in _views.values)
      if (!view.query.loadsAllData) view,
  ];

  /// The complete server data at [path] below this point, or null (Android
  /// `SyncPoint.getCompleteServerCache`).
  Node? completeServerCache(Path path) {
    for (final View view in _views.values) {
      final Node? serverCache = view.completeServerCache(path);
      if (serverCache != null) {
        return serverCache;
      }
    }
    return null;
  }

  /// The view of [query], or null; any complete view answers for a query that loads all data
  /// (Android `SyncPoint.viewForQuery`).
  View? viewForQuery(QuerySpec query) =>
      query.loadsAllData ? completeView : _views[query.params];

  /// Whether a view for [query] exists (Android `SyncPoint.viewExistsForQuery`).
  bool viewExistsForQuery(QuerySpec query) => viewForQuery(query) != null;

  /// Whether a view loading all data exists (Android `SyncPoint.hasCompleteView`).
  bool get hasCompleteView => completeView != null;

  /// The view loading all data, or null (Android `SyncPoint.getCompleteView`).
  View? get completeView {
    for (final View view in _views.values) {
      if (view.query.loadsAllData) {
        return view;
      }
    }
    return null;
  }

  /// The views by query parameters (Android `SyncPoint.getViews`, for tests); unmodifiable.
  Map<QueryParams, View> get views =>
      Map<QueryParams, View>.unmodifiable(_views);
}
