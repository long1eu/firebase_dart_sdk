// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'package:firebase_firestore/src/firebase/firestore/model/base_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/field_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/resource_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';

/// Helpers for dealing with paths stored in SQLite.
///
/// * Paths in their canonical string form do not sort as the server sorts them.
/// Specifically the server splits paths into segments first and then sorts,
/// putting end-of-segment before any character. In a UTF-8 string encoding the
/// slash ('/') or dot ('.') that denotes the end-of-segment naturally comes
/// after other characters so the intent here is to encode the path delimiters
/// in such a way that the resulting strings sort naturally.
///
/// * Paths are also used for prefix scans so it's important to distinguish
/// whole segments from any longer segments of which they might be a prefix. For
/// example, it's important to make it possible to scan documents in a
/// collection "foo" without encountering documents in a collection "foobar".
///
/// * Separate from the concerns about path ordering and separation, SQLite
/// imposes additional restrictions since it does not handle TEXT fields with
/// embedded NUL bytes particularly well. Rather than deal with these
/// limitations, this implementation sidesteps the issue entirely by avoiding
/// NUL bytes in the output altogether.
///
/// * Taken together this means paths when encoded for storage in SQLite have
/// the following characteristics:
///
/// <ul>
/// <li>Segment separators ("/" or ".") sort before everything else.
/// <li>All paths have a trailing separator.
/// <li>NUL bytes do not exist in the output, since SQLite doesn't treat them
/// well.
/// </ul>
///
/// * Therefore paths are encoded into string form using the following rules:
///
/// <ul>
/// <li>'\x01' is used as an escape character.
/// <li>Path separators are encoded as "\x01\x01"
/// <li>NUL bytes are encoded as "\x01\x10"
/// <li>'\x01' is encoded as "\x01\x11"
/// </ul>
///
/// * This encoding leaves some room between path separators and the NUL byte
/// just in case we decide to support integer document ids after all.
///
/// * Note that characters treated specially by the backend
/// (e.g. '.', '/', and '~') are not treated specially here. This class assumes
/// that any unescaping of path strings into actual Path objects will handle
/// these characters there.

class EncodedPath {
  static const int _escape = 0x01;
  static const int _encodedSeparator = 0x01;
  static const int _encodedNul = 0x10;
  static const int _encodedEscape = 0x11;

  /// Encodes a path into a SQLite-compatible string form.
  static String encode<B extends BasePath<B>>(B path) {
    final StringBuffer result = StringBuffer();
    final int length = path.length;
    for (int i = 0; i < length; i++) {
      if (result.length > 0) {
        _encodeSeparator(result);
      }
      _encodeSegment(path.getSegment(i), result);
    }
    _encodeSeparator(result);
    return result.toString();
  }

  /// Encodes a single segment of a path into the given StringBuffer.
  static void _encodeSegment(String segment, StringBuffer result) {
    final int length = segment.length;
    for (int i = 0; i < length; i++) {
      final int c = segment.codeUnitAt(i);
      if (c == 0x0) {
        result..writeCharCode(_escape)..writeCharCode(_encodedNul);
      } else if (c == _escape) {
        result..writeCharCode(_escape)..writeCharCode(_encodedEscape);
      } else {
        result.writeCharCode(c);
      }
    }
  }

  /// Encodes a path separator into the given [StringBuffer].
  static void _encodeSeparator(StringBuffer result) {
    result..writeCharCode(_escape)..writeCharCode(_encodedSeparator);
  }

  /// Decodes the given SQLite-compatible string form of a resource path into a
  /// [ResourcePath] instance. Note that this method is not suitable for use
  /// with decoding resource names from the server; those are One Platform
  /// format strings.
  static ResourcePath decodeResourcePath(String path) {
    return ResourcePath.fromSegments(_decode(path));
  }

  static FieldPath decodeFieldPath(String path) {
    return FieldPath.fromSegments(_decode(path));
  }

  static List<String> _decode(String path) {
    // Even the empty path must encode as a path of at least length 2. A path
    // with length of exactly 2 must be the empty path.
    final int length = path.length;
    Assert.hardAssert(length >= 2, 'Invalid path "$path"');
    if (length == 2) {
      Assert.hardAssert(
        path.codeUnitAt(0) == _escape &&
            path.codeUnitAt(1) == _encodedSeparator,
        'Non-empty path "$path" had length 2',
      );
      return <String>[];
    }

    // Escape characters cannot exist past the second-to-last position in the
    // source value.
    final int lastReasonableEscapeIndex = path.length - 2;

    final List<String> segments = <String>[];
    final StringBuffer segmentBuilder = StringBuffer();

    for (int start = 0; start < length;) {
      // The last two characters of a valid encoded path must be a separator,
      // so there must be an end to this segment.
      final int end = path.indexOf(String.fromCharCode(_escape), start);
      if (end < 0 || end > lastReasonableEscapeIndex) {
        throw ArgumentError('Invalid encoded resource path: "$path"');
      }

      final int next = path.codeUnitAt(end + 1);

      if (next == _encodedSeparator) {
        final String currentPiece = path.substring(start, end);
        String segment;
        if (segmentBuilder.length == 0) {
          // Avoid copying for the common case of a segment that excludes
          // \0 and \001.
          segment = currentPiece;
        } else {
          segmentBuilder.write(currentPiece);
          segment = segmentBuilder.toString();
          segmentBuilder.clear();
        }

        segments.add(segment);
      } else if (next == _encodedNul) {
        segmentBuilder
          ..write(path.substring(start, end))
          ..writeCharCode(0x00);
      } else if (next == _encodedEscape) {
        // The escape character can be use used in the output to encode itself.
        segmentBuilder.write(path.substring(start, end + 1));
      } else {
        throw ArgumentError('Invalid encoded resource path: "$path"');
      }

      start = end + 2;
    }

    return segments;
  }

  /// Computes the prefix successor of the given path, computed by encode above.
  /// A prefix successor is the first key that cannot be prefixed by the given
  /// path. It's useful for defining the end of a prefix scan such that all keys
  /// in the scan have the same prefix.
  ///
  /// * Note that this is not a general prefix successor implementation, which
  /// is tricky to get right with Strings, given that they encode down to UTF-8.
  /// Instead this relies on the fact that all paths encoded by this class are
  /// always terminated with a separator, and so a successor can always be
  /// cheaply computed by incrementing the last character of the path.
  static String prefixSuccessor(String path) {
    final List<int> list = path.codeUnits.toList();
    // TODO: this really should be a general thing, but not worth it right now
    Assert.hardAssert(list.last == _encodedSeparator,
        'successor may only operate on paths generated by encode');
    list[list.length - 1] = list.last + 1;
    return String.fromCharCodes(list);
  }
}
