// A CacheStore on SQLite (package:sqlite3): one table of keys and values.
//
// SQLite compares BLOBs as the store contract orders keys (by unsigned bytes, a prefix first), so a range scan is a
// range of the primary key. A transaction is a SQLite transaction; transactions run one at a time on the one
// connection.

import 'dart:typed_data';

import 'package:cloud_firestore_dart/cache_store.dart';
import 'package:sqlite3/sqlite3.dart';

class SqliteCacheStore implements CacheStore {
  /// A store in the SQLite database file at [path] (`:memory:` for a database in memory).
  SqliteCacheStore(this.path);

  final String path;

  Database? _database;

  /// The end of the last transaction: the next one starts after it.
  Future<void> _lastTransaction = Future<void>.value();

  Database get _db =>
      _database ?? (throw StateError('The store is not open'));

  @override
  Future<void> open() async {
    final Database database = sqlite3.open(path);
    database
      ..execute('PRAGMA journal_mode = WAL')
      ..execute(
        'CREATE TABLE IF NOT EXISTS entries '
        '(key BLOB PRIMARY KEY, value BLOB NOT NULL) WITHOUT ROWID',
      );
    _database = database;
  }

  @override
  Future<void> close() async {
    await _lastTransaction;
    // `dispose()` closes the database in sqlite3 2.x and still does in 3.x.
    // ignore: deprecated_member_use
    _database?.dispose();
    _database = null;
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(CacheStoreTransaction transaction) body, {
    bool readOnly = false,
  }) {
    final Future<T> result = _lastTransaction.then((_) => _run(body));
    _lastTransaction = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<T> _run<T>(
    Future<T> Function(CacheStoreTransaction transaction) body,
  ) async {
    final Database db = _db;
    db.execute('BEGIN IMMEDIATE');
    try {
      final T result = await body(_Transaction(db));
      db.execute('COMMIT');
      return result;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }
}

class _Transaction implements CacheStoreTransaction {
  _Transaction(this._db);

  final Database _db;

  @override
  Future<Uint8List?> get(Uint8List key) async {
    final ResultSet rows = _db.select(
      'SELECT value FROM entries WHERE key = ?',
      <Object>[key],
    );
    return rows.isEmpty ? null : rows.first['value'] as Uint8List;
  }

  @override
  Future<void> put(Uint8List key, Uint8List value) async {
    _db.execute('INSERT OR REPLACE INTO entries (key, value) VALUES (?, ?)', <Object>[
      key,
      value,
    ]);
  }

  @override
  Future<void> delete(Uint8List key) async {
    _db.execute('DELETE FROM entries WHERE key = ?', <Object>[key]);
  }

  @override
  Future<List<CacheStoreEntry>> scan(
    Uint8List start,
    Uint8List end, {
    bool reverse = false,
    int? limit,
  }) async {
    final ResultSet rows = _db.select(
      'SELECT key, value FROM entries WHERE key >= ? AND key < ? '
      'ORDER BY key ${reverse ? 'DESC' : 'ASC'} LIMIT ?',
      <Object>[start, end, limit ?? -1],
    );
    return <CacheStoreEntry>[
      for (final Row row in rows)
        CacheStoreEntry(row['key'] as Uint8List, row['value'] as Uint8List),
    ];
  }
}
