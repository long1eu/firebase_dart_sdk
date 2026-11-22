/// Comparators. JS: `core/snap/comparators.ts`; Android: `snapshot/NamedNode` ordering in
/// `snapshot/KeyIndex.java`.
library;

import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/named_node.dart';

/// Compares two named nodes by name only.
int nameOnlyComparator(NamedNode left, NamedNode right) =>
    throw UnimplementedError();

/// Compares two child keys.
int nameComparator(ChildKey left, ChildKey right) => throw UnimplementedError();
