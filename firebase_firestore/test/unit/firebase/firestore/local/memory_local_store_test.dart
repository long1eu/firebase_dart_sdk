// File created by
// Lung Razvan <long1eu>
// on 29/09/2018

import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_database_collection/firebase_database_collection.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/memory_persistence.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_data.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_purpose.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/set_mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/resource_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/remote_event.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/watch_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/watch_change_aggregator.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/watch_stream.dart';
import 'package:firebase_firestore/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';
import '../../firestore/test_util.dart' as t;
import 'cases/local_store_test_case.dart';
import 'persistence_test_helpers.dart';

void main() {
  LocalStoreTestCase testCase;

  setUp(() async {
    print('setUp');
    final MemoryPersistence persistence =
        await PersistenceTestHelpers.createEagerGCMemoryPersistence();

    testCase = LocalStoreTestCase(persistence, true);
    await testCase.setUp();
    print('setUpDone');
  });

  tearDown(() => Future<void>.delayed(
      Duration(milliseconds: 250), () => testCase?.tearDown()));

  test('testMutationBatchKeys', () {
    final SetMutation set1 =
        setMutation('foo/bar', map(<String>['foo', 'bar']));
    final SetMutation set2 =
        setMutation('foo/baz', map(<String>['foo', 'baz']));
    final MutationBatch batch =
        MutationBatch(1, Timestamp.now(), <SetMutation>[set1, set2]);
    final Set<DocumentKey> keys = batch.keys;
    expect(keys.length, 2);
  });

  test('testHandlesSetMutation', () async {
    await testCase
        .writeMutation(setMutation('foo/bar', map(<String>['foo', 'bar'])));

    testCase.assertChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']),
          DocumentState.LOCAL_MUTATIONS)
    ]);
    await testCase.assertContains(doc('foo/bar', 0, map(<String>['foo', 'bar']),
        DocumentState.LOCAL_MUTATIONS));

    await testCase.acknowledgeMutation(0);

    testCase.assertChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']),
          DocumentState.COMMITTED_MUTATIONS)
    ]);

    if (testCase.garbageCollectorIsEager) {
      // Nothing is pinning this anymore, as it has been acknowledged and there
      // are no targets active.
      await testCase.assertNotContains('foo/bar');
    } else {
      await testCase.assertContains(doc('foo/bar', 0,
          map(<String>['foo', 'bar']), DocumentState.COMMITTED_MUTATIONS));
    }
  });

  test('testHandlesSetMutationThenDocument', () async {
    await testCase
        .writeMutation(setMutation('foo/bar', map(<String>['foo', 'bar'])));
    testCase.assertChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']),
          DocumentState.LOCAL_MUTATIONS)
    ]);
    await testCase.assertContains(doc('foo/bar', 0, map(<String>['foo', 'bar']),
        DocumentState.LOCAL_MUTATIONS));

    final Query query = Query.atPath(ResourcePath.fromString('foo'));
    final int targetId = await testCase.allocateQuery(query);
    await testCase.applyRemoteEvent(TestUtil.updateRemoteEvent(
        doc('foo/bar', 2, map(<String>['it', 'changed']),
            DocumentState.LOCAL_MUTATIONS),
        <int>[targetId],
        <int>[]));
    testCase.assertChanged(<Document>[
      doc('foo/bar', 2, map(<String>['foo', 'bar']),
          DocumentState.LOCAL_MUTATIONS)
    ]);
    await testCase.assertContains(doc('foo/bar', 2, map(<String>['foo', 'bar']),
        DocumentState.LOCAL_MUTATIONS));
  });

  test('testHandlesSetMutationThenAckThenRelease', () async {
    final Query query =
        Query.atPath(ResourcePath.fromSegments(<String>['foo']));
    await testCase.allocateQuery(query);

    await testCase
        .writeMutation(setMutation('foo/bar', map(<String>['foo', 'bar'])));
    await testCase.notifyLocalViewChanges(
        viewChanges(2, <String>['foo/bar'], <String>[]));

    testCase.assertChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']),
          DocumentState.LOCAL_MUTATIONS)
    ]);
    await testCase.assertContains(doc('foo/bar', 0, map(<String>['foo', 'bar']),
        DocumentState.LOCAL_MUTATIONS));

    await testCase.acknowledgeMutation(1);

    testCase.assertChanged(<Document>[
      doc('foo/bar', 1, map(<String>['foo', 'bar']),
          DocumentState.COMMITTED_MUTATIONS)
    ]);
    await testCase.assertContains(doc('foo/bar', 1, map(<String>['foo', 'bar']),
        DocumentState.COMMITTED_MUTATIONS));

    await testCase.releaseQuery(query);

    // It has been acknowledged, and should no longer be retained as there is no target and mutation
    if (testCase.garbageCollectorIsEager) {
      await testCase.assertNotContains('foo/bar');
    } else {
      await testCase.assertContains(doc('foo/bar', 1,
          map(<String>['foo', 'bar']), DocumentState.COMMITTED_MUTATIONS));
    }
  });

  test('testHandlesAckThenRejectThenRemoteEvent', () async {
    // Start a query that requires acks to be held.
    final Query query =
        Query.atPath(ResourcePath.fromSegments(<String>['foo']));
    final int targetId = await testCase.allocateQuery(query);

    await testCase
        .writeMutation(setMutation('foo/bar', map(<String>['foo', 'bar'])));
    testCase.assertChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']),
          DocumentState.LOCAL_MUTATIONS)
    ]);
    await testCase.assertContains(doc('foo/bar', 0, map(<String>['foo', 'bar']),
        DocumentState.LOCAL_MUTATIONS));

    // The last seen version is zero, so this ack must be held.
    await testCase.acknowledgeMutation(1);
    if (testCase.garbageCollectorIsEager) {
      // Nothing is pinning this anymore, as it has been acknowledged and there are no targets
      // active.
      await testCase.assertNotContains('foo/bar');
    } else {
      await testCase.assertContains(doc('foo/bar', 1,
          map(<String>['foo', 'bar']), DocumentState.COMMITTED_MUTATIONS));
    }

    await testCase
        .writeMutation(setMutation('bar/baz', map(<String>['bar', 'baz'])));
    testCase.assertChanged(<Document>[
      doc('bar/baz', 0, map(<String>['bar', 'baz']),
          DocumentState.LOCAL_MUTATIONS)
    ]);
    await testCase.assertContains(doc('bar/baz', 0, map(<String>['bar', 'baz']),
        DocumentState.LOCAL_MUTATIONS));

    await testCase.rejectMutation();
    testCase.assertRemoved(<String>['bar/baz']);
    await testCase.assertNotContains('bar/baz');

    await testCase.applyRemoteEvent(addedRemoteEvent(
        doc('foo/bar', 2, map(<String>['it', 'changed'])),
        <int>[targetId],
        <int>[]));
    testCase.assertChanged(<Document>[
      doc('foo/bar', 2, map(<String>['it', 'changed']))
    ]);
    await testCase
        .assertContains(doc('foo/bar', 2, map(<String>['it', 'changed'])));
    await testCase.assertNotContains('bar/baz');
  });

  test('testHandlesDeletedDocumentThenSetMutationThenAck', () async {
    final Query query = TestUtil.query('foo');
    final int targetId = await testCase.allocateQuery(query);
    await testCase.applyRemoteEvent(
        updateRemoteEvent(deletedDoc('foo/bar', 2), <int>[targetId], <int>[]));
    testCase.assertRemoved(<String>['foo/bar']);
    // Under eager GC, there is no longer a reference for the document, and it
    // should be deleted.
    if (testCase.garbageCollectorIsEager) {
      await testCase.assertNotContains('foo/bar');
    } else {
      await testCase.assertContains(deletedDoc('foo/bar', 2));
    }

    await testCase
        .writeMutation(setMutation('foo/bar', map(<String>['foo', 'bar'])));
    testCase.assertChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']),
          DocumentState.LOCAL_MUTATIONS)
    ]);
    await testCase.assertContains(doc('foo/bar', 0, map(<String>['foo', 'bar']),
        DocumentState.LOCAL_MUTATIONS));

    await testCase.releaseQuery(query);
    await testCase.acknowledgeMutation(3);
    testCase.assertChanged(<Document>[
      doc('foo/bar', 3, map(<String>['foo', 'bar']),
          DocumentState.COMMITTED_MUTATIONS)
    ]);
    // It has been acknowledged, and should no longer be retained as there is no
    // target and mutation
    if (testCase.garbageCollectorIsEager) {
      await testCase.assertNotContains('foo/bar');
    }
  });

  test('testHandlesSetMutationThenDeletedDocument', () async {
    final Query query = TestUtil.query('foo');
    final int targetId = await testCase.allocateQuery(query);
    await testCase
        .writeMutation(setMutation('foo/bar', map(<String>['foo', 'bar'])));
    testCase.assertChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']),
          DocumentState.LOCAL_MUTATIONS)
    ]);

    await testCase.applyRemoteEvent(
        updateRemoteEvent(deletedDoc('foo/bar', 2), <int>[targetId], <int>[]));
    testCase.assertChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']),
          DocumentState.LOCAL_MUTATIONS)
    ]);
    await testCase.assertContains(doc('foo/bar', 0, map(<String>['foo', 'bar']),
        DocumentState.LOCAL_MUTATIONS));
  });

  test('testHandlesDocumentThenSetMutationThenAckThenDocument', () async {
    final Query query = Query.atPath(ResourcePath.fromString('foo'));
    final int targetId = await testCase.allocateQuery(query);
    await testCase.applyRemoteEvent(addedRemoteEvent(
        doc('foo/bar', 2, map(<String>['it', 'base'])),
        <int>[targetId],
        <int>[]));

    testCase.assertChanged(<Document>[
      doc('foo/bar', 2, map(<String>['it', 'base']))
    ]);
    await testCase
        .assertContains(doc('foo/bar', 2, map(<String>['it', 'base'])));

    await testCase
        .writeMutation(setMutation('foo/bar', map(<String>['foo', 'bar'])));
    testCase.assertChanged(<Document>[
      doc('foo/bar', 2, map(<String>['foo', 'bar']),
          DocumentState.LOCAL_MUTATIONS)
    ]);
    await testCase.assertContains(doc('foo/bar', 2, map(<String>['foo', 'bar']),
        DocumentState.LOCAL_MUTATIONS));

    await testCase.acknowledgeMutation(3);
    testCase.assertChanged(<Document>[
      doc('foo/bar', 3, map(<String>['foo', 'bar']),
          DocumentState.COMMITTED_MUTATIONS)
    ]);
    await testCase.assertContains(doc('foo/bar', 3, map(<String>['foo', 'bar']),
        DocumentState.COMMITTED_MUTATIONS));

    await testCase.applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 3, map(<String>['it', 'changed'])),
        <int>[targetId],
        <int>[]));
    testCase.assertChanged(<Document>[
      doc('foo/bar', 3, map(<String>['it', 'changed']))
    ]);
    await testCase
        .assertContains(doc('foo/bar', 3, map(<String>['it', 'changed'])));
  });

  test('testHandlesPatchWithoutPriorDocument', () async {
    await testCase
        .writeMutation(patchMutation('foo/bar', map(<String>['foo', 'bar'])));
    testCase.assertRemoved(<String>['foo/bar']);
    await testCase.assertNotContains('foo/bar');

    await testCase.acknowledgeMutation(1);
    testCase.assertChanged(<MaybeDocument>[TestUtil.unknownDoc('foo/bar', 1)]);

    if (testCase.garbageCollectorIsEager) {
      // Nothing is pinning this anymore, as it has been acknowledged and there are no targets
      // active.
      await testCase.assertNotContains('foo/bar');
    } else {
      await testCase.assertContains(TestUtil.unknownDoc('foo/bar', 1));
    }
  });

  test('testHandlesPatchMutationThenDocumentThenAck', () async {
    await testCase
        .writeMutation(patchMutation('foo/bar', map(<String>['foo', 'bar'])));
    testCase.assertRemoved(<String>['foo/bar']);
    await testCase.assertNotContains('foo/bar');

    final Query query = Query.atPath(ResourcePath.fromString('foo'));
    final int targetId = await testCase.allocateQuery(query);
    await testCase.applyRemoteEvent(addedRemoteEvent(
        doc('foo/bar', 1, map(<String>['it', 'base']),
            DocumentState.LOCAL_MUTATIONS),
        <int>[targetId],
        <int>[]));
    testCase.assertChanged(<MaybeDocument>[
      doc('foo/bar', 1, map(<String>['foo', 'bar', 'it', 'base']),
          DocumentState.LOCAL_MUTATIONS)
    ]);
    await testCase.assertContains(doc(
        'foo/bar',
        1,
        map(<String>['foo', 'bar', 'it', 'base']),
        DocumentState.LOCAL_MUTATIONS));

    await testCase.acknowledgeMutation(2);

    testCase.assertChanged(<Document>[
      doc('foo/bar', 2, map(<String>['foo', 'bar', 'it', 'base']),
          DocumentState.COMMITTED_MUTATIONS)
    ]);
    await testCase.assertContains(doc(
        'foo/bar',
        2,
        map(<String>['foo', 'bar', 'it', 'base']),
        DocumentState.COMMITTED_MUTATIONS));

    await testCase.applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 2, map(<String>['foo', 'bar', 'it', 'base'])),
        <int>[targetId],
        <int>[]));
    testCase.assertChanged(<Document>[
      doc('foo/bar', 2, map(<String>['foo', 'bar', 'it', 'base']))
    ]);
    await testCase.assertContains(
        doc('foo/bar', 2, map(<String>['foo', 'bar', 'it', 'base'])));
  });

  test('testHandlesPatchMutationThenAckThenDocument', () async {
    await testCase
        .writeMutation(patchMutation('foo/bar', map(<String>['foo', 'bar'])));
    testCase.assertRemoved(<String>['foo/bar']);
    await testCase.assertNotContains('foo/bar');

    await testCase.acknowledgeMutation(1);
    testCase.assertChanged(<MaybeDocument>[TestUtil.unknownDoc('foo/bar', 1)]);
    // There's no target pinning the doc, and we've ack'd the mutation.
    if (testCase.garbageCollectorIsEager) {
      await testCase.assertNotContains('foo/bar');
    } else {
      await testCase.assertContains(unknownDoc('foo/bar', 1));
    }

    final Query query = Query.atPath(ResourcePath.fromString('foo'));
    final int targetId = await testCase.allocateQuery(query);
    await testCase.applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 1, map(<String>['it', 'base'])),
        <int>[targetId],
        <int>[]));
    testCase.assertChanged(<Document>[
      doc('foo/bar', 1, map(<String>['it', 'base']))
    ]);
    await testCase
        .assertContains(doc('foo/bar', 1, map(<String>['it', 'base'])));
  });

  test('testHandlesDeleteMutationThenAck', () async {
    await testCase.writeMutation(deleteMutation('foo/bar'));
    testCase.assertRemoved(<String>['foo/bar']);
    await testCase.assertContains(deletedDoc('foo/bar', 0));

    await testCase.acknowledgeMutation(1);
    testCase.assertRemoved(<String>['foo/bar']);
    // There's no target pinning the doc, and we've ack'd the mutation.
    if (testCase.garbageCollectorIsEager) {
      await testCase.assertNotContains('foo/bar');
    } else {
      await testCase.assertContains(deletedDoc('foo/bar', 1, true));
    }
  });

  test('testHandlesDocumentThenDeleteMutationThenAck', () async {
    final Query query = Query.atPath(ResourcePath.fromString('foo'));
    final int targetId = await testCase.allocateQuery(query);
    await testCase.applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 1, map(<String>['it', 'base'])),
        <int>[targetId],
        <int>[]));
    testCase.assertChanged(<Document>[
      doc('foo/bar', 1, map(<String>['it', 'base']))
    ]);
    await testCase
        .assertContains(doc('foo/bar', 1, map(<String>['it', 'base'])));

    await testCase.writeMutation(deleteMutation('foo/bar'));
    testCase.assertRemoved(<String>['foo/bar']);
    await testCase.assertContains(deletedDoc('foo/bar', 0));

    // Remove the target so only the mutation is pinning the document.
    await testCase.releaseQuery(query);
    await testCase.acknowledgeMutation(2);
    if (testCase.garbageCollectorIsEager) {
      // Neither the target nor the mutation pin the document, it should be gone.
      await testCase.assertNotContains('foo/bar');
    } else {
      await testCase.assertContains(deletedDoc('foo/bar', 2, true));
    }
  });

  test('testHandlesDeleteMutationThenDocumentThenAck', () async {
    final Query query = Query.atPath(ResourcePath.fromString('foo'));
    final int targetId = await testCase.allocateQuery(query);
    await testCase.writeMutation(deleteMutation('foo/bar'));
    testCase.assertRemoved(<String>['foo/bar']);
    await testCase.assertContains(deletedDoc('foo/bar', 0));

    await testCase.applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 1, map(<String>['it', 'base'])),
        <int>[targetId],
        <int>[]));
    testCase.assertRemoved(<String>['foo/bar']);
    await testCase.assertContains(deletedDoc('foo/bar', 0));

    await testCase.releaseQuery(query);
    await testCase.acknowledgeMutation(2);
    testCase.assertRemoved(<String>['foo/bar']);
    if (testCase.garbageCollectorIsEager) {
      // The doc is not pinned in a target and we've acknowledged the mutation.
      // It shouldn't exist anymore.
      await testCase.assertNotContains('foo/bar');
    } else {
      await testCase.assertContains(deletedDoc('foo/bar', 2, true));
    }
  });

  test('testHandlesDocumentThenDeletedDocumentThenDocument', () async {
    final Query query = Query.atPath(ResourcePath.fromString('foo'));
    final int targetId = await testCase.allocateQuery(query);
    await testCase.applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 1, map(<String>['it', 'base'])),
        <int>[targetId],
        <int>[]));
    testCase.assertChanged(<Document>[
      doc('foo/bar', 1, map(<String>['it', 'base']))
    ]);
    await testCase
        .assertContains(doc('foo/bar', 1, map(<String>['it', 'base'])));

    await testCase.applyRemoteEvent(
        updateRemoteEvent(deletedDoc('foo/bar', 2), <int>[targetId], <int>[]));
    testCase.assertRemoved(<String>['foo/bar']);
    if (!testCase.garbageCollectorIsEager) {
      await testCase.assertContains(deletedDoc('foo/bar', 2));
    }

    await testCase.applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 3, map(<String>['it', 'changed'])),
        <int>[targetId],
        <int>[]));
    testCase.assertChanged(<Document>[
      doc('foo/bar', 3, map(<String>['it', 'changed']))
    ]);
    await testCase
        .assertContains(doc('foo/bar', 3, map(<String>['it', 'changed'])));
  });

  test('testHandlesSetMutationThenPatchMutationThenDocumentThenAckThenAck',
      () async {
    await testCase
        .writeMutation(setMutation('foo/bar', map(<String>['foo', 'old'])));
    testCase.assertChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'old']),
          DocumentState.LOCAL_MUTATIONS)
    ]);
    await testCase.assertContains(doc('foo/bar', 0, map(<String>['foo', 'old']),
        DocumentState.LOCAL_MUTATIONS));

    await testCase
        .writeMutation(patchMutation('foo/bar', map(<String>['foo', 'bar'])));
    testCase.assertChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']),
          DocumentState.LOCAL_MUTATIONS)
    ]);
    await testCase.assertContains(doc('foo/bar', 0, map(<String>['foo', 'bar']),
        DocumentState.LOCAL_MUTATIONS));

    final Query query = Query.atPath(ResourcePath.fromString('foo'));

    final int targetId = await testCase.allocateQuery(query);
    await testCase.applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 1, map(<String>['it', 'base']),
            DocumentState.LOCAL_MUTATIONS),
        <int>[targetId],
        <int>[]));
    testCase.assertChanged(<Document>[
      doc('foo/bar', 1, map(<String>['foo', 'bar']),
          DocumentState.LOCAL_MUTATIONS)
    ]);
    await testCase.assertContains(doc('foo/bar', 1, map(<String>['foo', 'bar']),
        DocumentState.LOCAL_MUTATIONS));

    await testCase.releaseQuery(query);
    await testCase.acknowledgeMutation(2); // delete mutation
    testCase.assertChanged(<Document>[
      doc('foo/bar', 2, map(<String>['foo', 'bar']),
          DocumentState.LOCAL_MUTATIONS)
    ]);
    await testCase.assertContains(doc('foo/bar', 2, map(<String>['foo', 'bar']),
        DocumentState.LOCAL_MUTATIONS));

    await testCase.acknowledgeMutation(3); // patch mutation
    testCase.assertChanged(<Document>[
      doc('foo/bar', 3, map(<String>['foo', 'bar']),
          DocumentState.COMMITTED_MUTATIONS)
    ]);

    if (testCase.garbageCollectorIsEager) {
      // we've ack'd all of the mutations, nothing is keeping this pinned anymore
      await testCase.assertNotContains('foo/bar');
    } else {
      await testCase.assertContains(doc('foo/bar', 3,
          map(<String>['foo', 'bar']), DocumentState.COMMITTED_MUTATIONS));
    }
  });

  test('testHandlesSetMutationAndPatchMutationTogether', () async {
    await testCase.writeMutations(<Mutation>[
      setMutation('foo/bar', map(<String>['foo', 'old'])),
      patchMutation('foo/bar', map(<String>['foo', 'bar']))
    ]);

    testCase.assertChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']),
          DocumentState.LOCAL_MUTATIONS)
    ]);
    await testCase.assertContains(doc('foo/bar', 0, map(<String>['foo', 'bar']),
        DocumentState.LOCAL_MUTATIONS));
  });

  test('testHandlesSetMutationThenPatchMutationThenReject', () async {
    if (!testCase.garbageCollectorIsEager) {
      return;
    }

    await testCase
        .writeMutation(setMutation('foo/bar', map(<String>['foo', 'old'])));
    await testCase.assertContains(doc('foo/bar', 0, map(<String>['foo', 'old']),
        DocumentState.LOCAL_MUTATIONS));
    await testCase.acknowledgeMutation(1);
    await testCase.assertNotContains('foo/bar');

    await testCase
        .writeMutation(patchMutation('foo/bar', map(<String>['foo', 'bar'])));
    // A blind patch is not visible in the cache
    await testCase.assertNotContains('foo/bar');

    await testCase.rejectMutation();
    await testCase.assertNotContains('foo/bar');
  });

  test('testHandlesSetMutationsAndPatchMutationOfJustOneTogether', () async {
    await testCase.writeMutations(<Mutation>[
      setMutation('foo/bar', map(<String>['foo', 'old'])),
      setMutation('bar/baz', map(<String>['bar', 'baz'])),
      patchMutation('foo/bar', map(<String>['foo', 'bar']))
    ]);

    testCase.assertChanged(<Document>[
      doc('bar/baz', 0, map(<String>['bar', 'baz']),
          DocumentState.LOCAL_MUTATIONS),
      doc('foo/bar', 0, map(<String>['foo', 'bar']),
          DocumentState.LOCAL_MUTATIONS)
    ]);

    await testCase.assertContains(doc('foo/bar', 0, map(<String>['foo', 'bar']),
        DocumentState.LOCAL_MUTATIONS));
    await testCase.assertContains(doc('bar/baz', 0, map(<String>['bar', 'baz']),
        DocumentState.LOCAL_MUTATIONS));
  });

  test('testHandlesDeleteMutationThenPatchMutationThenAckThenAck', () async {
    await testCase.writeMutation(deleteMutation('foo/bar'));
    testCase.assertRemoved(<String>['foo/bar']);
    await testCase.assertContains(deletedDoc('foo/bar', 0));

    await testCase
        .writeMutation(patchMutation('foo/bar', map(<String>['foo', 'bar'])));
    testCase.assertRemoved(<String>['foo/bar']);
    await testCase.assertContains(deletedDoc('foo/bar', 0));

    await testCase.acknowledgeMutation(2); // delete mutation
    testCase.assertRemoved(<String>['foo/bar']);
    await testCase.assertContains(deletedDoc('foo/bar', 2, true));

    await testCase.acknowledgeMutation(3); // patch mutation
    testCase.assertChanged(<MaybeDocument>[unknownDoc('foo/bar', 3)]);
    if (testCase.garbageCollectorIsEager) {
      // There are no more pending mutations, the doc has been dropped
      await testCase.assertNotContains('foo/bar');
    } else {
      await testCase.assertContains(unknownDoc('foo/bar', 3));
    }
  });

  test('testCollectsGarbageAfterChangeBatchWithNoTargetIDs', () async {
    if (!testCase.garbageCollectorIsEager) {
      return;
    }

    const int targetId = 1;
    await testCase.applyRemoteEvent(updateRemoteEvent(
        deletedDoc('foo/bar', 2), <int>[], <int>[], <int>[targetId]));
    await testCase.assertNotContains('foo/bar');

    await testCase.applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 2, map(<String>['foo', 'bar'])),
        <int>[],
        <int>[],
        <int>[targetId]));
    await testCase.assertNotContains('foo/bar');
  });

  test('testCollectsGarbageAfterChangeBatch', () async {
    if (!testCase.garbageCollectorIsEager) {
      return;
    }

    final Query query = Query.atPath(ResourcePath.fromString('foo'));
    await testCase.allocateQuery(query);
    testCase.assertTargetId(2);

    final List<int> none = <int>[];
    final List<int> two = <int>[2];
    await testCase.applyRemoteEvent(addedRemoteEvent(
        doc('foo/bar', 2, map(<String>['foo', 'bar'])), two, none));
    await testCase
        .assertContains(doc('foo/bar', 2, map(<String>['foo', 'bar'])));

    await testCase.applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 2, map(<String>['foo', 'baz'])), none, two));

    await testCase.assertNotContains('foo/bar');
  });

  test('testCollectsGarbageAfterAcknowledgedMutation', () async {
    if (!testCase.garbageCollectorIsEager) {
      return;
    }

    final Query query = Query.atPath(ResourcePath.fromString('foo'));
    final int targetId = await testCase.allocateQuery(query);
    await testCase.applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 0, map(<String>['foo', 'old'])),
        <int>[targetId],
        <int>[]));
    await testCase
        .writeMutation(patchMutation('foo/bar', map(<String>['foo', 'bar'])));
    await testCase.releaseQuery(query);
    await testCase
        .writeMutation(setMutation('foo/bah', map(<String>['foo', 'bah'])));
    await testCase.writeMutation(deleteMutation('foo/baz'));
    await testCase.assertContains(doc('foo/bar', 0, map(<String>['foo', 'bar']),
        DocumentState.LOCAL_MUTATIONS));
    await testCase.assertContains(doc('foo/bah', 0, map(<String>['foo', 'bah']),
        DocumentState.LOCAL_MUTATIONS));
    await testCase.assertContains(deletedDoc('foo/baz', 0));

    await testCase.acknowledgeMutation(3);
    await testCase.assertNotContains('foo/bar');
    await testCase.assertContains(doc('foo/bah', 0, map(<String>['foo', 'bah']),
        DocumentState.LOCAL_MUTATIONS));
    await testCase.assertContains(deletedDoc('foo/baz', 0));

    await testCase.acknowledgeMutation(4);
    await testCase.assertNotContains('foo/bar');
    await testCase.assertNotContains('foo/bah');
    await testCase.assertContains(deletedDoc('foo/baz', 0));

    await testCase.acknowledgeMutation(5);
    await testCase.assertNotContains('foo/bar');
    await testCase.assertNotContains('foo/bah');
    await testCase.assertNotContains('foo/baz');
  });

  test('testCollectsGarbageAfterRejectedMutation', () async {
    if (!testCase.garbageCollectorIsEager) {
      return;
    }

    final Query query = Query.atPath(ResourcePath.fromString('foo'));
    final int targetId = await testCase.allocateQuery(query);
    await testCase.applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 0, map(<String>['foo', 'old'])),
        <int>[targetId],
        <int>[]));
    await testCase
        .writeMutation(patchMutation('foo/bar', map(<String>['foo', 'bar'])));
    // Release the query so that our target count goes back to 0 and we are
    // considered up-to-date.
    await testCase.releaseQuery(query);
    await testCase
        .writeMutation(setMutation('foo/bah', map(<String>['foo', 'bah'])));
    await testCase.writeMutation(deleteMutation('foo/baz'));
    await testCase.assertContains(doc('foo/bar', 0, map(<String>['foo', 'bar']),
        DocumentState.LOCAL_MUTATIONS));
    await testCase.assertContains(doc('foo/bah', 0, map(<String>['foo', 'bah']),
        DocumentState.LOCAL_MUTATIONS));
    await testCase.assertContains(deletedDoc('foo/baz', 0));

    await testCase.rejectMutation(); // patch mutation
    await testCase.assertNotContains('foo/bar');
    await testCase.assertContains(doc('foo/bah', 0, map(<String>['foo', 'bah']),
        DocumentState.LOCAL_MUTATIONS));
    await testCase.assertContains(deletedDoc('foo/baz', 0));

    await testCase.rejectMutation(); // set mutation
    await testCase.assertNotContains('foo/bar');
    await testCase.assertNotContains('foo/bah');
    await testCase.assertContains(deletedDoc('foo/baz', 0));

    await testCase.rejectMutation(); // delete mutation
    await testCase.assertNotContains('foo/bar');
    await testCase.assertNotContains('foo/bah');
    await testCase.assertNotContains('foo/baz');
  });

  test('testPinsDocumentsInTheLocalView', () async {
    if (!testCase.garbageCollectorIsEager) {
      return;
    }

    final Query query = Query.atPath(ResourcePath.fromString('foo'));
    await testCase.allocateQuery(query);
    testCase.assertTargetId(2);

    final List<int> none = <int>[];
    final List<int> two = <int>[2];
    await testCase.applyRemoteEvent(addedRemoteEvent(
        doc('foo/bar', 1, map(<String>['foo', 'bar'])), two, none));
    await testCase
        .writeMutation(setMutation('foo/baz', map(<String>['foo', 'baz'])));
    await testCase
        .assertContains(doc('foo/bar', 1, map(<String>['foo', 'bar'])));
    await testCase.assertContains(doc('foo/baz', 0, map(<String>['foo', 'baz']),
        DocumentState.LOCAL_MUTATIONS));

    await testCase.notifyLocalViewChanges(
        viewChanges(2, <String>['foo/bar', 'foo/baz'], <String>[]));
    await testCase.applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 1, map(<String>['foo', 'bar'])), none, two));
    await testCase.applyRemoteEvent(updateRemoteEvent(
        doc('foo/baz', 2, map(<String>['foo', 'baz'])), two, none));
    await testCase.acknowledgeMutation(2);
    await testCase
        .assertContains(doc('foo/bar', 1, map(<String>['foo', 'bar'])));
    await testCase
        .assertContains(doc('foo/baz', 2, map(<String>['foo', 'baz'])));

    await testCase.notifyLocalViewChanges(
        viewChanges(2, <String>[], <String>['foo/bar', 'foo/baz']));
    await testCase.releaseQuery(query);

    await testCase.assertNotContains('foo/bar');
    await testCase.assertNotContains('foo/baz');
  });

  test('testThrowsAwayDocumentsWithUnknownTargetIDsImmediately', () async {
    if (!testCase.garbageCollectorIsEager) {
      return;
    }

    const int targetID = 321;
    await testCase.applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 1, map()), <int>[], <int>[], <int>[targetID]));

    await testCase.assertNotContains('foo/bar');
  });

  test('testCanExecuteDocumentQueries', () async {
    await testCase.localStore.writeLocally(<Mutation>[
      setMutation('foo/bar', map(<String>['foo', 'bar'])),
      setMutation('foo/baz', map(<String>['foo', 'baz'])),
      setMutation('foo/bar/Foo/Bar', map(<String>['Foo', 'Bar']))
    ]);

    final Query query =
        Query.atPath(ResourcePath.fromSegments(<String>['foo', 'bar']));
    final ImmutableSortedMap<DocumentKey, Document> docs =
        await testCase.localStore.executeQuery(query);
    expect(values(docs), <Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']),
          DocumentState.LOCAL_MUTATIONS)
    ]);
  });

  test('testCanExecuteCollectionQueries', () async {
    await testCase.localStore.writeLocally(<SetMutation>[
      setMutation('fo/bar', map(<String>['fo', 'bar'])),
      setMutation('foo/bar', map(<String>['foo', 'bar'])),
      setMutation('foo/baz', map(<String>['foo', 'baz'])),
      setMutation('foo/bar/Foo/Bar', map(<String>['Foo', 'Bar'])),
      setMutation('fooo/blah', map(<String>['fooo', 'blah']))
    ]);

    final Query query = Query.atPath(ResourcePath.fromString('foo'));
    final ImmutableSortedMap<DocumentKey, Document> docs =
        await testCase.localStore.executeQuery(query);

    expect(values(docs), <Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']),
          DocumentState.LOCAL_MUTATIONS),
      doc('foo/baz', 0, map(<String>['foo', 'baz']),
          DocumentState.LOCAL_MUTATIONS)
    ]);
  });

  test('testCanExecuteMixedCollectionQueries', () async {
    final Query query = Query.atPath(ResourcePath.fromString('foo'));
    await testCase.allocateQuery(query);
    testCase.assertTargetId(2);

    await testCase.applyRemoteEvent(updateRemoteEvent(
        doc('foo/baz', 10, map(<String>['a', 'b'])), <int>[2], <int>[]));
    await testCase.applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 20, map(<String>['a', 'b'])), <int>[2], <int>[]));
    await testCase
        .writeMutation(setMutation('foo/bonk', map(<String>['a', 'b'])));

    final ImmutableSortedMap<DocumentKey, Document> docs =
        await testCase.localStore.executeQuery(query);

    expect(values(docs), <Document>[
      doc('foo/bar', 20, map(<String>['a', 'b'])),
      doc('foo/baz', 10, map(<String>['a', 'b'])),
      doc('foo/bonk', 0, map(<String>['a', 'b']), DocumentState.LOCAL_MUTATIONS)
    ]);
  });

  test('testPersistsResumeTokens', () async {
    // This test only works in the absence of the EagerGarbageCollector.
    if (testCase.garbageCollectorIsEager) {
      return;
    }

    final Query query = TestUtil.query('foo/bar');
    final int targetId = await testCase.allocateQuery(query);
    final Uint8List resumeToken = TestUtil.resumeToken(1000);

    final QueryData queryData =
        TestUtil.queryData(targetId, QueryPurpose.listen, 'foo/bar');
    final t.TestTargetMetadataProvider testTargetMetadataProvider =
        t.TestUtil.testTargetMetadataProvider;

    testTargetMetadataProvider.setSyncedKeys(
        queryData, DocumentKey.emptyKeySet);

    final WatchChangeAggregator aggregator =
        WatchChangeAggregator(testTargetMetadataProvider);

    final WatchChangeWatchTargetChange watchChange =
        WatchChangeWatchTargetChange(
            WatchTargetChangeType.Current, <int>[targetId], resumeToken);
    aggregator.handleTargetChange(watchChange);
    final RemoteEvent remoteEvent = aggregator.createRemoteEvent(version(1000));
    await testCase.applyRemoteEvent(remoteEvent);

    // Stop listening so that the query should become inactive (but persistent)
    await testCase.localStore.releaseQuery(query);

    // Should come back with the same resume token
    final QueryData queryData2 = await testCase.localStore.allocateQuery(query);
    expect(queryData2.resumeToken, resumeToken);
  });

  test('testDoesNotReplaceResumeTokenWithEmptyByteString', () async {
    // This test only works in the absence of the EagerGarbageCollector.
    if (testCase.garbageCollectorIsEager) {
      return;
    }

    final Query query = TestUtil.query('foo/bar');
    final int targetId = await testCase.allocateQuery(query);
    final Uint8List resumeToken = TestUtil.resumeToken(1000);

    final QueryData queryData =
        TestUtil.queryData(targetId, QueryPurpose.listen, 'foo/bar');
    final t.TestTargetMetadataProvider testTargetMetadataProvider =
        t.TestUtil.testTargetMetadataProvider;
    testTargetMetadataProvider.setSyncedKeys(
        queryData, DocumentKey.emptyKeySet);

    final WatchChangeAggregator aggregator1 =
        WatchChangeAggregator(testTargetMetadataProvider);

    final WatchChangeWatchTargetChange watchChange1 =
        WatchChangeWatchTargetChange(
            WatchTargetChangeType.Current, <int>[targetId], resumeToken);
    aggregator1.handleTargetChange(watchChange1);
    final RemoteEvent remoteEvent1 =
        aggregator1.createRemoteEvent(version(1000));
    await testCase.applyRemoteEvent(remoteEvent1);

    // New message with empty resume token should not replace the old resume
    // token
    final WatchChangeAggregator aggregator2 =
        WatchChangeAggregator(testTargetMetadataProvider);
    final WatchChangeWatchTargetChange watchChange2 =
        WatchChangeWatchTargetChange(WatchTargetChangeType.Current,
            <int>[targetId], WatchStream.emptyResumeToken);
    aggregator2.handleTargetChange(watchChange2);
    final RemoteEvent remoteEvent2 =
        aggregator2.createRemoteEvent(version(2000));
    await testCase.applyRemoteEvent(remoteEvent2);

    // Stop listening so that the query should become inactive (but persistent)
    await testCase.localStore.releaseQuery(query);

    // Should come back with the same resume token
    final QueryData queryData2 = await testCase.localStore.allocateQuery(query);
    expect(queryData2.resumeToken, resumeToken);
  });

  test('testRemoteDocumentKeysForTarget', () async {
    final Query query = Query.atPath(ResourcePath.fromString('foo'));
    await testCase.allocateQuery(query);
    testCase.assertTargetId(2);

    await testCase.applyRemoteEvent(addedRemoteEvent(
        doc('foo/baz', 10, map(<String>['a', 'b'])), <int>[2], <int>[]));
    await testCase.applyRemoteEvent(addedRemoteEvent(
        doc('foo/bar', 20, map(<String>['a', 'b'])), <int>[2], <int>[]));
    await testCase
        .writeMutation(setMutation('foo/bonk', map(<String>['a', 'b'])));

    ImmutableSortedSet<DocumentKey> keys =
        await testCase.localStore.getRemoteDocumentKeys(2);
    expect(keys, <DocumentKey>[key('foo/bar'), key('foo/baz')]);

    keys = await testCase.localStore.getRemoteDocumentKeys(2);
    expect(keys, <DocumentKey>[key('foo/bar'), key('foo/baz')]);
  });
}

// ignore: always_specify_types
const version = TestUtil.version;
// ignore: always_specify_types
const key = TestUtil.key;
// ignore: always_specify_types
const map = TestUtil.map;
// ignore: always_specify_types
const unknownDoc = TestUtil.unknownDoc;
// ignore: always_specify_types
const doc = TestUtil.doc;
// ignore: always_specify_types
const setMutation = TestUtil.setMutation;
// ignore: always_specify_types
const patchMutation = TestUtil.patchMutation;
// ignore: always_specify_types
const deleteMutation = TestUtil.deleteMutation;
// ignore: always_specify_types
const updateRemoteEvent = TestUtil.updateRemoteEvent;
// ignore: always_specify_types
const addedRemoteEvent = TestUtil.addedRemoteEvent;
// ignore: always_specify_types
const query = TestUtil.query;
// ignore: always_specify_types
const viewChanges = TestUtil.viewChanges;
// ignore: always_specify_types
const deletedDoc = TestUtil.deletedDoc;
// ignore: always_specify_types
const values = TestUtil.values;
