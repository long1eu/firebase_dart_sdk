// Regression tests for the overlay findings of "Review 2" in
// reviews/review_followups.md.

import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../../../util/local_helpers.dart';
import '../../../../util/test_util.dart';
import 'persistence_test_helpers.dart';

void main() {
  final Map<String, Future<Persistence> Function()> variants =
      <String, Future<Persistence> Function()>{
    'memory (lru gc)': createLRUMemoryPersistence,
    'sqlite': () => createSQLitePersistence(
        'firebase/firestore/local/review2_overlay_test-${const Uuid().v4()}.db',
        const LruGarbageCollectorParams()),
  };

  for (final MapEntry<String, Future<Persistence> Function()> variant
      in variants.entries) {
    group('LocalStore ${variant.key}', () {
      late LocalStoreDriver d;

      setUp(() async {
        d = LocalStoreDriver(await variant.value());
        await d.start();
      });

      tearDown(() => d.shutdown());

      test(
          'a merge on a document that is cached as deleted is merged with the '
          'document once the backend creates it', () async {
        final Query query = Query(ResourcePath.fromString('foo'));
        await d.allocateQuery(query);

        // The cache knows that the document does not exist.
        await d.applyRemoteEvent(updateRemoteEvent(
            deletedDoc('foo/bar', 1), <int>[2], <int>[]));

        // set(..., merge) of one field: a patch without a precondition.
        await d.writeMutation(patchMutation(
            'foo/bar', map(<dynamic>['a', 1]), <FieldPath>[field('a')]));
        await d.expectContains(doc('foo/bar', 0, map(<dynamic>['a', 1]),
            DocumentState.localMutations));

        // Another client creates the document before the merge is acknowledged.
        await d.applyRemoteEvent(updateRemoteEvent(
            doc('foo/bar', 2, map(<dynamic>['b', 2])), <int>[2], <int>[]));

        // The pending merge only writes `a`: `b` of the backend is kept.
        await d.expectContains(doc('foo/bar', 0,
            map(<dynamic>['a', 1, 'b', 2]), DocumentState.localMutations));
      });
    });
  }
}
