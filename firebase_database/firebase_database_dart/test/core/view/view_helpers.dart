// Shared helpers of the view layer tests (no tests here).
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/index.dart';
import 'package:firebase_database_dart/src/core/snap/named_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/view/change.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/value_index.dart';
import 'package:firebase_database_dart/src/core/view/complete_child_source.dart';
import 'package:firebase_database_dart/src/core/view/filter/child_change_accumulator.dart';
import 'package:firebase_database_dart/src/core/view/filter/node_filter.dart';
import 'package:firebase_database_dart/src/core/view/query_params.dart';

/// The node of [json].
Node n(Object? json) => nodeFromJson(json);

/// The child key [name].
ChildKey k(String name) => ChildKey(name);

/// A change as text: `type key new old`, the nodes in export JSON.
String describe(Change c) {
  final StringBuffer out = StringBuffer(c.eventType.name);
  if (c.childKey != null) {
    out.write(' ${c.childKey}');
  }
  out.write(' ${c.node.toJson(exportFormat: true)}');
  if (c.oldNode != null) {
    out.write(' old ${c.oldNode!.toJson(exportFormat: true)}');
  }
  return out.toString();
}

/// [changes] as text, in order.
List<String> describeAll(List<Change> changes) =>
    changes.map(describe).toList();

/// A source that knows the complete data [full], as a complete server cache would.
final class FullSource implements CompleteChildSource {
  /// Creates the source.
  FullSource(this.full);

  /// The complete data.
  final Node full;

  @override
  Node? getCompleteChild(ChildKey key) => full.getImmediateChild(key);

  @override
  NamedNode? getChildAfterChild(
    Index index,
    NamedNode child, {
    required bool reverse,
  }) {
    final ChildrenNode node = full.withIndex(index) as ChildrenNode;
    final Iterable<NamedNode> children = reverse
        ? node.reverseChildren(index)
        : node.childrenInOrder(index);
    for (final NamedNode next in children) {
      final int cmp = index.compare(next, child);
      if (reverse ? cmp < 0 : cmp > 0) {
        return next;
      }
    }
    return null;
  }
}

/// The default parameters.
QueryParams get def => QueryParams.defaultParams;

QueryParams get byValue => def.orderBy(valueIndex);

/// The full node of [json] through [filter], from an empty node, with its changes.
({Node node, List<String> changes}) full(NodeFilter filter, Object? json) {
  final ChildChangeAccumulator acc = ChildChangeAccumulator();
  final Node node = filter.updateFullNode(
    ChildrenNode.empty.withIndex(filter.index),
    n(json),
    acc,
  );
  return (node: node, changes: describeAll(acc.changes));
}

/// [filter]'s updateChild of [key] to [json] on [snap].
({Node node, List<String> changes}) child(
  NodeFilter filter,
  Node snap,
  String key,
  Object? json, {
  CompleteChildSource source = noCompleteChildSource,
}) {
  final ChildChangeAccumulator acc = ChildChangeAccumulator();
  final Node node = filter.updateChild(
    snap,
    k(key),
    n(json),
    Path.empty,
    source,
    acc,
  );
  return (node: node, changes: describeAll(acc.changes));
}

Node indexed(Object? json, Index index) => n(json).withIndex(index);
