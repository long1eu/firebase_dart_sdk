/// A range merge as the server sends it in an `rm` push. JS: none; Android:
/// `connection/RangeMerge.java`.
///
/// Cross-team seam: JSON only.
library;

/// One element of the `d` list of an `rm` push: `{"s": start, "e": end, "m": data}`.
final class WireRangeMerge {
  /// Creates a range merge.
  const WireRangeMerge({
    this.exclusiveStart,
    this.inclusiveEnd,
    required this.data,
  });

  /// The exclusive start path in wire form (`/a/b`), or null for minus infinity.
  final String? exclusiveStart;

  /// The inclusive end path in wire form, or null for plus infinity.
  final String? inclusiveEnd;

  /// The new data of the range, decoded JSON.
  final Object? data;
}
