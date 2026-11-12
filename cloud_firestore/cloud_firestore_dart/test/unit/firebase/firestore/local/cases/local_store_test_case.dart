// File created by
// Lung Razvan <long1eu>
// on 29/09/2018
import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/target.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/default_query_engine.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_view_changes.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_write_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/mutation_queue.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/remote_document_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_purpose.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/overlay.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/patch_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/set_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/no_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart'
    as model;
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_event.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/target_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/watch_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/watch_change_aggregator.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../../../util/test_util.dart';
import '../../util/test_target_metadata_provider.dart' as t;
import '../accumulating_stats_collector.dart';
import '../counting_query_engine.dart';

class LocalStoreTestCase {
  LocalStoreTestCase(this._persistence, this._statsCollector,
      {required bool garbageCollectorIsEager})
      : _garbageCollectorIsEager = garbageCollectorIsEager;

  final AccumulatingStatsCollector _statsCollector;
  final Persistence _persistence;
  final bool _garbageCollectorIsEager;

  late List<MutationBatch> _batches;
  ImmutableSortedMap<DocumentKey, MaybeDocument>? _lastChanges;
  late int _lastTargetId;
  late LocalStore _localStore;
  late CountingQueryEngine _queryEngine;
  QueryResult? _lastQueryResult;

  Future<void> setUp() async {
    _batches = <MutationBatch>[];
    _lastChanges = null;
    _lastQueryResult = null;
    _lastTargetId = 0;

    _queryEngine = CountingQueryEngine(DefaultQueryEngine());
    _localStore = LocalStore(_persistence, User.unauthenticated,
        queryEngine: _queryEngine);
    await _localStore.start();
  }

  Future<void> tearDown() => _persistence.shutdown();

  @testMethod
  Future<void> testMutationBatchKeys() async {
    final SetMutation set1 =
        setMutation('foo/bar', map(<String>['foo', 'bar']));
    final SetMutation set2 =
        setMutation('foo/baz', map(<String>['foo', 'baz']));
    final MutationBatch batch = MutationBatch(
        batchId: 1,
        localWriteTime: Timestamp.now(),
        baseMutations: <Mutation>[],
        mutations: <SetMutation>[set1, set2]);
    final Set<DocumentKey> keys = batch.keys;
    expect(keys.length, 2);
  }

  @testMethod
  Future<void> testHandlesSetMutation() async {
    await _writeMutation(setMutation('foo/bar', map(<String>['foo', 'bar'])));

    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']),
          DocumentState.localMutations)
    ]);
    await _expectContains(doc('foo/bar', 0, map(<String>['foo', 'bar']),
        DocumentState.localMutations));

    await _acknowledgeMutation(1);

    _expectChanged(<Document>[
      doc('foo/bar', 1, map(<String>['foo', 'bar']),
          DocumentState.committedMutations)
    ]);

    if (_garbageCollectorIsEager) {
      // Nothing is pinning this anymore, as it has been acknowledged and there are no targets active.
      await _expectNotContains('foo/bar');
    } else {
      await _expectContains(doc('foo/bar', 1, map(<String>['foo', 'bar']),
          DocumentState.committedMutations));
    }
  }

  @testMethod
  Future<void> testHandlesSetMutationThenDocument() async {
    await _writeMutation(setMutation('foo/bar', map(<String>['foo', 'bar'])));
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']),
          DocumentState.localMutations)
    ]);
    await _expectContains(doc('foo/bar', 0, map(<String>['foo', 'bar']),
        DocumentState.localMutations));

    final Query query = Query(ResourcePath.fromString('foo'));
    final int targetId = await _allocateQuery(query);
    await _applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 2, map(<String>['it', 'changed']),
            DocumentState.localMutations),
        <int>[targetId],
        <int>[]));
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']),
          DocumentState.localMutations)
    ]);
    await _expectContains(doc('foo/bar', 0, map(<String>['foo', 'bar']),
        DocumentState.localMutations));
  }

  @testMethod
  Future<void> testHandlesSetMutationThenAckThenRelease() async {
    final Query query = Query(ResourcePath.fromSegments(<String>['foo']));
    await _allocateQuery(query);

    await _writeMutation(setMutation('foo/bar', map(<String>['foo', 'bar'])));
    await _notifyLocalViewChanges(viewChanges(
        2, /* fromCache= */ false, <String>['foo/bar'], <String>[]));

    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']),
          DocumentState.localMutations)
    ]);
    await _expectContains(doc('foo/bar', 0, map(<String>['foo', 'bar']),
        DocumentState.localMutations));

    await _acknowledgeMutation(1);

    _expectChanged(<Document>[
      doc('foo/bar', 1, map(<String>['foo', 'bar']),
          DocumentState.committedMutations)
    ]);
    await _expectContains(doc('foo/bar', 1, map(<String>['foo', 'bar']),
        DocumentState.committedMutations));

    await _releaseQuery(query);

    // It has been acknowledged, and should no longer be retained as there is no target and mutation
    if (_garbageCollectorIsEager) {
      await _expectNotContains('foo/bar');
    } else {
      await _expectContains(doc('foo/bar', 1, map(<String>['foo', 'bar']),
          DocumentState.committedMutations));
    }
  }

  @testMethod
  Future<void> testHandlesAckThenRejectThenRemoteEvent() async {
    // Start a query that requires acks to be held.
    final Query query = Query(ResourcePath.fromSegments(<String>['foo']));
    final int targetId = await _allocateQuery(query);

    await _writeMutation(setMutation('foo/bar', map(<String>['foo', 'bar'])));
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']),
          DocumentState.localMutations)
    ]);
    await _expectContains(doc('foo/bar', 0, map(<String>['foo', 'bar']),
        DocumentState.localMutations));

    // The last seen version is zero, so this ack must be held.
    await _acknowledgeMutation(1);
    if (_garbageCollectorIsEager) {
      // Nothing is pinning this anymore, as it has been acknowledged and there are no targets active.
      await _expectNotContains('foo/bar');
    } else {
      await _expectContains(doc('foo/bar', 1, map(<String>['foo', 'bar']),
          DocumentState.committedMutations));
    }

    await _writeMutation(setMutation('bar/baz', map(<String>['bar', 'baz'])));
    _expectChanged(<Document>[
      doc('bar/baz', 0, map(<String>['bar', 'baz']),
          DocumentState.localMutations)
    ]);
    await _expectContains(doc('bar/baz', 0, map(<String>['bar', 'baz']),
        DocumentState.localMutations));

    await _rejectMutation();
    _expectRemoved(<String>['bar/baz']);
    await _expectNotContains('bar/baz');

    await _applyRemoteEvent(addedRemoteEvent(
        doc('foo/bar', 2, map(<String>['it', 'changed'])),
        <int>[targetId],
        <int>[]));
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
    await _applyRemoteEvent(
        updateRemoteEvent(deletedDoc('foo/bar', 2), <int>[targetId], <int>[]));
    _expectRemoved(<String>['foo/bar']);
    // Under eager GC, there is no longer a reference for the document, and it should be deleted.
    if (_garbageCollectorIsEager) {
      await _expectNotContains('foo/bar');
    } else {
      await _expectContains(deletedDoc('foo/bar', 2));
    }

    await _writeMutation(setMutation('foo/bar', map(<String>['foo', 'bar'])));
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']),
          DocumentState.localMutations)
    ]);
    await _expectContains(doc('foo/bar', 0, map(<String>['foo', 'bar']),
        DocumentState.localMutations));

    await _releaseQuery(_query);
    await _acknowledgeMutation(3);
    _expectChanged(<Document>[
      doc('foo/bar', 3, map(<String>['foo', 'bar']),
          DocumentState.committedMutations)
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
      doc('foo/bar', 0, map(<String>['foo', 'bar']),
          DocumentState.localMutations)
    ]);

    await _applyRemoteEvent(
        updateRemoteEvent(deletedDoc('foo/bar', 2), <int>[targetId], <int>[]));
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']),
          DocumentState.localMutations)
    ]);
    await _expectContains(doc('foo/bar', 0, map(<String>['foo', 'bar']),
        DocumentState.localMutations));
  }

  @testMethod
  Future<void> testHandlesDocumentThenSetMutationThenAckThenDocument() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    final int targetId = await _allocateQuery(query);
    await _applyRemoteEvent(addedRemoteEvent(
        doc('foo/bar', 2, map(<String>['it', 'base'])),
        <int>[targetId],
        <int>[]));

    _expectChanged(<Document>[
      doc('foo/bar', 2, map(<String>['it', 'base']))
    ]);
    await _expectContains(doc('foo/bar', 2, map(<String>['it', 'base'])));

    await _writeMutation(setMutation('foo/bar', map(<String>['foo', 'bar'])));
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']),
          DocumentState.localMutations)
    ]);
    await _expectContains(doc('foo/bar', 0, map(<String>['foo', 'bar']),
        DocumentState.localMutations));

    await _acknowledgeMutation(3);
    _expectChanged(<Document>[
      doc('foo/bar', 3, map(<String>['foo', 'bar']),
          DocumentState.committedMutations)
    ]);
    await _expectContains(doc('foo/bar', 3, map(<String>['foo', 'bar']),
        DocumentState.committedMutations));

    await _applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 3, map(<String>['it', 'changed'])),
        <int>[targetId],
        <int>[]));
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
        doc('foo/bar', 1, map(<String>['it', 'base']),
            DocumentState.localMutations),
        <int>[targetId],
        <int>[]));
    _expectChanged(<MaybeDocument>[
      doc('foo/bar', 0, map(<String>['foo', 'bar', 'it', 'base']),
          DocumentState.localMutations)
    ]);
    await _expectContains(doc(
        'foo/bar',
        0,
        map(<String>['foo', 'bar', 'it', 'base']),
        DocumentState.localMutations));

    await _acknowledgeMutation(2);

    _expectChanged(<Document>[
      doc('foo/bar', 2, map(<String>['foo', 'bar', 'it', 'base']),
          DocumentState.committedMutations)
    ]);
    await _expectContains(doc(
        'foo/bar',
        2,
        map(<String>['foo', 'bar', 'it', 'base']),
        DocumentState.committedMutations));

    await _applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 2, map(<String>['foo', 'bar', 'it', 'base'])),
        <int>[targetId],
        <int>[]));
    _expectChanged(<Document>[
      doc('foo/bar', 2, map(<String>['foo', 'bar', 'it', 'base']))
    ]);
    await _expectContains(
        doc('foo/bar', 2, map(<String>['foo', 'bar', 'it', 'base'])));
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
    await _applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 1, map(<String>['it', 'base'])),
        <int>[targetId],
        <int>[]));
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
      await _expectContains(
          deletedDoc('foo/bar', 1, hasCommittedMutations: true));
    }
  }

  @testMethod
  Future<void> testHandlesDocumentThenDeleteMutationThenAck() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    final int targetId = await _allocateQuery(query);
    await _applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 1, map(<String>['it', 'base'])),
        <int>[targetId],
        <int>[]));
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
      await _expectContains(
          deletedDoc('foo/bar', 2, hasCommittedMutations: true));
    }
  }

  @testMethod
  Future<void> testHandlesDeleteMutationThenDocumentThenAck() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    final int targetId = await _allocateQuery(query);
    await _writeMutation(deleteMutation('foo/bar'));
    _expectRemoved(<String>['foo/bar']);
    await _expectContains(deletedDoc('foo/bar', 0));

    await _applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 1, map(<String>['it', 'base'])),
        <int>[targetId],
        <int>[]));
    _expectRemoved(<String>['foo/bar']);
    await _expectContains(deletedDoc('foo/bar', 0));

    await _releaseQuery(query);
    await _acknowledgeMutation(2);
    _expectRemoved(<String>['foo/bar']);
    if (_garbageCollectorIsEager) {
      // The doc is not pinned in a target and we've acknowledged the mutation. It shouldn't exist anymore.
      await _expectNotContains('foo/bar');
    } else {
      await _expectContains(
          deletedDoc('foo/bar', 2, hasCommittedMutations: true));
    }
  }

  @testMethod
  Future<void> testHandlesDocumentThenDeletedDocumentThenDocument() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    final int targetId = await _allocateQuery(query);
    await _applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 1, map(<String>['it', 'base'])),
        <int>[targetId],
        <int>[]));
    _expectChanged(<Document>[
      doc('foo/bar', 1, map(<String>['it', 'base']))
    ]);
    await _expectContains(doc('foo/bar', 1, map(<String>['it', 'base'])));

    await _applyRemoteEvent(
        updateRemoteEvent(deletedDoc('foo/bar', 2), <int>[targetId], <int>[]));
    _expectRemoved(<String>['foo/bar']);
    if (!_garbageCollectorIsEager) {
      await _expectContains(deletedDoc('foo/bar', 2));
    }

    await _applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 3, map(<String>['it', 'changed'])),
        <int>[targetId],
        <int>[]));
    _expectChanged(<Document>[
      doc('foo/bar', 3, map(<String>['it', 'changed']))
    ]);
    await _expectContains(doc('foo/bar', 3, map(<String>['it', 'changed'])));
  }

  @testMethod
  Future<void>
      testHandlesSetMutationThenPatchMutationThenDocumentThenAckThenAck() async {
    await _writeMutation(setMutation('foo/bar', map(<String>['foo', 'old'])));
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'old']),
          DocumentState.localMutations)
    ]);
    await _expectContains(doc('foo/bar', 0, map(<String>['foo', 'old']),
        DocumentState.localMutations));

    await _writeMutation(patchMutation('foo/bar', map(<String>['foo', 'bar'])));
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']),
          DocumentState.localMutations)
    ]);
    await _expectContains(doc('foo/bar', 0, map(<String>['foo', 'bar']),
        DocumentState.localMutations));

    final Query query = Query(ResourcePath.fromString('foo'));

    final int targetId = await _allocateQuery(query);
    await _applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 1, map(<String>['it', 'base']),
            DocumentState.localMutations),
        <int>[targetId],
        <int>[]));
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']),
          DocumentState.localMutations)
    ]);
    await _expectContains(doc('foo/bar', 0, map(<String>['foo', 'bar']),
        DocumentState.localMutations));

    await _releaseQuery(query);
    await _acknowledgeMutation(2); // delete mutation
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']),
          DocumentState.localMutations)
    ]);
    await _expectContains(doc('foo/bar', 0, map(<String>['foo', 'bar']),
        DocumentState.localMutations));

    await _acknowledgeMutation(3); // patch mutation
    _expectChanged(<Document>[
      doc('foo/bar', 3, map(<String>['foo', 'bar']),
          DocumentState.committedMutations)
    ]);

    if (_garbageCollectorIsEager) {
      // we've ack'd all of the mutations, nothing is keeping this pinned anymore
      await _expectNotContains('foo/bar');
    } else {
      await _expectContains(doc('foo/bar', 3, map(<String>['foo', 'bar']),
          DocumentState.committedMutations));
    }
  }

  @testMethod
  Future<void> testHandlesSetMutationAndPatchMutationTogether() async {
    await _writeMutations(<Mutation>[
      setMutation('foo/bar', map(<String>['foo', 'old'])),
      patchMutation('foo/bar', map(<String>['foo', 'bar']))
    ]);

    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']),
          DocumentState.localMutations)
    ]);
    await _expectContains(doc('foo/bar', 0, map(<String>['foo', 'bar']),
        DocumentState.localMutations));
  }

  @testMethod
  Future<void> testHandlesSetMutationThenPatchMutationThenReject() async {
    if (!_garbageCollectorIsEager) {
      return;
    }

    await _writeMutation(setMutation('foo/bar', map(<String>['foo', 'old'])));
    await _expectContains(doc('foo/bar', 0, map(<String>['foo', 'old']),
        DocumentState.localMutations));
    await _acknowledgeMutation(1);
    await _expectNotContains('foo/bar');

    await _writeMutation(patchMutation('foo/bar', map(<String>['foo', 'bar'])));
    // A blind patch is not visible in the cache
    await _expectNotContains('foo/bar');

    await _rejectMutation();
    await _expectNotContains('foo/bar');
  }

  @testMethod
  Future<void>
      testHandlesSetMutationsAndPatchMutationOfJustOneTogether() async {
    await _writeMutations(<Mutation>[
      setMutation('foo/bar', map(<String>['foo', 'old'])),
      setMutation('bar/baz', map(<String>['bar', 'baz'])),
      patchMutation('foo/bar', map(<String>['foo', 'bar']))
    ]);

    _expectChanged(<Document>[
      doc('bar/baz', 0, map(<String>['bar', 'baz']),
          DocumentState.localMutations),
      doc('foo/bar', 0, map(<String>['foo', 'bar']),
          DocumentState.localMutations)
    ]);

    await _expectContains(doc('foo/bar', 0, map(<String>['foo', 'bar']),
        DocumentState.localMutations));
    await _expectContains(doc('bar/baz', 0, map(<String>['bar', 'baz']),
        DocumentState.localMutations));
  }

  @testMethod
  Future<void>
      testHandlesDeleteMutationThenPatchMutationThenAckThenAck() async {
    await _writeMutation(deleteMutation('foo/bar'));
    _expectRemoved(<String>['foo/bar']);
    await _expectContains(deletedDoc('foo/bar', 0));

    await _writeMutation(patchMutation('foo/bar', map(<String>['foo', 'bar'])));
    _expectRemoved(<String>['foo/bar']);
    await _expectContains(deletedDoc('foo/bar', 0));

    await _acknowledgeMutation(2); // delete mutation
    _expectRemoved(<String>['foo/bar']);
    // The overlay of the pending patch (largest batch 3) still holds the delete (as upstream with overlays).
    await _expectContains(deletedDoc('foo/bar', 0));

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
    await _applyRemoteEvent(updateRemoteEvent(
        deletedDoc('foo/bar', 2), <int>[], <int>[], <int>[targetId]));
    await _expectNotContains('foo/bar');

    await _applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 2, map(<String>['foo', 'bar'])),
        <int>[],
        <int>[],
        <int>[targetId]));
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
    await _applyRemoteEvent(addedRemoteEvent(
        doc('foo/bar', 2, map(<String>['foo', 'bar'])), two, none));
    await _expectContains(doc('foo/bar', 2, map(<String>['foo', 'bar'])));

    await _applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 2, map(<String>['foo', 'baz'])), none, two));

    await _expectNotContains('foo/bar');
  }

  @testMethod
  Future<void> testCollectsGarbageAfterAcknowledgedMutation() async {
    if (!_garbageCollectorIsEager) {
      return;
    }

    final Query query = Query(ResourcePath.fromString('foo'));
    final int targetId = await _allocateQuery(query);
    await _applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 1, map(<String>['foo', 'old'])),
        <int>[targetId],
        <int>[]));
    await _writeMutation(patchMutation('foo/bar', map(<String>['foo', 'bar'])));
    await _releaseQuery(query);
    await _writeMutation(setMutation('foo/bah', map(<String>['foo', 'bah'])));
    await _writeMutation(deleteMutation('foo/baz'));
    await _expectContains(doc('foo/bar', 0, map(<String>['foo', 'bar']),
        DocumentState.localMutations));
    await _expectContains(doc('foo/bah', 0, map(<String>['foo', 'bah']),
        DocumentState.localMutations));
    await _expectContains(deletedDoc('foo/baz', 0));

    await _acknowledgeMutation(3);
    await _expectNotContains('foo/bar');
    await _expectContains(doc('foo/bah', 0, map(<String>['foo', 'bah']),
        DocumentState.localMutations));
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
    await _applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 1, map(<String>['foo', 'old'])),
        <int>[targetId],
        <int>[]));
    await _writeMutation(patchMutation('foo/bar', map(<String>['foo', 'bar'])));
    // Release the query so that our target count goes back to 0 and we are considered up-to-date.
    await _releaseQuery(query);
    await _writeMutation(setMutation('foo/bah', map(<String>['foo', 'bah'])));
    await _writeMutation(deleteMutation('foo/baz'));
    await _expectContains(doc('foo/bar', 0, map(<String>['foo', 'bar']),
        DocumentState.localMutations));
    await _expectContains(doc('foo/bah', 0, map(<String>['foo', 'bah']),
        DocumentState.localMutations));
    await _expectContains(deletedDoc('foo/baz', 0));

    await _rejectMutation(); // patch mutation
    await _expectNotContains('foo/bar');
    await _expectContains(doc('foo/bah', 0, map(<String>['foo', 'bah']),
        DocumentState.localMutations));
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
    await _applyRemoteEvent(addedRemoteEvent(
        doc('foo/bar', 1, map(<String>['foo', 'bar'])), two, none));
    await _writeMutation(setMutation('foo/baz', map(<String>['foo', 'baz'])));
    await _expectContains(doc('foo/bar', 1, map(<String>['foo', 'bar'])));
    await _expectContains(doc('foo/baz', 0, map(<String>['foo', 'baz']),
        DocumentState.localMutations));

    await _notifyLocalViewChanges(viewChanges(
        2, /* fromCache= */ false, <String>['foo/bar', 'foo/baz'], <String>[]));
    await _applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 1, map(<String>['foo', 'bar'])), none, two));
    await _applyRemoteEvent(updateRemoteEvent(
        doc('foo/baz', 2, map(<String>['foo', 'baz'])), two, none));
    await _acknowledgeMutation(2);
    await _expectContains(doc('foo/bar', 1, map(<String>['foo', 'bar'])));
    await _expectContains(doc('foo/baz', 2, map(<String>['foo', 'baz'])));

    await _notifyLocalViewChanges(viewChanges(
        2, /* fromCache= */ false, <String>[], <String>['foo/bar', 'foo/baz']));
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
    await _applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 1, map()), <int>[], <int>[], <int>[targetID]));

    await _expectNotContains('foo/bar');
  }

  @testMethod
  Future<void> testCanExecuteDocumentQueries() async {
    await _localStore.writeLocally(<Mutation>[
      setMutation('foo/bar', map(<String>['foo', 'bar'])),
      setMutation('foo/baz', map(<String>['foo', 'baz'])),
      setMutation('foo/bar/Foo/Bar', map(<String>['Foo', 'Bar']))
    ]);

    final Query query =
        Query(ResourcePath.fromSegments(<String>['foo', 'bar']));
    final ImmutableSortedMap<DocumentKey, Document> docs =
        (await _localStore.executeQuery(query, /* usePreviousResults= */ true))
            .documents;
    expect(values(docs), <Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']),
          DocumentState.localMutations)
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
    final ImmutableSortedMap<DocumentKey, Document> docs =
        (await _localStore.executeQuery(query, /* usePreviousResults= */ true))
            .documents;

    expect(values(docs), <Document>[
      doc('foo/bar', 0, map(<String>['foo', 'bar']),
          DocumentState.localMutations),
      doc('foo/baz', 0, map(<String>['foo', 'baz']),
          DocumentState.localMutations)
    ]);
  }

  @testMethod
  Future<void> testCanExecuteMixedCollectionQueries() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    await _allocateQuery(query);
    _expectTargetId(2);

    await _applyRemoteEvent(updateRemoteEvent(
        doc('foo/baz', 10, map(<String>['a', 'b'])), <int>[2], <int>[]));
    await _applyRemoteEvent(updateRemoteEvent(
        doc('foo/bar', 20, map(<String>['a', 'b'])), <int>[2], <int>[]));
    await _writeMutation(setMutation('foo/bonk', map(<String>['a', 'b'])));

    final ImmutableSortedMap<DocumentKey, Document> docs =
        (await _localStore.executeQuery(query, /* usePreviousResults= */ true))
            .documents;

    expect(values(docs), <Document>[
      doc('foo/bar', 20, map(<String>['a', 'b'])),
      doc('foo/baz', 10, map(<String>['a', 'b'])),
      doc('foo/bonk', 0, map(<String>['a', 'b']), DocumentState.localMutations)
    ]);
  }

  @testMethod
  Future<void> testReadsAllDocumentsForCollectionQueries() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    await _allocateQuery(query);

    await _applyRemoteEvent(
        updateRemoteEvent(doc('foo/baz', 10, map()), <int>[2], <int>[]));
    await _applyRemoteEvent(
        updateRemoteEvent(doc('foo/bar', 20, map()), <int>[2], <int>[]));
    await _writeMutation(setMutation('foo/bonk', map()));

    _resetPersistenceStats();

    await _localStore.executeQuery(query, /* usePreviousResults= */ true);

    _expectRemoteDocumentsRead(2);
    // With overlays, the mutation queue is not read for queries (upstream assertOverlaysRead).
    _expectMutationsRead(0);
    _expectOverlaysReadByEngine(byKey: 0, byCollection: 1);
  }

  @testMethod
  Future<void> testPersistsResumeTokens() async {
    // This test only works in the absence of the EagerGarbageCollector.
    if (_garbageCollectorIsEager) {
      return;
    }

    final Query _query = query('foo/bar');
    final int targetId = await _allocateQuery(_query);
    final Uint8List _resumeToken = resumeToken(1000)!;

    final QueryData _queryData =
        queryData(targetId, QueryPurpose.listen, 'foo/bar');
    final t.TestTargetMetadataProvider testTargetMetadataProvider = t
        .testTargetMetadataProvider
      ..setSyncedKeys(_queryData, DocumentKey.emptyKeySet);

    final WatchChangeAggregator aggregator =
        WatchChangeAggregator(testTargetMetadataProvider);

    final WatchChangeWatchTargetChange watchChange =
        WatchChangeWatchTargetChange(
            WatchTargetChangeType.current, <int>[targetId], _resumeToken);
    aggregator.handleTargetChange(watchChange);
    final RemoteEvent remoteEvent = aggregator.createRemoteEvent(version(1000));
    await _applyRemoteEvent(remoteEvent);

    // Stop listening so that the query should become inactive (but persistent)
    await _releaseQuery(_query);

    // Should come back with the same resume token
    final QueryData queryData2 = await _localStore.allocateTarget(_query.toTarget());
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
    final Uint8List _resumeToken = resumeToken(1000)!;

    final QueryData _queryData =
        queryData(targetId, QueryPurpose.listen, 'foo/bar');
    final t.TestTargetMetadataProvider testTargetMetadataProvider = t
        .testTargetMetadataProvider
      ..setSyncedKeys(_queryData, DocumentKey.emptyKeySet);

    final WatchChangeAggregator aggregator1 =
        WatchChangeAggregator(testTargetMetadataProvider);

    final WatchChangeWatchTargetChange watchChange1 =
        WatchChangeWatchTargetChange(
            WatchTargetChangeType.current, <int>[targetId], _resumeToken);
    aggregator1.handleTargetChange(watchChange1);
    final RemoteEvent remoteEvent1 =
        aggregator1.createRemoteEvent(version(1000));
    await _applyRemoteEvent(remoteEvent1);

    // New message with empty resume token should not replace the old resume token
    final WatchChangeAggregator aggregator2 =
        WatchChangeAggregator(testTargetMetadataProvider);
    final WatchChangeWatchTargetChange watchChange2 =
        WatchChangeWatchTargetChange(
            WatchTargetChangeType.current, <int>[targetId], Uint8List(0));
    aggregator2.handleTargetChange(watchChange2);
    final RemoteEvent remoteEvent2 =
        aggregator2.createRemoteEvent(version(2000));
    await _applyRemoteEvent(remoteEvent2);

    // Stop listening so that the query should become inactive (but persistent)
    await _releaseQuery(_query);

    // Should come back with the same resume token
    final QueryData queryData2 = await _localStore.allocateTarget(_query.toTarget());
    expect(queryData2.resumeToken, _resumeToken);
  }

  @testMethod
  Future<void> testRemoteDocumentKeysForTarget() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    await _allocateQuery(query);
    _expectTargetId(2);

    await _applyRemoteEvent(addedRemoteEvent(
        doc('foo/baz', 10, map(<String>['a', 'b'])), <int>[2], <int>[]));
    await _applyRemoteEvent(addedRemoteEvent(
        doc('foo/bar', 20, map(<String>['a', 'b'])), <int>[2], <int>[]));
    await _writeMutation(setMutation('foo/bonk', map(<String>['a', 'b'])));

    ImmutableSortedSet<DocumentKey> keys =
        await _localStore.getRemoteDocumentKeys(2);
    expect(keys, <DocumentKey>[key('foo/bar'), key('foo/baz')]);

    keys = await _localStore.getRemoteDocumentKeys(2);
    expect(keys, <DocumentKey>[key('foo/bar'), key('foo/baz')]);
  }

  // TODO(mrschmidt): The FieldValue.increment() field transform tests below
  //  would probably be better implemented as spec tests but currently they
  //  don't support transforms.
  @testMethod
  Future<void>
      testHandlesSetMutationThenTransformMutationThenTransformMutation() async {
    await _writeMutation(setMutation('foo/bar', map(<dynamic>['sum', 0])));
    await _expectContains(doc(
        'foo/bar', 0, map(<dynamic>['sum', 0]), DocumentState.localMutations));

    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<dynamic>['sum', 0]), DocumentState.localMutations)
    ]);

    await _writeMutation(transformMutation(
        'foo/bar', map(<dynamic>['sum', FieldValue.increment(1)])));
    await _expectContains(doc(
        'foo/bar', 0, map(<dynamic>['sum', 1]), DocumentState.localMutations));
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<dynamic>['sum', 1]), DocumentState.localMutations)
    ]);

    await _writeMutation(transformMutation(
        'foo/bar', map(<dynamic>['sum', FieldValue.increment(2)])));
    await _expectContains(doc(
        'foo/bar', 0, map(<dynamic>['sum', 3]), DocumentState.localMutations));
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<dynamic>['sum', 3]), DocumentState.localMutations)
    ]);
  }

  @testMethod
  Future<void> testHandlesSetMutationWithFoldedTransformThenAck() async {
    if (_garbageCollectorIsEager) {
      return;
    }

    // A single set mutation that carries its transform (as produced by the
    // user data converter); it goes through the mutation queue serializer.
    final Mutation set = SetMutation(
        key('foo/bar'),
        wrapMap(map(<dynamic>['x', 1])),
        Precondition.none,
        transformMutation(
                'foo/bar', map(<dynamic>['sum', FieldValue.increment(2)]))
            .fieldTransforms);
    await _writeMutation(set);
    await _expectContains(doc('foo/bar', 0, map(<dynamic>['x', 1, 'sum', 2]),
        DocumentState.localMutations));

    await _acknowledgeMutation(1, 2);
    await _expectContains(doc('foo/bar', 1, map(<dynamic>['x', 1, 'sum', 2]),
        DocumentState.committedMutations));
  }

  @testMethod
  Future<void>
      testHandlesSetMutationThenAckThenTransformMutationThenAckThenTransformMutation() async {
    if (_garbageCollectorIsEager) {
      // Since this test doesn't start a listen, Eager GC removes the documents from the cache as
      // soon as the mutation is applied. This creates a lot of special casing in this unit test but
      // does not expand its test coverage.
      return;
    }

    await _writeMutation(setMutation('foo/bar', map(<dynamic>['sum', 0])));
    await _expectContains(doc(
        'foo/bar', 0, map(<dynamic>['sum', 0]), DocumentState.localMutations));
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<dynamic>['sum', 0]), DocumentState.localMutations)
    ]);

    await _acknowledgeMutation(1);
    _expectChanged(<Document>[
      doc('foo/bar', 1, map(<dynamic>['sum', 0]),
          DocumentState.committedMutations)
    ]);
    await _expectContains(doc('foo/bar', 1, map(<dynamic>['sum', 0]),
        DocumentState.committedMutations));

    await _writeMutation(transformMutation(
        'foo/bar', map(<dynamic>['sum', FieldValue.increment(1)])));
    await _expectContains(doc(
        'foo/bar', 0, map(<dynamic>['sum', 1]), DocumentState.localMutations));
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<dynamic>['sum', 1]), DocumentState.localMutations)
    ]);

    await _acknowledgeMutation(2, 1);
    _expectChanged(<Document>[
      doc('foo/bar', 2, map(<dynamic>['sum', 1]),
          DocumentState.committedMutations)
    ]);
    await _expectContains(doc('foo/bar', 2, map(<dynamic>['sum', 1]),
        DocumentState.committedMutations));

    await _writeMutation(transformMutation(
        'foo/bar', map(<dynamic>['sum', FieldValue.increment(2)])));
    await _expectContains(doc(
        'foo/bar', 0, map(<dynamic>['sum', 3]), DocumentState.localMutations));
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<dynamic>['sum', 3]), DocumentState.localMutations)
    ]);
  }

  @testMethod
  Future<void>
      testHandlesSetMutationThenTransformMutationThenRemoteEventThenTransformMutation() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    await _allocateQuery(query);
    _expectTargetId(2);

    await _writeMutation(setMutation('foo/bar', map(<dynamic>['sum', 0])));
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<dynamic>['sum', 0]), DocumentState.localMutations)
    ]);
    await _expectContains(doc(
        'foo/bar', 0, map(<dynamic>['sum', 0]), DocumentState.localMutations));

    await _applyRemoteEvent(addedRemoteEvent(
        doc('foo/bar', 1, map(<dynamic>['sum', 0])), <int>[2], <int>[]));
    await _acknowledgeMutation(1);
    _expectChanged(<Document>[
      doc('foo/bar', 1, map(<dynamic>['sum', 0]), DocumentState.synced)
    ]);
    await _expectContains(
        doc('foo/bar', 1, map(<dynamic>['sum', 0]), DocumentState.synced));

    await _writeMutation(transformMutation(
        'foo/bar', map(<dynamic>['sum', FieldValue.increment(1)])));
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<dynamic>['sum', 1]), DocumentState.localMutations)
    ]);
    await _expectContains(doc(
        'foo/bar', 0, map(<dynamic>['sum', 1]), DocumentState.localMutations));

    // The value in this remote event gets ignored since we still have a pending transform mutation.
    await _applyRemoteEvent(addedRemoteEvent(
        doc('foo/bar', 2, map(<dynamic>['sum', 1337])), <int>[2], <int>[]));
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<dynamic>['sum', 1]), DocumentState.localMutations)
    ]);
    await _expectContains(doc(
        'foo/bar', 0, map(<dynamic>['sum', 1]), DocumentState.localMutations));

    // Add another increment. Note that we still compute the increment based on the local value.
    await _writeMutation(transformMutation(
        'foo/bar', map(<dynamic>['sum', FieldValue.increment(2)])));
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<dynamic>['sum', 3]), DocumentState.localMutations)
    ]);
    await _expectContains(doc(
        'foo/bar', 0, map(<dynamic>['sum', 3]), DocumentState.localMutations));

    await _acknowledgeMutation(3, 1);
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<dynamic>['sum', 3]), DocumentState.localMutations)
    ]);
    await _expectContains(doc(
        'foo/bar', 0, map(<dynamic>['sum', 3]), DocumentState.localMutations));

    await _acknowledgeMutation(4, 1339);
    _expectChanged(<Document>[
      doc('foo/bar', 4, map(<dynamic>['sum', 1339]),
          DocumentState.committedMutations)
    ]);
    await _expectContains(doc('foo/bar', 4, map(<dynamic>['sum', 1339]),
        DocumentState.committedMutations));
  }

  @testMethod
  Future<void> testHoldsBackOnlyNonIdempotentTransforms() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    await _allocateQuery(query);
    _expectTargetId(2);

    await _writeMutation(setMutation(
        'foo/bar', map(<dynamic>['sum', 0, 'array_union', <dynamic>[]])));
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<dynamic>['sum', 0, 'array_union', <dynamic>[]]),
          DocumentState.localMutations)
    ]);

    await _acknowledgeMutation(1);
    _expectChanged(<Document>[
      doc('foo/bar', 1, map(<dynamic>['sum', 0, 'array_union', <dynamic>[]]),
          DocumentState.committedMutations)
    ]);

    await _applyRemoteEvent(addedRemoteEvent(
        doc('foo/bar', 1, map(<dynamic>['sum', 0, 'array_union', <dynamic>[]])),
        <int>[2],
        <int>[]));
    _expectChanged(<Document>[
      doc('foo/bar', 1, map(<dynamic>['sum', 0, 'array_union', <dynamic>[]]),
          DocumentState.synced)
    ]);

    await _writeMutations(<Mutation>[
      transformMutation(
          'foo/bar', map(<dynamic>['sum', FieldValue.increment(1)])),
      transformMutation(
          'foo/bar',
          map(<dynamic>[
            'array_union',
            FieldValue.arrayUnion(<String>['foo'])
          ]))
    ]);
    _expectChanged(<Document>[
      doc(
          'foo/bar',
          0,
          map(<dynamic>[
            'sum',
            1,
            'array_union',
            <String>['foo']
          ]),
          DocumentState.localMutations)
    ]);

    // The sum transform and array union transform make the SDK ignore the backend's updated value: both are part of
    // the overlay (upstream testHoldsBackTransforms; before overlays the array union was recomputed on the backend
    // value).
    await _applyRemoteEvent(addedRemoteEvent(
        doc(
            'foo/bar',
            2,
            map(<dynamic>[
              'sum',
              1337,
              'array_union',
              <String>['bar']
            ])),
        <int>[2],
        <int>[]));
    _expectChanged(<Document>[
      doc(
          'foo/bar',
          0,
          map(<dynamic>[
            'sum',
            1,
            'array_union',
            <String>['foo']
          ]),
          DocumentState.localMutations)
    ]);
  }

  @testMethod
  Future<void> testHandlesMergeMutationWithTransformThenRemoteEvent() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    await _allocateQuery(query);
    _expectTargetId(2);

    await _writeMutations(<Mutation>[
      patchMutation('foo/bar', map(), <FieldPath>[]),
      transformMutation(
          'foo/bar', map(<dynamic>['sum', FieldValue.increment(1)]))
    ]);
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<dynamic>['sum', 1]), DocumentState.localMutations)
    ]);
    await _expectContains(doc(
        'foo/bar', 0, map(<dynamic>['sum', 1]), DocumentState.localMutations));

    await _applyRemoteEvent(addedRemoteEvent(
        doc('foo/bar', 1, map(<dynamic>['sum', 1337])), <int>[2], <int>[]));
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<dynamic>['sum', 1]), DocumentState.localMutations)
    ]);
    await _expectContains(doc(
        'foo/bar', 0, map(<dynamic>['sum', 1]), DocumentState.localMutations));
  }

  @testMethod
  Future<void> testHandlesPatchMutationWithTransformThenRemoteEvent() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    await _allocateQuery(query);
    _expectTargetId(2);

    await _writeMutations(<Mutation>[
      patchMutation('foo/bar', map()),
      transformMutation(
          'foo/bar', map(<dynamic>['sum', FieldValue.increment(1)]))
    ]);
    _expectChanged(<NoDocument>[deletedDoc('foo/bar', 0)]);
    await _expectNotContains('foo/bar');

    // Note: This test reflects the current behavior, but it may be preferable to replay the
    // mutation once we receive the first value from the remote event.

    await _applyRemoteEvent(addedRemoteEvent(
        doc('foo/bar', 1, map(<dynamic>['sum', 1337])), <int>[2], <int>[]));
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<dynamic>['sum', 1]), DocumentState.localMutations)
    ]);
    await _expectContains(doc(
        'foo/bar', 0, map(<dynamic>['sum', 1]), DocumentState.localMutations));
  }

  Future<void> _writeMutation(Mutation mutation) async {
    await _writeMutations(<Mutation>[mutation]);
  }

  Future<void> _writeMutations(List<Mutation> mutations) async {
    final LocalWriteResult result = await _localStore.writeLocally(mutations);
    _batches.add(MutationBatch(
      batchId: result.batchId,
      localWriteTime: Timestamp.now(),
      baseMutations: <Mutation>[],
      mutations: mutations,
    ));
    _lastChanges = result.changes;
  }

  Future<void> _applyRemoteEvent(RemoteEvent event) async {
    _lastChanges = await _localStore.applyRemoteEvent(event);
  }

  Future<void> _notifyLocalViewChanges(LocalViewChanges changes) async {
    await _localStore.notifyLocalViewChanges(<LocalViewChanges>[changes]);
  }

  Future<void> _acknowledgeMutation(int documentVersion,
      [Object? transformResult]) async {
    final MutationBatch batch = _batches.removeAt(0);
    final SnapshotVersion _version = version(documentVersion);
    final MutationResult mutationResult = MutationResult(
        _version,
        transformResult != null
            ? <model.FieldValue>[wrap(transformResult)]
            : <model.FieldValue>[]);
    final MutationBatchResult result = MutationBatchResult.create(
        batch, _version, <MutationResult>[mutationResult], Uint8List(0));
    _lastChanges = await _localStore.acknowledgeBatch(result);
  }

  Future<void> _rejectMutation() async {
    final MutationBatch batch = _batches.removeAt(0);
    _lastChanges = await _localStore.rejectBatch(batch.batchId);
  }

  @testMethod
  Future<void> testAllocatesTheSameTargetForMirrorQueries() async {
    // A limit query and a limitToLast query with the flipped ordering are sent
    // to the backend (and stored) as one and the same target.
    final Query limit = query('foo').orderBy(orderBy('sort')).limit(2);
    final Query limitToLast =
        query('foo').orderBy(orderBy('sort', 'desc')).limitToLast(2);

    final QueryData first = await _localStore.allocateTarget(limit.toTarget());
    final QueryData second =
        await _localStore.allocateTarget(limitToLast.toTarget());
    expect(second.targetId, first.targetId);
    expect(second.target, first.target);

    // The cache is keyed by target, so both queries find the same entry.
    final QueryData? byLimit =
        await _persistence.queryCache.getQueryData(limit.toTarget());
    final QueryData? byLimitToLast =
        await _persistence.queryCache.getQueryData(limitToLast.toTarget());
    expect(byLimit, isNotNull);
    expect(byLimit!.targetId, first.targetId);
    expect(byLimitToLast!.targetId, first.targetId);

    // A limitToLast query with the same ordering as the limit query is a
    // different target.
    final Query other =
        query('foo').orderBy(orderBy('sort')).limitToLast(2);
    final QueryData third = await _localStore.allocateTarget(other.toTarget());
    expect(third.targetId, isNot(first.targetId));
  }

  @testMethod
  Future<void> testExecutesLimitToLastQueryInTheQueryOrder() async {
    // The local store does not apply limits: it returns every matching
    // document, the view cuts the result.
    await _writeMutation(setMutation('foo/a', map(<dynamic>['sort', 1])));
    await _writeMutation(setMutation('foo/b', map(<dynamic>['sort', 2])));
    await _writeMutation(setMutation('foo/c', map(<dynamic>['sort', 3])));

    final Query q = query('foo').orderBy(orderBy('sort')).limitToLast(2);
    await _allocateQuery(q);
    final ImmutableSortedMap<DocumentKey, Document> docs =
        (await _localStore.executeQuery(q, /* usePreviousResults= */ true))
            .documents;
    expect(docs.length, 3);
  }

  @testMethod
  Future<void> testReadsAllDocumentsForInitialCollectionQueries() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    await _allocateQuery(query);

    await _applyRemoteEvent(
        updateRemoteEvent(doc('foo/baz', 10, map()), <int>[2], <int>[]));
    await _applyRemoteEvent(
        updateRemoteEvent(doc('foo/bar', 20, map()), <int>[2], <int>[]));
    await _writeMutation(setMutation('foo/bonk', map()));

    _resetPersistenceStats();

    await _localStore.executeQuery(query, /* usePreviousResults= */ true);

    _expectRemoteDocumentsReadByEngine(byKey: 0, byQuery: 2);
    _expectMutationsReadByEngine(byKey: 0, byQuery: 0);
    _expectOverlaysReadByEngine(byKey: 0, byCollection: 1);
  }

  @testMethod
  Future<void> testUsesTargetMappingToExecuteQueries() async {
    if (_garbageCollectorIsEager) {
      return;
    }

    // This test verifies that once a target mapping has been written, only documents that match the query are read
    // from the RemoteDocumentCache.
    final Query query = Query(ResourcePath.fromString('foo'))
        .filter(filter('matches', '==', true));
    final int targetId = await _allocateQuery(query);

    await _writeMutation(setMutation('foo/a', map(<dynamic>['matches', true])));
    await _writeMutation(setMutation('foo/b', map(<dynamic>['matches', true])));
    await _writeMutation(
        setMutation('foo/ignored', map(<dynamic>['matches', false])));
    await _acknowledgeMutation(10);
    await _acknowledgeMutation(10);
    await _acknowledgeMutation(10);

    // Execute the query, but note that we read all existing documents from the RemoteDocumentCache since we do not
    // yet have target mapping.
    await _executeQuery(query);
    _expectRemoteDocumentsReadByEngine(byKey: 0, byQuery: 2);

    // Issue a RemoteEvent to persist the target mapping.
    await _applyRemoteEvent(_addedRemoteEvents(<MaybeDocument>[
      doc('foo/a', 10, map(<dynamic>['matches', true])),
      doc('foo/b', 10, map(<dynamic>['matches', true])),
    ], <int>[
      targetId
    ]));
    await _applyRemoteEvent(_noChangeEvent(targetId, 10));
    await _updateViews(targetId, fromCache: false);

    // Execute the query again, this time verifying that we only read the two documents that match the query.
    await _executeQuery(query);
    _expectRemoteDocumentsReadByEngine(byKey: 2, byQuery: 0);
    _expectQueryReturned(<String>['foo/a', 'foo/b']);
  }

  @testMethod
  Future<void> testLastLimboFreeSnapshotIsAdvancedDuringViewProcessing() async {
    // This test verifies that the `lastLimboFreeSnapshot` version for QueryData is advanced when we compute a
    // limbo-free free view and that the mapping is persisted when we release a target.
    final Query query = Query(ResourcePath.fromString('foo'));
    final Target target = query.toTarget();
    final int targetId = await _allocateQuery(query);

    // Advance the target snapshot.
    await _applyRemoteEvent(_noChangeEvent(targetId, 10));

    // At this point, we have not yet confirmed that the target is limbo free.
    QueryData? cachedQueryData = await _localStore.getQueryData(target);
    expect(cachedQueryData!.lastLimboFreeSnapshotVersion, SnapshotVersion.none);

    // Mark the view synced, which updates the last limbo free snapshot version.
    await _updateViews(targetId, fromCache: false);
    cachedQueryData = await _localStore.getQueryData(target);
    expect(cachedQueryData!.lastLimboFreeSnapshotVersion, version(10));

    // The last limbo free snapshot version is persisted even if we release the target.
    await _localStore.releaseTarget(targetId);

    if (!_garbageCollectorIsEager) {
      cachedQueryData = await _localStore.getQueryData(target);
      expect(cachedQueryData!.lastLimboFreeSnapshotVersion, version(10));
    }
  }

  @testMethod
  Future<void> testQueriesIncludeLocallyModifiedDocuments() async {
    if (_garbageCollectorIsEager) {
      return;
    }

    // This test verifies that queries that have a persisted TargetMapping include documents that were modified by
    // local edits after the target mapping was written.
    final Query query = Query(ResourcePath.fromString('foo'))
        .filter(filter('matches', '==', true));
    final int targetId = await _allocateQuery(query);

    await _applyRemoteEvent(_addedRemoteEvents(<MaybeDocument>[
      doc('foo/a', 10, map(<dynamic>['matches', true]))
    ], <int>[
      targetId
    ]));
    await _applyRemoteEvent(_noChangeEvent(targetId, 10));
    await _updateViews(targetId, fromCache: false);

    // Execute the query based on the RemoteEvent.
    await _executeQuery(query);
    _expectQueryReturned(<String>['foo/a']);

    // Write a document.
    await _writeMutation(setMutation('foo/b', map(<dynamic>['matches', true])));

    // Execute the query and make sure that the pending mutation is included in the result.
    await _executeQuery(query);
    _expectQueryReturned(<String>['foo/a', 'foo/b']);

    await _acknowledgeMutation(11);

    // Execute the query and make sure that the acknowledged mutation is included in the result.
    await _executeQuery(query);
    _expectQueryReturned(<String>['foo/a', 'foo/b']);
  }

  @testMethod
  Future<void> testQueriesIncludeDocumentsFromOtherQueries() async {
    if (_garbageCollectorIsEager) {
      return;
    }

    // This test verifies that queries that have a persisted TargetMapping include documents that were modified by
    // other queries after the target mapping was written.
    final Query filteredQuery = Query(ResourcePath.fromString('foo'))
        .filter(filter('matches', '==', true));
    int targetId = await _allocateQuery(filteredQuery);

    await _applyRemoteEvent(_addedRemoteEvents(<MaybeDocument>[
      doc('foo/a', 10, map(<dynamic>['matches', true]))
    ], <int>[
      targetId
    ]));
    await _applyRemoteEvent(_noChangeEvent(targetId, 10));
    await _updateViews(targetId, fromCache: false);
    await _localStore.releaseTarget(targetId);

    // Start another query and add more matching documents to the collection.
    final Query fullQuery = Query(ResourcePath.fromString('foo'));
    targetId = await _allocateQuery(fullQuery);
    await _applyRemoteEvent(_addedRemoteEvents(<MaybeDocument>[
      doc('foo/a', 10, map(<dynamic>['matches', true])),
      doc('foo/b', 20, map(<dynamic>['matches', true])),
    ], <int>[
      targetId
    ]));
    await _localStore.releaseTarget(targetId);

    // Run the original query again and ensure that both the original matches as well as all new matches are included
    // in the result set.
    await _allocateQuery(filteredQuery);
    await _executeQuery(filteredQuery);
    _expectQueryReturned(<String>['foo/a', 'foo/b']);
  }

  @testMethod
  Future<void> testQueriesFilterDocumentsThatNoLongerMatch() async {
    if (_garbageCollectorIsEager) {
      return;
    }

    // This test verifies that documents that once matched a query are post-filtered if they no longer match the query
    // filter.

    // Add two document results for a simple filter query
    final Query filteredQuery = Query(ResourcePath.fromString('foo'))
        .filter(filter('matches', '==', true));
    int targetId = await _allocateQuery(filteredQuery);

    await _applyRemoteEvent(_addedRemoteEvents(<MaybeDocument>[
      doc('foo/a', 10, map(<dynamic>['matches', true])),
      doc('foo/b', 10, map(<dynamic>['matches', true])),
    ], <int>[
      targetId
    ]));
    await _applyRemoteEvent(_noChangeEvent(targetId, 10));
    await _updateViews(targetId, fromCache: false);
    await _localStore.releaseTarget(targetId);

    // Modify one of the documents to no longer match while the filtered query is inactive.
    final Query fullQuery = Query(ResourcePath.fromString('foo'));
    targetId = await _allocateQuery(fullQuery);
    await _applyRemoteEvent(_addedRemoteEvents(<MaybeDocument>[
      doc('foo/a', 10, map(<dynamic>['matches', true])),
      doc('foo/b', 20, map(<dynamic>['matches', false])),
    ], <int>[
      targetId
    ]));
    await _localStore.releaseTarget(targetId);

    // Re-run the filtered query and verify that the modified document is no longer returned.
    await _allocateQuery(filteredQuery);
    await _executeQuery(filteredQuery);
    _expectQueryReturned(<String>['foo/a']);
  }

  @testMethod
  Future<void>
      testQueriesIncludeBundledDocumentsReadAfterTheTargetWasSynced() async {
    if (_garbageCollectorIsEager) {
      return;
    }

    // A bundled document is stored with the read time of the bundle, not its update time: a query that was synced
    // before the bundle was loaded must see it even if the document was last updated before that.
    final Query filteredQuery = Query(ResourcePath.fromString('foo'))
        .filter(filter('matches', '==', true));
    final int targetId = await _allocateQuery(filteredQuery);

    await _applyRemoteEvent(_addedRemoteEvents(
        <MaybeDocument>[doc('foo/a', 10, map(<dynamic>['matches', true]))],
        <int>[targetId]));
    await _applyRemoteEvent(_noChangeEvent(targetId, 10));
    await _updateViews(targetId, fromCache: false);
    await _localStore.releaseTarget(targetId);

    final Document bundled = doc('foo/b', 5, map(<dynamic>['matches', true]));
    await _localStore.applyBundledDocuments(
        ImmutableSortedMap<DocumentKey, MaybeDocument>.emptyMap(
                DocumentKey.comparator)
            .insert(bundled.key, bundled),
        'bundle',
        readTimes: <DocumentKey, SnapshotVersion>{bundled.key: version(20)});

    await _allocateQuery(filteredQuery);
    await _executeQuery(filteredQuery);
    _expectQueryReturned(<String>['foo/a', 'foo/b']);
  }

  @testMethod
  Future<void>
      testClearsLastLimboFreeSnapshotOnExistenceFilterMismatch() async {
    // An existence filter mismatch invalidates the previous results of a target: the next execution must not reuse
    // them (upstream LocalStore.applyRemoteEvent).
    final Query query = Query(ResourcePath.fromString('foo'))
        .filter(filter('matches', '==', true));
    final Target target = query.toTarget();
    final int targetId = await _allocateQuery(query);

    await _applyRemoteEvent(_noChangeEvent(targetId, 10));
    await _updateViews(targetId, fromCache: false);
    expect(
        (await _localStore.getQueryData(target))!.lastLimboFreeSnapshotVersion,
        version(10));

    await _applyRemoteEvent(RemoteEvent(
      documentUpdates: <DocumentKey, MaybeDocument>{},
      resolvedLimboDocuments: <DocumentKey>{},
      snapshotVersion: version(20),
      targetChanges: <int, TargetChange>{
        targetId: TargetChange(
          resumeToken: Uint8List(0),
          current: false,
          addedDocuments: DocumentKey.emptyKeySet,
          modifiedDocuments: DocumentKey.emptyKeySet,
          removedDocuments: DocumentKey.emptyKeySet,
        )
      },
      targetMismatches: <int, QueryPurpose>{
        targetId: QueryPurpose.existenceFilterMismatch
      },
    ));

    expect(
        (await _localStore.getQueryData(target))!.lastLimboFreeSnapshotVersion,
        SnapshotVersion.none);
  }

  @testMethod
  Future<void> testWritesOverlaysAndRemovesThemOnAck() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    final int targetId = await _allocateQuery(query);
    await _applyRemoteEvent(_addedRemoteEvents(
        <MaybeDocument>[doc('foo/remote', 1, map(<dynamic>['a', 1]))],
        <int>[targetId]));

    await _writeMutation(setMutation('foo/local', map(<dynamic>['a', 1])));
    await _writeMutation(patchMutation('foo/remote', map(<dynamic>['b', 2])));

    // A document without remote version gets a set overlay, a patched remote document a patch overlay.
    expect(await _overlay('foo/local'),
        Overlay(1, setMutation('foo/local', map(<dynamic>['a', 1]))));
    final Overlay remoteOverlay = (await _overlay('foo/remote'))!;
    expect(remoteOverlay.largestBatchId, 2);
    expect(remoteOverlay.mutation, isA<PatchMutation>());

    await _acknowledgeMutation(2);
    expect(await _overlay('foo/local'), isNull);
    expect(await _overlay('foo/remote'), isNotNull);

    await _acknowledgeMutation(3);
    expect(await _overlay('foo/remote'), isNull);
  }

  @testMethod
  Future<void> testRejectRecalculatesOverlays() async {
    await _writeMutation(setMutation('foo/bar', map(<dynamic>['a', 1])));
    await _writeMutation(patchMutation('foo/bar', map(<dynamic>['b', 2])));
    expect((await _overlay('foo/bar'))!.largestBatchId, 2);

    // Reject the set: the overlay (of batch 2) is recalculated, and the remaining update no longer applies because the
    // document does not exist. The overlay of batch 2 must not be kept.
    await _rejectMutation();
    _expectRemoved(<String>['foo/bar']);
    expect(await _overlay('foo/bar'), isNull);
    await _expectNotContains('foo/bar');
  }

  @testMethod
  Future<void> testRemoteDeleteDropsPatchOverlay() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    final int targetId = await _allocateQuery(query);
    await _applyRemoteEvent(_addedRemoteEvents(
        <MaybeDocument>[doc('foo/bar', 1, map(<dynamic>['a', 1]))],
        <int>[targetId]));
    await _writeMutation(patchMutation('foo/bar', map(<dynamic>['b', 2])));
    expect((await _overlay('foo/bar'))!.mutation, isA<PatchMutation>());

    // The document is deleted remotely: the pending update no longer applies (its precondition fails), so the
    // document must not come back from its old patch overlay.
    await _applyRemoteEvent(updateRemoteEvent(
        deletedDoc('foo/bar', 2), <int>[targetId], <int>[]));
    _expectChanged(<MaybeDocument>[deletedDoc('foo/bar', 2)]);
    expect(await _overlay('foo/bar'), isNull);
    await _expectContains(deletedDoc('foo/bar', 2));
  }

  Future<Overlay?> _overlay(String path) {
    return _persistence
        .getDocumentOverlayCache(User.unauthenticated)
        .getOverlay(key(path));
  }

  Future<void> _executeQuery(Query query) async {
    _resetPersistenceStats();
    _lastQueryResult =
        await _localStore.executeQuery(query, /* usePreviousResults= */ true);
  }

  Future<void> _updateViews(int targetId, {required bool fromCache}) {
    return _notifyLocalViewChanges(
        viewChanges(targetId, fromCache, <String>[], <String>[]));
  }

  RemoteEvent _noChangeEvent(int targetId, int theVersion) {
    final t.TestTargetMetadataProvider provider = t.testTargetMetadataProvider;
    provider.setSyncedKeys(queryData(targetId, QueryPurpose.listen, 'foo/bar'),
        DocumentKey.emptyKeySet);
    final WatchChangeAggregator aggregator = WatchChangeAggregator(provider)
      ..handleTargetChange(WatchChangeWatchTargetChange(
          WatchTargetChangeType.noChange,
          <int>[targetId],
          resumeToken(theVersion)));
    return aggregator.createRemoteEvent(version(theVersion));
  }

  void _expectQueryReturned(List<String> keys) {
    expect(_lastQueryResult, isNotNull);
    final ImmutableSortedMap<DocumentKey, Document> documents =
        _lastQueryResult!.documents;
    for (String k in keys) {
      expect(documents.containsKey(key(k)), isTrue,
          reason: 'Expected query to return: $k');
    }
    expect(documents.length, keys.length);
  }

  /// Asserts the expected numbers of mutations read by the query engine's [MutationQueue] since the last call to
  /// [_resetPersistenceStats].
  void _expectMutationsReadByEngine(
      {required int byKey, required int byQuery}) {
    expect(_queryEngine.mutationsReadByQuery, byQuery,
        reason: 'Mutations read (by query)');
    expect(_queryEngine.mutationsReadByKey, byKey,
        reason: 'Mutations read (by key)');
  }

  /// Asserts the expected numbers of overlays read by the query engine's [DocumentOverlayCache] since the last call to
  /// [_resetPersistenceStats].
  void _expectOverlaysReadByEngine(
      {required int byKey, required int byCollection}) {
    expect(_queryEngine.overlaysReadByCollection, byCollection,
        reason: 'Overlays read (by collection)');
    expect(_queryEngine.overlaysReadByKey, byKey,
        reason: 'Overlays read (by key)');
  }

  /// Asserts the expected numbers of documents read by the query engine's [RemoteDocumentCache] since the last call
  /// to [_resetPersistenceStats].
  void _expectRemoteDocumentsReadByEngine(
      {required int byKey, required int byQuery}) {
    expect(_queryEngine.documentsReadByQuery, byQuery,
        reason: 'Remote documents read (by query)');
    expect(_queryEngine.documentsReadByKey, byKey,
        reason: 'Remote documents read (by key)');
  }

  Future<int> _allocateQuery(Query query) async {
    final QueryData queryData = await _localStore.allocateTarget(query.toTarget());
    _lastTargetId = queryData.targetId;
    return queryData.targetId;
  }

  Future<void> _releaseQuery(Query query) async {
    final QueryData? queryData =
        await _persistence.queryCache.getQueryData(query.toTarget());
    await _localStore.releaseTarget(queryData!.targetId);
  }

  /// Asserts that the last target ID is the given number.
  void _expectTargetId(int targetId) {
    expect(_lastTargetId, targetId);
  }

  /// Asserts that a the [_lastChanges] contain the docs in the given array.
  void _expectChanged(
      [List<MaybeDocument> expected = const <MaybeDocument>[]]) {
    expect(_lastChanges, isNotNull);

    final List<MaybeDocument> actualList = _lastChanges!
        .map((MapEntry<DocumentKey, MaybeDocument> entry) => entry.value)
        .toList();

    expect(actualList, expected);
    _lastChanges = null;
  }

  @testMethod
  Future<void> testOnlyPersistsUpdatesForDocumentsWhenVersionChanges() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    final int targetId = await _allocateQuery(query);
    expect(targetId, 2);

    await _applyRemoteEvent(addedRemoteEvent(
        doc('foo/bar', 1, map(<String>['val', 'old'])), <int>[2], <int>[]));
    _expectChanged(<Document>[
      doc('foo/bar', 1, map(<String>['val', 'old']))
    ]);
    await _expectContains(doc('foo/bar', 1, map(<String>['val', 'old'])));

    await _applyRemoteEvent(_addedRemoteEvents(<MaybeDocument>[
      doc('foo/bar', 1, map(<String>['val', 'new'])),
      doc('foo/baz', 2, map(<String>['val', 'new']))
    ], <int>[
      2
    ]));

    _expectChanged(<Document>[
      doc('foo/baz', 2, map(<String>['val', 'new']))
    ]);
    // The update for foo/bar is ignored.
    await _expectContains(doc('foo/bar', 1, map(<String>['val', 'old'])));
    await _expectContains(doc('foo/baz', 2, map(<String>['val', 'new'])));
  }

  @testMethod
  Future<void> testRemovesManufacturedNoDocumentsFromTheCache() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    final int targetId = await _allocateQuery(query);

    await _applyRemoteEvent(addedRemoteEvent(
        doc('foo/bar', 1, map(<String>['val', 'old'])),
        <int>[targetId],
        <int>[]));
    await _expectContains(doc('foo/bar', 1, map(<String>['val', 'old'])));

    // A failed limbo resolution manufactures a NoDocument with a version of NONE. It must remove the document from
    // the cache, even though its version is older than the cached one.
    final NoDocument manufactured = deletedDoc('foo/bar', 0);
    await _applyRemoteEvent(RemoteEvent(
      documentUpdates: <DocumentKey, MaybeDocument>{
        manufactured.key: manufactured
      },
      resolvedLimboDocuments: <DocumentKey>{manufactured.key},
    ));
    _expectRemoved(<String>['foo/bar']);
    await _expectNotContains('foo/bar');
  }

  @testMethod
  Future<void> testClearsResumeTokenOnExistenceFilterMismatch() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    final int targetId = await _allocateQuery(query);

    // Persist a resume token for the target.
    await _applyRemoteEvent(RemoteEvent(
      documentUpdates: <DocumentKey, MaybeDocument>{},
      resolvedLimboDocuments: <DocumentKey>{},
      snapshotVersion: version(10),
      targetChanges: <int, TargetChange>{
        targetId: TargetChange(
          resumeToken: resumeToken(10)!,
          current: true,
          addedDocuments: DocumentKey.emptyKeySet,
          modifiedDocuments: DocumentKey.emptyKeySet,
          removedDocuments: DocumentKey.emptyKeySet,
        )
      },
    ));
    QueryData? cached = await _persistence.queryCache.getQueryData(query.toTarget());
    expect(cached!.resumeToken, resumeToken(10));
    expect(cached.snapshotVersion, version(10));

    // An existence filter mismatch invalidates the target: the resume token must be cleared, also in the cache.
    await _applyRemoteEvent(RemoteEvent(
      documentUpdates: <DocumentKey, MaybeDocument>{},
      resolvedLimboDocuments: <DocumentKey>{},
      snapshotVersion: version(20),
      targetChanges: <int, TargetChange>{
        targetId: TargetChange(
          resumeToken: Uint8List(0),
          current: false,
          addedDocuments: DocumentKey.emptyKeySet,
          modifiedDocuments: DocumentKey.emptyKeySet,
          removedDocuments: DocumentKey.emptyKeySet,
        )
      },
      targetMismatches: <int, QueryPurpose>{
        targetId: QueryPurpose.existenceFilterMismatch
      },
    ));
    cached = await _persistence.queryCache.getQueryData(query.toTarget());
    expect(cached!.resumeToken, isEmpty);
    expect(cached.snapshotVersion, SnapshotVersion.none);
  }

  @testMethod
  Future<void> testGetHighestUnacknowledgedBatchId() async {
    expect(await _localStore.getHighestUnacknowledgedBatchId(),
        MutationBatch.unknown);

    await _writeMutation(setMutation('foo/bar', map(<dynamic>['abc', 123])));
    expect(await _localStore.getHighestUnacknowledgedBatchId(), 1);

    await _writeMutation(patchMutation('foo/bar', map(<dynamic>['abc', 321])));
    expect(await _localStore.getHighestUnacknowledgedBatchId(), 2);

    await _acknowledgeMutation(1);
    expect(await _localStore.getHighestUnacknowledgedBatchId(), 2);

    await _rejectMutation();
    expect(await _localStore.getHighestUnacknowledgedBatchId(),
        MutationBatch.unknown);
  }

  RemoteEvent _addedRemoteEvents(
      List<MaybeDocument> docs, List<int> updatedInTargets) {
    final WatchChangeAggregator aggregator =
        WatchChangeAggregator(TargetMetadataProvider(
      getRemoteKeysForTarget: (int targetId) => DocumentKey.emptyKeySet,
      getDatabaseId: () => DatabaseId.forDatabase('p', 'd'),
      getQueryDataForTarget: (int targetId) =>
          queryData(targetId, QueryPurpose.listen, 'foo'),
    ));
    SnapshotVersion snapshotVersion = SnapshotVersion.none;
    for (MaybeDocument doc in docs) {
      aggregator.handleDocumentChange(
          WatchChangeDocumentChange(updatedInTargets, <int>[], doc.key, doc));
      if (doc.version.compareTo(snapshotVersion) > 0) {
        snapshotVersion = doc.version;
      }
    }
    return aggregator.createRemoteEvent(snapshotVersion);
  }

  /// Asserts that the given keys were removed.
  void _expectRemoved(List<String> keyPaths) {
    expect(_lastChanges, isNotNull);

    final ImmutableSortedMap<DocumentKey, MaybeDocument> actual = _lastChanges!;
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
    final MaybeDocument? actual = await _localStore.readDocument(expected.key);

    expect(actual, expected);
  }

  /// Asserts that the given local store does not contain the given document.
  Future<void> _expectNotContains(String keyPathString) async {
    final DocumentKey key = DocumentKey.fromPathString(keyPathString);
    final MaybeDocument? actual = await _localStore.readDocument(key);
    expect(actual, isNull);
  }

  /// Asserts the expected numbers of mutation rows read by the [MutationQueue]
  /// since the last call to [_resetPersistenceStats].
  void _expectMutationsRead(int expected) {
    expect(_statsCollector.getRowsRead(MutationQueue.statsTag), expected);
  }

  /// Asserts the expected numbers of document rows read by the
  /// [RemoteDocumentCache] since the last call to [_resetPersistenceStats].
  void _expectRemoteDocumentsRead(int expected) {
    expect(_statsCollector.getRowsRead(RemoteDocumentCache.statsTag), expected);
  }

  /// Resets the count of rows read by [MutationQueue] and the
  /// [RemoteDocumentCache].
  void _resetPersistenceStats() {
    _statsCollector.reset();
    _queryEngine.resetCounts();
  }
}
