import 'dart:typed_data';

// switch to storage_engine.dart
import 'package:firebase_database_dart/src/core/compound_write.dart';
// switch to storage_engine.dart
import 'package:firebase_database_dart/src/core/path.dart';
// switch to storage_engine.dart
import 'package:firebase_database_dart/src/core/persistence/prune_forest.dart';
// switch to storage_engine.dart
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
// switch to storage_engine.dart
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
// switch to storage_engine.dart
import 'package:firebase_database_dart/src/core/snap/indexes/key_index.dart';
// switch to storage_engine.dart
import 'package:firebase_database_dart/src/core/snap/node.dart';
// switch to storage_engine.dart
import 'package:firebase_database_dart/src/core/util/hash.dart';
// switch to storage_engine.dart
import 'package:firebase_database_dart/src/core/util/immutable_tree.dart';
// switch to storage_engine.dart (DatabaseLogger: the main library if it is not there)
import 'package:firebase_database_dart/src/core/util/logger.dart';
// switch to storage_engine.dart
import 'package:firebase_database_dart/src/core/util/node_size_estimator.dart';
import 'package:firebase_database_dart_sqlite/src/node_codec.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_connection.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// The `server_cache` table in Android's nested-row layout
/// (`SqlPersistenceStorageEngine.java:86-88, 881-1101`), without its 256 KiB leaf parts.
///
/// A row holds the node at its path. Rows may overlap: a row below another one overrides that
/// part of it, and every write first deletes its own subtree. A children node whose estimated
/// JSON size is above [splitThreshold] is stored child by child (recursively), plus a `.priority`
/// row when it has a priority, plus an empty row at its own path that hides what an ancestor row
/// holds there.
///
/// Keeps the byte size of the table ([size]: path bytes plus value bytes of every row) in memory:
/// a full `SUM` at open and after a prune, plus the bytes of every row written, minus the bytes
/// measured before every delete, in the same transaction.
final class ServerCacheRows {
  /// Rows of the connection; unexpected rows are reported to the logger.
  ServerCacheRows(this._connection, this._log) {
    size = measureAll();
  }

  final SqliteConnection _connection;
  final DatabaseLogger _log;

  /// A children node above this estimated JSON size is stored child by child (Android's
  /// `CHILDREN_NODE_SPLIT_SIZE_THRESHOLD`).
  static const int splitThreshold = 16 * 1024;

  /// The most keys bound in one `IN (...)` list: `SQLITE_MAX_VARIABLE_NUMBER` was 999 before
  /// SQLite 3.32.
  static const int chunkSize = 500;

  /// The bytes of every row, paths included; restored by the engine on rollback.
  int size = 0;

  static const String _sumSql =
      'SELECT coalesce(sum(length(CAST(path AS BLOB)) + length(value)), 0) FROM server_cache';

  /// The bytes of every row, counted by SQLite.
  int measureAll() => _scalarInt(_connection.select(_sumSql));

  int _measureRange(String start, String end) => _scalarInt(
    _connection.select('$_sumSql WHERE path >= ? AND path < ?', <Object?>[
      start,
      end,
    ]),
  );

  static int _scalarInt(Iterable<sqlite.Row> rows) {
    for (final sqlite.Row row in rows) {
      final Object? value = row.columnAt(0);
      return value is int ? value : 0;
    }
    return 0;
  }

  /// The node at [path], combined from every row that holds part of it.
  Node load(Path path) {
    Node node = ChildrenNode.empty;
    bool sawDescendant = false;
    final Map<Path, Node> priorities = <Path, Node>{};
    int skipped = 0;
    for (final sqlite.Row row in _selectNested(path, withValues: true)) {
      final Object? key = row.columnAt(0);
      final Node? rowNode = _decode(row.columnAt(1));
      if (key is! String || rowNode == null) {
        skipped++;
        continue;
      }
      final Path rowPath = PathKey.toPath(key);
      if (rowPath.back?.isPriorityKey ?? false) {
        // Applied last: deeper rows may still fill the node the priority belongs to.
        priorities[rowPath] = rowNode;
      } else if (rowPath.contains(path) && !sawDescendant) {
        node = rowNode.getChild(Path.relative(rowPath, path));
      } else if (path.contains(rowPath)) {
        sawDescendant = true;
        node = node.updateChild(Path.relative(path, rowPath), rowNode);
      } else {
        skipped++;
      }
    }
    for (final MapEntry<Path, Node> entry in priorities.entries) {
      if (path.contains(entry.key)) {
        node = node.updateChild(Path.relative(path, entry.key), entry.value);
      }
    }
    if (skipped > 0) {
      _log(
        DatabaseLogLevel.warning,
        'Realtime Database offline cache: $skipped cached row(s) could not be read and were '
        'skipped.',
      );
    }
    return node;
  }

  Node? _decode(Object? value) {
    if (value is! Uint8List) {
      return null;
    }
    try {
      return NodeCodec.decodeNode(value);
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  /// The rows at [path], at its ancestors and below it, ordered by path (ancestors first).
  Iterable<sqlite.Row> _selectNested(Path path, {required bool withValues}) {
    final List<String> ancestors = PathKey.selfAndAncestors(path);
    final String start = ancestors.first;
    final String marks = List<String>.filled(ancestors.length, '?').join(', ');
    return _connection.select(
      'SELECT path${withValues ? ', value' : ''} FROM server_cache '
      'WHERE path IN ($marks) OR (path > ? AND path < ?) ORDER BY path',
      <Object?>[...ancestors, start, PathKey.rangeEnd(start)],
    );
  }

  /// Replaces the cache at [path] with [node].
  void overwrite(Path path, Node node) {
    _removeNested(path);
    _saveNested(path, node);
    final Path? parent = path.parent;
    if (node.isEmpty && parent != null) {
      _dropPrioritiesOfEmptiedNodes(parent);
    }
  }

  /// Replaces each child of [node] below [path], leaving the other children alone.
  ///
  /// A node holds no empty children, so this never empties a node.
  void mergeChildren(Path path, Node node) {
    node.forEachChild(keyIndex, (ChildKey key, Node child) {
      _removeNested(path.child(key));
      _saveNested(path.child(key), child);
      return false;
    });
  }

  /// Replaces the node at each path of [children] below [path].
  void mergeWrite(Path path, CompoundWrite children) {
    final List<Path> emptied = <Path>[];
    for (final MapEntry<Path, Node> write in children.entries) {
      final Path target = path.childPath(write.key);
      _removeNested(target);
      _saveNested(target, write.value);
      final Path? parent = target.parent;
      if (write.value.isEmpty && parent != null) {
        emptied.add(parent);
      }
    }
    for (final Path parent in emptied) {
      _dropPrioritiesOfEmptiedNodes(parent);
    }
  }

  /// Deletes the `.priority` rows of [deepest] and its ancestors whose node is now empty.
  ///
  /// A node loses its priority when it becomes empty, but a priority stored in a row of its own
  /// would otherwise come back when a later write fills the node again (Android's ignored
  /// `priorityIsCleared` test). Costs one indexed lookup per deletion.
  void _dropPrioritiesOfEmptiedNodes(Path deepest) {
    final List<String> keys = <String>[
      for (final String key in PathKey.selfAndAncestors(deepest))
        '$key.priority/',
    ];
    final String marks = List<String>.filled(keys.length, '?').join(', ');
    final List<String> found = <String>[
      for (final sqlite.Row row in _connection.select(
        'SELECT path FROM server_cache WHERE path IN ($marks)',
        keys,
      ))
        if (row.columnAt(0) case final String key) key,
    ];
    // Whether a node is empty does not depend on the priorities of its children, so the order of
    // these checks does not matter.
    for (final String priorityKey in found) {
      final Path owner = PathKey.toPath(priorityKey).parent!;
      if (load(owner).isEmpty) {
        _removeNested(PathKey.toPath(priorityKey));
      }
    }
  }

  int _saveNested(Path path, Node node) {
    if (!node.isLeafNode && estimateSerializedNodeSize(node) > splitThreshold) {
      int rows = 0;
      node.forEachChild(keyIndex, (ChildKey key, Node child) {
        rows += _saveNested(path.child(key), child);
        return false;
      });
      final Node priority = node.priority;
      if (!priority.isEmpty) {
        _saveRow(path.child(ChildKey.priority), priority);
        rows++;
      }
      // Hides what a row of an ancestor holds at this path.
      _saveRow(path, ChildrenNode.empty);
      return rows + 1;
    }
    _saveRow(path, node);
    return 1;
  }

  void _saveRow(Path path, Node node) {
    final String key = PathKey.of(path);
    final Uint8List value = NodeCodec.encodeNode(node);
    _connection.execute(
      'INSERT OR REPLACE INTO server_cache (path, value) VALUES (?, ?)',
      <Object?>[key, value],
    );
    size += utf8Length(key) + value.length;
  }

  void _removeNested(Path path) {
    final String start = PathKey.of(path);
    final String end = PathKey.rangeEnd(start);
    size -= _measureRange(start, end);
    _connection.execute(
      'DELETE FROM server_cache WHERE path >= ? AND path < ?',
      <Object?>[start, end],
    );
  }

  /// Deletes the rows below [root] that [forest] prunes and does not keep, then re-saves the kept
  /// parts of deleted rows (Android's `pruneCache` and `pruneTreeRecursive`,
  /// `SqlPersistenceStorageEngine.java:645-774`, with paths instead of row ids). Rows above [root]
  /// and rows neither pruned nor kept are left alone with a warning.
  void prune(Path root, PruneForest forest) {
    ImmutableTree<String> toPrune = ImmutableTree<String>.empty();
    ImmutableTree<String> toKeep = ImmutableTree<String>.empty();
    int above = 0;
    int unmarked = 0;
    for (final sqlite.Row row in _selectNested(root, withValues: false)) {
      final Object? key = row.columnAt(0);
      if (key is! String) {
        unmarked++;
        continue;
      }
      final Path rowPath = PathKey.toPath(key);
      if (!root.contains(rowPath)) {
        above++;
        continue;
      }
      final Path relative = Path.relative(root, rowPath);
      if (forest.shouldPruneUnkeptDescendants(relative)) {
        toPrune = toPrune.set(relative, key);
      } else if (forest.shouldKeep(relative)) {
        toKeep = toKeep.set(relative, key);
      } else {
        unmarked++;
      }
    }
    _warnSkippedPruneRows(above, unmarked);
    if (toPrune.isEmpty) {
      return;
    }
    final List<MapEntry<Path, Node>> resave = <MapEntry<Path, Node>>[];
    _collectResaves(root, Path.empty, toPrune, toKeep, forest, resave);
    _deleteRows(<String>[
      for (final MapEntry<Path, String> e in toPrune.entries) e.value,
    ]);
    for (final MapEntry<Path, Node> entry in resave) {
      _saveNested(root.childPath(entry.key), entry.value);
    }
    size = measureAll();
    _connection.execute('PRAGMA incremental_vacuum');
  }

  void _warnSkippedPruneRows(int above, int unmarked) {
    if (above > 0) {
      _log(
        DatabaseLogLevel.warning,
        'Realtime Database offline cache: a prune found $above row(s) stored above its root; '
        'they were left alone.',
      );
    }
    if (unmarked > 0) {
      _log(
        DatabaseLogLevel.warning,
        'Realtime Database offline cache: a prune found $unmarked row(s) neither pruned nor '
        'kept; they were left alone.',
      );
    }
  }

  /// Walks the rows to prune; for the top-most row on each branch, adds the kept parts of its
  /// node that have no kept row of their own to [resave] (paths relative to [pruneRoot]).
  void _collectResaves(
    Path pruneRoot,
    Path relativePath,
    ImmutableTree<String> toPrune,
    ImmutableTree<String> toKeep,
    PruneForest forest,
    List<MapEntry<Path, Node>> resave,
  ) {
    if (toPrune.value == null) {
      for (final MapEntry<ChildKey, ImmutableTree<String>> child
          in toPrune.children.entries) {
        _collectResaves(
          pruneRoot,
          relativePath.child(child.key),
          child.value,
          toKeep.getChild(child.key),
          forest.child(child.key),
          resave,
        );
      }
      return;
    }
    final List<Path> keptWithoutRow = forest.foldKeptNodes<List<Path>>(
      <Path>[],
      (Path keepPath, List<Path> paths) {
        if (toKeep.get(keepPath) == null) {
          paths.add(keepPath);
        }
        return paths;
      },
    );
    if (keptWithoutRow.isEmpty) {
      return;
    }
    final Node current = load(pruneRoot.childPath(relativePath));
    for (final Path keepPath in keptWithoutRow) {
      resave.add(
        MapEntry<Path, Node>(
          relativePath.childPath(keepPath),
          current.getChild(keepPath),
        ),
      );
    }
  }

  void _deleteRows(List<String> keys) {
    for (int start = 0; start < keys.length; start += chunkSize) {
      final int end = start + chunkSize < keys.length
          ? start + chunkSize
          : keys.length;
      final List<String> chunk = keys.sublist(start, end);
      final String marks = List<String>.filled(chunk.length, '?').join(', ');
      _connection.execute(
        'DELETE FROM server_cache WHERE path IN ($marks)',
        chunk,
      );
    }
  }
}
