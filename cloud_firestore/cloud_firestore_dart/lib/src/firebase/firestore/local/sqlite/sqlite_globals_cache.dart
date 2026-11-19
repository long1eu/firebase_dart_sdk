// Copyright 2024 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/globals_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';

/// A SQLite-backed cache of global values: key and value pairs in the table `globals` (port of the Android
/// `SQLiteGlobalsCache`).
///
/// The table is created by schema migration 16 (Android migration 17, `createGlobalsTable`) with
/// [createTableStatement].
class SQLiteGlobalsCache implements GlobalsCache {
  const SQLiteGlobalsCache(this._db);

  /// The statement that creates the `globals` table, as in Android's `SQLiteSchema.createGlobalsTable`.
  static const String createTableStatement =
      'CREATE TABLE globals (name TEXT PRIMARY KEY, value BLOB)';

  static const String _sessionToken = 'sessionToken';

  final SQLitePersistence _db;

  @override
  Future<Uint8List> getSessionToken() async {
    return await _get(_sessionToken) ?? Uint8List(0);
  }

  @override
  Future<void> setSessionToken(Uint8List value) {
    return _set(_sessionToken, value);
  }

  @override
  Future<Uint8List?> getValue(String name) => _get(name);

  @override
  Future<void> setValue(String name, Uint8List? value) {
    if (value == null) {
      return _db.execute('DELETE FROM globals WHERE name = ?', <Object?>[name]);
    }
    return _set(name, value);
  }

  /// NOT IN THE OFFICIAL SDKS: one row per user, named with this prefix and the uid. The value is the text
  /// `batchId,seconds,nanoseconds` in UTF-8.
  static const String _queuedWritesMergeMark = 'queuedWritesMergeMark/';

  @override
  Future<QueuedWritesMergeMark?> getQueuedWritesMergeMark(String uid) async {
    final Uint8List? value = await _get('$_queuedWritesMergeMark$uid');
    if (value == null) {
      return null;
    }
    final List<String> parts = utf8
        .decode(value, allowMalformed: true)
        .split(',');
    final List<int?> numbers = <int?>[
      for (final String part in parts) int.tryParse(part),
    ];
    if (numbers.length != 3 ||
        numbers.contains(null) ||
        numbers[2]! < 0 ||
        numbers[2]! >= 1000000000) {
      // Not written by this version: no mark, the whole queue is merged again.
      return null;
    }
    return QueuedWritesMergeMark(
      numbers[0]!,
      Timestamp(numbers[1]!, numbers[2]!),
    );
  }

  @override
  Future<void> setQueuedWritesMergeMark(
    String uid,
    QueuedWritesMergeMark mark,
  ) {
    final Timestamp time = mark.localWriteTime;
    return _set(
      '$_queuedWritesMergeMark$uid',
      Uint8List.fromList(
        utf8.encode('${mark.batchId},${time.seconds},${time.nanoseconds}'),
      ),
    );
  }

  /// The value as a blob. The column is typed by affinity only, and another process may have written a value of
  /// another type: SQLite converts it like the `Cursor.getBlob` of Android does for text (its UTF-8 bytes), and a
  /// number to the bytes of its text.
  Future<Uint8List?> _get(String name) async {
    final List<Map<String, dynamic>> rows = await _db.query(
      'SELECT CAST(value AS BLOB) AS value FROM globals WHERE name = ?',
      <Object?>[name],
    );
    if (rows.isEmpty) {
      return null;
    }
    final Object? value = rows.first['value'];
    return value is List<int> ? Uint8List.fromList(value) : null;
  }

  Future<void> _set(String name, Uint8List value) {
    return _db.execute(
      'INSERT OR REPLACE INTO globals (name, value) VALUES (?, ?)',
      <Object?>[name, value],
    );
  }
}
