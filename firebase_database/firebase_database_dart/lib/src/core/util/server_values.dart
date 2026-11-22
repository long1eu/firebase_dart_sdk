/// Resolution of server values (`{'.sv': ...}`) against existing data. JS:
/// `core/util/ServerValues.ts`; Android: `core/ServerValues.java`, `core/ValueProvider.java`.
library;

import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/write_id.dart';

/// Computes the complete event cache at a path excluding some writes; Repo passes
/// `SyncTree.calcCompleteEventCache` so this file does not depend on the sync tree.
typedef CompleteEventCacheFn = Node? Function(Path path, List<WriteId> writeIdsToExclude);

/// The values server values resolve to: `{'timestamp': <server time ms>}`.
Map<String, Object?> generateServerValues({required int timestamp}) => throw UnimplementedError();

/// Gives the existing value a deferred value is resolved against, lazily.
sealed class ValueProvider {
  /// Const constructor for subclasses.
  const ValueProvider();

  /// The provider of child [key].
  ValueProvider getImmediateChild(ChildKey key);

  /// The existing node.
  Node node();
}

/// A provider over a known node.
final class ExistingValueProvider extends ValueProvider {
  /// Wraps [existing].
  const ExistingValueProvider(this.existing);

  /// The node.
  final Node existing;

  @override
  ValueProvider getImmediateChild(ChildKey key) => throw UnimplementedError();

  @override
  Node node() => throw UnimplementedError();
}

/// A provider that asks the sync tree for the current value at [path] only when needed.
final class DeferredValueProvider extends ValueProvider {
  /// Reads through [calcCompleteEventCache] at [path].
  const DeferredValueProvider(this.calcCompleteEventCache, this.path);

  /// The sync tree's complete-event-cache function.
  final CompleteEventCacheFn calcCompleteEventCache;

  /// The path.
  final Path path;

  @override
  ValueProvider getImmediateChild(ChildKey key) => throw UnimplementedError();

  @override
  Node node() => throw UnimplementedError();
}

/// Resolves one leaf [value]: a server value map becomes its value (timestamp, or existing number
/// plus increment); anything else is returned as is.
Object resolveDeferredLeafValue(
  Object value,
  ValueProvider existing,
  Map<String, Object?> serverValues,
) => throw UnimplementedError();

/// Resolves every server value in [node] against [existing].
Node resolveDeferredValueSnapshot(Node node, Node existing, Map<String, Object?> serverValues) =>
    throw UnimplementedError();

/// Resolves every server value in [node] written at [path], reading existing data lazily
/// through [calcCompleteEventCache].
Node resolveDeferredValueTree(
  Path path,
  Node node,
  CompleteEventCacheFn calcCompleteEventCache,
  Map<String, Object?> serverValues,
) => throw UnimplementedError();

/// Resolves every server value in [merge] written at [path] (Android's
/// `resolveDeferredValueMerge`).
CompoundWrite resolveDeferredValueMerge(
  CompoundWrite merge,
  Path path,
  CompleteEventCacheFn calcCompleteEventCache,
  Map<String, Object?> serverValues,
) => throw UnimplementedError();
