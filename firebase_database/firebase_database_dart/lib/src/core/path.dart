/// Database paths. JS: `core/util/Path.ts` (`Path`, `ValidationPath`); Android: `core/Path.java`,
/// `core/ValidationPath.java`.
library;

import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/util/hash.dart';

/// The deepest path a write may have.
const int maxPathDepth = 32;

/// The longest path a write may have, in UTF-8 bytes.
const int maxPathLengthBytes = 768;

/// An immutable path of [ChildKey] segments, such as `/users/ada`.
final class Path implements Comparable<Path> {
  /// Parses [pathString]: segments separated by `/`, empty segments ignored, so `a/b`, `/a/b`
  /// and `/a//b/` are the same path.
  factory Path(String pathString) {
    if (pathString.isEmpty || pathString == '/') {
      return empty;
    }
    return Path.fromKeys(<ChildKey>[
      for (final String piece in pathString.split('/'))
        if (piece.isNotEmpty) ChildKey(piece),
    ]);
  }

  /// A path of [segments].
  const Path.fromKeys(this.segments);

  /// A path of the wire segment strings [segments]; empty strings are skipped.
  factory Path.fromStrings(List<String> segments) => Path.fromKeys(<ChildKey>[
    for (final String piece in segments)
      if (piece.isNotEmpty) ChildKey(piece),
  ]);

  /// The root path.
  static const Path empty = Path.fromKeys(<ChildKey>[]);

  /// The segments, root first.
  final List<ChildKey> segments;

  /// The first segment, or null for the root.
  ChildKey? get front => segments.isEmpty ? null : segments.first;

  /// The last segment, or null for the root.
  ChildKey? get back => segments.isEmpty ? null : segments.last;

  /// The number of segments.
  int get length => segments.length;

  /// Whether this is the root.
  bool get isEmpty => segments.isEmpty;

  /// The path without its first segment.
  Path popFront() {
    if (segments.length <= 1) {
      return empty;
    }
    return Path.fromKeys(segments.sublist(1));
  }

  /// The parent, or null for the root.
  Path? get parent {
    if (segments.isEmpty) {
      return null;
    }
    if (segments.length == 1) {
      return empty;
    }
    return Path.fromKeys(segments.sublist(0, segments.length - 1));
  }

  /// This path with [key] appended.
  Path child(ChildKey key) => Path.fromKeys(<ChildKey>[...segments, key]);

  /// This path with every segment of [other] appended.
  Path childPath(Path other) {
    if (other.isEmpty) {
      return this;
    }
    if (isEmpty) {
      return other;
    }
    return Path.fromKeys(<ChildKey>[...segments, ...other.segments]);
  }

  /// The path of [inner] relative to [outer]; [inner] must be [outer] or below it.
  ///
  /// Throws [StateError] otherwise.
  static Path relative(Path outer, Path inner) {
    if (!outer.contains(inner)) {
      throw StateError(
        'INTERNAL ERROR: innerPath ($inner) is not within outerPath ($outer)',
      );
    }
    if (outer.isEmpty) {
      return inner;
    }
    if (outer.length == inner.length) {
      return empty;
    }
    return Path.fromKeys(inner.segments.sublist(outer.length));
  }

  /// Whether [other] is this path or below it.
  bool contains(Path other) {
    final List<ChildKey> mine = segments;
    final List<ChildKey> theirs = other.segments;
    if (mine.length > theirs.length) {
      return false;
    }
    for (int i = 0; i < mine.length; i++) {
      if (mine[i] != theirs[i]) {
        return false;
      }
    }
    return true;
  }

  /// The segment names (the wire and persistence form).
  List<String> toStringList() => <String>[
    for (final ChildKey key in segments) key.name,
  ];

  /// The path with each segment percent-encoded, as REST URLs use it.
  String toUrlEncodedString() {
    if (segments.isEmpty) {
      return '/';
    }
    final StringBuffer buffer = StringBuffer();
    for (final ChildKey key in segments) {
      buffer
        ..write('/')
        ..write(Uri.encodeComponent(key.name));
    }
    return buffer.toString();
  }

  /// Compares segment by segment with the child-key order; a prefix sorts first.
  @override
  int compareTo(Path other) {
    final List<ChildKey> mine = segments;
    final List<ChildKey> theirs = other.segments;
    final int common = mine.length < theirs.length
        ? mine.length
        : theirs.length;
    for (int i = 0; i < common; i++) {
      final int cmp = mine[i].compareTo(theirs[i]);
      if (cmp != 0) {
        return cmp;
      }
    }
    return mine.length == theirs.length
        ? 0
        : (mine.length < theirs.length ? -1 : 1);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! Path) {
      return false;
    }
    final List<ChildKey> mine = segments;
    final List<ChildKey> theirs = other.segments;
    if (mine.length != theirs.length) {
      return false;
    }
    for (int i = 0; i < mine.length; i++) {
      if (mine[i] != theirs[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(segments);

  /// The wire form: `/a/b`, `/` for the root.
  @override
  String toString() {
    if (segments.isEmpty) {
      return '/';
    }
    final StringBuffer buffer = StringBuffer();
    for (final ChildKey key in segments) {
      buffer
        ..write('/')
        ..write(key.name);
    }
    return buffer.toString();
  }
}

/// A mutable path used while validating data, tracking depth and UTF-8 length to enforce
/// [maxPathDepth] and [maxPathLengthBytes].
///
/// Errors are [ArgumentError]s carrying the JS message text.
final class ValidationPath {
  /// Starts at [path]; errors are prefixed with [errorPrefix].
  ValidationPath(Path path, this.errorPrefix) : _parts = path.toStringList() {
    // One '/' per segment, at least one for the root.
    _byteLength = _parts.isEmpty ? 1 : _parts.length;
    for (final String part in _parts) {
      _byteLength += utf8Length(part);
    }
    _checkValid();
  }

  /// The prefix of every error message.
  final String errorPrefix;

  final List<String> _parts;
  int _byteLength = 0;

  /// Descends into [childName]; throws if the path gets too long or too deep.
  void push(String childName) {
    // Count the needed '/'.
    if (_parts.isNotEmpty) {
      _byteLength += 1;
    }
    _parts.add(childName);
    _byteLength += utf8Length(childName);
    _checkValid();
  }

  /// Ascends one level.
  void pop() {
    final String last = _parts.removeLast();
    _byteLength -= utf8Length(last);
    // Un-count the previous '/'.
    if (_parts.isNotEmpty) {
      _byteLength -= 1;
    }
  }

  void _checkValid() {
    if (_byteLength > maxPathLengthBytes) {
      throw ArgumentError(
        '${errorPrefix}has a key path longer than $maxPathLengthBytes bytes '
        '($_byteLength).',
      );
    }
    if (_parts.length > maxPathDepth) {
      throw ArgumentError(
        '${errorPrefix}path specified exceeds the maximum depth that can be '
        'written ($maxPathDepth) or object contains a cycle '
        '${toErrorString()}',
      );
    }
  }

  /// The path for error messages (`in property 'a.b'`).
  String toErrorString() =>
      _parts.isEmpty ? '' : "in property '${_parts.join('.')}'";
}
