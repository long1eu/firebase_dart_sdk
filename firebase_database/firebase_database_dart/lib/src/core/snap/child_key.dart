/// A child name with its integer form parsed once. JS: plain `string` names with `nameCompare`
/// (`core/util/util.ts`); Android: `snapshot/ChildKey.java`.
library;

/// The name of a child; integer-like names (within int32) carry [intValue] and sort numerically
/// before every other name.
final class ChildKey implements Comparable<ChildKey> {
  /// Creates the key for [name], parsing its integer form once.
  factory ChildKey(String name) => throw UnimplementedError();

  const ChildKey._(this.name, this.intValue);

  /// The key that sorts before every other key (`[MIN_NAME]`).
  static const ChildKey min = ChildKey._('[MIN_NAME]', null);

  /// The key that sorts after every other key (`[MAX_NAME]`).
  static const ChildKey max = ChildKey._('[MAX_NAME]', null);

  /// The `.priority` pseudo-child.
  static const ChildKey priority = ChildKey._('.priority', null);

  /// The `.info` root key.
  static const ChildKey info = ChildKey._('.info', null);

  /// The name.
  final String name;

  /// The integer value of an integer-like name, else null.
  final int? intValue;

  /// Whether this is the `.priority` key.
  bool get isPriorityKey => throw UnimplementedError();

  /// Whether the name is integer-like.
  bool get isInt => throw UnimplementedError();

  @override
  int compareTo(ChildKey other) => throw UnimplementedError();

  @override
  bool operator ==(Object other) => throw UnimplementedError();

  @override
  int get hashCode => throw UnimplementedError();

  @override
  String toString() => throw UnimplementedError();
}
