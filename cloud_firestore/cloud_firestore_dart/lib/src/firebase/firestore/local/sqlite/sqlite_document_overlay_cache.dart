// Copyright 2021 Google LLC
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

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/encoded_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/document_overlay_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/stored_proto.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/overlay.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:meta/meta.dart';

/// SQLite-backed [DocumentOverlayCache] of one user (table `document_overlays`, schema migration 11).
class SQLiteDocumentOverlayCache implements DocumentOverlayCache {
  /// The statements whose query plan matters with a long queue of pending writes, as constants so that
  /// `sqlite_overlay_query_plan_test.dart` checks the plan of exactly what runs here.
  @visibleForTesting
  static const String overlaysOfCollectionSql = '''
          SELECT overlay_mutation, largest_batch_id
          FROM document_overlays
          WHERE uid = ? AND collection_path = ? AND +largest_batch_id > ?
        ''';

  /// The overlays of a collection among the few written after a batch: through the index on the batch id.
  @visibleForTesting
  static const String newOverlaysOfCollectionSql = '''
          SELECT overlay_mutation, largest_batch_id
          FROM document_overlays INDEXED BY batch_id_overlay
          WHERE uid = ? AND largest_batch_id > ? AND collection_path = ?
        ''';

  /// Whether fewer than `LIMIT` overlays of the user were written after a batch (read from the index alone).
  @visibleForTesting
  static const String fewNewOverlaysSql = '''
          SELECT COUNT(*) AS count FROM (
            SELECT 1 FROM document_overlays INDEXED BY batch_id_overlay
            WHERE uid = ? AND largest_batch_id > ? LIMIT ?)
        ''';

  /// With fewer overlays than this after the batch asked for, [getOverlaysForCollection] reads them through the
  /// index on the batch id; with more, it reads the overlays of the collection.
  @visibleForTesting
  static int batchIdIndexMaxRows = 1000;

  @visibleForTesting
  static const String nextOverlaysOfGroupSql = '''
          SELECT overlay_mutation, largest_batch_id, collection_path, document_id
          FROM document_overlays
          WHERE uid = ? AND collection_group = ? AND largest_batch_id > ?
          ORDER BY largest_batch_id, collection_path, document_id
          LIMIT ?
        ''';

  @visibleForTesting
  static const String restOfBatchOfGroupSql = '''
          SELECT overlay_mutation, largest_batch_id
          FROM document_overlays
          WHERE uid = ? AND collection_group = ?
            AND (+collection_path > ? OR (+collection_path = ? AND document_id > ?))
            AND largest_batch_id = ?
        ''';

  SQLiteDocumentOverlayCache(this._db, this._serializer, User user)
    : _uid = user.isAuthenticated ? user.uid! : '';

  final SQLitePersistence _db;
  final LocalSerializer _serializer;
  final String _uid;

  @override
  Future<Overlay?> getOverlay(DocumentKey key) async {
    final String collectionPath = EncodedPath.encode(key.path.popLast());
    final String documentId = key.path.getLastSegment();
    final List<Map<String, dynamic>> rows = await _db.query(
      // @formatter:off
      '''
          SELECT overlay_mutation, largest_batch_id
          FROM document_overlays
          WHERE uid = ? AND collection_path = ? AND document_id = ?
        ''',
      // @formatter:on
      <Object>[_uid, collectionPath, documentId],
    );
    if (rows.isEmpty) {
      return null;
    }
    return _decodeOverlay(rows.first);
  }

  @override
  Future<Map<DocumentKey, Overlay>> getOverlays(
    Iterable<DocumentKey> keys,
  ) async {
    // Group the keys by collection, so that each collection is read with one (long) query.
    final Map<ResourcePath, List<Object?>> documentIdsByCollection =
        <ResourcePath, List<Object?>>{};
    for (DocumentKey key in keys) {
      documentIdsByCollection
          .putIfAbsent(key.path.popLast(), () => <Object?>[])
          .add(key.path.getLastSegment());
    }

    final Map<DocumentKey, Overlay> result = <DocumentKey, Overlay>{};
    for (MapEntry<ResourcePath, List<Object?>> entry
        in documentIdsByCollection.entries) {
      final LongQuery longQuery = LongQuery(
        _db,
        'SELECT overlay_mutation, largest_batch_id FROM document_overlays '
            'WHERE uid = ? AND collection_path = ? AND document_id IN (',
        <Object?>[_uid, EncodedPath.encode(entry.key)],
        entry.value,
        ')',
      );
      while (longQuery.hasMoreSubqueries) {
        for (Map<String, dynamic> row
            in await longQuery.performNextSubquery()) {
          final Overlay overlay = _decodeOverlay(row);
          result[overlay.key] = overlay;
        }
      }
    }
    return result;
  }

  Future<void> _saveOverlay(
    int largestBatchId,
    DocumentKey key,
    Mutation mutation,
  ) async {
    final ResourcePath path = key.path;
    final String group = path.segments[path.length - 2];
    final String collectionPath = EncodedPath.encode(path.popLast());
    final String documentId = path.getLastSegment();
    await _db.execute(
      // @formatter:off
      '''
          INSERT OR REPLACE INTO document_overlays
          (uid, collection_group, collection_path, document_id, largest_batch_id, overlay_mutation)
          VALUES (?, ?, ?, ?, ?, ?)
        ''',
      // @formatter:on
      <Object>[
        _uid,
        group,
        collectionPath,
        documentId,
        largestBatchId,
        _serializer.encodeOverlayMutation(mutation).writeToBuffer(),
      ],
    );
  }

  @override
  Future<void> saveOverlays(
    int largestBatchId,
    Map<DocumentKey, Mutation> overlays,
  ) async {
    for (MapEntry<DocumentKey, Mutation> entry in overlays.entries) {
      await _saveOverlay(largestBatchId, entry.key, entry.value);
    }
  }

  @override
  Future<void> removeOverlaysForBatchId(int batchId) async {
    await _db.execute(
      'DELETE FROM document_overlays WHERE uid = ? AND largest_batch_id = ?',
      <Object>[_uid, batchId],
    );
  }

  @override
  Future<void> removeOverlays(Iterable<DocumentKey> keys) async {
    for (DocumentKey key in keys) {
      await _db.execute(
        'DELETE FROM document_overlays WHERE uid = ? AND collection_path = ? AND document_id = ?',
        <Object>[
          _uid,
          EncodedPath.encode(key.path.popLast()),
          key.path.getLastSegment(),
        ],
      );
    }
  }

  @override
  Future<Map<DocumentKey, Overlay>> getOverlaysForCollection(
    ResourcePath collection,
    int sinceBatchId,
  ) async {
    // DEVIATION FROM UPSTREAM, which has one statement and leaves the choice of the index to SQLite. Without
    // statistics SQLite prefers `batch_id_overlay` (uid, largest_batch_id): with the range `largest_batch_id > -1`
    // that walks every overlay of the user (246 ms for a collection of 10 among 1M pending writes). The primary key
    // (uid, collection_path, document_id) reads only the collection, but all of it: 150 ms for the few overlays
    // written after the offset of an index in a collection of 100,000 pending writes. So the batch id index is used
    // when few overlays of the user are newer than [sinceBatchId], and the primary key otherwise.
    final String path = EncodedPath.encode(collection);
    final bool few =
        sinceBatchId >= 0 &&
        ((await _db.query(fewNewOverlaysSql, <Object>[
                  _uid,
                  sinceBatchId,
                  batchIdIndexMaxRows,
                ])).single['count']
                as int) <
            batchIdIndexMaxRows;
    final List<Map<String, dynamic>> rows = few
        ? await _db.query(newOverlaysOfCollectionSql, <Object>[
            _uid,
            sinceBatchId,
            path,
          ])
        : await _db.query(overlaysOfCollectionSql, <Object>[
            _uid,
            path,
            sinceBatchId,
          ]);
    return <DocumentKey, Overlay>{
      for (Overlay overlay in rows.map(_decodeOverlay)) overlay.key: overlay,
    };
  }

  @override
  Future<Map<DocumentKey, Overlay>> getOverlaysForCollectionGroup(
    String collectionGroup,
    int sinceBatchId,
    int count,
  ) async {
    final Map<DocumentKey, Overlay> result = <DocumentKey, Overlay>{};
    // Read through `collection_group_batch_id_overlay` (uid, collection_group, largest_batch_id, schema migration 20):
    // the first [count] rows of the group from the offset, instead of every later overlay of the user.
    final List<Map<String, dynamic>> rows = await _db.query(
      nextOverlaysOfGroupSql,
      <Object>[_uid, collectionGroup, sinceBatchId, count],
    );
    if (rows.isEmpty) {
      return result;
    }
    for (Map<String, dynamic> row in rows) {
      final Overlay overlay = _decodeOverlay(row);
      result[overlay.key] = overlay;
    }

    // This function should not return partial batch overlays, even if the number of overlays in the result set exceeds
    // the given `count` argument. Since the `LIMIT` in the above query might result in a partial batch, the following
    // query appends any remaining overlays for the last batch. The unary `+` keeps SQLite off the primary key, where
    // `collection_path > ?` is a range over the overlays of every later collection of the user (seconds at 1M).
    final Map<String, dynamic> last = rows.last;
    final List<Map<String, dynamic>> remaining = await _db
        .query(restOfBatchOfGroupSql, <Object>[
          _uid,
          collectionGroup,
          last['collection_path'],
          last['collection_path'],
          last['document_id'],
          last['largest_batch_id'],
        ]);
    for (Map<String, dynamic> row in remaining) {
      final Overlay overlay = _decodeOverlay(row);
      result[overlay.key] = overlay;
    }
    return result;
  }

  Overlay _decodeOverlay(Map<String, dynamic> row) {
    final Uint8List rawMutation = row['overlay_mutation'];
    final int largestBatchId = row['largest_batch_id'];
    final Mutation mutation = _serializer.decodeOverlayMutation(
      parseStoredProto('Overlay', () => proto.Write.fromBuffer(rawMutation)),
    );
    return Overlay(largestBatchId, mutation);
  }
}
