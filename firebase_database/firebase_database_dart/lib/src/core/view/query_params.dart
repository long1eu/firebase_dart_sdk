/// Query parameters and their wire forms. JS: `core/view/QueryParams.ts`; Android:
/// `core/view/QueryParams.java`.
///
/// The node filter for the parameters is `nodeFilterFor` in `view/filter/node_filter.dart` (JS
/// `queryParamsGetNodeFilter`), so this data-layer file does not depend on the view layer.
library;

import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/index.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';

/// Which end a limit counts from.
enum ViewFrom {
  /// `limitToFirst` (wire `l`).
  left,

  /// `limitToLast` (wire `r`).
  right,
}

/// The immutable parameters of a query: index, bounds and limit. Every builder returns a copy.
final class QueryParams {
  /// The parameters of the default query (priority index, no bounds, no limit).
  static QueryParams get defaultParams => throw UnimplementedError();

  /// Parses the wire object (the inverse of [toWireObject]), as persisted tracked queries store it.
  factory QueryParams.fromWireObject(Map<String, Object?> wire) => throw UnimplementedError();

  /// The index.
  Index get index => throw UnimplementedError();

  /// Whether a start bound is set.
  bool get hasStart => throw UnimplementedError();

  /// The start value; only with [hasStart].
  Node get indexStartValue => throw UnimplementedError();

  /// The start key: the given key, or [ChildKey.min] (or [ChildKey.max] for `startAfter` without
  /// a key); only with [hasStart].
  ChildKey get indexStartName => throw UnimplementedError();

  /// Whether the start bound is inclusive (false after `startAfter`).
  bool get startInclusive => throw UnimplementedError();

  /// Whether an end bound is set.
  bool get hasEnd => throw UnimplementedError();

  /// The end value; only with [hasEnd].
  Node get indexEndValue => throw UnimplementedError();

  /// The end key; only with [hasEnd].
  ChildKey get indexEndName => throw UnimplementedError();

  /// Whether the end bound is inclusive (false after `endBefore`).
  bool get endInclusive => throw UnimplementedError();

  /// Whether a limit is set.
  bool get hasLimit => throw UnimplementedError();

  /// Whether a limit with an explicit side is set.
  bool get hasAnchoredLimit => throw UnimplementedError();

  /// The limit; only with [hasLimit].
  int get limit => throw UnimplementedError();

  /// Whether the view is anchored at the start.
  bool get isViewFromLeft => throw UnimplementedError();

  /// Whether the query loads all data (no bounds, no limit).
  bool get loadsAllData => throw UnimplementedError();

  /// Whether this is the default query (also the priority index).
  bool get isDefault => throw UnimplementedError();

  /// Whether the parameters are consistent.
  bool get isValid => throw UnimplementedError();

  /// With `limitToFirst(limit)`.
  QueryParams limitToFirst(int limit) => throw UnimplementedError();

  /// With `limitToLast(limit)`.
  QueryParams limitToLast(int limit) => throw UnimplementedError();

  /// With an inclusive start bound.
  QueryParams startAt(Node indexValue, [ChildKey? key]) => throw UnimplementedError();

  /// With an exclusive start bound.
  QueryParams startAfter(Node indexValue, [ChildKey? key]) => throw UnimplementedError();

  /// With an inclusive end bound.
  QueryParams endAt(Node indexValue, [ChildKey? key]) => throw UnimplementedError();

  /// With an exclusive end bound.
  QueryParams endBefore(Node indexValue, [ChildKey? key]) => throw UnimplementedError();

  /// Ordered by [index].
  QueryParams orderBy(Index index) => throw UnimplementedError();

  /// The wire object (`sp`, `sn`, `sin`, `ep`, `en`, `ein`, `l`, `vf`, `i`), equal to the JS SDK's.
  Map<String, Object?> toWireObject() => throw UnimplementedError();

  /// The query identifier: `default`, or the canonical JSON of [toWireObject] (JS
  /// `ObjectToUniqueKey`).
  String toQueryIdentifier() => throw UnimplementedError();

  /// The REST query parameters (`orderBy`, `startAt`, ..., `limitToFirst`).
  Map<String, String> toRestQueryStringParameters() => throw UnimplementedError();

  @override
  bool operator ==(Object other) => throw UnimplementedError();

  @override
  int get hashCode => throw UnimplementedError();

  @override
  String toString() => throw UnimplementedError();
}
