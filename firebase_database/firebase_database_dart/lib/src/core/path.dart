/// Database paths. JS: `core/util/Path.ts` (`Path`, `ValidationPath`); Android: `core/Path.java`,
/// `core/ValidationPath.java`.
library;

import 'package:firebase_database_dart/src/core/snap/child_key.dart';

/// The deepest path a write may have.
const int maxPathDepth = 32;

/// The longest path a write may have, in UTF-8 bytes.
const int maxPathLengthBytes = 768;

/// An immutable path of [ChildKey] segments, such as `/users/ada`.
final class Path implements Comparable<Path> {
  /// Parses [pathString]: segments separated by `/`, empty segments ignored.
  factory Path(String pathString) => throw UnimplementedError();

  /// A path of [segments].
  const Path.fromKeys(this.segments);

  /// A path of the wire segment strings [segments].
  factory Path.fromStrings(List<String> segments) => throw UnimplementedError();

  /// The root path.
  static const Path empty = Path.fromKeys(<ChildKey>[]);

  /// The segments, root first.
  final List<ChildKey> segments;

  /// The first segment, or null for the root.
  ChildKey? get front => throw UnimplementedError();

  /// The last segment, or null for the root.
  ChildKey? get back => throw UnimplementedError();

  /// The number of segments.
  int get length => throw UnimplementedError();

  /// Whether this is the root.
  bool get isEmpty => throw UnimplementedError();

  /// The path without its first segment.
  Path popFront() => throw UnimplementedError();

  /// The parent, or null for the root.
  Path? get parent => throw UnimplementedError();

  /// This path with [key] appended.
  Path child(ChildKey key) => throw UnimplementedError();

  /// This path with every segment of [other] appended.
  Path childPath(Path other) => throw UnimplementedError();

  /// The path of [inner] relative to [outer]; [inner] must be [outer] or below it.
  static Path relative(Path outer, Path inner) => throw UnimplementedError();

  /// Whether [other] is this path or below it.
  bool contains(Path other) => throw UnimplementedError();

  /// The segment names (the wire and persistence form).
  List<String> toStringList() => throw UnimplementedError();

  /// The path with each segment percent-encoded, as REST URLs use it.
  String toUrlEncodedString() => throw UnimplementedError();

  /// Compares segment by segment with the child-key order; a prefix sorts first.
  @override
  int compareTo(Path other) => throw UnimplementedError();

  @override
  bool operator ==(Object other) => throw UnimplementedError();

  @override
  int get hashCode => throw UnimplementedError();

  /// The wire form: `/a/b`, `/` for the root.
  @override
  String toString() => throw UnimplementedError();
}

/// A mutable path used while validating data, tracking depth and UTF-8 length to enforce
/// [maxPathDepth] and [maxPathLengthBytes].
final class ValidationPath {
  /// Starts at [path]; errors are prefixed with [errorPrefix].
  ValidationPath(Path path, this.errorPrefix) {
    throw UnimplementedError(path.toString());
  }

  /// The prefix of every error message.
  final String errorPrefix;

  /// Descends into [childName]; throws if the path gets too long or too deep.
  void push(String childName) => throw UnimplementedError();

  /// Ascends one level.
  void pop() => throw UnimplementedError();

  /// The path for error messages (`in property 'a.b'`).
  String toErrorString() => throw UnimplementedError();
}
