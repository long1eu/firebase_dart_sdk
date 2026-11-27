/// Priority helpers. JS: `core/snap/snap.ts` (`priorityHashText`, `validatePriorityNode`); Android:
/// `snapshot/PriorityUtilities.java`.
library;

import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/leaf_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/util/numbers.dart';

/// The hash text of a priority: `number:<ieee754>` or `string:<s>`.
///
/// A server value priority hashes as JS concatenates an object: `string:[object Object]`.
String priorityHashText(Object priority) {
  if (priority is num) {
    return 'number:${doubleToIeee754String(priority.toDouble())}';
  } else if (priority is String) {
    return 'string:$priority';
  } else {
    return 'string:[object Object]';
  }
}

/// Asserts that [priorityNode] is a valid priority (empty, number, string or server value leaf).
///
/// Throws a [StateError] (JS internal assertion) when it is not.
void validatePriorityNode(Node priorityNode) {
  final bool isMax = identical(priorityNode, MaxNode.instance);
  if (priorityNode is LeafNode) {
    final Object value = priorityNode.value;
    if (!(value is String ||
        value is num ||
        (value is Map && value.containsKey('.sv')))) {
      throw StateError('Priority must be a string or number.');
    }
  } else if (!isMax && !priorityNode.isEmpty) {
    throw StateError('priority of unexpected type.');
  }
  // Don't read the priority of the max node (it is its own priority).
  if (!isMax && !priorityNode.priority.isEmpty) {
    throw StateError("Priority nodes can't have a priority of their own.");
  }
}

/// The priority node for a JSON priority value (null gives the empty node).
Node parsePriority(Object? priority) =>
    priority == null ? ChildrenNode.empty : nodeFromJson(priority);
