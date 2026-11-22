/// Keeps at most the limit of children within the range, from the anchored side. JS: `core/view/filter/LimitedFilter.ts`; Android: `core/view/filter/LimitedFilter.java`.
library;

import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/index.dart';

import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/view/complete_child_source.dart';
import 'package:firebase_database_dart/src/core/view/filter/child_change_accumulator.dart';
import 'package:firebase_database_dart/src/core/view/filter/node_filter.dart';
import 'package:firebase_database_dart/src/core/view/query_params.dart';

/// Keeps at most the limit of children within the range, from the anchored side.
final class LimitedFilter implements NodeFilter {
  /// Creates the filter.
  factory LimitedFilter(QueryParams params) => throw UnimplementedError();

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
