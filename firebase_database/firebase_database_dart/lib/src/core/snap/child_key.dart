/// A child name with its integer form parsed once. JS: plain `string` names with `nameCompare`
/// (`core/util/util.ts`); Android: `snapshot/ChildKey.java`.
library;

import 'package:firebase_database_dart/src/core/util/numbers.dart';

/// The name of a child; integer-like names (within int32) carry [intValue] and sort numerically
/// before every other name.
final class ChildKey implements Comparable<ChildKey> {
  /// Creates the key for [name], parsing its integer form once.
  ///
  /// The names of [min], [max], [priority] and [info] return those constants.
  factory ChildKey(String name) {
    switch (name) {
      case '.priority':
        return priority;
      case '.info':
        return info;
      case '[MIN_NAME]':
        return min;
      case '[MAX_NAME]':
        return max;
    }
    return ChildKey._(name, tryParseIntKey(name));
  }

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
  bool get isPriorityKey => identical(this, priority) || name == '.priority';

  /// Whether the name is integer-like.
  bool get isInt => intValue != null;

  @override
  int compareTo(ChildKey other) {
    if (identical(this, other)) {
      return 0;
    } else if (identical(this, min) || identical(other, max)) {
      return -1;
    } else if (identical(other, min) || identical(this, max)) {
      return 1;
    }
    final int? a = intValue;
    final int? b = other.intValue;
    if (a != null) {
      if (b == null) {
        return -1;
      }
      final int diff = a - b;
      return diff == 0 ? name.length - other.name.length : diff;
    } else if (b != null) {
      return 1;
    }
    return name.compareTo(other.name);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ChildKey && other.name == name;

  @override
  int get hashCode => name.hashCode;

  /// The name.
  @override
  String toString() => name;
}
