// File created by
// Lung Razvan <long1eu>
// on 29/09/2018

import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_database_collection/firebase_database_collection.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/persistence.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_data.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_purpose.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/sqlite_persistence.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
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

import '../../../util/test_util.dart';
import '../test_util.dart' as t;
import 'local_store_test_case.dart';
import 'persistence_test_helpers.dart';

void main() {
  SQLiteLocalStoreTest instance;

  setUp(() async {
    print('setUp');
    final SQLitePersistence persistence =
        await PersistenceTestHelpers.openSQLitePersistence(
            'firebase/firestore/local/local_store_${PersistenceTestHelpers.nextSQLiteDatabaseName()}.db');

    instance = SQLiteLocalStoreTest(persistence);
    await instance.setUp();
    print('setUpDone');
  });

  tearDown(() =>
      Future.delayed(Duration(milliseconds: 250), () => instance?.tearDown()));

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
    await instance
        .writeMutation(setMutation('foo/bar', map(<String>['foo', 'bar'])));

    instance.assertChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']), true)
    ]);

    await instance
        .assertContains(doc('foo/bar', 0, map(<String>['foo', 'bar']), true));

    await instance.acknowledgeMutation(0);
    instance.assertChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']), false)
    ]);

    if (instance.garbageCollectorIsEager) {
      // Nothing is pinning this anymore, as it has been acknowledged and there
      // are no targets active.
      await instance.assertNotContains('foo/bar');
    } else {
      await instance.assertContains(
          doc('foo/bar', 0, map(<String>['foo', 'bar']), false));
    }
  });

  test('testHandlesSetMutationThenDocument', () async {
    await instance
        .writeMutation(setMutation('foo/bar', map(<String>['foo', 'bar'])));
    instance.assertChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']), true)
    ]);
    await instance
        .assertContains(doc('foo/bar', 0, map(<String>['foo', 'bar']), true));

    final Query query = Query.atPath(ResourcePath.fromString('foo'));
    final int targetId = await instance.allocateQuery(query);
    await instance.applyRemoteEvent(TestUtil.updateRemoteEvent(
        doc('foo/bar', 2, map(<String>['it', 'changed']), true),
        <int>[targetId],
        <int>[]));
    instance.assertChanged(<Document>[
      doc('foo/bar', 2, map(<String>['foo', 'bar']), true)
    ]);
    await instance
        .assertContains(doc('foo/bar', 2, map(<String>['foo', 'bar']), true));
  });

  test('testHandlesAckThenRejectThenRemoteEvent', () async {
    // Start a query that requires acks to be held.
    final Query query =
        Query.atPath(ResourcePath.fromSegments(<String>['foo']));
    final int targetId = await instance.allocateQuery(query);

    await instance
        .writeMutation(setMutation('foo/bar', map(<String>['foo', 'bar'])));
    instance.assertChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']), true)
    ]);
    await instance
        .assertContains(doc('foo/bar', 0, map(<String>['foo', 'bar']), true));

    // The last seen version is zero, so this ack must be held.
    await instance.acknowledgeMutation(1);
    instance.assertChanged();
    await instance
        .assertContains(doc('foo/bar', 0, map(<String>['foo', 'bar']), true));

    await instance
        .writeMutation(setMutation('bar/baz', map(<String>['bar', 'baz'])));
    instance.assertChanged(<Document>[
      doc('bar/baz', 0, map(<String>['bar', 'baz']), true)
    ]);
    await instance
        .assertContains(doc('bar/baz', 0, map(<String>['bar', 'baz']), true));

    await instance.rejectMutation();
    instance.assertRemoved(<String>['bar/baz']);
    await instance.assertNotContains('bar/baz');

    await instance.applyRemoteEvent(addedRemoteEvent(
        doc('foo/bar', 2, map(<String>['it', 'changed']), false),
        <int>[targetId],
        <int>[]));
    instance.assertChanged(<Document>[
      doc('foo/bar', 2, map(<String>['it', 'changed']), false)
    ]);
    await instance.assertContains(
        doc('foo/bar', 2, map(<String>['it', 'changed']), false));
    await instance.assertNotContains('bar/baz');
  });

  test('testHandlesDeletedDocumentThenSetMutationThenAck', () async {
    final Query query = TestUtil.query('foo');
    final int targetId = await instance.allocateQuery(query);
    await instance.applyRemoteEvent(
        updateRemoteEvent(deletedDoc('foo/bar', 2), <int>[targetId], <int>[]));
    instance.assertRemoved(<String>['foo/bar']);
    // Under eager GC, there is no longer a reference for the document, and it
    // should be deleted.
    if (instance.garbageCollectorIsEager) {
      await instance.assertNotContains('foo/bar');
    } else {
      await instance.assertContains(deletedDoc('foo/bar', 2));
    }

    await instance
        .writeMutation(setMutation('foo/bar', map(<String>['foo', 'bar'])));
    instance.assertChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']), true)
    ]);
    await instance
        .assertContains(doc('foo/bar', 0, map(<String>['foo', 'bar']), true));

    await instance.releaseQuery(query);
    await instance.acknowledgeMutation(3);
    instance.assertChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']), false)
    ]);
    // It has been acknowledged, and should no longer be retained as there is no
    // target and mutation
    if (instance.garbageCollectorIsEager) {
      await instance.assertNotContains('foo/bar');
    }
  });

  test('testHandlesSetMutationThenDeletedDocument', () async {
    final Query query = TestUtil.query('foo');
    final int targetId = await instance.allocateQuery(query);
    await instance
        .writeMutation(setMutation('foo/bar', map(<String>['foo', 'bar'])));
    instance.assertChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']), true)
    ]);

    await instance.applyRemoteEvent(
        updateRemoteEvent(deletedDoc('foo/bar', 2), <int>[targetId], <int>[]));
    instance.assertChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']), true)
    ]);
    await instance
        .assertContains(doc('foo/bar', 0, map(<String>['foo', 'bar']), true));
  });

  test('testHandlesDocumentThenSetMutationThenAckThenDocument', () async {
    final Query query = Query.atPath(ResourcePath.fromString('foo'));
    final int targetId = await instance.allocateQuery(query);
    await instance.applyRemoteEvent(addedRemoteEvent(
        doc('foo/bar', 2, map(<String>['it', 'base']), false),
        <int>[targetId],
        <int>[]));

    instance.assertChanged(<Document>[
      doc('foo/bar', 2, map(<String>['it', 'base']), false)
    ]);
    await instance
        .assertContains(doc('foo/bar', 2, map(<String>['it', 'base']), false));

    await instance
        .writeMutation(setMutation('foo/bar', map(<String>['foo', 'bar'])));
    instance.assertChanged(<Document>[
      doc('foo/bar', 2, map(<String>['foo', 'bar']), true)
    ]);
    await instance
        .assertContains(doc('foo/bar', 2, map(<String>['foo', 'bar']), true));

    await instance.acknowledgeMutation(3);
    // We haven't seen the remote event yet.
    instance.assertChanged();
    await instance
        .assertContains(doc('foo/bar', 2, map(<String>['foo', 'bar']), true));

    await instance.applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 3, map(<String>['it', 'changed']), false),
        <int>[targetId],
        <int>[]));
    instance.assertChanged(<Document>[
      doc('foo/bar', 3, map(<String>['it', 'changed']), false)
    ]);
    await instance.assertContains(
        doc('foo/bar', 3, map(<String>['it', 'changed']), false));
  });

  test('testHandlesPatchWithoutPriorDocument', () async {
    await instance
        .writeMutation(patchMutation('foo/bar', map(<String>['foo', 'bar'])));
    instance.assertRemoved(<String>['foo/bar']);
    await instance.assertNotContains('foo/bar');

    await instance.acknowledgeMutation(1);
    instance.assertRemoved(<String>['foo/bar']);
    await instance.assertNotContains('foo/bar');
  });

  test('testHandlesPatchMutationThenDocumentThenAck', () async {
    await instance
        .writeMutation(patchMutation('foo/bar', map(<String>['foo', 'bar'])));
    instance.assertRemoved(<String>['foo/bar']);
    await instance.assertNotContains('foo/bar');

    final Query query = Query.atPath(ResourcePath.fromString('foo'));
    final int targetId = await instance.allocateQuery(query);
    await instance.applyRemoteEvent(addedRemoteEvent(
        doc('foo/bar', 1, map(<String>['it', 'base']), true),
        <int>[targetId],
        <int>[]));
    instance.assertChanged(<Document>[
      doc('foo/bar', 1, map(<String>['foo', 'bar', 'it', 'base']), true)
    ]);
    await instance.assertContains(
        doc('foo/bar', 1, map(<String>['foo', 'bar', 'it', 'base']), true));

    await instance.acknowledgeMutation(2);

    instance.assertChanged();
    await instance.assertContains(
        doc('foo/bar', 1, map(<String>['foo', 'bar', 'it', 'base']), true));

    await instance.applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 2, map(<String>['foo', 'bar', 'it', 'base']), false),
        <int>[targetId],
        <int>[]));
    instance.assertChanged(<Document>[
      doc('foo/bar', 2, map(<String>['foo', 'bar', 'it', 'base']), false)
    ]);
    await instance.assertContains(
        doc('foo/bar', 2, map(<String>['foo', 'bar', 'it', 'base']), false));
  });

  test('testHandlesPatchMutationThenAckThenDocument', () async {
    await instance
        .writeMutation(patchMutation('foo/bar', map(<String>['foo', 'bar'])));
    instance.assertRemoved(<String>['foo/bar']);
    await instance.assertNotContains('foo/bar');

    await instance.acknowledgeMutation(1);
    instance.assertRemoved(<String>['foo/bar']);
    await instance.assertNotContains('foo/bar');

    final Query query = Query.atPath(ResourcePath.fromString('foo'));
    final int targetId = await instance.allocateQuery(query);
    await instance.applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 1, map(<String>['it', 'base']), false),
        <int>[targetId],
        <int>[]));
    instance.assertChanged(<Document>[
      doc('foo/bar', 1, map(<String>['it', 'base']), false)
    ]);
    await instance
        .assertContains(doc('foo/bar', 1, map(<String>['it', 'base']), false));
  });

  test('testHandlesDeleteMutationThenAck', () async {
    await instance.writeMutation(deleteMutation('foo/bar'));
    instance.assertRemoved(<String>['foo/bar']);
    await instance.assertContains(deletedDoc('foo/bar', 0));

    await instance.acknowledgeMutation(1);
    instance.assertRemoved(<String>['foo/bar']);
    // There's no target pinning the doc, and we've ack'd the mutation.
    if (instance.garbageCollectorIsEager) {
      await instance.assertNotContains('foo/bar');
    } else {
      await instance.assertContains(deletedDoc('foo/bar', 0));
    }
  });

  test('testHandlesDocumentThenDeleteMutationThenAck', () async {
    final Query query = Query.atPath(ResourcePath.fromString('foo'));
    final int targetId = await instance.allocateQuery(query);
    await instance.applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 1, map(<String>['it', 'base']), false),
        <int>[targetId],
        <int>[]));
    instance.assertChanged(<Document>[
      doc('foo/bar', 1, map(<String>['it', 'base']), false)
    ]);
    await instance
        .assertContains(doc('foo/bar', 1, map(<String>['it', 'base']), false));

    await instance.writeMutation(deleteMutation('foo/bar'));
    instance.assertRemoved(<String>['foo/bar']);
    await instance.assertContains(deletedDoc('foo/bar', 0));

    // Remove the target so only the mutation is pinning the document.
    await instance.releaseQuery(query);
    await instance.acknowledgeMutation(2);
    if (instance.garbageCollectorIsEager) {
      // Neither the target nor the mutation pin the document, it should be gone.
      await instance.assertNotContains('foo/bar');
    } else {
      await instance.assertContains(deletedDoc('foo/bar', 0));
    }
  });

  test('testHandlesDeleteMutationThenDocumentThenAck', () async {
    final Query query = Query.atPath(ResourcePath.fromString('foo'));
    final int targetId = await instance.allocateQuery(query);
    await instance.writeMutation(deleteMutation('foo/bar'));
    instance.assertRemoved(<String>['foo/bar']);
    await instance.assertContains(deletedDoc('foo/bar', 0));

    await instance.applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 1, map(<String>['it', 'base']), false),
        <int>[targetId],
        <int>[]));
    instance.assertRemoved(<String>['foo/bar']);
    await instance.assertContains(deletedDoc('foo/bar', 0));

    await instance.releaseQuery(query);
    await instance.acknowledgeMutation(2);
    instance.assertRemoved(<String>['foo/bar']);
    if (instance.garbageCollectorIsEager) {
      // The doc is not pinned in a target and we've acknowledged the mutation.
      // It shouldn't exist anymore.
      await instance.assertNotContains('foo/bar');
    } else {
      await instance.assertContains(deletedDoc('foo/bar', 0));
    }
  });

  test('testHandlesDocumentThenDeletedDocumentThenDocument', () async {
    final Query query = Query.atPath(ResourcePath.fromString('foo'));
    final int targetId = await instance.allocateQuery(query);
    await instance.applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 1, map(<String>['it', 'base']), false),
        <int>[targetId],
        <int>[]));
    instance.assertChanged(<Document>[
      doc('foo/bar', 1, map(<String>['it', 'base']), false)
    ]);
    await instance
        .assertContains(doc('foo/bar', 1, map(<String>['it', 'base']), false));

    await instance.applyRemoteEvent(
        updateRemoteEvent(deletedDoc('foo/bar', 2), <int>[targetId], <int>[]));
    instance.assertRemoved(<String>['foo/bar']);
    if (!instance.garbageCollectorIsEager) {
      await instance.assertContains(deletedDoc('foo/bar', 2));
    }

    await instance.applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 3, map(<String>['it', 'changed']), false),
        <int>[targetId],
        <int>[]));
    instance.assertChanged(<Document>[
      doc('foo/bar', 3, map(<String>['it', 'changed']), false)
    ]);
    await instance.assertContains(
        doc('foo/bar', 3, map(<String>['it', 'changed']), false));
  });

  test('testHandlesSetMutationThenPatchMutationThenDocumentThenAckThenAck',
      () async {
    await instance
        .writeMutation(setMutation('foo/bar', map(<String>['foo', 'old'])));
    instance.assertChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'old']), true)
    ]);
    await instance
        .assertContains(doc('foo/bar', 0, map(<String>['foo', 'old']), true));

    await instance
        .writeMutation(patchMutation('foo/bar', map(<String>['foo', 'bar'])));
    instance.assertChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']), true)
    ]);
    await instance
        .assertContains(doc('foo/bar', 0, map(<String>['foo', 'bar']), true));

    final Query query = Query.atPath(ResourcePath.fromString('foo'));
    final int targetId = await instance.allocateQuery(query);
    await instance.applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 1, map(<String>['it', 'base']), true),
        <int>[targetId],
        <int>[]));
    instance.assertChanged(<Document>[
      doc('foo/bar', 1, map(<String>['foo', 'bar']), true)
    ]);
    await instance
        .assertContains(doc('foo/bar', 1, map(<String>['foo', 'bar']), true));

    await instance.releaseQuery(query);
    await instance.acknowledgeMutation(2); // delete mutation
    instance.assertChanged(<Document>[
      doc('foo/bar', 1, map(<String>['foo', 'bar']), true)
    ]);
    await instance
        .assertContains(doc('foo/bar', 1, map(<String>['foo', 'bar']), true));

    await instance.acknowledgeMutation(3); // patch mutation
    instance.assertChanged(<Document>[
      doc('foo/bar', 1, map(<String>['foo', 'bar']), false)
    ]);
    if (instance.garbageCollectorIsEager) {
      // we've ack'd all of the mutations, nothing is keeping this pinned anymore
      await instance.assertNotContains('foo/bar');
    } else {
      await instance.assertContains(
          doc('foo/bar', 1, map(<String>['foo', 'bar']), false));
    }
  });

  test('testHandlesSetMutationAndPatchMutationTogether', () async {
    await instance.writeMutations(<Mutation>[
      setMutation('foo/bar', map(<String>['foo', 'old'])),
      patchMutation('foo/bar', map(<String>['foo', 'bar']))
    ]);

    instance.assertChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']), true)
    ]);
    await instance
        .assertContains(doc('foo/bar', 0, map(<String>['foo', 'bar']), true));
  });

  test('testHandlesSetMutationThenPatchMutationThenReject', () async {
    if (!instance.garbageCollectorIsEager) {
      return;
    }

    await instance
        .writeMutation(setMutation('foo/bar', map(<String>['foo', 'old'])));
    await instance
        .assertContains(doc('foo/bar', 0, map(<String>['foo', 'old']), true));
    await instance.acknowledgeMutation(1);
    await instance.assertNotContains('foo/bar');

    instance
        .writeMutation(patchMutation('foo/bar', map(<String>['foo', 'bar'])));
    // A blind patch is not visible in the cache
    await instance.assertNotContains('foo/bar');

    await instance.rejectMutation();
    await instance.assertNotContains('foo/bar');
  });

  test('testHandlesSetMutationsAndPatchMutationOfJustOneTogether', () async {
    await instance.writeMutations(<Mutation>[
      setMutation('foo/bar', map(<String>['foo', 'old'])),
      setMutation('bar/baz', map(<String>['bar', 'baz'])),
      patchMutation('foo/bar', map(<String>['foo', 'bar']))
    ]);

    instance.assertChanged(<Document>[
      doc('bar/baz', 0, map(<String>['bar', 'baz']), true),
      doc('foo/bar', 0, map(<String>['foo', 'bar']), true)
    ]);

    await instance
        .assertContains(doc('foo/bar', 0, map(<String>['foo', 'bar']), true));
    await instance
        .assertContains(doc('bar/baz', 0, map(<String>['bar', 'baz']), true));
  });

  test('testHandlesDeleteMutationThenPatchMutationThenAckThenAck', () async {
    await instance.writeMutation(deleteMutation('foo/bar'));
    instance.assertRemoved(<String>['foo/bar']);
    await instance.assertContains(deletedDoc('foo/bar', 0));

    await instance
        .writeMutation(patchMutation('foo/bar', map(<String>['foo', 'bar'])));
    instance.assertRemoved(<String>['foo/bar']);
    await instance.assertContains(deletedDoc('foo/bar', 0));

    await instance.acknowledgeMutation(2); // delete mutation
    instance.assertRemoved(<String>['foo/bar']);
    await instance.assertContains(deletedDoc('foo/bar', 0));

    await instance.acknowledgeMutation(3); // patch mutation
    instance.assertRemoved(<String>['foo/bar']);
    if (instance.garbageCollectorIsEager) {
      // There are no more pending mutations, the doc has been dropped
      await instance.assertNotContains('foo/bar');
    } else {
      await instance.assertContains(deletedDoc('foo/bar', 0));
    }
  });

  test('testCollectsGarbageAfterChangeBatchWithNoTargetIDs', () async {
    if (!instance.garbageCollectorIsEager) {
      return;
    }

    const int targetId = 1;
    await instance.applyRemoteEvent(updateRemoteEvent(
        deletedDoc('foo/bar', 2), <int>[], <int>[], <int>[targetId]));
    await instance.assertNotContains('foo/bar');

    await instance.applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 2, map(<String>['foo', 'bar']), false),
        <int>[],
        <int>[],
        <int>[targetId]));
    await instance.assertNotContains('foo/bar');
  });

  test('testCollectsGarbageAfterChangeBatch', () async {
    if (!instance.garbageCollectorIsEager) {
      return;
    }

    final Query query = Query.atPath(ResourcePath.fromString('foo'));
    await instance.allocateQuery(query);
    instance.assertTargetId(2);

    final List<int> none = <int>[];
    final List<int> two = <int>[2];
    await instance.applyRemoteEvent(addedRemoteEvent(
        doc('foo/bar', 2, map(<String>['foo', 'bar']), false), two, none));
    await instance
        .assertContains(doc('foo/bar', 2, map(<String>['foo', 'bar']), false));

    await instance.applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 2, map(<String>['foo', 'baz']), false), none, two));

    await instance.assertNotContains('foo/bar');
  });

  test('testCollectsGarbageAfterAcknowledgedMutation', () async {
    if (!instance.garbageCollectorIsEager) {
      return;
    }

    final Query query = Query.atPath(ResourcePath.fromString('foo'));
    final int targetId = await instance.allocateQuery(query);
    await instance.applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 0, map(<String>['foo', 'old']), false),
        <int>[targetId],
        <int>[]));
    await instance
        .writeMutation(patchMutation('foo/bar', map(<String>['foo', 'bar'])));
    await instance.releaseQuery(query);
    await instance
        .writeMutation(setMutation('foo/bah', map(<String>['foo', 'bah'])));
    await instance.writeMutation(deleteMutation('foo/baz'));
    await instance
        .assertContains(doc('foo/bar', 0, map(<String>['foo', 'bar']), true));
    await instance
        .assertContains(doc('foo/bah', 0, map(<String>['foo', 'bah']), true));
    await instance.assertContains(deletedDoc('foo/baz', 0));

    await instance.acknowledgeMutation(3);
    await instance.assertNotContains('foo/bar');
    await instance
        .assertContains(doc('foo/bah', 0, map(<String>['foo', 'bah']), true));
    await instance.assertContains(deletedDoc('foo/baz', 0));

    await instance.acknowledgeMutation(4);
    await instance.assertNotContains('foo/bar');
    await instance.assertNotContains('foo/bah');
    await instance.assertContains(deletedDoc('foo/baz', 0));

    await instance.acknowledgeMutation(5);
    await instance.assertNotContains('foo/bar');
    await instance.assertNotContains('foo/bah');
    await instance.assertNotContains('foo/baz');
  });

  test('testCollectsGarbageAfterRejectedMutation', () async {
    if (!instance.garbageCollectorIsEager) {
      return;
    }

    final Query query = Query.atPath(ResourcePath.fromString('foo'));
    final int targetId = await instance.allocateQuery(query);
    await instance.applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 0, map(<String>['foo', 'old']), false),
        <int>[targetId],
        <int>[]));
    await instance
        .writeMutation(patchMutation('foo/bar', map(<String>['foo', 'bar'])));
    // Release the query so that our target count goes back to 0 and we are
    // considered up-to-date.
    await instance.releaseQuery(query);
    await instance
        .writeMutation(setMutation('foo/bah', map(<String>['foo', 'bah'])));
    await instance.writeMutation(deleteMutation('foo/baz'));
    await instance
        .assertContains(doc('foo/bar', 0, map(<String>['foo', 'bar']), true));
    await instance
        .assertContains(doc('foo/bah', 0, map(<String>['foo', 'bah']), true));
    await instance.assertContains(deletedDoc('foo/baz', 0));

    await instance.rejectMutation(); // patch mutation
    await instance.assertNotContains('foo/bar');
    await instance
        .assertContains(doc('foo/bah', 0, map(<String>['foo', 'bah']), true));
    await instance.assertContains(deletedDoc('foo/baz', 0));

    await instance.rejectMutation(); // set mutation
    await instance.assertNotContains('foo/bar');
    await instance.assertNotContains('foo/bah');
    await instance.assertContains(deletedDoc('foo/baz', 0));

    await instance.rejectMutation(); // delete mutation
    await instance.assertNotContains('foo/bar');
    await instance.assertNotContains('foo/bah');
    await instance.assertNotContains('foo/baz');
  });

  test('testPinsDocumentsInTheLocalView', () async {
    if (!instance.garbageCollectorIsEager) {
      return;
    }

    final Query query = Query.atPath(ResourcePath.fromString('foo'));
    await instance.allocateQuery(query);
    instance.assertTargetId(2);

    final List<int> none = <int>[];
    final List<int> two = <int>[2];
    await instance.applyRemoteEvent(addedRemoteEvent(
        doc('foo/bar', 1, map(<String>['foo', 'bar']), false), two, none));
    await instance
        .writeMutation(setMutation('foo/baz', map(<String>['foo', 'baz'])));
    await instance
        .assertContains(doc('foo/bar', 1, map(<String>['foo', 'bar']), false));
    await instance
        .assertContains(doc('foo/baz', 0, map(<String>['foo', 'baz']), true));

    await instance.notifyLocalViewChanges(
        viewChanges(2, <String>['foo/bar', 'foo/baz'], <String>[]));
    await instance.applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 1, map(<String>['foo', 'bar']), false), none, two));
    await instance.applyRemoteEvent(updateRemoteEvent(
        doc('foo/baz', 2, map(<String>['foo', 'baz']), false), two, none));
    await instance.acknowledgeMutation(2);
    await instance
        .assertContains(doc('foo/bar', 1, map(<String>['foo', 'bar']), false));
    await instance
        .assertContains(doc('foo/baz', 2, map(<String>['foo', 'baz']), false));

    await instance.notifyLocalViewChanges(
        viewChanges(2, <String>[], <String>['foo/bar', 'foo/baz']));
    await instance.releaseQuery(query);

    await instance.assertNotContains('foo/bar');
    await instance.assertNotContains('foo/baz');
  });

  test('testThrowsAwayDocumentsWithUnknownTargetIDsImmediately', () async {
    if (!instance.garbageCollectorIsEager) {
      return;
    }

    const int targetID = 321;
    await instance.applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 1, map(), false), <int>[], <int>[], <int>[targetID]));

    await instance.assertNotContains('foo/bar');
  });

  test('testCanExecuteDocumentQueries', () async {
    await instance.localStore.writeLocally(<Mutation>[
      setMutation('foo/bar', map(<String>['foo', 'bar'])),
      setMutation('foo/baz', map(<String>['foo', 'baz'])),
      setMutation('foo/bar/Foo/Bar', map(<String>['Foo', 'Bar']))
    ]);

    final Query query =
        Query.atPath(ResourcePath.fromSegments(<String>['foo', 'bar']));
    final ImmutableSortedMap<DocumentKey, Document> docs =
        await instance.localStore.executeQuery(query);
    expect(values(docs), <Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']), true)
    ]);
  });

  test('testCanExecuteCollectionQueries', () async {
    await instance.localStore.writeLocally(<SetMutation>[
      setMutation('fo/bar', map(<String>['fo', 'bar'])),
      setMutation('foo/bar', map(<String>['foo', 'bar'])),
      setMutation('foo/baz', map(<String>['foo', 'baz'])),
      setMutation('foo/bar/Foo/Bar', map(<String>['Foo', 'Bar'])),
      setMutation('fooo/blah', map(<String>['fooo', 'blah']))
    ]);

    final Query query = Query.atPath(ResourcePath.fromString('foo'));
    final ImmutableSortedMap<DocumentKey, Document> docs =
        await instance.localStore.executeQuery(query);

    expect(values(docs), <Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']), true),
      doc('foo/baz', 0, map(<String>['foo', 'baz']), true)
    ]);
  });

  test('testCanExecuteMixedCollectionQueries', () async {
    final Query query = Query.atPath(ResourcePath.fromString('foo'));
    await instance.allocateQuery(query);
    instance.assertTargetId(2);

    await instance.applyRemoteEvent(updateRemoteEvent(
        doc('foo/baz', 10, map(<String>['a', 'b']), false), <int>[2], <int>[]));
    await instance.applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 20, map(<String>['a', 'b']), false), <int>[2], <int>[]));
    await instance
        .writeMutation(setMutation('foo/bonk', map(<String>['a', 'b'])));

    final ImmutableSortedMap<DocumentKey, Document> docs =
        await instance.localStore.executeQuery(query);

    expect(values(docs), <Document>[
      doc('foo/bar', 20, map(<String>['a', 'b']), false),
      doc('foo/baz', 10, map(<String>['a', 'b']), false),
      doc('foo/bonk', 0, map(<String>['a', 'b']), true)
    ]);
  });

  test('testPersistsResumeTokens', () async {
    // This test only works in the absence of the EagerGarbageCollector.
    if (instance.garbageCollectorIsEager) {
      return;
    }

    final Query query = TestUtil.query('foo/bar');
    final int targetId = await instance.allocateQuery(query);
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
    await instance.applyRemoteEvent(remoteEvent);

    // Stop listening so that the query should become inactive (but persistent)
    await instance.localStore.releaseQuery(query);

    // Should come back with the same resume token
    final QueryData queryData2 = await instance.localStore.allocateQuery(query);
    expect(queryData2.resumeToken, resumeToken);
  });

  test('testDoesNotReplaceResumeTokenWithEmptyByteString', () async {
    // This test only works in the absence of the EagerGarbageCollector.
    if (instance.garbageCollectorIsEager) {
      return;
    }

    final Query query = TestUtil.query('foo/bar');
    final int targetId = await instance.allocateQuery(query);
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
    await instance.applyRemoteEvent(remoteEvent1);

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
    await instance.applyRemoteEvent(remoteEvent2);

    // Stop listening so that the query should become inactive (but persistent)
    await instance.localStore.releaseQuery(query);

    // Should come back with the same resume token
    final QueryData queryData2 = await instance.localStore.allocateQuery(query);
    expect(queryData2.resumeToken, resumeToken);
  });

  test('testRemoteDocumentKeysForTarget', () async {
    final Query query = Query.atPath(ResourcePath.fromString('foo'));
    await instance.allocateQuery(query);
    instance.assertTargetId(2);

    await instance.applyRemoteEvent(addedRemoteEvent(
        doc('foo/baz', 10, map(<String>['a', 'b']), false), <int>[2], <int>[]));
    await instance.applyRemoteEvent(addedRemoteEvent(
        doc('foo/bar', 20, map(<String>['a', 'b']), false), <int>[2], <int>[]));
    await instance
        .writeMutation(setMutation('foo/bonk', map(<String>['a', 'b'])));

    ImmutableSortedSet<DocumentKey> keys =
        await instance.localStore.getRemoteDocumentKeys(2);
    expect(keys, <DocumentKey>[key('foo/bar'), key('foo/baz')]);

    keys = await instance.localStore.getRemoteDocumentKeys(2);
    expect(keys, <DocumentKey>[key('foo/bar'), key('foo/baz')]);
  });
}

class SQLiteLocalStoreTest extends LocalStoreTestCase {
  @override
  final Persistence persistence;

  SQLiteLocalStoreTest(this.persistence);

  @override
  bool get garbageCollectorIsEager => false;
}

// ignore: always_specify_types
const version = TestUtil.version;
// ignore: always_specify_types
const key = TestUtil.key;
// ignore: always_specify_types
const map = TestUtil.map;
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
