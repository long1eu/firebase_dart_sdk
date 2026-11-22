/// Priority helpers. JS: `core/snap/snap.ts` (`priorityHashText`, `validatePriorityNode`); Android:
/// `snapshot/PriorityUtilities.java`.
library;

import 'package:firebase_database_dart/src/core/snap/node.dart';

/// The hash text of a priority: `number:<ieee754>` or `string:<s>`.
String priorityHashText(Object priority) => throw UnimplementedError();

/// Asserts that [priorityNode] is a valid priority (empty, number, string or server value leaf).
void validatePriorityNode(Node priorityNode) => throw UnimplementedError();

/// The priority node for a JSON priority value (null gives the empty node).
Node parsePriority(Object? priority) => throw UnimplementedError();
