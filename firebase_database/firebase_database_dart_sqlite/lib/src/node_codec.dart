import 'dart:convert';
import 'dart:typed_data';

// not exported by storage_engine.dart
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/storage_engine.dart';

/// The `path` column form of a [Path]: `/` for the root, `/a/b/` otherwise (Android's
/// `pathToKey`, `SqlPersistenceStorageEngine.java:1066-1077`).
///
/// With SQLite's BINARY collation the subtree of a key `k` is exactly the range `[k, rangeEnd(k))`:
/// keys never contain `/`, every descendant starts with `k`, and `0` is the byte after `/`.
abstract final class PathKey {
  /// The key of [path].
  static String of(Path path) => path.isEmpty ? '/' : '$path/';

  /// The path of a stored [key].
  static Path toPath(String key) => Path(key);

  /// The first key after the subtree of [key]: its trailing `/` replaced by `0`.
  static String rangeEnd(String key) => '${key.substring(0, key.length - 1)}0';

  /// The keys of [path] and of each of its ancestors, deepest first.
  static List<String> selfAndAncestors(Path path) {
    final List<String> keys = <String>[];
    Path? current = path;
    while (current != null) {
      keys.add(of(current));
      current = current.parent;
    }
    return keys;
  }
}

/// The value column form of nodes and merges: the export JSON (`.value`, `.priority`, unresolved
/// server values kept) as UTF-8 bytes, as Android and iOS store it.
///
/// Numbers are whatever the data layer's [Node.toJson] gives and [nodeFromJson] takes: an `int`
/// stays an `int` at any size, a `double` such as `1.0` or `-0.0` stays a `double`. This codec adds
/// no number rule of its own.
///
/// Decoding is bounded (threat model T10/T22): a non-recursive scan rejects nesting deeper than
/// [maxNestingDepth] before the JSON decoder and the recursive [nodeFromJson] run, so a damaged or
/// hostile file can not overflow the stack.
abstract final class NodeCodec {
  /// The deepest nesting of objects and arrays a stored value may have: 32 levels of data, the
  /// `.value`/`.priority` wrappers and a margin (threat model T10).
  static const int maxNestingDepth = 64;

  /// The empty node (no value, no children, no priority).
  static final Node emptyNode = nodeFromJson(null);

  static final Converter<List<int>, Object?> _decoder = utf8.decoder.fuse(
    json.decoder,
  );

  /// The stored form of [node].
  static Uint8List encodeNode(Node node) =>
      _encode(node.toJson(exportFormat: true));

  /// The stored form of [merge]: a map from relative path strings to export JSON.
  static Uint8List encodeMerge(CompoundWrite merge) =>
      _encode(merge.toJson(exportFormat: true));

  /// The node stored as [bytes]. Throws a [FormatException] or an [ArgumentError] when the bytes
  /// are not a stored node.
  static Node decodeNode(Uint8List bytes) => nodeFromJson(decodeJson(bytes));

  /// The merge stored as [bytes]. Throws a [FormatException] or an [ArgumentError] when the bytes
  /// are not a stored merge.
  static CompoundWrite decodeMerge(Uint8List bytes) {
    final Object? value = decodeJson(bytes);
    if (value is! Map<String, Object?>) {
      throw const FormatException('A stored merge is not a JSON object.');
    }
    return CompoundWrite.fromValue(value);
  }

  /// The JSON value of [bytes], after the nesting check. Throws a [FormatException] when the bytes
  /// are not UTF-8 JSON or nest deeper than [maxNestingDepth].
  static Object? decodeJson(List<int> bytes) {
    checkNesting(bytes);
    return _decoder.convert(bytes);
  }

  /// Throws a [FormatException] when the JSON in [bytes] nests objects and arrays deeper than
  /// [maxNestingDepth]. Brackets inside strings do not count. Does not validate the JSON.
  static void checkNesting(List<int> bytes) {
    int depth = 0;
    bool inString = false;
    bool escaped = false;
    for (int i = 0; i < bytes.length; i++) {
      final int byte = bytes[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (byte == _backslash) {
          escaped = true;
        } else if (byte == _quote) {
          inString = false;
        }
      } else if (byte == _quote) {
        inString = true;
      } else if (byte == _openBrace || byte == _openBracket) {
        depth++;
        if (depth > maxNestingDepth) {
          throw FormatException(
            'A stored value nests deeper than $maxNestingDepth levels.',
          );
        }
      } else if (byte == _closeBrace || byte == _closeBracket) {
        depth--;
      }
    }
  }

  static Uint8List _encode(Object? value) => utf8.encode(jsonEncode(value));

  static const int _quote = 0x22;
  static const int _backslash = 0x5C;
  static const int _openBrace = 0x7B;
  static const int _closeBrace = 0x7D;
  static const int _openBracket = 0x5B;
  static const int _closeBracket = 0x5D;
}
