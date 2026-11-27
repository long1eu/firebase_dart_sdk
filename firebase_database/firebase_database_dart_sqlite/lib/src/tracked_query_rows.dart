import 'dart:convert';

import 'package:firebase_database_dart/firebase_database_dart.dart'
    show DatabaseLogLevel, DatabaseLogger;
import 'package:firebase_database_dart/storage_engine.dart';
import 'package:firebase_database_dart_sqlite/src/node_codec.dart';
import 'package:firebase_database_dart_sqlite/src/sql_in_list.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_connection.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// The `tracked_queries` and `tracked_keys` tables.
final class TrackedQueryRows {
  /// Rows of the connection; undecodable rows are reported to the logger.
  TrackedQueryRows(this._connection, this._log);

  final SqliteConnection _connection;
  final DatabaseLogger _log;

  /// The `query_params` column form of the parameters of [spec]: the wire object as JSON with its
  /// keys sorted at every level, so one query always has one text (the unique index
  /// `tracked_queries_by_query` relies on it). Numbers are as the core puts them in the wire
  /// object (an integral double within 2^53 is already an int there, so `1.0` and `1` are one
  /// query); `jsonEncode` adds no rule of its own.
  static String encodeParams(QuerySpec spec) =>
      jsonEncode(_sortedKeys(spec.toWireObject()));

  static Object? _sortedKeys(Object? value) {
    if (value is! Map) {
      return value;
    }
    final List<String> keys = value.keys.cast<String>().toList()..sort();
    return <String, Object?>{
      for (final String key in keys) key: _sortedKeys(value[key]),
    };
  }

  /// Stores [query], replacing the row of the same id.
  ///
  /// A row of another id for the same query is replaced too (the unique index resolves the
  /// conflict); its keys are deleted first so that they do not outlive it.
  /// `TrackedQueryManager` keeps one id per query, so this happens only with a damaged store.
  void save(TrackedQuery query) {
    final String path = PathKey.of(query.querySpec.path);
    final String params = encodeParams(query.querySpec);
    _connection.execute(
      'DELETE FROM tracked_keys WHERE query_id IN (SELECT id FROM tracked_queries '
      'WHERE path = ? AND query_params = ? AND id <> ?)',
      <Object?>[path, params, query.id],
    );
    _connection.execute(
      'INSERT OR REPLACE INTO tracked_queries '
      '(id, path, query_params, last_use_ms, complete, active) VALUES (?, ?, ?, ?, ?, ?)',
      <Object?>[
        query.id,
        path,
        params,
        query.lastUse,
        if (query.complete) 1 else 0,
        if (query.active) 1 else 0,
      ],
    );
  }

  /// Deletes tracked query [id] and its keys.
  void delete(int id) {
    _connection.execute('DELETE FROM tracked_queries WHERE id = ?', <Object?>[
      id,
    ]);
    _connection.execute(
      'DELETE FROM tracked_keys WHERE query_id = ?',
      <Object?>[id],
    );
  }

  /// The tracked queries in id order. A row that does not decode is skipped with a warning.
  List<TrackedQuery> load() {
    final List<TrackedQuery> queries = <TrackedQuery>[];
    int skipped = 0;
    for (final sqlite.Row row in _connection.select(
      'SELECT id, path, query_params, last_use_ms, complete, active '
      'FROM tracked_queries ORDER BY id',
    )) {
      final TrackedQuery? query = _decode(row);
      if (query == null) {
        skipped++;
      } else {
        queries.add(query);
      }
    }
    if (skipped > 0) {
      _log(
        DatabaseLogLevel.warning,
        'Realtime Database offline cache: $skipped stored tracked queries could not be read and '
        'were skipped.',
      );
    }
    return queries;
  }

  static TrackedQuery? _decode(sqlite.Row row) {
    final Object? id = row.columnAt(0);
    final Object? path = row.columnAt(1);
    final Object? params = row.columnAt(2);
    final Object? lastUse = row.columnAt(3);
    final Object? complete = row.columnAt(4);
    final Object? active = row.columnAt(5);
    if (id is! int ||
        path is! String ||
        params is! String ||
        lastUse is! int ||
        complete is! int ||
        active is! int) {
      return null;
    }
    try {
      final Object? wire = NodeCodec.decodeJson(utf8.encode(params));
      if (wire is! Map<String, Object?>) {
        return null;
      }
      return TrackedQuery(
        id: id,
        querySpec: QuerySpec.fromPathAndWireObject(PathKey.toPath(path), wire),
        lastUse: lastUse,
        complete: complete != 0,
        active: active != 0,
      );
    } on Object {
      // A damaged or hostile row (threat model T22) is a cache miss, never an error: the JSON
      // decoder, nodeFromJson and the core's constructors throw several kinds (FormatException,
      // ArgumentError, UnsupportedError for an infinite limit, TypeError).
      return null;
    }
  }

  /// Marks every active query inactive with [lastUse].
  void resetPreviouslyActive(int lastUse) {
    _connection.execute(
      'UPDATE tracked_queries SET active = 0, last_use_ms = ? WHERE active = 1',
      <Object?>[lastUse],
    );
  }

  /// Replaces the keys of query [id] with [keys].
  void saveKeys(int id, Set<ChildKey> keys) {
    _connection.execute(
      'DELETE FROM tracked_keys WHERE query_id = ?',
      <Object?>[id],
    );
    _insertKeys(id, keys);
  }

  /// Removes [removed] from the keys of query [id], then adds [added].
  void updateKeys(int id, Set<ChildKey> added, Set<ChildKey> removed) {
    for (final ChildKey key in removed) {
      _connection.execute(
        'DELETE FROM tracked_keys WHERE query_id = ? AND key = ?',
        <Object?>[id, key.name],
      );
    }
    _insertKeys(id, added);
  }

  void _insertKeys(int id, Set<ChildKey> keys) {
    for (final ChildKey key in keys) {
      _connection.execute(
        'INSERT OR REPLACE INTO tracked_keys (query_id, key) VALUES (?, ?)',
        <Object?>[id, key.name],
      );
    }
  }

  /// The union of the keys of [ids].
  Set<ChildKey> loadKeys(Set<int> ids) {
    final Set<ChildKey> keys = <ChildKey>{};
    for (final List<int> chunk in SqlInList.chunks(ids.toList())) {
      for (final sqlite.Row row in _connection.select(
        'SELECT DISTINCT key FROM tracked_keys '
        'WHERE query_id IN (${SqlInList.marks(chunk)})',
        SqlInList.pad(chunk),
      )) {
        final Object? key = row.columnAt(0);
        if (key is String) {
          keys.add(ChildKey(key));
        }
      }
    }
    return keys;
  }
}
