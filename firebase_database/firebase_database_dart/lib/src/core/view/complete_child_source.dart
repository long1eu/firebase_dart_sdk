/// Sources of complete children for filtered views. JS: `core/view/CompleteChildSource.ts`;
/// Android: `core/view/filter/NodeFilter.java` (`CompleteChildSource`) and
/// `core/view/ViewProcessor.java` (`NO_COMPLETE_SOURCE`, `WriteTreeCompleteChildSource`).
library;

import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/index.dart';
import 'package:firebase_database_dart/src/core/snap/named_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/view/cache_node.dart';
import 'package:firebase_database_dart/src/core/view/view_cache.dart';
import 'package:firebase_database_dart/src/core/write_tree_ref.dart';

/// Finds complete children that a filtered view may need to pull in from outside its cache.
abstract interface class CompleteChildSource {
  /// The complete child [key], or null when unknown.
  Node? getCompleteChild(ChildKey key);

  /// The complete child after [child] in [index] order ([reverse]: before), or null.
  NamedNode? getChildAfterChild(
    Index index,
    NamedNode child, {
    required bool reverse,
  });
}

/// The source that knows nothing (JS `NoCompleteChildSource_`, Android
/// `ViewProcessor.NO_COMPLETE_SOURCE`).
final class NoCompleteChildSource implements CompleteChildSource {
  /// Use [noCompleteChildSource].
  const NoCompleteChildSource();

  /// Always null (JS `NoCompleteChildSource_.getCompleteChild`).
  @override
  Node? getCompleteChild(ChildKey key) => null;

  /// Always null (JS `NoCompleteChildSource_.getChildAfterChild`).
  @override
  NamedNode? getChildAfterChild(
    Index index,
    NamedNode child, {
    required bool reverse,
  }) => null;
}

/// The single [NoCompleteChildSource].
const CompleteChildSource noCompleteChildSource = NoCompleteChildSource();

/// A source over the pending writes, the view cache and an optional complete server cache.
final class WriteTreeCompleteChildSource implements CompleteChildSource {
  /// Creates the source.
  const WriteTreeCompleteChildSource(
    this.writes,
    this.viewCache,
    this.optCompleteServerCache,
  );

  /// The writes at the view's path.
  final WriteTreeRef writes;

  /// The view's caches.
  final ViewCache viewCache;

  /// A complete server cache from elsewhere in the tree, or null.
  final Node? optCompleteServerCache;

  /// The child from the event cache when complete there, else from the writes over the server
  /// cache (JS `WriteTreeCompleteChildSource.getCompleteChild`).
  @override
  Node? getCompleteChild(ChildKey key) {
    final CacheNode node = viewCache.eventCache;
    if (node.isCompleteForChild(key)) {
      return node.node.getImmediateChild(key);
    }
    final Node? completeServer = optCompleteServerCache;
    final CacheNode serverNode = completeServer != null
        ? CacheNode(completeServer, fullyInitialized: true, filtered: false)
        : viewCache.serverCache;
    return writes.calcCompleteChild(key, serverNode);
  }

  /// The next child with the writes applied over the complete server data (JS
  /// `WriteTreeCompleteChildSource.getChildAfterChild`, Android `calcNextNodeAfterPost`).
  ///
  /// Without complete server data only a write shadowing the whole view can answer, as Android's
  /// `WriteTree.calcNextNodeAfterPost` with a null server node.
  @override
  NamedNode? getChildAfterChild(
    Index index,
    NamedNode child, {
    required bool reverse,
  }) {
    Node? completeServerData =
        optCompleteServerCache ?? viewCache.completeServerSnap;
    if (completeServerData == null) {
      // The write tree ignores the server data when a write shadows the root, so the shadowing
      // node stands in for it.
      completeServerData = writes.shadowingWrite(Path.empty);
      if (completeServerData == null) {
        return null;
      }
    }
    return writes.calcNextNodeAfterPost(
      completeServerData,
      child,
      index,
      reverse: reverse,
    );
  }
}
