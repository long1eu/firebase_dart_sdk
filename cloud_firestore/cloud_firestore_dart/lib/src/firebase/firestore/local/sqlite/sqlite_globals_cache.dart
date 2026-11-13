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
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/globals_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';

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
