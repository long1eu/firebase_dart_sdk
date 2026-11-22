/// Keeps the children between the start and end posts of the query. JS: `core/view/filter/RangedFilter.ts`; Android: `core/view/filter/RangedFilter.java`.
library;

import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/index.dart';
import 'package:firebase_database_dart/src/core/snap/named_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/view/complete_child_source.dart';
import 'package:firebase_database_dart/src/core/view/filter/child_change_accumulator.dart';
import 'package:firebase_database_dart/src/core/view/filter/node_filter.dart';
import 'package:firebase_database_dart/src/core/view/query_params.dart';

/// Keeps the children between the start and end posts of the query.
final class RangedFilter implements NodeFilter {
  /// Creates the filter.
  factory RangedFilter(QueryParams params) => throw UnimplementedError();

  /// The start post.
  NamedNode get startPost => throw UnimplementedError();

  /// The end post.
  NamedNode get endPost => throw UnimplementedError();

  /// Whether [node] is within the range.
  bool matches(NamedNode node) => throw UnimplementedError();

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
