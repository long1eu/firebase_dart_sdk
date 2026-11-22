/// Does not filter; keeps the node indexed by its index. JS: `core/view/filter/IndexedFilter.ts`; Android: `core/view/filter/IndexedFilter.java`.
library;

import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/index.dart';

import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/view/complete_child_source.dart';
import 'package:firebase_database_dart/src/core/view/filter/child_change_accumulator.dart';
import 'package:firebase_database_dart/src/core/view/filter/node_filter.dart';

/// Does not filter; keeps the node indexed by its index.
final class IndexedFilter implements NodeFilter {
  /// Creates the filter.
  factory IndexedFilter(Index index) => throw UnimplementedError();

  @override
  Node updateChild(
    Node snap,
    ChildKey key,
    Node newChild,
    Path affectedPath,
    CompleteChildSource source,
    ChildChangeAccumulator? accumulator,
  ) => throw UnimplementedError();

  @override
  Node updateFullNode(
    Node oldSnap,
    Node newSnap,
    ChildChangeAccumulator? accumulator,
  ) => throw UnimplementedError();

  @override
  Node updatePriority(Node oldSnap, Node newPriority) =>
      throw UnimplementedError();

  @override
  bool get filtersNodes => throw UnimplementedError();

  @override
  NodeFilter get indexedFilter => throw UnimplementedError();

  @override
  Index get index => throw UnimplementedError();
}
