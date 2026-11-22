/// A range merge (`rm` push) applied to a cached node. JS: none; Android:
/// `snapshot/RangeMerge.java`.
library;

import 'package:firebase_database_dart/src/core/connection/wire_range_merge.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';

/// Replaces every leaf after [exclusiveStart] and up to [inclusiveEnd] with the leaves of [snap]
/// in that range; a null bound is unbounded.
final class RangeMerge {
  /// Creates a range merge.
  const RangeMerge(this.exclusiveStart, this.inclusiveEnd, this.snap);

  /// Converts the wire form.
  factory RangeMerge.fromWire(WireRangeMerge merge) =>
      throw UnimplementedError();

  /// The exclusive start, or null for minus infinity.
  final Path? exclusiveStart;

  /// The inclusive end, or null for plus infinity.
  final Path? inclusiveEnd;

  /// The new data of the range.
  final Node snap;

  /// [node] with this merge applied.
  Node applyTo(Node node) => throw UnimplementedError();

  @override
  String toString() => throw UnimplementedError();
}
