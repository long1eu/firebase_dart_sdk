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

  /// With a new event cache.
  ViewCache updateEventSnap(Node eventSnap, {required bool complete, required bool filtered}) =>
      throw UnimplementedError();

  /// With a new server cache.
  ViewCache updateServerSnap(Node serverSnap, {required bool complete, required bool filtered}) =>
      throw UnimplementedError();

  /// The event cache node if fully initialised, else null.
  Node? get completeEventSnap => throw UnimplementedError();

  /// The server cache node if fully initialised, else null.
  Node? get completeServerSnap => throw UnimplementedError();
}
