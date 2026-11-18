// With a long queue of writes that the backend has not acknowledged, every overlay of the user is a row of
// document_overlays. These statements must read the rows of one collection or one collection group, not all of
// them (tool/bench/offline_forever_bench.dart measures the difference: 246 ms against under 1 ms for a collection
// of 10 among 1M pending writes).

import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_document_overlay_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:test/test.dart';

import 'mock/database_mock.dart';

void main() {
  const String name =
      'firebase/firestore/local/sqlite_overlay_query_plan_test.db';
  late DatabaseMock db;

  setUp(() async {
    DatabaseMock.deleteDatabaseFiles(name);
    db = await DatabaseMock.create(name)
      ..renamePath = false;
  });

  tearDown(() {
    db.close();
    DatabaseMock.deleteDatabaseFiles(name);
  });

  Future<String> plan(String statement, List<Object> args) async {
    final List<Map<String, dynamic>> rows = await db.query(
      'EXPLAIN QUERY PLAN $statement',
      args,
    );
    return rows.map((Map<String, dynamic> row) => row['detail']).join('\n');
  }

  test(
    'the overlays of a collection are read through the primary key',
    () async {
      await SQLiteSchema(db).runMigrations();
      final String detail = await plan(
        SQLiteDocumentOverlayCache.overlaysOfCollectionSql,
        <Object>['', 'c', -1],
      );
      expect(detail, contains('uid=? AND collection_path=?'));
      expect(detail, isNot(contains('batch_id_overlay')));
    },
  );

  test(
    'the next overlays of a collection group are read in batch order from an index, without sorting the group',
    () async {
      await SQLiteSchema(db).runMigrations();
      final String detail = await plan(
        SQLiteDocumentOverlayCache.nextOverlaysOfGroupSql,
        <Object>['', 'g', -1, 50],
      );
      expect(
        detail,
        contains(
          'collection_group_batch_id_overlay (uid=? AND collection_group=? AND largest_batch_id>?)',
        ),
      );
    },
  );

  test(
    'the rest of a batch of a collection group is found by group and batch id',
    () async {
      await SQLiteSchema(db).runMigrations();
      final String detail = await plan(
        SQLiteDocumentOverlayCache.restOfBatchOfGroupSql,
        <Object>['', 'g', 'c', 'c', 'd', 7],
      );
      expect(
        detail,
        contains(
          'collection_group_batch_id_overlay (uid=? AND collection_group=? AND largest_batch_id=?)',
        ),
      );
    },
  );

  test(
    'migration 20 adds the index to an existing database, and can run twice',
    () async {
      final SQLiteSchema schema = SQLiteSchema(db);
      await schema.runMigrations(0, 19);
      expect(
        await plan(SQLiteDocumentOverlayCache.nextOverlaysOfGroupSql, <Object>[
          '',
          'g',
          -1,
          50,
        ]),
        isNot(contains('collection_group_batch_id_overlay')),
      );
      await schema.runMigrations(19, 20);
      await schema.runMigrations(19, 20);
      final List<Map<String, dynamic>> indexes = await db.query(
        "SELECT name FROM sqlite_master WHERE type = 'index'",
      );
      expect(
        indexes.map((Map<String, dynamic> row) => row['name']),
        contains('collection_group_batch_id_overlay'),
      );
    },
  );
}
