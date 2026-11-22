import 'dart:typed_data';

import 'package:firebase_database_dart/firebase_database_dart.dart'
    show DatabaseLogLevel, DatabaseLogger;
import 'package:firebase_database_dart/storage_engine.dart';
import 'package:firebase_database_dart_sqlite/src/node_codec.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_connection.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// The `user_writes` table: one row per pending write, keyed by its write id.
///
/// A write is one row whatever its size: `package:sqlite3` reads a whole blob, so Android's
/// 256 KiB parts (`SqlPersistenceStorageEngine.java:150-154`) are not needed.
final class UserWriteRows {
  /// Rows of the connection; undecodable rows are reported to the logger.
  UserWriteRows(this._connection, this._log);

  final SqliteConnection _connection;
  final DatabaseLogger _log;

  static const String _overwrite = 'o';
  static const String _merge = 'm';

  /// Stores an overwrite of [node] at [path] as write [writeId], replacing a write of the same id.
  void saveOverwrite(Path path, Node node, int writeId) =>
      _save(writeId, path, _overwrite, NodeCodec.encodeNode(node));

  /// Stores a merge of [children] at [path] as write [writeId], replacing a write of the same id.
  void saveMerge(Path path, CompoundWrite children, int writeId) =>
      _save(writeId, path, _merge, NodeCodec.encodeMerge(children));

  void _save(int writeId, Path path, String type, Uint8List value) {
    _connection.execute(
      'INSERT OR REPLACE INTO user_writes (id, path, type, value) VALUES (?, ?, ?, ?)',
      <Object?>[writeId, PathKey.of(path), type, value],
    );
  }

  /// Removes write [writeId]; an unknown id removes nothing.
  void remove(int writeId) {
    _connection.execute('DELETE FROM user_writes WHERE id = ?', <Object?>[
      writeId,
    ]);
  }

  /// Removes every write.
  void removeAll() {
    _connection.execute('DELETE FROM user_writes');
  }

  /// The stored writes in write-id order. A row that does not decode is skipped with a warning
  /// (iOS drops such rows too, `FLevelDBStorageEngine.m:384-395`).
  List<UserWriteRecord> load() {
    final List<UserWriteRecord> writes = <UserWriteRecord>[];
    int skipped = 0;
    for (final sqlite.Row row in _connection.select(
      'SELECT id, path, type, value FROM user_writes ORDER BY id',
    )) {
      final UserWriteRecord? record = _decode(row);
      if (record == null) {
        skipped++;
      } else {
        writes.add(record);
      }
    }
    if (skipped > 0) {
      _log(
        DatabaseLogLevel.warning,
        'Realtime Database offline cache: $skipped stored write(s) could not be read and were '
        'skipped.',
      );
    }
    return writes;
  }

  static UserWriteRecord? _decode(sqlite.Row row) {
    final Object? id = row.columnAt(0);
    final Object? path = row.columnAt(1);
    final Object? type = row.columnAt(2);
    final Object? value = row.columnAt(3);
    if (id is! int || path is! String || value is! Uint8List) {
      return null;
    }
    try {
      switch (type) {
        case _overwrite:
          return UserWriteRecord.overwrite(
            id,
            PathKey.toPath(path),
            NodeCodec.decodeNode(value),
            visible: true,
          );
        case _merge:
          return UserWriteRecord.merge(
            id,
            PathKey.toPath(path),
            NodeCodec.decodeMerge(value),
          );
      }
      return null;
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }
}
