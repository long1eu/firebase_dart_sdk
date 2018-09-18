// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_firestore/src/firebase/firestore/model/base_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';

/// A dot separated path for navigating sub-objects with in a document
class FieldPath extends BasePath<FieldPath> {
  static final FieldPath keyPath =
      FieldPath.fromSingleSegment(DocumentKey.keyFieldName);

  static const FieldPath emptyPath = FieldPath._(const <String>[]);

  const FieldPath._(List<String> segments) : super(segments);

  /// Creates a [FieldPath] with a single field. Does not split on dots.
  factory FieldPath.fromSingleSegment(String fieldName) {
    return FieldPath._(List.unmodifiable(<String>[fieldName]));
  }

  /// Creates a [FieldPath] from a list of parsed field path segments.
  factory FieldPath.fromSegments(List<String> segments) {
    return segments.isEmpty ? FieldPath.emptyPath : FieldPath._(segments);
  }

  @override
  FieldPath createPathWithSegments(List<String> segments) {
    return FieldPath._(segments);
  }

  /// Creates a [FieldPath] from a server-encoded field path.
  static FieldPath fromServerFormat(String path) {
    final List<String> res = <String>[];
    StringBuffer buffer = StringBuffer();
    // TODO: We should make this more strict.
    // Right now, it allows non-identifier path components, even if they aren't escaped.

    int i = 0;

    // If we're inside '`' backticks, then we should ignore '.' dots.
    bool inBackticks = false;

    while (i < path.length) {
      int c = path.codeUnitAt(i);
      //U+005C => \
      if (c == 0x5C) {
        if (i + 1 == path.length) {
          throw ArgumentError('Trailing escape character is not allowed');
        }
        i++;
        buffer.write(path.codeUnitAt(i));
      } else
      //U+002E => .
      if (c == 0x2E) {
        if (!inBackticks) {
          String elem = buffer.toString();
          if (elem.isEmpty) {
            throw ArgumentError(
                'Invalid field path ($path). Paths must not be empty, begin '
                'with \'.\', end with \'.\', or contain \'..\'');
          }
          buffer = StringBuffer();
          res.add(elem);
        } else {
          // escaped, append to current segment
          buffer.write(c);
        }
      } else
      //U+0060 => `
      if (c == 0x60) {
        inBackticks = !inBackticks;
      } else {
        buffer.write(c);
      }
      i++;
    }
    String lastElem = buffer.toString();
    if (lastElem.isEmpty) {
      throw ArgumentError(
          'Invalid field path ($path). Paths must not be empty, begin with '
          '\'.\', end with \'.\', or contain \'..\'"');
    }
    res.add(lastElem);
    return FieldPath._(res);
  }

  /// Return true if the string could be used as a segment in a field path
  /// without escaping. Valid identifies follow the regex [a-zA-Z_][a-zA-Z0-9_]
  static bool _isValidIdentifier(String identifier) {
    if (identifier.isEmpty) {
      return false;
    }

    int first = identifier.codeUnitAt(0);
    if (first != 0x5F /* _ */ &&
        (first < 0x61 /* a */ || first > 0x7A /* z */) &&
        (first < 0x41 /* A */ || first > 0x5A /* Z */)) {
      return false;
    }

    for (int i = 1; i < identifier.length; i++) {
      int c = identifier.codeUnitAt(i);
      if (c != 0x5F /* _ */ &&
          (c < 0x61 /* a */ || c > 0x7A /* z */) &&
          (c < 0x41 /* A */ || c > 0x5A /* Z */) &&
          (c < 0x30 /* 0 */ || c > 0x39 /* 9 */)) {
        return false;
      }
    }
    return true;
  }

  @override
  String get canonicalString {
    StringBuffer builder = StringBuffer();
    for (int i = 0; i < length; i++) {
      if (i > 0) {
        builder.write(".");
      }
      // Escape backslashes and dots.
      String escaped = getSegment(i);
      escaped = escaped.replaceAll("\\", "\\\\").replaceAll("`", "\\`");

      if (!_isValidIdentifier(escaped)) {
        escaped = '`' + escaped + '`';
      }

      builder.write(escaped);
    }
    return builder.toString();
  }

  bool get isKeyField => this == keyPath;
}
