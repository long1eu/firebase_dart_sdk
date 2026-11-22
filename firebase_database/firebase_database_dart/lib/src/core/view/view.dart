/// One query's view at a sync point. JS: `core/view/View.ts`; Android: `core/view/View.java`.
library;

import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/core/event_registration.dart';
import 'package:firebase_database_dart/src/core/operation/operation.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/priority_index.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/view/cache_node.dart';
import 'package:firebase_database_dart/src/core/view/change.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';
import 'package:firebase_database_dart/src/core/view/event_generator.dart';
import 'package:firebase_database_dart/src/core/view/filter/indexed_filter.dart';
import 'package:firebase_database_dart/src/core/view/filter/node_filter.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:firebase_database_dart/src/core/view/view_cache.dart';
import 'package:firebase_database_dart/src/core/view/view_processor.dart';
import 'package:firebase_database_dart/src/core/write_tree_ref.dart';

/// The events and changes of one operation on a view.
final class ViewOperationResult {
  /// Creates a result.
  const ViewOperationResult(this.events, this.changes);

  /// The events to raise.
  final List<DataEvent> events;

  /// The changes (the sync point tracks child keys of filtered queries from them).
  final List<Change> changes;
}

/// The caches, registrations and processor of one query.
final class View {
  /// Creates a view of [query] starting from [initialViewCache]: the server cache is only
  /// indexed (a tagged listen filters it later), the event cache goes through the query's filter
  /// (JS `View` constructor, Android `View.View`).
  factory View(QuerySpec query, ViewCache initialViewCache) {
    final IndexedFilter indexFilter = IndexedFilter(query.index);
    final NodeFilter filter = nodeFilterFor(query.params);
    final CacheNode initialServerCache = initialViewCache.serverCache;
    final CacheNode initialEventCache = initialViewCache.eventCache;
    final Node emptyIndexedNode = ChildrenNode.empty.withIndex(query.index);
    // Don't filter the server node with other filters than the index: wait for a tagged listen.
    final Node serverSnap = indexFilter.updateFullNode(
      emptyIndexedNode,
      initialServerCache.node,
      null,
    );
    final Node eventSnap = filter.updateFullNode(
      emptyIndexedNode,
      initialEventCache.node,
      null,
    );
    final ViewCache viewCache = ViewCache(
      CacheNode(
        eventSnap,
        fullyInitialized: initialEventCache.fullyInitialized,
        filtered: filter.filtersNodes,
      ),
      CacheNode(
        serverSnap,
        fullyInitialized: initialServerCache.fullyInitialized,
        filtered: indexFilter.filtersNodes,
      ),
    );
    return View._(
      query,
      ViewProcessor(filter),
      viewCache,
      EventGenerator(query),
    );
  }

  View._(this._query, this._processor, this._viewCache, this._eventGenerator);

  final QuerySpec _query;
  final ViewProcessor _processor;
  ViewCache _viewCache;
  final EventGenerator _eventGenerator;
  final List<EventRegistration> _eventRegistrations = <EventRegistration>[];

  /// The query (Android `View.getQuery`).
  QuerySpec get query => _query;

  /// The current caches.
  ViewCache get viewCache => _viewCache;

  /// The registrations, in the order they were added (Android `View.getEventRegistrations`).
  List<EventRegistration> get eventRegistrations =>
      List<EventRegistration>.unmodifiable(_eventRegistrations);

  /// The complete event cache, or null (Android `View.getCompleteNode`).
  Node? get completeNode => _viewCache.completeEventSnap;

  /// The server cache node (Android `View.getServerCache`).
  Node get serverCache => _viewCache.serverCache.node;

  /// The event cache node (Android `View.getEventCache`).
  Node get eventCache => _viewCache.eventCache.node;

  /// The complete server data at [path] below the view, or null; a filtered view only answers
  /// for a child it has (Android `View.getCompleteServerCache`).
  Node? completeServerCache(Path path) {
    final Node? cache = _viewCache.completeServerSnap;
    if (cache != null) {
      final ChildKey? front = path.front;
      if (_query.loadsAllData ||
          (front != null && !cache.getImmediateChild(front).isEmpty)) {
        return cache.getChild(path);
      }
    }
    return null;
  }

  /// Whether no registration is left (Android `View.isEmpty`).
  bool get isEmpty => _eventRegistrations.isEmpty;

  /// Adds [registration] (Android `View.addEventRegistration`).
  void addEventRegistration(EventRegistration registration) =>
      _eventRegistrations.add(registration);

  /// Removes [registration] (all when null); with [cancelError] removes all and returns their
  /// cancel events (Android `View.removeEventRegistration`).
  ///
  /// A removed registration is zombified, except on cancel: Android zombifies there too, but the
  /// event dispatcher here skips events of zombied registrations, so the registrations stay
  /// alive until their cancel event fires (`CallbackEventRegistration.fireCancelEvent` zombifies).
  List<Event> removeEventRegistration(
    EventRegistration? registration,
    DatabaseError? cancelError,
  ) {
    final List<Event> cancelEvents;
    if (cancelError != null) {
      assert(
        registration == null,
        'A cancel should cancel all event registrations',
      );
      final Path path = _query.path;
      cancelEvents = <Event>[
        for (final EventRegistration eventRegistration in _eventRegistrations)
          CancelEvent(eventRegistration, cancelError, path),
      ];
      _eventRegistrations.clear();
      return cancelEvents;
    }
    if (registration != null) {
      int indexToDelete = -1;
      for (int i = 0; i < _eventRegistrations.length; i++) {
        final EventRegistration candidate = _eventRegistrations[i];
        if (candidate.isSameListener(registration)) {
          indexToDelete = i;
          if (candidate.isZombied) {
            break;
          }
        }
      }
      if (indexToDelete != -1) {
        _eventRegistrations.removeAt(indexToDelete).zombify();
      }
    } else {
      final List<EventRegistration> removed = List<EventRegistration>.of(
        _eventRegistrations,
      );
      _eventRegistrations.clear();
      for (final EventRegistration eventRegistration in removed) {
        eventRegistration.zombify();
      }
    }
    return const <Event>[];
  }

  /// Applies [operation] and returns the events for the registrations (Android
  /// `View.applyOperation`).
  ViewOperationResult applyOperation(
    Operation operation,
    WriteTreeRef writesCache,
    Node? optCompleteServerCache,
  ) {
    if (operation is Merge && operation.source.queryParams != null) {
      assert(
        _viewCache.completeServerSnap != null,
        'We should always have a full cache before handling merges',
      );
      assert(
        _viewCache.completeEventSnap != null,
        'Missing event cache, even though we have a server cache',
      );
    }
    final ViewCache oldViewCache = _viewCache;
    final ProcessorResult result = _processor.applyOperation(
      oldViewCache,
      operation,
      writesCache,
      optCompleteServerCache,
    );
    assert(
      result.viewCache.eventCache.node.isIndexed(_processor.filter.index),
      'Event snap not indexed',
    );
    assert(
      result.viewCache.serverCache.node.isIndexed(_processor.filter.index),
      'Server snap not indexed',
    );
    assert(
      result.viewCache.serverCache.fullyInitialized ||
          !oldViewCache.serverCache.fullyInitialized,
      'Once a server snap is complete, it should never go back',
    );
    _viewCache = result.viewCache;
    final List<DataEvent> events = _generateEventsForChanges(
      result.changes,
      result.viewCache.eventCache.node,
      null,
    );
    return ViewOperationResult(events, result.changes);
  }

  /// The events a new [registration] gets for the current data: a child added per child, then
  /// the value when the event cache is complete (rule 7: a partial cache gives no value event;
  /// Android `View.getInitialEvents`).
  List<DataEvent> initialEvents(EventRegistration registration) {
    final CacheNode eventSnap = _viewCache.eventCache;
    final List<Change> initialChanges = <Change>[];
    eventSnap.node.forEachChild(priorityIndex, (ChildKey key, Node child) {
      initialChanges.add(Change.childAdded(key, child));
      return false;
    });
    if (eventSnap.fullyInitialized) {
      initialChanges.add(Change.value(eventSnap.node));
    }
    return _generateEventsForChanges(
      initialChanges,
      eventSnap.node,
      registration,
    );
  }

  List<DataEvent> _generateEventsForChanges(
    List<Change> changes,
    Node eventCache,
    EventRegistration? registration,
  ) => _eventGenerator.generateEventsForChanges(
    changes,
    eventCache,
    registration == null
        ? List<EventRegistration>.of(_eventRegistrations)
        : <EventRegistration>[registration],
  );
}
