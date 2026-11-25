import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_database_dart/firebase_database_dart.dart'
    show DatabaseLogLevel, DatabaseLogger;
import 'package:firebase_database_dart/storage_engine.dart';
import 'package:firebase_database_dart_sqlite/src/node_codec.dart';
import 'package:firebase_database_dart_sqlite/src/sql_in_list.dart';
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
    // Rows come ordered by path: the ancestors of [path] (and [path] itself) first, root first,
    // then the rows below it. A row below another one was written after it.
    Node node = NodeCodec.emptyNode;
    // An ancestor row that does not decode hides everything below it, until a deeper ancestor row
    // (written later, covering all of [path]) replaces it.
    bool ancestorUnreadable = false;
    // Rows below [path] that do not decode: their subtrees read as absent.
    final List<Path> unreadable = <Path>[];
    final Map<Path, Node> priorities = <Path, Node>{};
    int skipped = 0;
    for (final sqlite.Row row in _selectNested(path, withValues: true)) {
      final Object? key = row.columnAt(0);
      if (key is! String) {
        skipped++;
        continue;
      }
      final Path rowPath = PathKey.toPath(key);
      final bool isAncestor = rowPath.contains(path);
      if (!isAncestor && !path.contains(rowPath)) {
        skipped++;
        continue;
      }
      if (!isAncestor &&
          (ancestorUnreadable ||
              unreadable.any((Path hidden) => hidden.contains(rowPath)))) {
        continue;
      }
      final Node? rowNode = _decode(row.columnAt(1));
      if (rowNode == null) {
        skipped++;
        if (isAncestor) {
          node = NodeCodec.emptyNode;
          ancestorUnreadable = true;
        } else {
          // Never let an ancestor row show through: the subtree of this row is not known.
          unreadable.add(rowPath);
          node = node.updateChild(
            Path.relative(path, rowPath),
            NodeCodec.emptyNode,
          );
        }
      } else if (isAncestor) {
        node = rowNode.getChild(Path.relative(rowPath, path));
        ancestorUnreadable = false;
      } else if (rowPath.back?.isPriorityKey ?? false) {
        // Applied last: deeper rows may still fill the node the priority belongs to.
        priorities[rowPath] = rowNode;
      } else {
        node = node.updateChild(Path.relative(path, rowPath), rowNode);
      }
    }
    for (final MapEntry<Path, Node> entry in priorities.entries) {
      node = node.updateChild(Path.relative(path, entry.key), entry.value);
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
    } on Object {
      // A damaged or hostile row (threat model T22) is a cache miss, never an error: the JSON
      // decoder, nodeFromJson and the core's constructors throw several kinds (FormatException,
      // ArgumentError, UnsupportedError for an infinite limit, TypeError).
      return null;
    }
  }

  /// The rows at [path], at its ancestors and below it, ordered by path (ancestors first).
  ///
  /// Two statements, each read in primary-key order: one `OR` would make SQLite sort the whole
  /// subtree in a temporary B-tree before the first row. Every ancestor key sorts before the
  /// range, so concatenating keeps the order.
  Iterable<sqlite.Row> _selectNested(Path path, {required bool withValues}) {
    final List<String> ancestors = PathKey.selfAndAncestors(path);
    final String start = ancestors.first;
    final String columns = withValues ? 'path, value' : 'path';
    final Iterable<sqlite.Row> above = _connection.select(
      'SELECT $columns FROM server_cache '
      'WHERE path IN (${SqlInList.marks(ancestors)}) ORDER BY path',
      SqlInList.pad(ancestors),
    );
    final Iterable<sqlite.Row> below = _connection.select(
      'SELECT $columns FROM server_cache WHERE path > ? AND path < ? ORDER BY path',
      <Object?>[start, PathKey.rangeEnd(start)],
    );
    return above.followedBy(below);
  }

  /// Replaces the cache at [path] with [node].
  void overwrite(Path path, Node node) {
    _removeNested(path);
    _saveNested(path, node);
    final Path? parent = path.parent;
    if (node.isEmpty && parent != null) {
      _clearEmptiedNodes(parent);
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
      _clearEmptiedNodes(parent);
    }
  }

  /// After a write that deleted something below [deepest]: for [deepest] and each ancestor that
  /// has a priority (a `.priority` row of its own, or one inside an ancestor's row) and is now
  /// empty, replaces its subtree with one empty row.
  ///
  /// A node loses its priority when it becomes empty. Without this, the priority would come back
  /// when a later write fills the node again: from a `.priority` row (Android's ignored
  /// `priorityIsCleared` test) or from an ancestor row that still holds it. The empty row hides
  /// both. Costs one indexed lookup of at most two keys per level, and the decoding of the
  /// ancestor rows, per deleting write; the node itself is loaded only when it has a priority.
  void _clearEmptiedNodes(Path deepest) {
    final List<String> levels = PathKey.selfAndAncestors(deepest);
    final List<String> keys = <String>[
      ...levels,
      for (final String key in levels) '$key.priority/',
    ];
    // Each row found, decoded once (null when it does not decode).
    final Map<String, Node?> rows = <String, Node?>{};
    for (final List<String> chunk in SqlInList.chunks(keys)) {
      for (final sqlite.Row row in _connection.select(
        'SELECT path, value FROM server_cache '
        'WHERE path IN (${SqlInList.marks(chunk)})',
        SqlInList.pad(chunk),
      )) {
        if (row.columnAt(0) case final String key) {
          rows[key] = _decode(row.columnAt(1));
        }
      }
    }
    // Deepest first: once a level holds data, every level above it does too.
    for (final String level in levels) {
      if (!_hasPriority(level, levels, rows)) {
        continue;
      }
      final Path owner = PathKey.toPath(level);
      if (!load(owner).isEmpty) {
        return;
      }
      _removeNested(owner);
      _saveRow(owner, NodeCodec.emptyNode);
    }
  }

  /// Whether the node at [level] has a priority in [rows]: a `.priority` row of its own, or a
  /// priority inside the deepest row at or above it ([levels] runs deepest first).
  bool _hasPriority(
    String level,
    List<String> levels,
    Map<String, Node?> rows,
  ) {
    if (rows.containsKey('$level.priority/')) {
      return true;
    }
    for (final String above in levels.skip(levels.indexOf(level))) {
      if (rows.containsKey(above)) {
        final Node? row = rows[above];
        final Path relative = Path.relative(
          PathKey.toPath(above),
          PathKey.toPath(level),
        );
        return row != null && !row.getChild(relative).priority.isEmpty;
      }
    }
    return false;
  }

  int _saveNested(Path path, Node node) {
    if (!node.isLeafNode && _estimatedSize(node) > splitThreshold) {
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
      _saveRow(path, NodeCodec.emptyNode);
      return rows + 1;
    }
    _saveRow(path, node);
    return 1;
  }

  /// The estimated JSON size of [node]; 0, with a warning, when the estimator fails.
  ///
  /// The estimator throws on an unresolved server value (`{'.sv': ...}`), which the server cache
  /// should never hold; such a node is then stored in one row, unresolved, and never reaches the
  /// application as an error.
  int _estimatedSize(Node node) {
    try {
      return estimateSerializedNodeSize(node);
    } on ArgumentError {
      _log(
        DatabaseLogLevel.warning,
        'Realtime Database offline cache: a node written to the server cache holds an '
        'unresolved server value; it is stored without splitting.',
      );
      return 0;
    }
  }

  void _saveRow(Path path, Node node) {
    final String key = PathKey.of(path);
    final Uint8List value = NodeCodec.encodeNode(node);
    _connection.execute(
      'INSERT OR REPLACE INTO server_cache (path, value) VALUES (?, ?)',
      <Object?>[key, value],
    );
    size += utf8.encode(key).length + value.length;
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
    for (final MapEntry<Path, String> row in toPrune.entries) {
      // Only the top-most row on each branch: the rows below it are inside its node.
      if (toPrune.findRootMostValueAndPath(row.key)!.path == row.key) {
        _collectResaves(
          root,
          row.key,
          toKeep.subtree(row.key),
          forest.childAtPath(row.key),
          resave,
        );
      }
    }
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

  /// For the top-most row to prune at [relativePath] (relative to [pruneRoot]), adds the kept
  /// parts of its node that have no kept row of their own to [resave]. [toKeep] and [forest] are
  /// the kept rows and the forest at [relativePath].
  void _collectResaves(
    Path pruneRoot,
    Path relativePath,
    ImmutableTree<String> toKeep,
    PruneForest forest,
    List<MapEntry<Path, Node>> resave,
  ) {
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
    for (final List<String> chunk in SqlInList.chunks(keys)) {
      _connection.execute(
        'DELETE FROM server_cache WHERE path IN (${SqlInList.marks(chunk)})',
        SqlInList.pad(chunk),
      );
    }
  }
}
