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

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_documents_view.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/mutation_queue.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/overlay_migration_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:meta/meta.dart';

/// Builds the document overlays from the mutation queues of all users, once, after the schema migration that added
/// the overlay table (port of the Android SDK's SQLiteOverlayMigrationManager, 2cba82f / 7926a0a).
class SQLiteOverlayMigrationManager implements OverlayMigrationManager {
  const SQLiteOverlayMigrationManager(this._db);

  final SQLitePersistence _db;

  @override
  Future<void> run() => _buildOverlays();

  Future<void> _buildOverlays() {
    return _db.runTransaction('build overlays', () async {
      if (!await hasPendingOverlayMigration()) {
        return;
      }

      // PORTING NOTE: the overlays are rebuilt from scratch. Upstream keeps the rows that are already there, which can
      // be stale when an older version of the SDK (without overlays) changed the mutation queue in between.
      await _db.execute('DELETE FROM document_overlays');

      for (String uid in await _getAllUserIds()) {
        final User user = uid.isEmpty ? User.unauthenticated : User(uid);
        final MutationQueue mutationQueue = _db.getMutationQueue(user);

        // Get all document keys that have local mutations
        final Set<DocumentKey> allDocumentKeys = <DocumentKey>{};
        final List<MutationBatch> batches = await mutationQueue
            .getAllMutationBatches();
        for (MutationBatch batch in batches) {
          allDocumentKeys.addAll(batch.keys);
        }

        // Recalculate and save overlays
        final LocalDocumentsView localView = LocalDocumentsView(
          remoteDocumentCache: _db.remoteDocumentCache,
          mutationQueue: mutationQueue,
          documentOverlayCache: _db.getDocumentOverlayCache(user),
          indexManager: _db.indexManager,
        );
        await localView.recalculateAndSaveOverlays(allDocumentKeys);
      }

      await _removePendingOverlayMigrations();
    });
  }

  /// The users that have pending mutations.
  Future<Set<String>> _getAllUserIds() async {
    final List<Map<String, dynamic>> rows = await _db.query(
      'SELECT DISTINCT uid FROM mutations',
    );
    return rows.map((Map<String, dynamic> row) => row['uid'] as String).toSet();
  }

  @visibleForTesting
  Future<bool> hasPendingOverlayMigration() async {
    final List<Map<String, dynamic>> rows = await _db.query(
      'SELECT migration_name FROM data_migrations WHERE migration_name = ?',
      <Object>[Persistence.dataMigrationBuildOverlays],
    );
    return rows.isNotEmpty;
  }

  Future<void> _removePendingOverlayMigrations() async {
    await _db.execute(
      'DELETE FROM data_migrations WHERE migration_name = ?',
      <Object>[Persistence.dataMigrationBuildOverlays],
    );
  }
}
