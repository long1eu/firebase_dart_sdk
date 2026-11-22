/// The two caches of a view. JS: `core/view/ViewCache.ts`; Android: `core/view/ViewCache.java`.
library;

import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/view/cache_node.dart';

/// The event cache (what the user saw, with local writes) and the server cache of a view.
final class ViewCache {
  /// Creates a view cache.
  const ViewCache(this.eventCache, this.serverCache);

  /// The event cache.
  final CacheNode eventCache;

  /// The server cache.
  final CacheNode serverCache;

  /// With a new event cache (JS `viewCacheUpdateEventSnap`, Android `ViewCache.updateEventSnap`).
  ViewCache updateEventSnap(
    Node eventSnap, {
    required bool complete,
    required bool filtered,
  }) => ViewCache(
    CacheNode(eventSnap, fullyInitialized: complete, filtered: filtered),
    serverCache,
  );

  /// With a new server cache (JS `viewCacheUpdateServerSnap`, Android
  /// `ViewCache.updateServerSnap`).
  ViewCache updateServerSnap(
    Node serverSnap, {
    required bool complete,
    required bool filtered,
  }) => ViewCache(
    eventCache,
    CacheNode(serverSnap, fullyInitialized: complete, filtered: filtered),
  );

  /// The event cache node if fully initialised, else null (JS
  /// `viewCacheGetCompleteEventSnap`).
  Node? get completeEventSnap =>
      eventCache.fullyInitialized ? eventCache.node : null;

  /// The server cache node if fully initialised, else null (JS
  /// `viewCacheGetCompleteServerSnap`).
  Node? get completeServerSnap =>
      serverCache.fullyInitialized ? serverCache.node : null;
}
