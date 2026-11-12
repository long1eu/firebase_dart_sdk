// The parts of the local store benchmark that depend on the version of the local store. This file is for the current
// engine (index-free queries and document overlays, schema 11). To measure an older commit, copy the benchmark into a
// worktree of that commit and replace this file (see notes/perf/local_store_bench.md for the pre-overlay variant).

import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/index_backfiller.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_view_changes.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/database.dart';

const String engineName = 'overlays + index-free + field indexes (schema 13)';

/// Whether the engine has document overlays (and with them the overlay data migration).
const bool hasOverlays = true;

/// Runs [query] and returns the number of documents.
Future<int> runQuery(LocalStore store, Query query,
    {required bool usePreviousResults}) async {
  return (await store.executeQuery(query, usePreviousResults)).documents.length;
}

/// View changes that mark the view of [targetId] as synced (not from cache).
LocalViewChanges syncedViewChanges(int targetId) {
  return LocalViewChanges(targetId, /* fromCache= */ false,
      DocumentKey.emptyKeySet, DocumentKey.emptyKeySet);
}

/// Puts the database into the state right after the schema migration that adds overlays: no overlays, data migration
/// pending.
Future<void> makeOverlayMigrationPending(Database db) async {
  await db.execute('DELETE FROM document_overlays');
  await db.execute(
      "INSERT OR IGNORE INTO data_migrations (migration_name) VALUES ('BUILD_OVERLAYS')");
}

/// Configures an ascending field index on [field] of [collectionGroup] and backfills it. Returns the number of
/// documents indexed, or null if the engine has no field indexes.
Future<int?> createFieldIndex(Persistence persistence, LocalStore store,
    String collectionGroup, String field) async {
  await store.configureFieldIndexes(<FieldIndex>[
    FieldIndex(
        FieldIndex.unknownId,
        collectionGroup,
        <IndexSegment>[
          IndexSegment(FieldPath.fromSingleSegment(field), SegmentKind.ascending)
        ],
        FieldIndex.initialState),
  ]);
  final IndexBackfiller backfiller = IndexBackfiller(persistence, store)
    ..maxDocumentsToProcess = 1000;
  int total = 0;
  while (true) {
    final int processed = await backfiller.backfill();
    if (processed == 0) {
      return total;
    }
    total += processed;
  }
}
