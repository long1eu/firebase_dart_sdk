import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/geo_point.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/memory/memory_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/index_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../../../util/core_helpers.dart';
import '../../../../util/index_helpers.dart';
import '../../../../util/test_util.dart';
import 'persistence_test_helpers.dart';

/// Cases that are not in SQLiteIndexManagerTest of the Android SDK: range
/// filters on reference fields (which upstream serves wrongly from an index),
/// the per user index entries, and the parts that are specific to the port.
void main() {
  late SQLitePersistence persistence;
  late IndexManager indexManager;

  setUp(() async {
    persistence = await createSQLitePersistence(
        'firebase/firestore/local/sqlite_field_index_manager_extra_test-${const Uuid().v4()}.db');
    indexManager = persistence.getIndexManager(User.unauthenticated);
    await indexManager.start();
  });

  tearDown(() => persistence.shutdown());

  Future<void> addDocs(IndexManager manager, List<MaybeDocument> docs) {
    return manager.updateIndexEntries(<DocumentKey, MaybeDocument?>{
      for (final MaybeDocument doc in docs) doc.key: doc,
    });
  }

  Future<List<String>> idsFromIndex(IndexManager manager, Query query) async {
    final List<DocumentKey>? keys =
        await manager.getDocumentsMatchingTarget(query.toTarget());
    expect(keys, isNotNull, reason: 'Target cannot be served from index.');
    return keys!.map((DocumentKey key) => key.path.getLastSegment()).toList();
  }

  group('references', () {
    // References of different depths, one of them a prefix of another, next
    // to values of the types that sort right before and after references.
    final List<Document> docs = <Document>[
      doc('coll/a', 1, map(<dynamic>['r', ref('x/a')])),
      doc('coll/b', 1, map(<dynamic>['r', ref('x/b')])),
      doc('coll/c', 1, map(<dynamic>['r', ref('x/b/y/c')])),
      doc('coll/d', 1, map(<dynamic>['r', ref('x/c')])),
      doc(
          'coll/e',
          1,
          map(<dynamic>[
            'r',
            blob(<int>[255])
          ])),
      doc('coll/f', 1, map(<dynamic>['r', const GeoPoint(0, 0)])),
      doc('coll/g', 1, map(<dynamic>['other', 1])),
    ];

    List<String> idsFromScan(Query query) {
      final List<Document> matching = docs.where(query.matches).toList()
        ..sort(query.comparator);
      return matching.map((Document d) => d.key.path.getLastSegment()).toList();
    }

    for (final SegmentKind kind in <SegmentKind>[
      SegmentKind.ascending,
      SegmentKind.descending
    ]) {
      final String dir = kind == SegmentKind.ascending ? 'asc' : 'desc';

      test('range filters on a reference field match a scan (${kind.name})',
          () async {
        await indexManager.addFieldIndex(
            fieldIndex('coll', fieldsAndKinds: <Object>['r', kind]));
        await addDocs(indexManager, docs);

        for (final String op in <String>['<', '<=', '==', '>=', '>', '!=']) {
          for (final String target in <String>[
            'x/a',
            'x/b',
            'x/b/y/c',
            'x/z'
          ]) {
            final Query query = Query(path('coll'))
                .filter(filter('r', op, ref(target)))
                .orderBy(orderBy('r', dir));
            expect(await idsFromIndex(indexManager, query), idsFromScan(query),
                reason: 'r $op $target');
          }
        }
      });

      test(
          'cursors and limits on a reference field match a scan (${kind.name})',
          () async {
        await indexManager.addFieldIndex(
            fieldIndex('coll', fieldsAndKinds: <Object>['r', kind]));
        await addDocs(indexManager, docs);

        final Query ordered = Query(path('coll')).orderBy(orderBy('r', dir));
        expect(await idsFromIndex(indexManager, ordered), idsFromScan(ordered));

        for (int limit = 1; limit <= 6; limit++) {
          final Query limited = ordered.limitToFirst(limit);
          expect(await idsFromIndex(indexManager, limited),
              idsFromScan(ordered).take(limit).toList(),
              reason: 'limit $limit');
        }

        for (final bool inclusive in <bool>[true, false]) {
          final Query startAt =
              ordered.startAt(bound(inclusive, <Object?>[ref('x/b')]));
          expect(
              await idsFromIndex(indexManager, startAt), idsFromScan(startAt),
              reason: 'startAt inclusive=$inclusive');
          final Query endAt =
              ordered.endAt(bound(inclusive, <Object?>[ref('x/b')]));
          expect(await idsFromIndex(indexManager, endAt), idsFromScan(endAt),
              reason: 'endAt inclusive=$inclusive');
        }
      });
    }
  });

  test('index entries are kept per user', () async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['a', SegmentKind.ascending]));
    await addDocs(indexManager, <MaybeDocument>[
      doc('coll/anonymous', 1, map(<dynamic>['a', 1]))
    ]);

    final IndexManager other = persistence.getIndexManager(const User('other'));
    await other.start();
    // The index is configured for every user, its entries are not.
    expect(other.getFieldIndexes('coll'), hasLength(1));
    final Query query = Query(path('coll')).orderBy(orderBy('a'));
    expect(await idsFromIndex(other, query), isEmpty);

    await addDocs(other, <MaybeDocument>[
      doc('coll/other', 1, map(<dynamic>['a', 2]))
    ]);
    expect(await idsFromIndex(other, query), <String>['other']);
    expect(await idsFromIndex(indexManager, query), <String>['anonymous']);
  });

  test('a document that lost a field loses its index entry', () async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['a', SegmentKind.ascending]));
    final Query query = Query(path('coll')).orderBy(orderBy('a'));

    await addDocs(indexManager, <MaybeDocument>[
      doc('coll/doc', 1, map(<dynamic>['a', 1]))
    ]);
    expect(await idsFromIndex(indexManager, query), <String>['doc']);

    await addDocs(indexManager, <MaybeDocument>[
      doc('coll/doc', 2, map(<dynamic>['b', 1]))
    ]);
    expect(await idsFromIndex(indexManager, query), isEmpty);
  });

  test('a key without a document loses its index entries', () async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['a', SegmentKind.ascending]));
    final Query query = Query(path('coll')).orderBy(orderBy('a'));
    await addDocs(indexManager, <MaybeDocument>[
      doc('coll/doc', 1, map(<dynamic>['a', 1]))
    ]);

    await indexManager.updateIndexEntries(
        <DocumentKey, MaybeDocument?>{key('coll/doc'): null});
    expect(await idsFromIndex(indexManager, query), isEmpty);
  });

  test('deleteAllFieldIndexes removes configuration, state and entries',
      () async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['a', SegmentKind.ascending]));
    await indexManager.addFieldIndex(fieldIndex('other',
        fieldsAndKinds: <Object>['b', SegmentKind.contains]));
    await addDocs(indexManager, <MaybeDocument>[
      doc('coll/doc', 1, map(<dynamic>['a', 1]))
    ]);
    await indexManager.updateCollectionGroup('coll', IndexOffset.none);

    await indexManager.deleteAllFieldIndexes();

    expect(indexManager.getFieldIndexes(), isEmpty);
    expect(indexManager.getFieldIndexes('coll'), isEmpty);
    expect(indexManager.getNextCollectionGroupToUpdate(), isNull);
    for (final String table in <String>[
      'index_configuration',
      'index_state',
      'index_entries'
    ]) {
      expect(await persistence.query('SELECT * FROM $table'), isEmpty,
          reason: table);
    }

    // A restart does not bring them back.
    final IndexManager restarted =
        persistence.getIndexManager(User.unauthenticated);
    await restarted.start();
    expect(restarted.getFieldIndexes(), isEmpty);
  });

  test('the configuration survives a restart with its segments', () async {
    await indexManager
        .addFieldIndex(fieldIndex('coll', fieldsAndKinds: <Object>[
      'a.b',
      SegmentKind.ascending,
      'tags',
      SegmentKind.contains,
      'c',
      SegmentKind.descending
    ]));

    final IndexManager restarted =
        persistence.getIndexManager(User.unauthenticated);
    await restarted.start();
    final FieldIndex index = restarted.getFieldIndexes('coll').single;
    expect(index.indexId, 0);
    expect(index.indexState, FieldIndex.initialState);
    expect(index.segments, <IndexSegment>[
      IndexSegment(field('a.b'), SegmentKind.ascending),
      IndexSegment(field('tags'), SegmentKind.contains),
      IndexSegment(field('c'), SegmentKind.descending),
    ]);

    // The next index gets the next id.
    await restarted.addFieldIndex(fieldIndex('coll'));
    expect(
        restarted
            .getFieldIndexes('coll')
            .map((FieldIndex i) => i.indexId)
            .toSet(),
        <int>{0, 1});
  });

  test('getMinOffset is the least advanced offset with the largest batch id',
      () async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        indexId: 1,
        indexState: IndexState(1, IndexOffset(version(10), key('coll/a'), 3)),
        fieldsAndKinds: <Object>['a', SegmentKind.ascending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        indexId: 2,
        indexState: IndexState(2, IndexOffset(version(5), key('coll/b'), 7)),
        fieldsAndKinds: <Object>['b', SegmentKind.ascending]));

    expect(indexManager.getMinOffset('coll'),
        IndexOffset(version(5), key('coll/b'), 7));
    expect(
        indexManager.getMinOffsetForTarget(
            Query(path('coll')).orderBy(orderBy('a')).toTarget()),
        IndexOffset(version(10), key('coll/a'), 3));
  });

  group('the shared index manager of the persistence', () {
    test('serves the collection parent index without being started', () async {
      await persistence.indexManager
          .addToCollectionParentIndex(path('rooms/foo/messages'));
      expect(await persistence.indexManager.getCollectionParents('messages'),
          <Object>[path('rooms/foo')]);
      // Every index manager sees the same parents.
      expect(await indexManager.getCollectionParents('messages'),
          <Object>[path('rooms/foo')]);
    });

    test('rejects the field index methods', () async {
      expect(() => persistence.indexManager.addFieldIndex(fieldIndex('coll')),
          throwsA(isA<AssertionError>()));
      expect(() => persistence.indexManager.getFieldIndexes('coll'),
          throwsA(isA<AssertionError>()));
      expect(
          () => persistence.indexManager
              .getIndexType(Query(path('coll')).toTarget()),
          throwsA(isA<AssertionError>()));
    });
  });

  test('memory persistence has no field indexes', () async {
    final MemoryPersistence memory =
        MemoryPersistence.createEagerGcMemoryPersistence();
    await memory.start();
    addTearDown(memory.shutdown);

    final IndexManager manager = memory.getIndexManager(User.unauthenticated);
    await manager.start();
    await manager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['a', SegmentKind.ascending]));
    await addDocs(manager, <MaybeDocument>[
      doc('coll/doc', 1, map(<dynamic>['a', 1]))
    ]);

    final Query query = Query(path('coll')).orderBy(orderBy('a'));
    expect(manager.getFieldIndexes(), isEmpty);
    expect(manager.getFieldIndexes('coll'), isEmpty);
    expect(manager.getIndexType(query.toTarget()), IndexType.none);
    expect(await manager.getDocumentsMatchingTarget(query.toTarget()), isNull);
    expect(manager.getNextCollectionGroupToUpdate(), isNull);
    expect(manager.getMinOffset('coll'), IndexOffset.none);
    expect(manager.getMinOffsetForTarget(query.toTarget()), IndexOffset.none);
  });
}
