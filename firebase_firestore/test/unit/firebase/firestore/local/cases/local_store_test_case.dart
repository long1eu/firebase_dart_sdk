// File created by
// Lung Razvan <long1eu>
// on 29/09/2018
import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_database_collection/firebase_database_collection.dart';
import 'package:firebase_firestore/src/firebase/firestore/auth/user.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/local_store.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/local_view_changes.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/local_write_result.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/persistence.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_data.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_purpose.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/set_mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/no_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/resource_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/remote_event.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/watch_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/watch_change_aggregator.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/watch_stream.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/write_stream.dart';
import 'package:firebase_firestore/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../../../util/test_util.dart';
import '../../../firestore/test_util.dart' as t;

class LocalStoreTestCase {
  LocalStoreTestCase(this._persistence, {bool garbageCollectorIsEager})
      : _garbageCollectorIsEager = garbageCollectorIsEager;

  final Persistence _persistence;
  final bool _garbageCollectorIsEager;

  List<MutationBatch> _batches;
  ImmutableSortedMap<DocumentKey, MaybeDocument> _lastChanges;
  int _lastTargetId;
  LocalStore _localStore;

  Future<void> setUp() async {
    _localStore = LocalStore(_persistence, User.unauthenticated);
    await _localStore.start();

    _batches = <MutationBatch>[];
    _lastChanges = null;
    _lastTargetId = 0;
  }

  Future<void> tearDown() => _persistence.shutdown();

  @testMethod
  Future<void> testMutationBatchKeys() async {
    final SetMutation set1 = setMutation('foo/bar', map(<String>['foo', 'bar']));
    final SetMutation set2 = setMutation('foo/baz', map(<String>['foo', 'baz']));
    final MutationBatch batch = MutationBatch(1, Timestamp.now(), <SetMutation>[set1, set2]);
    final Set<DocumentKey> keys = batch.keys;
    expect(keys.length, 2);
  }

  @testMethod
  Future<void> testHandlesSetMutation() async {
    await _writeMutation(setMutation('foo/bar', map(<String>['foo', 'bar'])));

    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']), DocumentState.localMutations)
    ]);
    await _expectContains(doc('foo/bar', 0, map(<String>['foo', 'bar']), DocumentState.localMutations));

    await _acknowledgeMutation(0);

    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']), DocumentState.committedMutations)
    ]);

    if (_garbageCollectorIsEager) {
      // Nothing is pinning this anymore, as it has been acknowledged and there are no targets active.
      await _expectNotContains('foo/bar');
    } else {
      await _expectContains(doc('foo/bar', 0, map(<String>['foo', 'bar']), DocumentState.committedMutations));
    }
  }

  @testMethod
  Future<void> testHandlesSetMutationThenDocument() async {
    await _writeMutation(setMutation('foo/bar', map(<String>['foo', 'bar'])));
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']), DocumentState.localMutations)
    ]);
    await _expectContains(doc('foo/bar', 0, map(<String>['foo', 'bar']), DocumentState.localMutations));

    final Query query = Query(ResourcePath.fromString('foo'));
    final int targetId = await _allocateQuery(query);
    await _applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 2, map(<String>['it', 'changed']), DocumentState.localMutations), <int>[targetId], <int>[]));
    _expectChanged(<Document>[
      doc('foo/bar', 2, map(<String>['foo', 'bar']), DocumentState.localMutations)
    ]);
    await _expectContains(doc('foo/bar', 2, map(<String>['foo', 'bar']), DocumentState.localMutations));
  }

  @testMethod
  Future<void> testHandlesSetMutationThenAckThenRelease() async {
    final Query query = Query(ResourcePath.fromSegments(<String>['foo']));
    await _allocateQuery(query);

    await _writeMutation(setMutation('foo/bar', map(<String>['foo', 'bar'])));
    await _notifyLocalViewChanges(viewChanges(2, <String>['foo/bar'], <String>[]));

    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']), DocumentState.localMutations)
    ]);
    await _expectContains(doc('foo/bar', 0, map(<String>['foo', 'bar']), DocumentState.localMutations));

    await _acknowledgeMutation(1);

    _expectChanged(<Document>[
      doc('foo/bar', 1, map(<String>['foo', 'bar']), DocumentState.committedMutations)
    ]);
    await _expectContains(doc('foo/bar', 1, map(<String>['foo', 'bar']), DocumentState.committedMutations));

    await _releaseQuery(query);

    // It has been acknowledged, and should no longer be retained as there is no target and mutation
    if (_garbageCollectorIsEager) {
      await _expectNotContains('foo/bar');
    } else {
      await _expectContains(doc('foo/bar', 1, map(<String>['foo', 'bar']), DocumentState.committedMutations));
    }
  }

  @testMethod
  Future<void> testHandlesAckThenRejectThenRemoteEvent() async {
    // Start a query that requires acks to be held.
    final Query query = Query(ResourcePath.fromSegments(<String>['foo']));
    final int targetId = await _allocateQuery(query);

    await _writeMutation(setMutation('foo/bar', map(<String>['foo', 'bar'])));
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']), DocumentState.localMutations)
    ]);
    await _expectContains(doc('foo/bar', 0, map(<String>['foo', 'bar']), DocumentState.localMutations));

    // The last seen version is zero, so this ack must be held.
    await _acknowledgeMutation(1);
    if (_garbageCollectorIsEager) {
      // Nothing is pinning this anymore, as it has been acknowledged and there are no targets active.
      await _expectNotContains('foo/bar');
    } else {
      await _expectContains(doc('foo/bar', 1, map(<String>['foo', 'bar']), DocumentState.committedMutations));
    }

    await _writeMutation(setMutation('bar/baz', map(<String>['bar', 'baz'])));
    _expectChanged(<Document>[
      doc('bar/baz', 0, map(<String>['bar', 'baz']), DocumentState.localMutations)
    ]);
    await _expectContains(doc('bar/baz', 0, map(<String>['bar', 'baz']), DocumentState.localMutations));

    await _rejectMutation();
    _expectRemoved(<String>['bar/baz']);
    await _expectNotContains('bar/baz');

    await _applyRemoteEvent(
        addedRemoteEvent(doc('foo/bar', 2, map(<String>['it', 'changed'])), <int>[targetId], <int>[]));
    _expectChanged(<Document>[
      doc('foo/bar', 2, map(<String>['it', 'changed']))
    ]);
    await _expectContains(doc('foo/bar', 2, map(<String>['it', 'changed'])));
    await _expectNotContains('bar/baz');
  }

  @testMethod
  Future<void> testHandlesDeletedDocumentThenSetMutationThenAck() async {
    final Query _query = query('foo');
    final int targetId = await _allocateQuery(_query);
    await _applyRemoteEvent(updateRemoteEvent(deletedDoc('foo/bar', 2), <int>[targetId], <int>[]));
    _expectRemoved(<String>['foo/bar']);
    // Under eager GC, there is no longer a reference for the document, and it should be deleted.
    if (_garbageCollectorIsEager) {
      await _expectNotContains('foo/bar');
    } else {
      await _expectContains(deletedDoc('foo/bar', 2));
    }

    await _writeMutation(setMutation('foo/bar', map(<String>['foo', 'bar'])));
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']), DocumentState.localMutations)
    ]);
    await _expectContains(doc('foo/bar', 0, map(<String>['foo', 'bar']), DocumentState.localMutations));

    await _releaseQuery(_query);
    await _acknowledgeMutation(3);
    _expectChanged(<Document>[
      doc('foo/bar', 3, map(<String>['foo', 'bar']), DocumentState.committedMutations)
    ]);
    // It has been acknowledged, and should no longer be retained as there is no target and mutation
    if (_garbageCollectorIsEager) {
      await _expectNotContains('foo/bar');
    }
  }

  @testMethod
  Future<void> testHandlesSetMutationThenDeletedDocument() async {
    final Query _query = query('foo');
    final int targetId = await _allocateQuery(_query);
    await _writeMutation(setMutation('foo/bar', map(<String>['foo', 'bar'])));
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']), DocumentState.localMutations)
    ]);

    await _applyRemoteEvent(updateRemoteEvent(deletedDoc('foo/bar', 2), <int>[targetId], <int>[]));
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']), DocumentState.localMutations)
    ]);
    await _expectContains(doc('foo/bar', 0, map(<String>['foo', 'bar']), DocumentState.localMutations));
  }

  @testMethod
  Future<void> testHandlesDocumentThenSetMutationThenAckThenDocument() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    final int targetId = await _allocateQuery(query);
    await _applyRemoteEvent(addedRemoteEvent(doc('foo/bar', 2, map(<String>['it', 'base'])), <int>[targetId], <int>[]));

    _expectChanged(<Document>[
      doc('foo/bar', 2, map(<String>['it', 'base']))
    ]);
    await _expectContains(doc('foo/bar', 2, map(<String>['it', 'base'])));

    await _writeMutation(setMutation('foo/bar', map(<String>['foo', 'bar'])));
    _expectChanged(<Document>[
      doc('foo/bar', 2, map(<String>['foo', 'bar']), DocumentState.localMutations)
    ]);
    await _expectContains(doc('foo/bar', 2, map(<String>['foo', 'bar']), DocumentState.localMutations));

    await _acknowledgeMutation(3);
    _expectChanged(<Document>[
      doc('foo/bar', 3, map(<String>['foo', 'bar']), DocumentState.committedMutations)
    ]);
    await _expectContains(doc('foo/bar', 3, map(<String>['foo', 'bar']), DocumentState.committedMutations));

    await _applyRemoteEvent(
        updateRemoteEvent(doc('foo/bar', 3, map(<String>['it', 'changed'])), <int>[targetId], <int>[]));
    _expectChanged(<Document>[
      doc('foo/bar', 3, map(<String>['it', 'changed']))
    ]);
    await _expectContains(doc('foo/bar', 3, map(<String>['it', 'changed'])));
  }

  @testMethod
  Future<void> testHandlesPatchWithoutPriorDocument() async {
    await _writeMutation(patchMutation('foo/bar', map(<String>['foo', 'bar'])));
    _expectRemoved(<String>['foo/bar']);
    await _expectNotContains('foo/bar');

    await _acknowledgeMutation(1);
    _expectChanged(<MaybeDocument>[unknownDoc('foo/bar', 1)]);

    if (_garbageCollectorIsEager) {
      // Nothing is pinning this anymore, as it has been acknowledged and there are no targets active.
      await _expectNotContains('foo/bar');
    } else {
      await _expectContains(unknownDoc('foo/bar', 1));
    }
  }

  @testMethod
  Future<void> testHandlesPatchMutationThenDocumentThenAck() async {
    await _writeMutation(patchMutation('foo/bar', map(<String>['foo', 'bar'])));
    _expectRemoved(<String>['foo/bar']);
    await _expectNotContains('foo/bar');

    final Query query = Query(ResourcePath.fromString('foo'));
    final int targetId = await _allocateQuery(query);
    await _applyRemoteEvent(addedRemoteEvent(
        doc('foo/bar', 1, map(<String>['it', 'base']), DocumentState.localMutations), <int>[targetId], <int>[]));
    _expectChanged(<MaybeDocument>[
      doc('foo/bar', 1, map(<String>['foo', 'bar', 'it', 'base']), DocumentState.localMutations)
    ]);
    await _expectContains(doc('foo/bar', 1, map(<String>['foo', 'bar', 'it', 'base']), DocumentState.localMutations));

    await _acknowledgeMutation(2);

    _expectChanged(<Document>[
      doc('foo/bar', 2, map(<String>['foo', 'bar', 'it', 'base']), DocumentState.committedMutations)
    ]);
    await _expectContains(
        doc('foo/bar', 2, map(<String>['foo', 'bar', 'it', 'base']), DocumentState.committedMutations));

    await _applyRemoteEvent(
        updateRemoteEvent(doc('foo/bar', 2, map(<String>['foo', 'bar', 'it', 'base'])), <int>[targetId], <int>[]));
    _expectChanged(<Document>[
      doc('foo/bar', 2, map(<String>['foo', 'bar', 'it', 'base']))
    ]);
    await _expectContains(doc('foo/bar', 2, map(<String>['foo', 'bar', 'it', 'base'])));
  }

  @testMethod
  Future<void> testHandlesPatchMutationThenAckThenDocument() async {
    await _writeMutation(patchMutation('foo/bar', map(<String>['foo', 'bar'])));
    _expectRemoved(<String>['foo/bar']);
    await _expectNotContains('foo/bar');

    await _acknowledgeMutation(1);
    _expectChanged(<MaybeDocument>[unknownDoc('foo/bar', 1)]);
    // There's no target pinning the doc, and we've ack'd the mutation.
    if (_garbageCollectorIsEager) {
      await _expectNotContains('foo/bar');
    } else {
      await _expectContains(unknownDoc('foo/bar', 1));
    }

    final Query query = Query(ResourcePath.fromString('foo'));
    final int targetId = await _allocateQuery(query);
    await _applyRemoteEvent(
        updateRemoteEvent(doc('foo/bar', 1, map(<String>['it', 'base'])), <int>[targetId], <int>[]));
    _expectChanged(<Document>[
      doc('foo/bar', 1, map(<String>['it', 'base']))
    ]);
    await _expectContains(doc('foo/bar', 1, map(<String>['it', 'base'])));
  }

  @testMethod
  Future<void> testHandlesDeleteMutationThenAck() async {
    await _writeMutation(deleteMutation('foo/bar'));
    _expectRemoved(<String>['foo/bar']);
    await _expectContains(deletedDoc('foo/bar', 0));

    await _acknowledgeMutation(1);
    _expectRemoved(<String>['foo/bar']);
    // There's no target pinning the doc, and we've ack'd the mutation.
    if (_garbageCollectorIsEager) {
      await _expectNotContains('foo/bar');
    } else {
      await _expectContains(deletedDoc('foo/bar', 1, hasCommittedMutations: true));
    }
  }

  @testMethod
  Future<void> testHandlesDocumentThenDeleteMutationThenAck() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    final int targetId = await _allocateQuery(query);
    await _applyRemoteEvent(
        updateRemoteEvent(doc('foo/bar', 1, map(<String>['it', 'base'])), <int>[targetId], <int>[]));
    _expectChanged(<Document>[
      doc('foo/bar', 1, map(<String>['it', 'base']))
    ]);
    await _expectContains(doc('foo/bar', 1, map(<String>['it', 'base'])));

    await _writeMutation(deleteMutation('foo/bar'));
    _expectRemoved(<String>['foo/bar']);
    await _expectContains(deletedDoc('foo/bar', 0));

    // Remove the target so only the mutation is pinning the document.
    await _releaseQuery(query);
    await _acknowledgeMutation(2);
    if (_garbageCollectorIsEager) {
      // Neither the target nor the mutation pin the document, it should be gone.
      await _expectNotContains('foo/bar');
    } else {
      await _expectContains(deletedDoc('foo/bar', 2, hasCommittedMutations: true));
    }
  }

  @testMethod
  Future<void> testHandlesDeleteMutationThenDocumentThenAck() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    final int targetId = await _allocateQuery(query);
    await _writeMutation(deleteMutation('foo/bar'));
    _expectRemoved(<String>['foo/bar']);
    await _expectContains(deletedDoc('foo/bar', 0));

    await _applyRemoteEvent(
        updateRemoteEvent(doc('foo/bar', 1, map(<String>['it', 'base'])), <int>[targetId], <int>[]));
    _expectRemoved(<String>['foo/bar']);
    await _expectContains(deletedDoc('foo/bar', 0));

    await _releaseQuery(query);
    await _acknowledgeMutation(2);
    _expectRemoved(<String>['foo/bar']);
    if (_garbageCollectorIsEager) {
      // The doc is not pinned in a target and we've acknowledged the mutation. It shouldn't exist anymore.
      await _expectNotContains('foo/bar');
    } else {
      await _expectContains(deletedDoc('foo/bar', 2, hasCommittedMutations: true));
    }
  }

  @testMethod
  Future<void> testHandlesDocumentThenDeletedDocumentThenDocument() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    final int targetId = await _allocateQuery(query);
    await _applyRemoteEvent(
        updateRemoteEvent(doc('foo/bar', 1, map(<String>['it', 'base'])), <int>[targetId], <int>[]));
    _expectChanged(<Document>[
      doc('foo/bar', 1, map(<String>['it', 'base']))
    ]);
    await _expectContains(doc('foo/bar', 1, map(<String>['it', 'base'])));

    await _applyRemoteEvent(updateRemoteEvent(deletedDoc('foo/bar', 2), <int>[targetId], <int>[]));
    _expectRemoved(<String>['foo/bar']);
    if (!_garbageCollectorIsEager) {
      await _expectContains(deletedDoc('foo/bar', 2));
    }

    await _applyRemoteEvent(
        updateRemoteEvent(doc('foo/bar', 3, map(<String>['it', 'changed'])), <int>[targetId], <int>[]));
    _expectChanged(<Document>[
      doc('foo/bar', 3, map(<String>['it', 'changed']))
    ]);
    await _expectContains(doc('foo/bar', 3, map(<String>['it', 'changed'])));
  }

  @testMethod
  Future<void> testHandlesSetMutationThenPatchMutationThenDocumentThenAckThenAck() async {
    await _writeMutation(setMutation('foo/bar', map(<String>['foo', 'old'])));
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'old']), DocumentState.localMutations)
    ]);
    await _expectContains(doc('foo/bar', 0, map(<String>['foo', 'old']), DocumentState.localMutations));

    await _writeMutation(patchMutation('foo/bar', map(<String>['foo', 'bar'])));
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']), DocumentState.localMutations)
    ]);
    await _expectContains(doc('foo/bar', 0, map(<String>['foo', 'bar']), DocumentState.localMutations));

    final Query query = Query(ResourcePath.fromString('foo'));

    final int targetId = await _allocateQuery(query);
    await _applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 1, map(<String>['it', 'base']), DocumentState.localMutations), <int>[targetId], <int>[]));
    _expectChanged(<Document>[
      doc('foo/bar', 1, map(<String>['foo', 'bar']), DocumentState.localMutations)
    ]);
    await _expectContains(doc('foo/bar', 1, map(<String>['foo', 'bar']), DocumentState.localMutations));

    await _releaseQuery(query);
    await _acknowledgeMutation(2); // delete mutation
    _expectChanged(<Document>[
      doc('foo/bar', 2, map(<String>['foo', 'bar']), DocumentState.localMutations)
    ]);
    await _expectContains(doc('foo/bar', 2, map(<String>['foo', 'bar']), DocumentState.localMutations));

    await _acknowledgeMutation(3); // patch mutation
    _expectChanged(<Document>[
      doc('foo/bar', 3, map(<String>['foo', 'bar']), DocumentState.committedMutations)
    ]);

    if (_garbageCollectorIsEager) {
      // we've ack'd all of the mutations, nothing is keeping this pinned anymore
      await _expectNotContains('foo/bar');
    } else {
      await _expectContains(doc('foo/bar', 3, map(<String>['foo', 'bar']), DocumentState.committedMutations));
    }
  }

  @testMethod
  Future<void> testHandlesSetMutationAndPatchMutationTogether() async {
    await _writeMutations(<Mutation>[
      setMutation('foo/bar', map(<String>['foo', 'old'])),
      patchMutation('foo/bar', map(<String>['foo', 'bar']))
    ]);

    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']), DocumentState.localMutations)
    ]);
    await _expectContains(doc('foo/bar', 0, map(<String>['foo', 'bar']), DocumentState.localMutations));
  }

  @testMethod
  Future<void> testHandlesSetMutationThenPatchMutationThenReject() async {
    if (!_garbageCollectorIsEager) {
      return;
    }

    await _writeMutation(setMutation('foo/bar', map(<String>['foo', 'old'])));
    await _expectContains(doc('foo/bar', 0, map(<String>['foo', 'old']), DocumentState.localMutations));
    await _acknowledgeMutation(1);
    await _expectNotContains('foo/bar');

    await _writeMutation(patchMutation('foo/bar', map(<String>['foo', 'bar'])));
    // A blind patch is not visible in the cache
    await _expectNotContains('foo/bar');

    await _rejectMutation();
    await _expectNotContains('foo/bar');
  }

  @testMethod
  Future<void> testHandlesSetMutationsAndPatchMutationOfJustOneTogether() async {
    await _writeMutations(<Mutation>[
      setMutation('foo/bar', map(<String>['foo', 'old'])),
      setMutation('bar/baz', map(<String>['bar', 'baz'])),
      patchMutation('foo/bar', map(<String>['foo', 'bar']))
    ]);

    _expectChanged(<Document>[
      doc('bar/baz', 0, map(<String>['bar', 'baz']), DocumentState.localMutations),
      doc('foo/bar', 0, map(<String>['foo', 'bar']), DocumentState.localMutations)
    ]);

    await _expectContains(doc('foo/bar', 0, map(<String>['foo', 'bar']), DocumentState.localMutations));
    await _expectContains(doc('bar/baz', 0, map(<String>['bar', 'baz']), DocumentState.localMutations));
  }

  @testMethod
  Future<void> testHandlesDeleteMutationThenPatchMutationThenAckThenAck() async {
    await _writeMutation(deleteMutation('foo/bar'));
    _expectRemoved(<String>['foo/bar']);
    await _expectContains(deletedDoc('foo/bar', 0));

    await _writeMutation(patchMutation('foo/bar', map(<String>['foo', 'bar'])));
    _expectRemoved(<String>['foo/bar']);
    await _expectContains(deletedDoc('foo/bar', 0));

    await _acknowledgeMutation(2); // delete mutation
    _expectRemoved(<String>['foo/bar']);
    await _expectContains(deletedDoc('foo/bar', 2, hasCommittedMutations: true));

    await _acknowledgeMutation(3); // patch mutation
    _expectChanged(<MaybeDocument>[unknownDoc('foo/bar', 3)]);
    if (_garbageCollectorIsEager) {
      // There are no more pending mutations, the doc has been dropped
      await _expectNotContains('foo/bar');
    } else {
      await _expectContains(unknownDoc('foo/bar', 3));
    }
  }

  @testMethod
  Future<void> testCollectsGarbageAfterChangeBatchWithNoTargetIDs() async {
    if (!_garbageCollectorIsEager) {
      return;
    }

    const int targetId = 1;
    await _applyRemoteEvent(updateRemoteEvent(deletedDoc('foo/bar', 2), <int>[], <int>[], <int>[targetId]));
    await _expectNotContains('foo/bar');

    await _applyRemoteEvent(
        updateRemoteEvent(doc('foo/bar', 2, map(<String>['foo', 'bar'])), <int>[], <int>[], <int>[targetId]));
    await _expectNotContains('foo/bar');
  }

  @testMethod
  Future<void> testCollectsGarbageAfterChangeBatch() async {
    if (!_garbageCollectorIsEager) {
      return;
    }

    final Query query = Query(ResourcePath.fromString('foo'));
    await _allocateQuery(query);
    _expectTargetId(2);

    final List<int> none = <int>[];
    final List<int> two = <int>[2];
    await _applyRemoteEvent(addedRemoteEvent(doc('foo/bar', 2, map(<String>['foo', 'bar'])), two, none));
    await _expectContains(doc('foo/bar', 2, map(<String>['foo', 'bar'])));

    await _applyRemoteEvent(updateRemoteEvent(doc('foo/bar', 2, map(<String>['foo', 'baz'])), none, two));

    await _expectNotContains('foo/bar');
  }

  @testMethod
  Future<void> testCollectsGarbageAfterAcknowledgedMutation() async {
    if (!_garbageCollectorIsEager) {
      return;
    }

    final Query query = Query(ResourcePath.fromString('foo'));
    final int targetId = await _allocateQuery(query);
    await _applyRemoteEvent(
        updateRemoteEvent(doc('foo/bar', 0, map(<String>['foo', 'old'])), <int>[targetId], <int>[]));
    await _writeMutation(patchMutation('foo/bar', map(<String>['foo', 'bar'])));
    await _releaseQuery(query);
    await _writeMutation(setMutation('foo/bah', map(<String>['foo', 'bah'])));
    await _writeMutation(deleteMutation('foo/baz'));
    await _expectContains(doc('foo/bar', 0, map(<String>['foo', 'bar']), DocumentState.localMutations));
    await _expectContains(doc('foo/bah', 0, map(<String>['foo', 'bah']), DocumentState.localMutations));
    await _expectContains(deletedDoc('foo/baz', 0));

    await _acknowledgeMutation(3);
    await _expectNotContains('foo/bar');
    await _expectContains(doc('foo/bah', 0, map(<String>['foo', 'bah']), DocumentState.localMutations));
    await _expectContains(deletedDoc('foo/baz', 0));

    await _acknowledgeMutation(4);
    await _expectNotContains('foo/bar');
    await _expectNotContains('foo/bah');
    await _expectContains(deletedDoc('foo/baz', 0));

    await _acknowledgeMutation(5);
    await _expectNotContains('foo/bar');
    await _expectNotContains('foo/bah');
    await _expectNotContains('foo/baz');
  }

  @testMethod
  Future<void> testCollectsGarbageAfterRejectedMutation() async {
    if (!_garbageCollectorIsEager) {
      return;
    }

    final Query query = Query(ResourcePath.fromString('foo'));
    final int targetId = await _allocateQuery(query);
    await _applyRemoteEvent(
        updateRemoteEvent(doc('foo/bar', 0, map(<String>['foo', 'old'])), <int>[targetId], <int>[]));
    await _writeMutation(patchMutation('foo/bar', map(<String>['foo', 'bar'])));
    // Release the query so that our target count goes back to 0 and we are considered up-to-date.
    await _releaseQuery(query);
    await _writeMutation(setMutation('foo/bah', map(<String>['foo', 'bah'])));
    await _writeMutation(deleteMutation('foo/baz'));
    await _expectContains(doc('foo/bar', 0, map(<String>['foo', 'bar']), DocumentState.localMutations));
    await _expectContains(doc('foo/bah', 0, map(<String>['foo', 'bah']), DocumentState.localMutations));
    await _expectContains(deletedDoc('foo/baz', 0));

    await _rejectMutation(); // patch mutation
    await _expectNotContains('foo/bar');
    await _expectContains(doc('foo/bah', 0, map(<String>['foo', 'bah']), DocumentState.localMutations));
    await _expectContains(deletedDoc('foo/baz', 0));

    await _rejectMutation(); // set mutation
    await _expectNotContains('foo/bar');
    await _expectNotContains('foo/bah');
    await _expectContains(deletedDoc('foo/baz', 0));

    await _rejectMutation(); // delete mutation
    await _expectNotContains('foo/bar');
    await _expectNotContains('foo/bah');
    await _expectNotContains('foo/baz');
  }

  @testMethod
  Future<void> testPinsDocumentsInTheLocalView() async {
    if (!_garbageCollectorIsEager) {
      return;
    }

    final Query query = Query(ResourcePath.fromString('foo'));
    await _allocateQuery(query);
    _expectTargetId(2);

    final List<int> none = <int>[];
    final List<int> two = <int>[2];
    await _applyRemoteEvent(addedRemoteEvent(doc('foo/bar', 1, map(<String>['foo', 'bar'])), two, none));
    await _writeMutation(setMutation('foo/baz', map(<String>['foo', 'baz'])));
    await _expectContains(doc('foo/bar', 1, map(<String>['foo', 'bar'])));
    await _expectContains(doc('foo/baz', 0, map(<String>['foo', 'baz']), DocumentState.localMutations));

    await _notifyLocalViewChanges(viewChanges(2, <String>['foo/bar', 'foo/baz'], <String>[]));
    await _applyRemoteEvent(updateRemoteEvent(doc('foo/bar', 1, map(<String>['foo', 'bar'])), none, two));
    await _applyRemoteEvent(updateRemoteEvent(doc('foo/baz', 2, map(<String>['foo', 'baz'])), two, none));
    await _acknowledgeMutation(2);
    await _expectContains(doc('foo/bar', 1, map(<String>['foo', 'bar'])));
    await _expectContains(doc('foo/baz', 2, map(<String>['foo', 'baz'])));

    await _notifyLocalViewChanges(viewChanges(2, <String>[], <String>['foo/bar', 'foo/baz']));
    await _releaseQuery(query);

    await _expectNotContains('foo/bar');
    await _expectNotContains('foo/baz');
  }

  @testMethod
  Future<void> testThrowsAwayDocumentsWithUnknownTargetIDsImmediately() async {
    if (!_garbageCollectorIsEager) {
      return;
    }

    const int targetID = 321;
    await _applyRemoteEvent(updateRemoteEvent(doc('foo/bar', 1, map()), <int>[], <int>[], <int>[targetID]));

    await _expectNotContains('foo/bar');
  }

  @testMethod
  Future<void> testCanExecuteDocumentQueries() async {
    await _localStore.writeLocally(<Mutation>[
      setMutation('foo/bar', map(<String>['foo', 'bar'])),
      setMutation('foo/baz', map(<String>['foo', 'baz'])),
      setMutation('foo/bar/Foo/Bar', map(<String>['Foo', 'Bar']))
    ]);

    final Query query = Query(ResourcePath.fromSegments(<String>['foo', 'bar']));
    final ImmutableSortedMap<DocumentKey, Document> docs = await _localStore.executeQuery(query);
    expect(values(docs), <Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']), DocumentState.localMutations)
    ]);
  }

  @testMethod
  Future<void> testCanExecuteCollectionQueries() async {
    await _localStore.writeLocally(<SetMutation>[
      setMutation('fo/bar', map(<String>['fo', 'bar'])),
      setMutation('foo/bar', map(<String>['foo', 'bar'])),
      setMutation('foo/baz', map(<String>['foo', 'baz'])),
      setMutation('foo/bar/Foo/Bar', map(<String>['Foo', 'Bar'])),
      setMutation('fooo/blah', map(<String>['fooo', 'blah']))
    ]);

    final Query query = Query(ResourcePath.fromString('foo'));
    final ImmutableSortedMap<DocumentKey, Document> docs = await _localStore.executeQuery(query);

    expect(values(docs), <Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']), DocumentState.localMutations),
      doc('foo/baz', 0, map(<String>['foo', 'baz']), DocumentState.localMutations)
    ]);
  }

  @testMethod
  Future<void> testCanExecuteMixedCollectionQueries() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    await _allocateQuery(query);
    _expectTargetId(2);

    await _applyRemoteEvent(updateRemoteEvent(doc('foo/baz', 10, map(<String>['a', 'b'])), <int>[2], <int>[]));
    await _applyRemoteEvent(updateRemoteEvent(doc('foo/bar', 20, map(<String>['a', 'b'])), <int>[2], <int>[]));
    await _writeMutation(setMutation('foo/bonk', map(<String>['a', 'b'])));

    final ImmutableSortedMap<DocumentKey, Document> docs = await _localStore.executeQuery(query);

    expect(values(docs), <Document>[
      doc('foo/bar', 20, map(<String>['a', 'b'])),
      doc('foo/baz', 10, map(<String>['a', 'b'])),
      doc('foo/bonk', 0, map(<String>['a', 'b']), DocumentState.localMutations)
    ]);
  }

  @testMethod
  Future<void> testPersistsResumeTokens() async {
    // This test only works in the absence of the EagerGarbageCollector.
    if (_garbageCollectorIsEager) {
      return;
    }

    final Query _query = query('foo/bar');
    final int targetId = await _allocateQuery(_query);
    final Uint8List _resumeToken = resumeToken(1000);

    final QueryData _queryData = queryData(targetId, QueryPurpose.listen, 'foo/bar');
    final t.TestTargetMetadataProvider testTargetMetadataProvider = t.testTargetMetadataProvider
      ..setSyncedKeys(_queryData, DocumentKey.emptyKeySet);

    final WatchChangeAggregator aggregator = WatchChangeAggregator(testTargetMetadataProvider);

    final WatchChangeWatchTargetChange watchChange =
        WatchChangeWatchTargetChange(WatchTargetChangeType.current, <int>[targetId], _resumeToken);
    aggregator.handleTargetChange(watchChange);
    final RemoteEvent remoteEvent = aggregator.createRemoteEvent(version(1000));
    await _applyRemoteEvent(remoteEvent);

    // Stop listening so that the query should become inactive (but persistent)
    await _localStore.releaseQuery(_query);

    // Should come back with the same resume token
    final QueryData queryData2 = await _localStore.allocateQuery(_query);
    expect(queryData2.resumeToken, _resumeToken);
  }

  @testMethod
  Future<void> testDoesNotReplaceResumeTokenWithEmptyByteString() async {
    // This test only works in the absence of the EagerGarbageCollector.
    if (_garbageCollectorIsEager) {
      return;
    }

    final Query _query = query('foo/bar');
    final int targetId = await _allocateQuery(_query);
    final Uint8List _resumeToken = resumeToken(1000);

    final QueryData _queryData = queryData(targetId, QueryPurpose.listen, 'foo/bar');
    final t.TestTargetMetadataProvider testTargetMetadataProvider = t.testTargetMetadataProvider
      ..setSyncedKeys(_queryData, DocumentKey.emptyKeySet);

    final WatchChangeAggregator aggregator1 = WatchChangeAggregator(testTargetMetadataProvider);

    final WatchChangeWatchTargetChange watchChange1 =
        WatchChangeWatchTargetChange(WatchTargetChangeType.current, <int>[targetId], _resumeToken);
    aggregator1.handleTargetChange(watchChange1);
    final RemoteEvent remoteEvent1 = aggregator1.createRemoteEvent(version(1000));
    await _applyRemoteEvent(remoteEvent1);

    // New message with empty resume token should not replace the old resume token
    final WatchChangeAggregator aggregator2 = WatchChangeAggregator(testTargetMetadataProvider);
    final WatchChangeWatchTargetChange watchChange2 =
        WatchChangeWatchTargetChange(WatchTargetChangeType.current, <int>[targetId], WatchStream.emptyResumeToken);
    aggregator2.handleTargetChange(watchChange2);
    final RemoteEvent remoteEvent2 = aggregator2.createRemoteEvent(version(2000));
    await _applyRemoteEvent(remoteEvent2);

    // Stop listening so that the query should become inactive (but persistent)
    await _localStore.releaseQuery(_query);

    // Should come back with the same resume token
    final QueryData queryData2 = await _localStore.allocateQuery(_query);
    expect(queryData2.resumeToken, _resumeToken);
  }

  @testMethod
  Future<void> testRemoteDocumentKeysForTarget() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    await _allocateQuery(query);
    _expectTargetId(2);

    await _applyRemoteEvent(addedRemoteEvent(doc('foo/baz', 10, map(<String>['a', 'b'])), <int>[2], <int>[]));
    await _applyRemoteEvent(addedRemoteEvent(doc('foo/bar', 20, map(<String>['a', 'b'])), <int>[2], <int>[]));
    await _writeMutation(setMutation('foo/bonk', map(<String>['a', 'b'])));

    ImmutableSortedSet<DocumentKey> keys = await _localStore.getRemoteDocumentKeys(2);
    expect(keys, <DocumentKey>[key('foo/bar'), key('foo/baz')]);

    keys = await _localStore.getRemoteDocumentKeys(2);
    expect(keys, <DocumentKey>[key('foo/bar'), key('foo/baz')]);
  }

  Future<void> _writeMutation(Mutation mutation) async {
    await _writeMutations(<Mutation>[mutation]);
  }

  Future<void> _writeMutations(List<Mutation> mutations) async {
    final LocalWriteResult result = await _localStore.writeLocally(mutations);
    _batches.add(MutationBatch(result.batchId, Timestamp.now(), mutations));
    _lastChanges = result.changes;
  }

  Future<void> _applyRemoteEvent(RemoteEvent event) async {
    _lastChanges = await _localStore.applyRemoteEvent(event);
  }

  Future<void> _notifyLocalViewChanges(LocalViewChanges changes) async {
    await _localStore.notifyLocalViewChanges(<LocalViewChanges>[changes]);
  }

  Future<void> _acknowledgeMutation(int documentVersion) async {
    final MutationBatch batch = _batches.removeAt(0);
    final SnapshotVersion _version = version(documentVersion);
    final MutationResult mutationResult = MutationResult(_version, /*transformResults:*/ null);
    final MutationBatchResult result =
        MutationBatchResult.create(batch, _version, <MutationResult>[mutationResult], WriteStream.emptyStreamToken);
    _lastChanges = await _localStore.acknowledgeBatch(result);
  }

  Future<void> _rejectMutation() async {
    final MutationBatch batch = _batches.removeAt(0);
    _lastChanges = await _localStore.rejectBatch(batch.batchId);
  }

  Future<int> _allocateQuery(Query query) async {
    final QueryData queryData = await _localStore.allocateQuery(query);
    _lastTargetId = queryData.targetId;
    return queryData.targetId;
  }

  Future<void> _releaseQuery(Query query) async {
    await _localStore.releaseQuery(query);
  }

  /// Asserts that the last target ID is the given number.
  void _expectTargetId(int targetId) {
    expect(_lastTargetId, targetId);
  }

  /// Asserts that a the [_lastChanges] contain the docs in the given array.
  void _expectChanged([List<MaybeDocument> expected = const <MaybeDocument>[]]) {
    expect(_lastChanges, isNotNull);

    final List<MaybeDocument> actualList =
        _lastChanges.map((MapEntry<DocumentKey, MaybeDocument> entry) => entry.value).toList();

    expect(actualList, expected);
    _lastChanges = null;
  }

  /// Asserts that the given keys were removed.
  void _expectRemoved(List<String> keyPaths) {
    expect(_lastChanges, isNotNull);

    final ImmutableSortedMap<DocumentKey, MaybeDocument> actual = _lastChanges;
    expect(actual.length, keyPaths.length);

    int i = 0;
    for (MapEntry<DocumentKey, MaybeDocument> actualEntry in actual) {
      expect(actualEntry.key, key(keyPaths[i++]));
      expect(actualEntry.value, const TypeMatcher<NoDocument>());
    }
    _lastChanges = null;
  }

  /// Asserts that the given local store contains the given document.
  Future<void> _expectContains(MaybeDocument expected) async {
    final MaybeDocument actual = await _localStore.readDocument(expected.key);

    expect(actual, expected);
  }

  /// Asserts that the given local store does not contain the given document.
  Future<void> _expectNotContains(String keyPathString) async {
    final DocumentKey key = DocumentKey.fromPathString(keyPathString);
    final MaybeDocument actual = await _localStore.readDocument(key);
    expect(actual, isNull);
  }
}
