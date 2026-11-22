/// A change computed by the view processor. JS: `core/view/Change.ts`; Android:
/// `core/view/Change.java`.
library;

import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';

/// One change of a view: its [eventType], the new [node], the old one for child changes, the
/// [childKey] for child changes and the [prevName] once known.
final class Change {
  const Change._(
    this.eventType,
    this.node, {
    this.oldNode,
    this.childKey,
    this.prevName,
  });

  /// The value changed to [node].
  const Change.value(Node node) : this._(EventType.value, node);

  /// Child [key] was added with [node].
  const Change.childAdded(ChildKey key, Node node)
    : this._(EventType.childAdded, node, childKey: key);

  /// Child [key] was removed; [node] is the old data.
  const Change.childRemoved(ChildKey key, Node node)
    : this._(EventType.childRemoved, node, childKey: key);

  /// Child [key] changed from [oldNode] to [node].
  const Change.childChanged(ChildKey key, Node node, Node oldNode)
    : this._(EventType.childChanged, node, oldNode: oldNode, childKey: key);

  /// Child [key] moved.
  const Change.childMoved(ChildKey key, Node node)
    : this._(EventType.childMoved, node, childKey: key);

  /// The kind.
  final EventType eventType;

  /// The new data (indexed).
  final Node node;

  /// The old data of a child change.
  final Node? oldNode;

  /// The child of a child change.
  final ChildKey? childKey;

  /// The previous sibling.
  final ChildKey? prevName;

  /// This change with [prevName].
  Change withPrevName(ChildKey? prevName) => throw UnimplementedError();

  @override
  String toString() => throw UnimplementedError();
}
