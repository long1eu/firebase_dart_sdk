/// Resolution of server values (`{'.sv': ...}`) against existing data. JS:
/// `core/util/ServerValues.ts`; Android: `core/ServerValues.java`, `core/ValueProvider.java`.
library;

import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/key_index.dart';
import 'package:firebase_database_dart/src/core/snap/leaf_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/priority.dart';
import 'package:firebase_database_dart/src/core/util/numbers.dart';
import 'package:firebase_database_dart/src/core/write_id.dart';

const String _serverValueKey = '.sv';
const String _timestampOp = 'timestamp';
const String _incrementOp = 'increment';

/// Computes the complete event cache at a path excluding some writes; Repo passes
/// `SyncTree.calcCompleteEventCache` so this file does not depend on the sync tree.
typedef CompleteEventCacheFn =
    Node? Function(Path path, List<WriteId> writeIdsToExclude);

/// The values server values resolve to: `{'timestamp': <server time ms>}`.
Map<String, Object?> generateServerValues({required int timestamp}) =>
    <String, Object?>{_timestampOp: timestamp};

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
  ValueProvider getImmediateChild(ChildKey key) =>
      ExistingValueProvider(existing.getImmediateChild(key));

  @override
  Node node() => existing;
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
  ValueProvider getImmediateChild(ChildKey key) =>
      DeferredValueProvider(calcCompleteEventCache, path.child(key));

  @override
  Node node() =>
      calcCompleteEventCache(path, const <WriteId>[]) ?? ChildrenNode.empty;
}

/// Resolves one leaf [value]: a server value map becomes its value (timestamp, or existing number
/// plus increment); anything else is returned as is.
///
/// Unknown or malformed server values are returned unchanged (Android; JS asserts).
Object resolveDeferredLeafValue(
  Object value,
  ValueProvider existing,
  Map<String, Object?> serverValues,
) {
  if (value is! Map || !value.containsKey(_serverValueKey)) {
    return value;
  }
  final Object? op = value[_serverValueKey];
  Object? result;
  if (op is String) {
    if (op == _timestampOp) {
      result = serverValues[_timestampOp];
    }
  } else if (op is Map) {
    final Object? delta = op[_incrementOp];
    if (delta is num) {
      result = _resolveIncrement(delta, existing);
    }
  }
  return result ?? value;
}

/// The existing number plus [delta], or [delta] when the existing value is not a number. Integer
/// sums stay integers while within plus or minus 2^53, beyond that the sum is a double, as JS.
num _resolveIncrement(num delta, ValueProvider existing) {
  final Node existingNode = existing.node();
  if (!existingNode.isLeafNode) {
    return delta;
  }
  final Object existingValue = (existingNode as LeafNode).value;
  if (existingValue is! num) {
    return delta;
  }
  if (existingValue is int && delta is int) {
    final int sum = existingValue + delta;
    if (sum.abs() <= maxSafeInteger) {
      return sum;
    }
  }
  return normalizeNumber(existingValue.toDouble() + delta.toDouble());
}

Node _resolveDeferredValue(
  Node node,
  ValueProvider existing,
  Map<String, Object?> serverValues,
) {
  final Node priorityNode = node.priority;
  final Object? rawPriority = priorityNode.isEmpty
      ? null
      : (priorityNode as LeafNode).value;
  final Object? priority = rawPriority == null
      ? null
      : resolveDeferredLeafValue(
          rawPriority,
          existing.getImmediateChild(ChildKey.priority),
          serverValues,
        );

  if (node.isLeafNode) {
    final LeafNode leaf = node as LeafNode;
    final Object value = resolveDeferredLeafValue(
      leaf.value,
      existing,
      serverValues,
    );
    if (!identical(value, leaf.value) || !identical(priority, rawPriority)) {
      return LeafNode(value, parsePriority(priority));
    }
    return node;
  }
  if (node.isEmpty) {
    return node;
  }

  Node newNode = node;
  if (!identical(priority, rawPriority)) {
    newNode = newNode.updatePriority(parsePriority(priority));
  }
  node.forEachChild(keyIndex, (ChildKey key, Node child) {
    final Node newChild = _resolveDeferredValue(
      child,
      existing.getImmediateChild(key),
      serverValues,
    );
    if (!identical(newChild, child)) {
      newNode = newNode.updateImmediateChild(key, newChild);
    }
    return false;
  });
  return newNode;
}

/// Resolves every server value in [node] against [existing].
Node resolveDeferredValueSnapshot(
  Node node,
  Node existing,
  Map<String, Object?> serverValues,
) => _resolveDeferredValue(node, ExistingValueProvider(existing), serverValues);

/// Resolves every server value in [node] written at [path], reading existing data lazily
/// through [calcCompleteEventCache].
Node resolveDeferredValueTree(
  Path path,
  Node node,
  CompleteEventCacheFn calcCompleteEventCache,
  Map<String, Object?> serverValues,
) => _resolveDeferredValue(
  node,
  DeferredValueProvider(calcCompleteEventCache, path),
  serverValues,
);

/// Resolves every server value in [merge] written at [path] (Android's
/// `resolveDeferredValueMerge`).
CompoundWrite resolveDeferredValueMerge(
  CompoundWrite merge,
  Path path,
  CompleteEventCacheFn calcCompleteEventCache,
  Map<String, Object?> serverValues,
) {
  CompoundWrite write = CompoundWrite.empty;
  for (final MapEntry<Path, Node> entry in merge.entries) {
    write = write.addWrite(
      entry.key,
      _resolveDeferredValue(
        entry.value,
        DeferredValueProvider(
          calcCompleteEventCache,
          path.childPath(entry.key),
        ),
        serverValues,
      ),
    );
  }
  return write;
}
