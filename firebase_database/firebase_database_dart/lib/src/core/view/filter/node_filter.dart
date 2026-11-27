/// Node filters applied by views. JS: `core/view/filter/NodeFilter.ts`,
/// `core/view/QueryParams.ts` (`queryParamsGetNodeFilter`); Android:
/// `core/view/filter/NodeFilter.java`, `core/view/QueryParams.java` (`getNodeFilter`).
library;

import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/index.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/view/complete_child_source.dart';
import 'package:firebase_database_dart/src/core/view/filter/child_change_accumulator.dart';
import 'package:firebase_database_dart/src/core/view/filter/indexed_filter.dart';
import 'package:firebase_database_dart/src/core/view/filter/limited_filter.dart';
import 'package:firebase_database_dart/src/core/view/filter/ranged_filter.dart';
import 'package:firebase_database_dart/src/core/view/query_params.dart';

/// Applies changes to an indexed node while keeping only the children a query includes, and
/// reports child changes to an optional accumulator.
abstract interface class NodeFilter {
  /// [snap] with child [key] set to [newChild]; [source] supplies children to pull in.
  Node updateChild(
    Node snap,
    ChildKey key,
    Node newChild,
    Path affectedPath,
    CompleteChildSource source,
    ChildChangeAccumulator? accumulator,
  );

  /// [newSnap] filtered, reporting the changes from [oldSnap].
  Node updateFullNode(
    Node oldSnap,
    Node newSnap,
    ChildChangeAccumulator? accumulator,
  );

  /// [oldSnap] with [newPriority].
  Node updatePriority(Node oldSnap, Node newPriority);

  /// Whether children may be filtered out.
  bool get filtersNodes;

  /// The filter that indexes without filtering.
  NodeFilter get indexedFilter;

  /// The index.
  Index get index;
}

/// The filter for [params]: indexed when the query loads all data, limited when it has a limit,
/// else ranged (JS `queryParamsGetNodeFilter`, Android `QueryParams.getNodeFilter`).
NodeFilter nodeFilterFor(QueryParams params) {
  if (params.loadsAllData) {
    return IndexedFilter(params.index);
  } else if (params.hasLimit) {
    return LimitedFilter(params);
  } else {
    return RangedFilter(params);
  }
}
