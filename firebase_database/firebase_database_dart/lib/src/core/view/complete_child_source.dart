/// Sources of complete children for filtered views. JS: `core/view/CompleteChildSource.ts`;
/// Android: `core/view/filter/NodeFilter.java` (`CompleteChildSource`) and
/// `core/view/ViewProcessor.java` (`NO_COMPLETE_SOURCE`, `WriteTreeCompleteChildSource`).
library;

import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/index.dart';
import 'package:firebase_database_dart/src/core/snap/named_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
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

/// The source that knows nothing.
final class NoCompleteChildSource implements CompleteChildSource {
  /// Use [noCompleteChildSource].
  const NoCompleteChildSource();

  @override
  Node? getCompleteChild(ChildKey key) => throw UnimplementedError();

  @override
  NamedNode? getChildAfterChild(
    Index index,
    NamedNode child, {
    required bool reverse,
  }) => throw UnimplementedError();
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

  @override
  Node? getCompleteChild(ChildKey key) => throw UnimplementedError();

  @override
  NamedNode? getChildAfterChild(
    Index index,
    NamedNode child, {
    required bool reverse,
  }) => throw UnimplementedError();
}
