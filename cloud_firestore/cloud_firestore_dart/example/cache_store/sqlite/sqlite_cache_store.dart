// A CacheStore on SQLite (package:sqlite3): one table of keys and values.
//
// SQLite compares BLOBs as the store contract orders keys (by unsigned bytes, a prefix first), so a range scan is a
// range of the primary key. A write is one SQLite transaction.
//
// A statement outside of a transaction takes and releases SQLite's locks by itself, which costs about as much as the
// read. So the reads share one read transaction, which ends when the event loop turns (or before a write): the SDK
// reads a few times per document, all in one turn. Nobody else writes to the store, so the reads see no less.

import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/cache_store.dart';
import 'package:sqlite3/sqlite3.dart';

class SqliteCacheStore implements CacheStore {
  /// A store in the SQLite database file at [path] (`:memory:` for a database in memory).
  SqliteCacheStore(this.path);

  final String path;

  Database? _database;

  Database get _db => _database ?? (throw StateError('The store is not open'));

  /// Whether the read transaction is open.
  bool _reading = false;

  /// The database, in the read transaction.
  Database _read() {
    final Database db = _db;
    if (!_reading) {
      db.execute('BEGIN');
      _reading = true;
      Timer.run(_endRead);
    }
    return db;
  }

  void _endRead() {
    if (_reading) {
      _reading = false;
      _database?.execute('COMMIT');
    }
  }

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
    _endRead();
    // `dispose()` closes the database in sqlite3 2.x and still does in 3.x.
    // ignore: deprecated_member_use
    _database?.dispose();
    _database = null;
  }

  @override
  Future<Uint8List?> get(Uint8List key) async {
    final ResultSet rows = _read().select(
      'SELECT value FROM entries WHERE key = ?',
      <Object>[key],
    );
    return rows.isEmpty ? null : rows.first['value'] as Uint8List;
  }

  @override
  Future<List<CacheStoreEntry>> scan(
    Uint8List start,
    Uint8List end, {
    bool reverse = false,
    int? limit,
  }) async {
    final ResultSet rows = _read().select(
      'SELECT key, value FROM entries WHERE key >= ? AND key < ? '
      'ORDER BY key ${reverse ? 'DESC' : 'ASC'} LIMIT ?',
      <Object>[start, end, limit ?? -1],
    );
    return <CacheStoreEntry>[
      for (final Row row in rows)
        CacheStoreEntry(row['key'] as Uint8List, row['value'] as Uint8List),
    ];
  }

  @override
  Future<void> write(
    List<CacheStoreEntry> puts,
    List<Uint8List> deletes,
  ) async {
    if (puts.isEmpty && deletes.isEmpty) {
      return;
    }
    _endRead();
    final Database db = _db;
    db.execute('BEGIN IMMEDIATE');
    try {
      if (puts.isNotEmpty) {
        final PreparedStatement put = db.prepare(
          'INSERT OR REPLACE INTO entries (key, value) VALUES (?, ?)',
        );
        try {
          for (final CacheStoreEntry entry in puts) {
            put.execute(<Object>[entry.key, entry.value]);
          }
        } finally {
          // ignore: deprecated_member_use
          put.dispose();
        }
      }
      if (deletes.isNotEmpty) {
        final PreparedStatement delete = db.prepare(
          'DELETE FROM entries WHERE key = ?',
        );
        try {
          for (final Uint8List key in deletes) {
            delete.execute(<Object>[key]);
          }
        } finally {
          // ignore: deprecated_member_use
          delete.dispose();
        }
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }
}
