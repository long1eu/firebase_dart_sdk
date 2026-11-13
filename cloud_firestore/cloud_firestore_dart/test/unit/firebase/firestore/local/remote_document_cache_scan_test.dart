// Not upstream: collection scans over more rows than the SQLite cache reads per statement, and reads of the documents
// changed after an offset through either plan of the SQLite cache (the `read_time` index when few documents changed,
// a scan of the collection otherwise). Memory persistence runs the same cases as the reference.

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/remote_document_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_context.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../../../util/test_util.dart';
import 'persistence_test_helpers.dart';

void main() {
  final Map<String, Future<Persistence> Function()>
  variants = <String, Future<Persistence> Function()>{
    'memory': createEagerGCMemoryPersistence,
    'sqlite': () => createSQLitePersistence(
      'firebase/firestore/local/remote_document_cache_scan_test-${const Uuid().v4()}.db',
    ),
  };

  for (final MapEntry<String, Future<Persistence> Function()> variant
      in variants.entries) {
    group(variant.key, () {
      late Persistence persistence;
      late RemoteDocumentCache cache;

      setUp(() async {
        persistence = await variant.value();
        cache = persistence.remoteDocumentCache;
      });

      tearDown(() => persistence.shutdown());

      /// Adds `coll/<i>` for i in [from, to) with read time [readTime], `match: i % 7 == 0`, plus one document of
      /// another collection and one of a subcollection per 100 documents.
      Future<void> addDocs(int from, int to, int readTime) {
        return persistence.runTransaction('add docs', () async {
          for (int i = from; i < to; i++) {
            final String id = i.toString().padLeft(6, '0');
            await cache.add(
              doc('coll/$id', readTime, map(<dynamic>['match', i % 7 == 0])),
              version(readTime),
            );
            if (i % 100 == 0) {
              await cache.add(
                doc('colm/$id', readTime, map(<dynamic>['match', true])),
                version(readTime),
              );
              await cache.add(
                doc('coll/$id/sub/x', readTime, map(<dynamic>['match', true])),
                version(readTime),
              );
            }
          }
        });
      }

      Future<List<String>> matching(
        IndexOffset offset, [
        QueryContext? context,
      ]) async {
        final ImmutableSortedMap<DocumentKey, Document> docs = await persistence
            .runTransactionAndReturn(
              'query',
              () => cache.getAllDocumentsMatchingQuery(
                query('coll').filter(filter('match', '==', true)),
                offset,
                context: context,
              ),
            );
        return <String>[
          for (final MapEntry<DocumentKey, Document> entry in docs)
            entry.key.path.getLastSegment(),
        ];
      }

      List<String> ids(Iterable<int> values) => <String>[
        for (final int i in values)
          if (i % 7 == 0) i.toString().padLeft(6, '0'),
      ];

      test('a collection scan reads every page', () async {
        await addDocs(0, 2500, 10);
        final QueryContext context = QueryContext();
        expect(
          await matching(IndexOffset.none, context),
          ids(Iterable<int>.generate(2500)),
        );
        // The memory cache does not count the documents it reads, as upstream.
        if (variant.key == 'sqlite') {
          expect(context.documentReadCount, 2500);
        }
      });

      test('few documents after the offset', () async {
        await addDocs(0, 2500, 10);
        await addDocs(2500, 2600, 20);
        expect(
          await matching(
            IndexOffset.createSuccessor(
              version(10),
              FieldIndex.initialLargestBatchId,
            ),
          ),
          ids(Iterable<int>.generate(100, (int i) => 2500 + i)),
        );
        // At the read time of the offset, only the documents after its key.
        expect(
          await matching(
            IndexOffset(
              version(20),
              key('coll/002550'),
              FieldIndex.initialLargestBatchId,
            ),
          ),
          ids(Iterable<int>.generate(49, (int i) => 2551 + i)),
        );
      });

      test('many documents after the offset', () async {
        await addDocs(0, 1000, 10);
        await addDocs(1000, 7500, 20);
        expect(
          await matching(
            IndexOffset.createSuccessor(
              version(10),
              FieldIndex.initialLargestBatchId,
            ),
          ),
          ids(Iterable<int>.generate(6500, (int i) => 1000 + i)),
        );
        expect(
          await matching(
            IndexOffset(
              version(20),
              key('coll/007000'),
              FieldIndex.initialLargestBatchId,
            ),
          ),
          ids(Iterable<int>.generate(499, (int i) => 7001 + i)),
        );
      });
    });
  }
}
