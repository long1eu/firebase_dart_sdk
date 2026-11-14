// File created by
// Lung Razvan <long1eu>
// on 29/09/2018
import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart'
    show
        Blob,
        BsonObjectId,
        BsonTimestamp,
        Decimal128Value,
        GeoPoint,
        Int32Value,
        MaxKey,
        MinKey,
        RegexValue,
        VectorValue;
import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/target.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/default_query_engine.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/encoded_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/index_backfiller.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_view_changes.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_write_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/mutation_queue.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/remote_document_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_purpose.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/field_mask.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/field_transform.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/overlay.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/patch_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/server_timestamp_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/set_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/no_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart'
    as model;
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/existence_filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_event.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/target_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/watch_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/watch_change_aggregator.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/user_data_converter.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../../../util/index_helpers.dart';
import '../../../../../util/test_util.dart';
import '../../util/test_target_metadata_provider.dart' as t;
import '../accumulating_stats_collector.dart';
import '../counting_query_engine.dart';

class LocalStoreTestCase {
  LocalStoreTestCase(
    this._persistence,
    this._statsCollector, {
    required bool garbageCollectorIsEager,
  }) : _garbageCollectorIsEager = garbageCollectorIsEager;

  final AccumulatingStatsCollector _statsCollector;
  final Persistence _persistence;
  final bool _garbageCollectorIsEager;

  late List<MutationBatch> _batches;
  ImmutableSortedMap<DocumentKey, MaybeDocument>? _lastChanges;
  late int _lastTargetId;
  late LocalStore _localStore;
  late CountingQueryEngine _queryEngine;
  late DefaultQueryEngine _defaultEngine;
  int? _backfillerMaxDocumentsToProcess;
  QueryResult? _lastQueryResult;

  Future<void> setUp() async {
    _batches = <MutationBatch>[];
    _lastChanges = null;
    _lastQueryResult = null;
    _lastTargetId = 0;

    _defaultEngine = DefaultQueryEngine();
    _backfillerMaxDocumentsToProcess = null;
    _queryEngine = CountingQueryEngine(_defaultEngine);
    _localStore = LocalStore(
      _persistence,
      User.unauthenticated,
      queryEngine: _queryEngine,
    );
    await _localStore.start();
  }

  Future<void> tearDown() => _persistence.shutdown();

  @testMethod
  Future<void> testMutationBatchKeys() async {
    final SetMutation set1 = setMutation(
      'foo/bar',
      map(<String>['foo', 'bar']),
    );
    final SetMutation set2 = setMutation(
      'foo/baz',
      map(<String>['foo', 'baz']),
    );
    final MutationBatch batch = MutationBatch(
      batchId: 1,
      localWriteTime: Timestamp.now(),
      baseMutations: <Mutation>[],
      mutations: <SetMutation>[set1, set2],
    );
    final Set<DocumentKey> keys = batch.keys;
    expect(keys.length, 2);
  }

  @testMethod
  Future<void> testHandlesSetMutation() async {
    await _writeMutation(setMutation('foo/bar', map(<String>['foo', 'bar'])));

    _expectChanged(<Document>[
      doc(
        'foo/bar',
        0,
        map(<String>['foo', 'bar']),
        DocumentState.localMutations,
      ),
    ]);
    await _expectContains(
      doc(
        'foo/bar',
        0,
        map(<String>['foo', 'bar']),
        DocumentState.localMutations,
      ),
    );

    await _acknowledgeMutation(1);

    _expectChanged(<Document>[
      doc(
        'foo/bar',
        1,
        map(<String>['foo', 'bar']),
        DocumentState.committedMutations,
      ),
    ]);

    if (_garbageCollectorIsEager) {
      // Nothing is pinning this anymore, as it has been acknowledged and there are no targets active.
      await _expectNotContains('foo/bar');
    } else {
      await _expectContains(
        doc(
          'foo/bar',
          1,
          map(<String>['foo', 'bar']),
          DocumentState.committedMutations,
        ),
      );
    }
  }

  @testMethod
  Future<void> testHandlesSetMutationThenDocument() async {
    await _writeMutation(setMutation('foo/bar', map(<String>['foo', 'bar'])));
    _expectChanged(<Document>[
      doc(
        'foo/bar',
        0,
        map(<String>['foo', 'bar']),
        DocumentState.localMutations,
      ),
    ]);
    await _expectContains(
      doc(
        'foo/bar',
        0,
        map(<String>['foo', 'bar']),
        DocumentState.localMutations,
      ),
    );

    final Query query = Query(ResourcePath.fromString('foo'));
    final int targetId = await _allocateQuery(query);
    await _applyRemoteEvent(
      updateRemoteEvent(
        doc(
          'foo/bar',
          2,
          map(<String>['it', 'changed']),
          DocumentState.localMutations,
        ),
        <int>[targetId],
        <int>[],
      ),
    );
    _expectChanged(<Document>[
      doc(
        'foo/bar',
        0,
        map(<String>['foo', 'bar']),
        DocumentState.localMutations,
      ),
    ]);
    await _expectContains(
      doc(
        'foo/bar',
        0,
        map(<String>['foo', 'bar']),
        DocumentState.localMutations,
      ),
    );
  }

  @testMethod
  Future<void> testHandlesSetMutationThenAckThenRelease() async {
    final Query query = Query(ResourcePath.fromSegments(<String>['foo']));
    await _allocateQuery(query);

    await _writeMutation(setMutation('foo/bar', map(<String>['foo', 'bar'])));
    await _notifyLocalViewChanges(
      viewChanges(2, /* fromCache= */ false, <String>['foo/bar'], <String>[]),
    );

    _expectChanged(<Document>[
      doc(
        'foo/bar',
        0,
        map(<String>['foo', 'bar']),
        DocumentState.localMutations,
      ),
    ]);
    await _expectContains(
      doc(
        'foo/bar',
        0,
        map(<String>['foo', 'bar']),
        DocumentState.localMutations,
      ),
    );

    await _acknowledgeMutation(1);

    _expectChanged(<Document>[
      doc(
        'foo/bar',
        1,
        map(<String>['foo', 'bar']),
        DocumentState.committedMutations,
      ),
    ]);
    await _expectContains(
      doc(
        'foo/bar',
        1,
        map(<String>['foo', 'bar']),
        DocumentState.committedMutations,
      ),
    );

    await _releaseQuery(query);

    // It has been acknowledged, and should no longer be retained as there is no target and mutation
    if (_garbageCollectorIsEager) {
      await _expectNotContains('foo/bar');
    } else {
      await _expectContains(
        doc(
          'foo/bar',
          1,
          map(<String>['foo', 'bar']),
          DocumentState.committedMutations,
        ),
      );
    }
  }

  @testMethod
  Future<void> testHandlesAckThenRejectThenRemoteEvent() async {
    // Start a query that requires acks to be held.
    final Query query = Query(ResourcePath.fromSegments(<String>['foo']));
    final int targetId = await _allocateQuery(query);

    await _writeMutation(setMutation('foo/bar', map(<String>['foo', 'bar'])));
    _expectChanged(<Document>[
      doc(
        'foo/bar',
        0,
        map(<String>['foo', 'bar']),
        DocumentState.localMutations,
      ),
    ]);
    await _expectContains(
      doc(
        'foo/bar',
        0,
        map(<String>['foo', 'bar']),
        DocumentState.localMutations,
      ),
    );

    // The last seen version is zero, so this ack must be held.
    await _acknowledgeMutation(1);
    if (_garbageCollectorIsEager) {
      // Nothing is pinning this anymore, as it has been acknowledged and there are no targets active.
      await _expectNotContains('foo/bar');
    } else {
      await _expectContains(
        doc(
          'foo/bar',
          1,
          map(<String>['foo', 'bar']),
          DocumentState.committedMutations,
        ),
      );
    }

    await _writeMutation(setMutation('bar/baz', map(<String>['bar', 'baz'])));
    _expectChanged(<Document>[
      doc(
        'bar/baz',
        0,
        map(<String>['bar', 'baz']),
        DocumentState.localMutations,
      ),
    ]);
    await _expectContains(
      doc(
        'bar/baz',
        0,
        map(<String>['bar', 'baz']),
        DocumentState.localMutations,
      ),
    );

    await _rejectMutation();
    _expectRemoved(<String>['bar/baz']);
    await _expectNotContains('bar/baz');

    await _applyRemoteEvent(
      addedRemoteEvent(doc('foo/bar', 2, map(<String>['it', 'changed'])), <int>[
        targetId,
      ], <int>[]),
    );
    _expectChanged(<Document>[
      doc('foo/bar', 2, map(<String>['it', 'changed'])),
    ]);
    await _expectContains(doc('foo/bar', 2, map(<String>['it', 'changed'])));
    await _expectNotContains('bar/baz');
  }

  @testMethod
  Future<void> testHandlesDeletedDocumentThenSetMutationThenAck() async {
    final Query _query = query('foo');
    final int targetId = await _allocateQuery(_query);
    await _applyRemoteEvent(
      updateRemoteEvent(deletedDoc('foo/bar', 2), <int>[targetId], <int>[]),
    );
    _expectRemoved(<String>['foo/bar']);
    // Under eager GC, there is no longer a reference for the document, and it should be deleted.
    if (_garbageCollectorIsEager) {
      await _expectNotContains('foo/bar');
    } else {
      await _expectContains(deletedDoc('foo/bar', 2));
    }

    await _writeMutation(setMutation('foo/bar', map(<String>['foo', 'bar'])));
    _expectChanged(<Document>[
      doc(
        'foo/bar',
        0,
        map(<String>['foo', 'bar']),
        DocumentState.localMutations,
      ),
    ]);
    await _expectContains(
      doc(
        'foo/bar',
        0,
        map(<String>['foo', 'bar']),
        DocumentState.localMutations,
      ),
    );

    await _releaseQuery(_query);
    await _acknowledgeMutation(3);
    _expectChanged(<Document>[
      doc(
        'foo/bar',
        3,
        map(<String>['foo', 'bar']),
        DocumentState.committedMutations,
      ),
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
      doc(
        'foo/bar',
        0,
        map(<String>['foo', 'bar']),
        DocumentState.localMutations,
      ),
    ]);

    await _applyRemoteEvent(
      updateRemoteEvent(deletedDoc('foo/bar', 2), <int>[targetId], <int>[]),
    );
    _expectChanged(<Document>[
      doc(
        'foo/bar',
        0,
        map(<String>['foo', 'bar']),
        DocumentState.localMutations,
      ),
    ]);
    await _expectContains(
      doc(
        'foo/bar',
        0,
        map(<String>['foo', 'bar']),
        DocumentState.localMutations,
      ),
    );
  }

  @testMethod
  Future<void> testHandlesDocumentThenSetMutationThenAckThenDocument() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    final int targetId = await _allocateQuery(query);
    await _applyRemoteEvent(
      addedRemoteEvent(doc('foo/bar', 2, map(<String>['it', 'base'])), <int>[
        targetId,
      ], <int>[]),
    );

    _expectChanged(<Document>[
      doc('foo/bar', 2, map(<String>['it', 'base'])),
    ]);
    await _expectContains(doc('foo/bar', 2, map(<String>['it', 'base'])));

    await _writeMutation(setMutation('foo/bar', map(<String>['foo', 'bar'])));
    _expectChanged(<Document>[
      doc(
        'foo/bar',
        0,
        map(<String>['foo', 'bar']),
        DocumentState.localMutations,
      ),
    ]);
    await _expectContains(
      doc(
        'foo/bar',
        0,
        map(<String>['foo', 'bar']),
        DocumentState.localMutations,
      ),
    );

    await _acknowledgeMutation(3);
    _expectChanged(<Document>[
      doc(
        'foo/bar',
        3,
        map(<String>['foo', 'bar']),
        DocumentState.committedMutations,
      ),
    ]);
    await _expectContains(
      doc(
        'foo/bar',
        3,
        map(<String>['foo', 'bar']),
        DocumentState.committedMutations,
      ),
    );

    await _applyRemoteEvent(
      updateRemoteEvent(
        doc('foo/bar', 3, map(<String>['it', 'changed'])),
        <int>[targetId],
        <int>[],
      ),
    );
    _expectChanged(<Document>[
      doc('foo/bar', 3, map(<String>['it', 'changed'])),
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
    await _applyRemoteEvent(
      addedRemoteEvent(
        doc(
          'foo/bar',
          1,
          map(<String>['it', 'base']),
          DocumentState.localMutations,
        ),
        <int>[targetId],
        <int>[],
      ),
    );
    _expectChanged(<MaybeDocument>[
      doc(
        'foo/bar',
        0,
        map(<String>['foo', 'bar', 'it', 'base']),
        DocumentState.localMutations,
      ),
    ]);
    await _expectContains(
      doc(
        'foo/bar',
        0,
        map(<String>['foo', 'bar', 'it', 'base']),
        DocumentState.localMutations,
      ),
    );

    await _acknowledgeMutation(2);

    _expectChanged(<Document>[
      doc(
        'foo/bar',
        2,
        map(<String>['foo', 'bar', 'it', 'base']),
        DocumentState.committedMutations,
      ),
    ]);
    await _expectContains(
      doc(
        'foo/bar',
        2,
        map(<String>['foo', 'bar', 'it', 'base']),
        DocumentState.committedMutations,
      ),
    );

    await _applyRemoteEvent(
      updateRemoteEvent(
        doc('foo/bar', 2, map(<String>['foo', 'bar', 'it', 'base'])),
        <int>[targetId],
        <int>[],
      ),
    );
    _expectChanged(<Document>[
      doc('foo/bar', 2, map(<String>['foo', 'bar', 'it', 'base'])),
    ]);
    await _expectContains(
      doc('foo/bar', 2, map(<String>['foo', 'bar', 'it', 'base'])),
    );
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
      updateRemoteEvent(doc('foo/bar', 1, map(<String>['it', 'base'])), <int>[
        targetId,
      ], <int>[]),
    );
    _expectChanged(<Document>[
      doc('foo/bar', 1, map(<String>['it', 'base'])),
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
        deletedDoc('foo/bar', 1, hasCommittedMutations: true),
      );
    }
  }

  @testMethod
  Future<void> testHandlesDocumentThenDeleteMutationThenAck() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    final int targetId = await _allocateQuery(query);
    await _applyRemoteEvent(
      updateRemoteEvent(doc('foo/bar', 1, map(<String>['it', 'base'])), <int>[
        targetId,
      ], <int>[]),
    );
    _expectChanged(<Document>[
      doc('foo/bar', 1, map(<String>['it', 'base'])),
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
        deletedDoc('foo/bar', 2, hasCommittedMutations: true),
      );
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
      updateRemoteEvent(doc('foo/bar', 1, map(<String>['it', 'base'])), <int>[
        targetId,
      ], <int>[]),
    );
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
        deletedDoc('foo/bar', 2, hasCommittedMutations: true),
      );
    }
  }

  @testMethod
  Future<void> testHandlesDocumentThenDeletedDocumentThenDocument() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    final int targetId = await _allocateQuery(query);
    await _applyRemoteEvent(
      updateRemoteEvent(doc('foo/bar', 1, map(<String>['it', 'base'])), <int>[
        targetId,
      ], <int>[]),
    );
    _expectChanged(<Document>[
      doc('foo/bar', 1, map(<String>['it', 'base'])),
    ]);
    await _expectContains(doc('foo/bar', 1, map(<String>['it', 'base'])));

    await _applyRemoteEvent(
      updateRemoteEvent(deletedDoc('foo/bar', 2), <int>[targetId], <int>[]),
    );
    _expectRemoved(<String>['foo/bar']);
    if (!_garbageCollectorIsEager) {
      await _expectContains(deletedDoc('foo/bar', 2));
    }

    await _applyRemoteEvent(
      updateRemoteEvent(
        doc('foo/bar', 3, map(<String>['it', 'changed'])),
        <int>[targetId],
        <int>[],
      ),
    );
    _expectChanged(<Document>[
      doc('foo/bar', 3, map(<String>['it', 'changed'])),
    ]);
    await _expectContains(doc('foo/bar', 3, map(<String>['it', 'changed'])));
  }

  @testMethod
  Future<void>
  testHandlesSetMutationThenPatchMutationThenDocumentThenAckThenAck() async {
    await _writeMutation(setMutation('foo/bar', map(<String>['foo', 'old'])));
    _expectChanged(<Document>[
      doc(
        'foo/bar',
        0,
        map(<String>['foo', 'old']),
        DocumentState.localMutations,
      ),
    ]);
    await _expectContains(
      doc(
        'foo/bar',
        0,
        map(<String>['foo', 'old']),
        DocumentState.localMutations,
      ),
    );

    await _writeMutation(patchMutation('foo/bar', map(<String>['foo', 'bar'])));
    _expectChanged(<Document>[
      doc(
        'foo/bar',
        0,
        map(<String>['foo', 'bar']),
        DocumentState.localMutations,
      ),
    ]);
    await _expectContains(
      doc(
        'foo/bar',
        0,
        map(<String>['foo', 'bar']),
        DocumentState.localMutations,
      ),
    );

    final Query query = Query(ResourcePath.fromString('foo'));

    final int targetId = await _allocateQuery(query);
    await _applyRemoteEvent(
      updateRemoteEvent(
        doc(
          'foo/bar',
          1,
          map(<String>['it', 'base']),
          DocumentState.localMutations,
        ),
        <int>[targetId],
        <int>[],
      ),
    );
    _expectChanged(<Document>[
      doc(
        'foo/bar',
        0,
        map(<String>['foo', 'bar']),
        DocumentState.localMutations,
      ),
    ]);
    await _expectContains(
      doc(
        'foo/bar',
        0,
        map(<String>['foo', 'bar']),
        DocumentState.localMutations,
      ),
    );

    await _releaseQuery(query);
    await _acknowledgeMutation(2); // delete mutation
    _expectChanged(<Document>[
      doc(
        'foo/bar',
        0,
        map(<String>['foo', 'bar']),
        DocumentState.localMutations,
      ),
    ]);
    await _expectContains(
      doc(
        'foo/bar',
        0,
        map(<String>['foo', 'bar']),
        DocumentState.localMutations,
      ),
    );

    await _acknowledgeMutation(3); // patch mutation
    _expectChanged(<Document>[
      doc(
        'foo/bar',
        3,
        map(<String>['foo', 'bar']),
        DocumentState.committedMutations,
      ),
    ]);

    if (_garbageCollectorIsEager) {
      // we've ack'd all of the mutations, nothing is keeping this pinned anymore
      await _expectNotContains('foo/bar');
    } else {
      await _expectContains(
        doc(
          'foo/bar',
          3,
          map(<String>['foo', 'bar']),
          DocumentState.committedMutations,
        ),
      );
    }
  }

  @testMethod
  Future<void> testHandlesSetMutationAndPatchMutationTogether() async {
    await _writeMutations(<Mutation>[
      setMutation('foo/bar', map(<String>['foo', 'old'])),
      patchMutation('foo/bar', map(<String>['foo', 'bar'])),
    ]);

    _expectChanged(<Document>[
      doc(
        'foo/bar',
        0,
        map(<String>['foo', 'bar']),
        DocumentState.localMutations,
      ),
    ]);
    await _expectContains(
      doc(
        'foo/bar',
        0,
        map(<String>['foo', 'bar']),
        DocumentState.localMutations,
      ),
    );
  }

  @testMethod
  Future<void> testHandlesSetMutationThenPatchMutationThenReject() async {
    if (!_garbageCollectorIsEager) {
      return;
    }

    await _writeMutation(setMutation('foo/bar', map(<String>['foo', 'old'])));
    await _expectContains(
      doc(
        'foo/bar',
        0,
        map(<String>['foo', 'old']),
        DocumentState.localMutations,
      ),
    );
    await _acknowledgeMutation(1);
    await _expectNotContains('foo/bar');

    await _writeMutation(patchMutation('foo/bar', map(<String>['foo', 'bar'])));
    // A blind patch is not visible in the cache
    await _expectNotContains('foo/bar');

    await _rejectMutation();
    await _expectNotContains('foo/bar');
  }

  /// Port of the JS SDK's `handles SetMutation -> Ack -> PatchMutation -> Reject` (local_store.test.ts), which only
  /// runs with eager garbage collection.
  @testMethod
  Future<void>
  testHandlesSetMutationThenAckThenPatchMutationThenReject() async {
    await _writeMutation(setMutation('foo/bar', map(<dynamic>['foo', 'old'])));
    await _expectContains(
      doc(
        'foo/bar',
        0,
        map(<dynamic>['foo', 'old']),
        DocumentState.localMutations,
      ),
    );

    await _acknowledgeMutation(1);
    // After having been ack'd, there is nothing pinning the document
    await _expectNotContains('foo/bar');

    await _writeMutation(
      patchMutation('foo/bar', map(<dynamic>['foo', 'bar'])),
    );
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
      patchMutation('foo/bar', map(<String>['foo', 'bar'])),
    ]);

    _expectChanged(<Document>[
      doc(
        'bar/baz',
        0,
        map(<String>['bar', 'baz']),
        DocumentState.localMutations,
      ),
      doc(
        'foo/bar',
        0,
        map(<String>['foo', 'bar']),
        DocumentState.localMutations,
      ),
    ]);

    await _expectContains(
      doc(
        'foo/bar',
        0,
        map(<String>['foo', 'bar']),
        DocumentState.localMutations,
      ),
    );
    await _expectContains(
      doc(
        'bar/baz',
        0,
        map(<String>['bar', 'baz']),
        DocumentState.localMutations,
      ),
    );
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
    await _applyRemoteEvent(
      updateRemoteEvent(deletedDoc('foo/bar', 2), <int>[], <int>[], <int>[
        targetId,
      ]),
    );
    await _expectNotContains('foo/bar');

    await _applyRemoteEvent(
      updateRemoteEvent(
        doc('foo/bar', 2, map(<String>['foo', 'bar'])),
        <int>[],
        <int>[],
        <int>[targetId],
      ),
    );
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
    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('foo/bar', 2, map(<String>['foo', 'bar'])),
        two,
        none,
      ),
    );
    await _expectContains(doc('foo/bar', 2, map(<String>['foo', 'bar'])));

    await _applyRemoteEvent(
      updateRemoteEvent(
        doc('foo/bar', 2, map(<String>['foo', 'baz'])),
        none,
        two,
      ),
    );

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
      updateRemoteEvent(doc('foo/bar', 1, map(<String>['foo', 'old'])), <int>[
        targetId,
      ], <int>[]),
    );
    await _writeMutation(patchMutation('foo/bar', map(<String>['foo', 'bar'])));
    await _releaseQuery(query);
    await _writeMutation(setMutation('foo/bah', map(<String>['foo', 'bah'])));
    await _writeMutation(deleteMutation('foo/baz'));
    await _expectContains(
      doc(
        'foo/bar',
        0,
        map(<String>['foo', 'bar']),
        DocumentState.localMutations,
      ),
    );
    await _expectContains(
      doc(
        'foo/bah',
        0,
        map(<String>['foo', 'bah']),
        DocumentState.localMutations,
      ),
    );
    await _expectContains(deletedDoc('foo/baz', 0));

    await _acknowledgeMutation(3);
    await _expectNotContains('foo/bar');
    await _expectContains(
      doc(
        'foo/bah',
        0,
        map(<String>['foo', 'bah']),
        DocumentState.localMutations,
      ),
    );
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
      updateRemoteEvent(doc('foo/bar', 1, map(<String>['foo', 'old'])), <int>[
        targetId,
      ], <int>[]),
    );
    await _writeMutation(patchMutation('foo/bar', map(<String>['foo', 'bar'])));
    // Release the query so that our target count goes back to 0 and we are considered up-to-date.
    await _releaseQuery(query);
    await _writeMutation(setMutation('foo/bah', map(<String>['foo', 'bah'])));
    await _writeMutation(deleteMutation('foo/baz'));
    await _expectContains(
      doc(
        'foo/bar',
        0,
        map(<String>['foo', 'bar']),
        DocumentState.localMutations,
      ),
    );
    await _expectContains(
      doc(
        'foo/bah',
        0,
        map(<String>['foo', 'bah']),
        DocumentState.localMutations,
      ),
    );
    await _expectContains(deletedDoc('foo/baz', 0));

    await _rejectMutation(); // patch mutation
    await _expectNotContains('foo/bar');
    await _expectContains(
      doc(
        'foo/bah',
        0,
        map(<String>['foo', 'bah']),
        DocumentState.localMutations,
      ),
    );
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
    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('foo/bar', 1, map(<String>['foo', 'bar'])),
        two,
        none,
      ),
    );
    await _writeMutation(setMutation('foo/baz', map(<String>['foo', 'baz'])));
    await _expectContains(doc('foo/bar', 1, map(<String>['foo', 'bar'])));
    await _expectContains(
      doc(
        'foo/baz',
        0,
        map(<String>['foo', 'baz']),
        DocumentState.localMutations,
      ),
    );

    await _notifyLocalViewChanges(
      viewChanges(2, /* fromCache= */ false, <String>[
        'foo/bar',
        'foo/baz',
      ], <String>[]),
    );
    await _applyRemoteEvent(
      updateRemoteEvent(
        doc('foo/bar', 1, map(<String>['foo', 'bar'])),
        none,
        two,
      ),
    );
    await _applyRemoteEvent(
      updateRemoteEvent(
        doc('foo/baz', 2, map(<String>['foo', 'baz'])),
        two,
        none,
      ),
    );
    await _acknowledgeMutation(2);
    await _expectContains(doc('foo/bar', 1, map(<String>['foo', 'bar'])));
    await _expectContains(doc('foo/baz', 2, map(<String>['foo', 'baz'])));

    await _notifyLocalViewChanges(
      viewChanges(2, /* fromCache= */ false, <String>[], <String>[
        'foo/bar',
        'foo/baz',
      ]),
    );
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
    await _applyRemoteEvent(
      updateRemoteEvent(doc('foo/bar', 1, map()), <int>[], <int>[], <int>[
        targetID,
      ]),
    );

    await _expectNotContains('foo/bar');
  }

  @testMethod
  Future<void> testCanExecuteDocumentQueries() async {
    await _localStore.writeLocally(<Mutation>[
      setMutation('foo/bar', map(<String>['foo', 'bar'])),
      setMutation('foo/baz', map(<String>['foo', 'baz'])),
      setMutation('foo/bar/Foo/Bar', map(<String>['Foo', 'Bar'])),
    ]);

    final Query query = Query(
      ResourcePath.fromSegments(<String>['foo', 'bar']),
    );
    final ImmutableSortedMap<DocumentKey, Document> docs =
        (await _localStore.executeQuery(
          query,
          /* usePreviousResults= */ true,
        )).documents;
    expect(values(docs), <Document>[
      doc(
        'foo/bar',
        0,
        map(<String>['foo', 'bar']),
        DocumentState.localMutations,
      ),
    ]);
  }

  @testMethod
  Future<void> testCanExecuteCollectionQueries() async {
    await _localStore.writeLocally(<SetMutation>[
      setMutation('fo/bar', map(<String>['fo', 'bar'])),
      setMutation('foo/bar', map(<String>['foo', 'bar'])),
      setMutation('foo/baz', map(<String>['foo', 'baz'])),
      setMutation('foo/bar/Foo/Bar', map(<String>['Foo', 'Bar'])),
      setMutation('fooo/blah', map(<String>['fooo', 'blah'])),
    ]);

    final Query query = Query(ResourcePath.fromString('foo'));
    final ImmutableSortedMap<DocumentKey, Document> docs =
        (await _localStore.executeQuery(
          query,
          /* usePreviousResults= */ true,
        )).documents;

    expect(values(docs), <Document>[
      doc(
        'foo/bar',
        0,
        map(<String>['foo', 'bar']),
        DocumentState.localMutations,
      ),
      doc(
        'foo/baz',
        0,
        map(<String>['foo', 'baz']),
        DocumentState.localMutations,
      ),
    ]);
  }

  @testMethod
  Future<void> testCanExecuteMixedCollectionQueries() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    await _allocateQuery(query);
    _expectTargetId(2);

    await _applyRemoteEvent(
      updateRemoteEvent(doc('foo/baz', 10, map(<String>['a', 'b'])), <int>[
        2,
      ], <int>[]),
    );
    await _applyRemoteEvent(
      updateRemoteEvent(doc('foo/bar', 20, map(<String>['a', 'b'])), <int>[
        2,
      ], <int>[]),
    );
    await _writeMutation(setMutation('foo/bonk', map(<String>['a', 'b'])));

    final ImmutableSortedMap<DocumentKey, Document> docs =
        (await _localStore.executeQuery(
          query,
          /* usePreviousResults= */ true,
        )).documents;

    expect(values(docs), <Document>[
      doc('foo/bar', 20, map(<String>['a', 'b'])),
      doc('foo/baz', 10, map(<String>['a', 'b'])),
      doc('foo/bonk', 0, map(<String>['a', 'b']), DocumentState.localMutations),
    ]);
  }

  @testMethod
  Future<void> testReadsAllDocumentsForCollectionQueries() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    await _allocateQuery(query);

    await _applyRemoteEvent(
      updateRemoteEvent(doc('foo/baz', 10, map()), <int>[2], <int>[]),
    );
    await _applyRemoteEvent(
      updateRemoteEvent(doc('foo/bar', 20, map()), <int>[2], <int>[]),
    );
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

    final QueryData _queryData = queryData(
      targetId,
      QueryPurpose.listen,
      'foo/bar',
    );
    final t.TestTargetMetadataProvider testTargetMetadataProvider =
        t.testTargetMetadataProvider
          ..setSyncedKeys(_queryData, DocumentKey.emptyKeySet);

    final WatchChangeAggregator aggregator = WatchChangeAggregator(
      testTargetMetadataProvider,
    );
    addWatchTargets(aggregator, <List<int>>[
      <int>[targetId],
    ]);

    final WatchChangeWatchTargetChange watchChange =
        WatchChangeWatchTargetChange(WatchTargetChangeType.current, <int>[
          targetId,
        ], _resumeToken);
    aggregator.handleTargetChange(watchChange);
    final RemoteEvent remoteEvent = aggregator.createRemoteEvent(version(1000));
    await _applyRemoteEvent(remoteEvent);

    // Stop listening so that the query should become inactive (but persistent)
    await _releaseQuery(_query);

    // Should come back with the same resume token
    final QueryData queryData2 = await _localStore.allocateTarget(
      _query.toTarget(),
    );
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

    final QueryData _queryData = queryData(
      targetId,
      QueryPurpose.listen,
      'foo/bar',
    );
    final t.TestTargetMetadataProvider testTargetMetadataProvider =
        t.testTargetMetadataProvider
          ..setSyncedKeys(_queryData, DocumentKey.emptyKeySet);

    final WatchChangeAggregator aggregator1 = WatchChangeAggregator(
      testTargetMetadataProvider,
    );
    addWatchTargets(aggregator1, <List<int>>[
      <int>[targetId],
    ]);

    final WatchChangeWatchTargetChange watchChange1 =
        WatchChangeWatchTargetChange(WatchTargetChangeType.current, <int>[
          targetId,
        ], _resumeToken);
    aggregator1.handleTargetChange(watchChange1);
    final RemoteEvent remoteEvent1 = aggregator1.createRemoteEvent(
      version(1000),
    );
    await _applyRemoteEvent(remoteEvent1);

    // New message with empty resume token should not replace the old resume token
    final WatchChangeAggregator aggregator2 = WatchChangeAggregator(
      testTargetMetadataProvider,
    );
    addWatchTargets(aggregator2, <List<int>>[
      <int>[targetId],
    ]);
    final WatchChangeWatchTargetChange watchChange2 =
        WatchChangeWatchTargetChange(WatchTargetChangeType.current, <int>[
          targetId,
        ], Uint8List(0));
    aggregator2.handleTargetChange(watchChange2);
    final RemoteEvent remoteEvent2 = aggregator2.createRemoteEvent(
      version(2000),
    );
    await _applyRemoteEvent(remoteEvent2);

    // Stop listening so that the query should become inactive (but persistent)
    await _releaseQuery(_query);

    // Should come back with the same resume token
    final QueryData queryData2 = await _localStore.allocateTarget(
      _query.toTarget(),
    );
    expect(queryData2.resumeToken, _resumeToken);
  }

  @testMethod
  Future<void> testRemoteDocumentKeysForTarget() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    await _allocateQuery(query);
    _expectTargetId(2);

    await _applyRemoteEvent(
      addedRemoteEvent(doc('foo/baz', 10, map(<String>['a', 'b'])), <int>[
        2,
      ], <int>[]),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(doc('foo/bar', 20, map(<String>['a', 'b'])), <int>[
        2,
      ], <int>[]),
    );
    await _writeMutation(setMutation('foo/bonk', map(<String>['a', 'b'])));

    ImmutableSortedSet<DocumentKey> keys = await _localStore
        .getRemoteDocumentKeys(2);
    expect(keys, <DocumentKey>[key('foo/bar'), key('foo/baz')]);

    keys = await _localStore.getRemoteDocumentKeys(2);
    expect(keys, <DocumentKey>[key('foo/bar'), key('foo/baz')]);
  }

  // TODO(mrschmidt): The FieldValue.increment() field transform tests below
  //  would probably be better implemented as spec tests but currently they
  //  don't support transforms.
  // PORTING NOTE: upstream MutableDocument.setHasLocalMutations() resets the version to 0, so the
  //  documents with local mutations below are expected at version 0.
  @testMethod
  Future<void> testHandlesSetMutationThenTransformThenTransform() async {
    await _writeMutation(setMutation('foo/bar', map(<dynamic>['sum', 0])));
    await _expectContains(
      doc('foo/bar', 0, map(<dynamic>['sum', 0]), DocumentState.localMutations),
    );
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<dynamic>['sum', 0]), DocumentState.localMutations),
    ]);

    await _writeMutation(
      transformMutation(
        'foo/bar',
        map(<dynamic>['sum', FieldValue.increment(1)]),
      ),
    );
    await _expectContains(
      doc('foo/bar', 0, map(<dynamic>['sum', 1]), DocumentState.localMutations),
    );
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<dynamic>['sum', 1]), DocumentState.localMutations),
    ]);

    await _writeMutation(
      transformMutation(
        'foo/bar',
        map(<dynamic>['sum', FieldValue.increment(2)]),
      ),
    );
    await _expectContains(
      doc('foo/bar', 0, map(<dynamic>['sum', 3]), DocumentState.localMutations),
    );
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<dynamic>['sum', 3]), DocumentState.localMutations),
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
        'foo/bar',
        map(<dynamic>['sum', FieldValue.increment(2)]),
      ).fieldTransforms,
    );
    await _writeMutation(set);
    await _expectContains(
      doc(
        'foo/bar',
        0,
        map(<dynamic>['x', 1, 'sum', 2]),
        DocumentState.localMutations,
      ),
    );

    await _acknowledgeMutation(1, 2);
    await _expectContains(
      doc(
        'foo/bar',
        1,
        map(<dynamic>['x', 1, 'sum', 2]),
        DocumentState.committedMutations,
      ),
    );
  }

  @testMethod
  Future<void>
  testHandlesSetMutationThenAckThenTransformThenAckThenTransform() async {
    // Since this test doesn't start a listen, Eager GC removes the documents from the cache as
    // soon as the mutation is applied. This creates a lot of special casing in this unit test but
    // does not expand its test coverage.
    if (_garbageCollectorIsEager) {
      return;
    }

    await _writeMutation(setMutation('foo/bar', map(<dynamic>['sum', 0])));
    await _expectContains(
      doc('foo/bar', 0, map(<dynamic>['sum', 0]), DocumentState.localMutations),
    );
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<dynamic>['sum', 0]), DocumentState.localMutations),
    ]);

    await _acknowledgeMutation(1);
    _expectChanged(<Document>[
      doc(
        'foo/bar',
        1,
        map(<dynamic>['sum', 0]),
        DocumentState.committedMutations,
      ),
    ]);
    await _expectContains(
      doc(
        'foo/bar',
        1,
        map(<dynamic>['sum', 0]),
        DocumentState.committedMutations,
      ),
    );

    await _writeMutation(
      transformMutation(
        'foo/bar',
        map(<dynamic>['sum', FieldValue.increment(1)]),
      ),
    );
    await _expectContains(
      doc('foo/bar', 0, map(<dynamic>['sum', 1]), DocumentState.localMutations),
    );
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<dynamic>['sum', 1]), DocumentState.localMutations),
    ]);

    await _acknowledgeMutation(2, 1);
    _expectChanged(<Document>[
      doc(
        'foo/bar',
        2,
        map(<dynamic>['sum', 1]),
        DocumentState.committedMutations,
      ),
    ]);
    await _expectContains(
      doc(
        'foo/bar',
        2,
        map(<dynamic>['sum', 1]),
        DocumentState.committedMutations,
      ),
    );

    await _writeMutation(
      transformMutation(
        'foo/bar',
        map(<dynamic>['sum', FieldValue.increment(2)]),
      ),
    );
    await _expectContains(
      doc('foo/bar', 0, map(<dynamic>['sum', 3]), DocumentState.localMutations),
    );
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<dynamic>['sum', 3]), DocumentState.localMutations),
    ]);
  }

  @testMethod
  Future<void>
  testHandlesSetMutationThenTransformThenRemoteEventThenTransform() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    await _allocateQuery(query);
    _expectTargetId(2);

    await _writeMutation(setMutation('foo/bar', map(<dynamic>['sum', 0])));
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<dynamic>['sum', 0]), DocumentState.localMutations),
    ]);
    await _expectContains(
      doc('foo/bar', 0, map(<dynamic>['sum', 0]), DocumentState.localMutations),
    );

    await _applyRemoteEvent(
      addedRemoteEvent(doc('foo/bar', 1, map(<dynamic>['sum', 0])), <int>[
        2,
      ], <int>[]),
    );
    await _acknowledgeMutation(1);
    _expectChanged(<Document>[
      doc('foo/bar', 1, map(<dynamic>['sum', 0])),
    ]);
    await _expectContains(doc('foo/bar', 1, map(<dynamic>['sum', 0])));

    await _writeMutation(
      transformMutation(
        'foo/bar',
        map(<dynamic>['sum', FieldValue.increment(1)]),
      ),
    );
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<dynamic>['sum', 1]), DocumentState.localMutations),
    ]);
    await _expectContains(
      doc('foo/bar', 0, map(<dynamic>['sum', 1]), DocumentState.localMutations),
    );

    // The value in this remote event gets ignored since we still have a pending transform mutation.
    await _applyRemoteEvent(
      addedRemoteEvent(doc('foo/bar', 2, map(<dynamic>['sum', 1337])), <int>[
        2,
      ], <int>[]),
    );
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<dynamic>['sum', 1]), DocumentState.localMutations),
    ]);
    await _expectContains(
      doc('foo/bar', 0, map(<dynamic>['sum', 1]), DocumentState.localMutations),
    );

    // Add another increment. Note that we still compute the increment based on the local value.
    await _writeMutation(
      transformMutation(
        'foo/bar',
        map(<dynamic>['sum', FieldValue.increment(2)]),
      ),
    );
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<dynamic>['sum', 3]), DocumentState.localMutations),
    ]);
    await _expectContains(
      doc('foo/bar', 0, map(<dynamic>['sum', 3]), DocumentState.localMutations),
    );

    await _acknowledgeMutation(3, 1);
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<dynamic>['sum', 3]), DocumentState.localMutations),
    ]);
    await _expectContains(
      doc('foo/bar', 0, map(<dynamic>['sum', 3]), DocumentState.localMutations),
    );

    await _acknowledgeMutation(4, 1339);
    _expectChanged(<Document>[
      doc(
        'foo/bar',
        4,
        map(<dynamic>['sum', 1339]),
        DocumentState.committedMutations,
      ),
    ]);
    await _expectContains(
      doc(
        'foo/bar',
        4,
        map(<dynamic>['sum', 1339]),
        DocumentState.committedMutations,
      ),
    );
  }

  @testMethod
  Future<void> testHoldsBackTransforms() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    await _allocateQuery(query);
    _expectTargetId(2);

    await _writeMutation(
      setMutation(
        'foo/bar',
        map(<dynamic>['sum', 0, 'array_union', <dynamic>[]]),
      ),
    );
    _expectChanged(<Document>[
      doc(
        'foo/bar',
        0,
        map(<dynamic>['sum', 0, 'array_union', <dynamic>[]]),
        DocumentState.localMutations,
      ),
    ]);

    await _acknowledgeMutation(1);
    _expectChanged(<Document>[
      doc(
        'foo/bar',
        1,
        map(<dynamic>['sum', 0, 'array_union', <dynamic>[]]),
        DocumentState.committedMutations,
      ),
    ]);

    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('foo/bar', 1, map(<dynamic>['sum', 0, 'array_union', <dynamic>[]])),
        <int>[2],
        <int>[],
      ),
    );
    _expectChanged(<Document>[
      doc('foo/bar', 1, map(<dynamic>['sum', 0, 'array_union', <dynamic>[]])),
    ]);

    await _writeMutation(
      transformMutation(
        'foo/bar',
        map(<dynamic>['sum', FieldValue.increment(1)]),
      ),
    );
    _expectChanged(<Document>[
      doc(
        'foo/bar',
        0,
        map(<dynamic>['sum', 1, 'array_union', <dynamic>[]]),
        DocumentState.localMutations,
      ),
    ]);

    await _writeMutation(
      transformMutation(
        'foo/bar',
        map(<dynamic>[
          'array_union',
          FieldValue.arrayUnion(<String>['foo']),
        ]),
      ),
    );
    _expectChanged(<Document>[
      doc(
        'foo/bar',
        0,
        map(<dynamic>[
          'sum',
          1,
          'array_union',
          <String>['foo'],
        ]),
        DocumentState.localMutations,
      ),
    ]);

    // The sum transform and array union transform make the SDK ignore the
    // backend's updated value.
    await _applyRemoteEvent(
      addedRemoteEvent(
        doc(
          'foo/bar',
          2,
          map(<dynamic>[
            'sum',
            1337,
            'array_union',
            <String>['bar'],
          ]),
        ),
        <int>[2],
        <int>[],
      ),
    );
    _expectChanged(<Document>[
      doc(
        'foo/bar',
        0,
        map(<dynamic>[
          'sum',
          1,
          'array_union',
          <String>['foo'],
        ]),
        DocumentState.localMutations,
      ),
    ]);

    // With a field transform acknowledgement, the overlay is recalculated with
    // remaining local mutations.
    await _acknowledgeMutation(3, 1338);
    _expectChanged(<Document>[
      doc(
        'foo/bar',
        0,
        map(<dynamic>[
          'sum',
          1338,
          'array_union',
          <String>['bar', 'foo'],
        ]),
        DocumentState.localMutations,
      ),
    ]);

    await _acknowledgeMutation(4, <String>['bar', 'foo']);
    _expectChanged(<Document>[
      doc(
        'foo/bar',
        4,
        map(<dynamic>[
          'sum',
          1338,
          'array_union',
          <String>['bar', 'foo'],
        ]),
        DocumentState.committedMutations,
      ),
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
        'foo/bar',
        map(<dynamic>['sum', FieldValue.increment(1)]),
      ),
    ]);
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<dynamic>['sum', 1]), DocumentState.localMutations),
    ]);
    await _expectContains(
      doc('foo/bar', 0, map(<dynamic>['sum', 1]), DocumentState.localMutations),
    );

    await _applyRemoteEvent(
      addedRemoteEvent(doc('foo/bar', 1, map(<dynamic>['sum', 1337])), <int>[
        2,
      ], <int>[]),
    );
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<dynamic>['sum', 1]), DocumentState.localMutations),
    ]);
    await _expectContains(
      doc('foo/bar', 0, map(<dynamic>['sum', 1]), DocumentState.localMutations),
    );
  }

  @testMethod
  Future<void> testHandlesPatchMutationWithTransformThenRemoteEvent() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    await _allocateQuery(query);
    _expectTargetId(2);

    await _writeMutations(<Mutation>[
      patchMutation('foo/bar', map()),
      transformMutation(
        'foo/bar',
        map(<dynamic>['sum', FieldValue.increment(1)]),
      ),
    ]);
    _expectChanged(<NoDocument>[deletedDoc('foo/bar', 0)]);
    await _expectNotContains('foo/bar');

    // Note: This test reflects the current behavior, but it may be preferable to replay the
    // mutation once we receive the first value from the remote event.

    await _applyRemoteEvent(
      addedRemoteEvent(doc('foo/bar', 1, map(<dynamic>['sum', 1337])), <int>[
        2,
      ], <int>[]),
    );
    _expectChanged(<Document>[
      doc('foo/bar', 0, map(<dynamic>['sum', 1]), DocumentState.localMutations),
    ]);
    await _expectContains(
      doc('foo/bar', 0, map(<dynamic>['sum', 1]), DocumentState.localMutations),
    );
  }

  Future<void> _writeMutation(Mutation mutation) async {
    await _writeMutations(<Mutation>[mutation]);
  }

  Future<void> _writeMutations(List<Mutation> mutations) async {
    final LocalWriteResult result = await _localStore.writeLocally(mutations);
    _batches.add(
      MutationBatch(
        batchId: result.batchId,
        localWriteTime: Timestamp.now(),
        baseMutations: <Mutation>[],
        mutations: mutations,
      ),
    );
    _lastChanges = result.changes;
  }

  Future<void> _applyRemoteEvent(RemoteEvent event) async {
    _lastChanges = await _localStore.applyRemoteEvent(event);
  }

  Future<void> _notifyLocalViewChanges(LocalViewChanges changes) async {
    await _localStore.notifyLocalViewChanges(<LocalViewChanges>[changes]);
  }

  Future<void> _acknowledgeMutation(
    int documentVersion, [
    Object? transformResult,
  ]) async {
    final MutationBatch batch = _batches.removeAt(0);
    final SnapshotVersion _version = version(documentVersion);
    final MutationResult mutationResult = MutationResult(
      _version,
      transformResult != null
          ? <model.FieldValue>[wrap(transformResult)]
          : <model.FieldValue>[],
    );
    final MutationBatchResult result = MutationBatchResult.create(
      batch,
      _version,
      <MutationResult>[mutationResult],
      Uint8List(0),
    );
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
    final Query limitToLast = query(
      'foo',
    ).orderBy(orderBy('sort', 'desc')).limitToLast(2);

    final QueryData first = await _localStore.allocateTarget(limit.toTarget());
    final QueryData second = await _localStore.allocateTarget(
      limitToLast.toTarget(),
    );
    expect(second.targetId, first.targetId);
    expect(second.target, first.target);

    // The cache is keyed by target, so both queries find the same entry.
    final QueryData? byLimit = await _persistence.queryCache.getQueryData(
      limit.toTarget(),
    );
    final QueryData? byLimitToLast = await _persistence.queryCache.getQueryData(
      limitToLast.toTarget(),
    );
    expect(byLimit, isNotNull);
    expect(byLimit!.targetId, first.targetId);
    expect(byLimitToLast!.targetId, first.targetId);

    // A limitToLast query with the same ordering as the limit query is a
    // different target.
    final Query other = query('foo').orderBy(orderBy('sort')).limitToLast(2);
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
        (await _localStore.executeQuery(
          q,
          /* usePreviousResults= */ true,
        )).documents;
    expect(docs.length, 3);
  }

  @testMethod
  Future<void> testReadsAllDocumentsForInitialCollectionQueries() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    await _allocateQuery(query);

    await _applyRemoteEvent(
      updateRemoteEvent(doc('foo/baz', 10, map()), <int>[2], <int>[]),
    );
    await _applyRemoteEvent(
      updateRemoteEvent(doc('foo/bar', 20, map()), <int>[2], <int>[]),
    );
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
    final Query query = Query(
      ResourcePath.fromString('foo'),
    ).filter(filter('matches', '==', true));
    final int targetId = await _allocateQuery(query);

    await _writeMutation(setMutation('foo/a', map(<dynamic>['matches', true])));
    await _writeMutation(setMutation('foo/b', map(<dynamic>['matches', true])));
    await _writeMutation(
      setMutation('foo/ignored', map(<dynamic>['matches', false])),
    );
    await _acknowledgeMutation(10);
    await _acknowledgeMutation(10);
    await _acknowledgeMutation(10);

    // Execute the query, but note that we read all existing documents from the RemoteDocumentCache since we do not
    // yet have target mapping.
    await _executeQuery(query);
    _expectRemoteDocumentsReadByEngine(byKey: 0, byQuery: 2);

    // Issue a RemoteEvent to persist the target mapping.
    await _applyRemoteEvent(
      _addedRemoteEvents(
        <MaybeDocument>[
          doc('foo/a', 10, map(<dynamic>['matches', true])),
          doc('foo/b', 10, map(<dynamic>['matches', true])),
        ],
        <int>[targetId],
      ),
    );
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
    final Query query = Query(
      ResourcePath.fromString('foo'),
    ).filter(filter('matches', '==', true));
    final int targetId = await _allocateQuery(query);

    await _applyRemoteEvent(
      _addedRemoteEvents(
        <MaybeDocument>[
          doc('foo/a', 10, map(<dynamic>['matches', true])),
        ],
        <int>[targetId],
      ),
    );
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
    final Query filteredQuery = Query(
      ResourcePath.fromString('foo'),
    ).filter(filter('matches', '==', true));
    int targetId = await _allocateQuery(filteredQuery);

    await _applyRemoteEvent(
      _addedRemoteEvents(
        <MaybeDocument>[
          doc('foo/a', 10, map(<dynamic>['matches', true])),
        ],
        <int>[targetId],
      ),
    );
    await _applyRemoteEvent(_noChangeEvent(targetId, 10));
    await _updateViews(targetId, fromCache: false);
    await _localStore.releaseTarget(targetId);

    // Start another query and add more matching documents to the collection.
    final Query fullQuery = Query(ResourcePath.fromString('foo'));
    targetId = await _allocateQuery(fullQuery);
    await _applyRemoteEvent(
      _addedRemoteEvents(
        <MaybeDocument>[
          doc('foo/a', 10, map(<dynamic>['matches', true])),
          doc('foo/b', 20, map(<dynamic>['matches', true])),
        ],
        <int>[targetId],
      ),
    );
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
    final Query filteredQuery = Query(
      ResourcePath.fromString('foo'),
    ).filter(filter('matches', '==', true));
    int targetId = await _allocateQuery(filteredQuery);

    await _applyRemoteEvent(
      _addedRemoteEvents(
        <MaybeDocument>[
          doc('foo/a', 10, map(<dynamic>['matches', true])),
          doc('foo/b', 10, map(<dynamic>['matches', true])),
        ],
        <int>[targetId],
      ),
    );
    await _applyRemoteEvent(_noChangeEvent(targetId, 10));
    await _updateViews(targetId, fromCache: false);
    await _localStore.releaseTarget(targetId);

    // Modify one of the documents to no longer match while the filtered query is inactive.
    final Query fullQuery = Query(ResourcePath.fromString('foo'));
    targetId = await _allocateQuery(fullQuery);
    await _applyRemoteEvent(
      _addedRemoteEvents(
        <MaybeDocument>[
          doc('foo/a', 10, map(<dynamic>['matches', true])),
          doc('foo/b', 20, map(<dynamic>['matches', false])),
        ],
        <int>[targetId],
      ),
    );
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
    final Query filteredQuery = Query(
      ResourcePath.fromString('foo'),
    ).filter(filter('matches', '==', true));
    final int targetId = await _allocateQuery(filteredQuery);

    await _applyRemoteEvent(
      _addedRemoteEvents(
        <MaybeDocument>[
          doc('foo/a', 10, map(<dynamic>['matches', true])),
        ],
        <int>[targetId],
      ),
    );
    await _applyRemoteEvent(_noChangeEvent(targetId, 10));
    await _updateViews(targetId, fromCache: false);
    await _localStore.releaseTarget(targetId);

    final Document bundled = doc('foo/b', 5, map(<dynamic>['matches', true]));
    await _localStore.applyBundledDocuments(
      ImmutableSortedMap<DocumentKey, MaybeDocument>.emptyMap(
        DocumentKey.comparator,
      ).insert(bundled.key, bundled),
      'bundle',
      readTimes: <DocumentKey, SnapshotVersion>{bundled.key: version(20)},
    );

    await _allocateQuery(filteredQuery);
    await _executeQuery(filteredQuery);
    _expectQueryReturned(<String>['foo/a', 'foo/b']);
  }

  @testMethod
  Future<void> testIgnoresTargetMappingAfterExistenceFilterMismatch() async {
    if (_garbageCollectorIsEager) {
      return;
    }

    final Query query = Query(
      ResourcePath.fromString('foo'),
    ).filter(filter('matches', '==', true));
    final int targetId = await _allocateQuery(query);
    final Target target = query.toTarget();

    await _executeQuery(query);

    // Persist a mapping with a single document
    await _applyRemoteEvent(
      addedRemoteEvent(doc('foo/a', 10, map(<dynamic>['matches', true])), <int>[
        targetId,
      ], <int>[]),
    );
    await _applyRemoteEvent(_noChangeEvent(targetId, 10));
    await _updateViews(targetId, fromCache: false);

    QueryData cachedTargetData = (await _localStore.getQueryData(target))!;
    expect(cachedTargetData.lastLimboFreeSnapshotVersion, version(10));

    // Create an existence filter mismatch and verify that the last limbo free snapshot version
    // is deleted
    await _applyRemoteEvent(
      _existenceFilterEvent(
        targetId,
        keySet(<DocumentKey>[key('foo/a')]),
        2,
        20,
      ),
    );
    cachedTargetData = (await _localStore.getQueryData(target))!;
    expect(cachedTargetData.lastLimboFreeSnapshotVersion, version(0));
    expect(cachedTargetData.resumeToken, isEmpty);

    // Re-run the query as a collection scan
    await _executeQuery(query);
    _expectRemoteDocumentsReadByEngine(byKey: 0, byQuery: 1);
    _expectQueryReturned(<String>['foo/a']);
  }

  @testMethod
  Future<void> testWritesOverlaysAndRemovesThemOnAck() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    final int targetId = await _allocateQuery(query);
    await _applyRemoteEvent(
      _addedRemoteEvents(
        <MaybeDocument>[
          doc('foo/remote', 1, map(<dynamic>['a', 1])),
        ],
        <int>[targetId],
      ),
    );

    await _writeMutation(setMutation('foo/local', map(<dynamic>['a', 1])));
    await _writeMutation(patchMutation('foo/remote', map(<dynamic>['b', 2])));

    // A document without remote version gets a set overlay, a patched remote document a patch overlay.
    expect(
      await _overlay('foo/local'),
      Overlay(1, setMutation('foo/local', map(<dynamic>['a', 1]))),
    );
    final Overlay remoteOverlay = (await _overlay('foo/remote'))!;
    expect(remoteOverlay.largestBatchId, 2);
    expect(remoteOverlay.mutation, isA<PatchMutation>());

    await _acknowledgeMutation(2);
    expect(await _overlay('foo/local'), isNull);
    expect(await _overlay('foo/remote'), isNotNull);

    await _acknowledgeMutation(3);
    expect(await _overlay('foo/remote'), isNull);
  }

  /// DEVIATION FROM UPSTREAM (removeOverlays): recalculating a document whose pending mutations no longer apply
  /// removes its overlay. Upstream only saves the overlays that exist after a recalculation and keeps the old one.
  @testMethod
  Future<void> testDeviationRejectRemovesOverlayThatNoLongerApplies() async {
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

  /// DEVIATION FROM UPSTREAM (removeOverlays), see [testDeviationRejectRemovesOverlayThatNoLongerApplies]: without the
  /// removal the stale patch overlay (which has no precondition) brings the remotely deleted document back on the
  /// next read.
  @testMethod
  Future<void> testDeviationRemoteDeleteRemovesPatchOverlay() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    final int targetId = await _allocateQuery(query);
    await _applyRemoteEvent(
      _addedRemoteEvents(
        <MaybeDocument>[
          doc('foo/bar', 1, map(<dynamic>['a', 1])),
        ],
        <int>[targetId],
      ),
    );
    await _writeMutation(patchMutation('foo/bar', map(<dynamic>['b', 2])));
    expect((await _overlay('foo/bar'))!.mutation, isA<PatchMutation>());

    // The document is deleted remotely: the pending update no longer applies (its precondition fails), so the
    // document must not come back from its old patch overlay.
    await _applyRemoteEvent(
      updateRemoteEvent(deletedDoc('foo/bar', 2), <int>[targetId], <int>[]),
    );
    _expectChanged(<MaybeDocument>[deletedDoc('foo/bar', 2)]);
    expect(await _overlay('foo/bar'), isNull);
    await _expectContains(deletedDoc('foo/bar', 2));
  }

  /// DEVIATION FROM UPSTREAM (empty patch mask): a merge of no fields keeps an overlay, so the document it creates (or
  /// the pending write state it sets) survives the next read. Upstream calculates no overlay for an empty mask.
  @testMethod
  Future<void> testDeviationEmptyMergeKeepsItsOverlay() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    final int targetId = await _allocateQuery(query);
    await _applyRemoteEvent(
      updateRemoteEvent(deletedDoc('foo/deleted', 1), <int>[targetId], <int>[]),
    );
    await _applyRemoteEvent(
      _addedRemoteEvents(
        <MaybeDocument>[
          doc('foo/existing', 1, map(<dynamic>['x', 1])),
        ],
        <int>[targetId],
      ),
    );

    // set({}, merge: true) on a document that is cached as deleted and on one that exists.
    await _writeMutation(patchMutation('foo/deleted', map(), <FieldPath>[]));
    await _writeMutation(patchMutation('foo/existing', map(), <FieldPath>[]));

    final Mutation existingOverlay = (await _overlay('foo/existing'))!.mutation;
    expect(existingOverlay, isA<PatchMutation>());
    expect((existingOverlay as PatchMutation).mask.mask, isEmpty);
    if (!_garbageCollectorIsEager) {
      // (The eager collector does not keep the deleted document, and a document without remote version gets a set
      // overlay.)
      final Mutation deletedOverlay = (await _overlay('foo/deleted'))!.mutation;
      expect(deletedOverlay, isA<PatchMutation>());
      expect((deletedOverlay as PatchMutation).mask.mask, isEmpty);
    }
    await _expectContains(
      doc('foo/deleted', 0, map(), DocumentState.localMutations),
    );
    await _expectContains(
      doc(
        'foo/existing',
        0,
        map(<dynamic>['x', 1]),
        DocumentState.localMutations,
      ),
    );

    // The overlay is a patch, so the document picks up the remote fields when it appears on the backend.
    await _applyRemoteEvent(
      _addedRemoteEvents(
        <MaybeDocument>[
          doc('foo/deleted', 2, map(<dynamic>['y', 2])),
        ],
        <int>[targetId],
      ),
    );
    await _expectContains(
      doc(
        'foo/deleted',
        0,
        map(<dynamic>['y', 2]),
        DocumentState.localMutations,
      ),
    );
  }

  /// DEVIATION FROM UPSTREAM (set overlay of a merge): a merge on a document without remote version is stored as a set
  /// overlay. When the document arrives from the backend the overlay is recalculated, so the remote fields the merge
  /// does not touch show up (as when replaying the mutation queue). Upstream keeps applying the set overlay.
  @testMethod
  Future<void>
  testDeviationSetOverlayOfMergeIsRecalculatedWhenDocumentArrives() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    final int targetId = await _allocateQuery(query);

    await _writeMutation(
      patchMutation('foo/bar', map(<dynamic>['a', 1]), <FieldPath>[field('a')]),
    );
    expect((await _overlay('foo/bar'))!.mutation, isA<SetMutation>());
    await _expectContains(
      doc('foo/bar', 0, map(<dynamic>['a', 1]), DocumentState.localMutations),
    );

    await _applyRemoteEvent(
      _addedRemoteEvents(
        <MaybeDocument>[
          doc('foo/bar', 1, map(<dynamic>['x', 1])),
        ],
        <int>[targetId],
      ),
    );
    _expectChanged(<Document>[
      doc(
        'foo/bar',
        0,
        map(<dynamic>['a', 1, 'x', 1]),
        DocumentState.localMutations,
      ),
    ]);
    await _expectContains(
      doc(
        'foo/bar',
        0,
        map(<dynamic>['a', 1, 'x', 1]),
        DocumentState.localMutations,
      ),
    );
    expect((await _overlay('foo/bar'))!.mutation, isA<PatchMutation>());
  }

  /// A side effect of the deviation above: the set overlay of a plain set (`add` / `set` with
  /// `FieldValue.serverTimestamp()`) on a document without remote version is recalculated as well when watch sends
  /// the document before the acknowledgement. The pending write is applied again on top of watch's document, so its
  /// sentinel now records the backend's timestamp as its previous value: the local view changes and the view raises
  /// a `modified` event with pending writes (seen against the emulator as three events for one `add`). Upstream keeps
  /// applying the stored set overlay (JS local_documents_view.ts, `existenceStateChanged.has(doc.key) && (overlay ===
  /// undefined || overlay.mutation instanceof PatchMutation)`), whose data does not change: two events.
  @testMethod
  Future<void>
  testDeviationSetOverlayWithServerTimestampIsRecalculatedWhenDocumentArrives() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    final int targetId = await _allocateQuery(query);

    await _writeMutation(
      UserDataConverter(DatabaseId.forProject('project'))
          .parseSetData(<String, Object?>{
            'a': 1,
            't': FieldValue.serverTimestamp(),
          })
          .toMutation(key('foo/bar'), Precondition.none),
    );
    expect((await _overlay('foo/bar'))!.mutation, isA<SetMutation>());
    final Document written =
        (await _localStore.readDocument(key('foo/bar')))! as Document;
    final model.ServerTimestampValue before =
        written.getField(field('t'))! as model.ServerTimestampValue;
    expect(before.previousFieldValue, isNull);

    // Watch sends the document, with the timestamp the backend set, before the acknowledgement.
    final Timestamp serverTime = Timestamp(1700000000, 200000000);
    await _applyRemoteEvent(
      _addedRemoteEvents(
        <MaybeDocument>[
          doc('foo/bar', 1, map(<dynamic>['a', 1, 't', serverTime])),
        ],
        <int>[targetId],
      ),
    );
    final Document rebased =
        (await _localStore.readDocument(key('foo/bar')))! as Document;
    expect(rebased.hasLocalMutations, isTrue);
    final model.ServerTimestampValue after =
        rebased.getField(field('t'))! as model.ServerTimestampValue;
    expect(after.localWriteTime, before.localWriteTime);
    // Upstream: still null, and rebased.data == written.data.
    expect(after.previousValue, serverTime);
    expect(rebased.data == written.data, isFalse);
  }

  Future<Overlay?> _overlay(String path) {
    return _persistence
        .getDocumentOverlayCache(User.unauthenticated)
        .getOverlay(key(path));
  }

  Future<void> _executeQuery(Query query) async {
    _resetPersistenceStats();
    _lastQueryResult = await _localStore.executeQuery(
      query,
      /* usePreviousResults= */ true,
    );
  }

  Future<void> _updateViews(int targetId, {required bool fromCache}) {
    return _notifyLocalViewChanges(
      viewChanges(targetId, fromCache, <String>[], <String>[]),
    );
  }

  RemoteEvent _noChangeEvent(int targetId, int theVersion) {
    final t.TestTargetMetadataProvider provider = t.testTargetMetadataProvider;
    provider.setSyncedKeys(
      queryData(targetId, QueryPurpose.listen, 'foo/bar'),
      DocumentKey.emptyKeySet,
    );
    final WatchChangeAggregator aggregator = WatchChangeAggregator(provider);
    addWatchTargets(aggregator, <List<int>>[
      <int>[targetId],
    ]);
    aggregator.handleTargetChange(
      WatchChangeWatchTargetChange(WatchTargetChangeType.noChange, <int>[
        targetId,
      ], resumeToken(theVersion)),
    );
    return aggregator.createRemoteEvent(version(theVersion));
  }

  RemoteEvent _existenceFilterEvent(
    int targetId,
    ImmutableSortedSet<DocumentKey> syncedKeys,
    int remoteCount,
    int theVersion,
  ) {
    final t.TestTargetMetadataProvider provider = t.testTargetMetadataProvider;
    provider.setSyncedKeys(
      queryData(targetId, QueryPurpose.listen, 'foo'),
      syncedKeys,
    );
    final WatchChangeAggregator aggregator = WatchChangeAggregator(provider);
    addWatchTargets(aggregator, <List<int>>[
      <int>[targetId],
    ]);
    aggregator.handleExistenceFilter(
      WatchChangeExistenceFilterWatchChange(
        targetId,
        ExistenceFilter(remoteCount),
      ),
    );
    return aggregator.createRemoteEvent(version(theVersion));
  }

  // JS: local_store_indexeddb.test.ts, "Indexes BSON ObjectId fields".
  @testMethod
  Future<void> testJsIndexesBSONObjectIdFields() async {
    final FieldIndex index = fieldIndex(
      'coll',
      indexId: 0,
      indexState: FieldIndex.initialState,
      fieldsAndKinds: <Object>['key', SegmentKind.ascending],
    );
    await _configureFieldIndexes(<FieldIndex>[index]);
    await _writeMutation(
      setMutation(
        'coll/a',
        map(<dynamic>['key', BsonObjectId('507f191e810c19729de860ea')]),
      ),
    );
    await _writeMutation(
      setMutation(
        'coll/b',
        map(<dynamic>['key', BsonObjectId('507f191e810c19729de860eb')]),
      ),
    );
    await _writeMutation(
      setMutation(
        'coll/c',
        map(<dynamic>['key', BsonObjectId('507f191e810c19729de860ec')]),
      ),
    );
    await _backfillIndexes();
    Query qry = query('coll').orderBy(orderBy('key', 'asc'));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 3, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/a': OverlayType.set,
      'coll/b': OverlayType.set,
      'coll/c': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>['coll/a', 'coll/b', 'coll/c']);
    qry = query(
      'coll',
    ).filter(filter('key', '==', BsonObjectId('507f191e810c19729de860ea')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 1, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{'coll/a': OverlayType.set});
    _expectQueryReturnedInOrder(qry, <String>['coll/a']);
    qry = query(
      'coll',
    ).filter(filter('key', '!=', BsonObjectId('507f191e810c19729de860ea')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/b': OverlayType.set,
      'coll/c': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>['coll/b', 'coll/c']);
    qry = query(
      'coll',
    ).filter(filter('key', '>=', BsonObjectId('507f191e810c19729de860eb')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/b': OverlayType.set,
      'coll/c': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>['coll/b', 'coll/c']);
    qry = query(
      'coll',
    ).filter(filter('key', '<', BsonObjectId('507f191e810c19729de860ea')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 0, byCollection: 0);
    _expectQueryReturnedInOrder(qry, <String>[]);
    qry = query('coll').filter(
      filter('key', 'in', <Object?>[
        BsonObjectId('507f191e810c19729de860ea'),
        BsonObjectId('507f191e810c19729de860eb'),
      ]),
    );
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/a': OverlayType.set,
      'coll/b': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>['coll/a', 'coll/b']);
    qry = query('coll').filter(
      filter('key', 'not-in', <Object?>[
        BsonObjectId('507f191e810c19729de860ea'),
        BsonObjectId('507f191e810c19729de860eb'),
      ]),
    );
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 1, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{'coll/c': OverlayType.set});
    _expectQueryReturnedInOrder(qry, <String>['coll/c']);
  }

  // JS: local_store_indexeddb.test.ts, "Indexes BSON Timestamp fields".
  @testMethod
  Future<void> testJsIndexesBSONTimestampFields() async {
    final FieldIndex index = fieldIndex(
      'coll',
      indexId: 0,
      indexState: FieldIndex.initialState,
      fieldsAndKinds: <Object>['key', SegmentKind.ascending],
    );
    await _configureFieldIndexes(<FieldIndex>[index]);
    await _writeMutation(
      setMutation('coll/a', map(<dynamic>['key', BsonTimestamp(1000, 1000)])),
    );
    await _writeMutation(
      setMutation('coll/b', map(<dynamic>['key', BsonTimestamp(1001, 1000)])),
    );
    await _writeMutation(
      setMutation('coll/c', map(<dynamic>['key', BsonTimestamp(1000, 1001)])),
    );
    await _backfillIndexes();
    Query qry = query('coll').orderBy(orderBy('key', 'asc'));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 3, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/a': OverlayType.set,
      'coll/b': OverlayType.set,
      'coll/c': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>['coll/a', 'coll/c', 'coll/b']);
    qry = query('coll').filter(filter('key', '==', BsonTimestamp(1000, 1000)));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 1, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{'coll/a': OverlayType.set});
    _expectQueryReturnedInOrder(qry, <String>['coll/a']);
    qry = query('coll').filter(filter('key', '!=', BsonTimestamp(1000, 1000)));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/b': OverlayType.set,
      'coll/c': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>['coll/c', 'coll/b']);
    qry = query('coll').filter(filter('key', '>=', BsonTimestamp(1000, 1001)));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/b': OverlayType.set,
      'coll/c': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>['coll/c', 'coll/b']);
    qry = query('coll').filter(filter('key', '<', BsonTimestamp(1000, 1000)));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 0, byCollection: 0);
    _expectQueryReturnedInOrder(qry, <String>[]);
    qry = query('coll').filter(
      filter('key', 'in', <Object?>[
        BsonTimestamp(1000, 1000),
        BsonTimestamp(1001, 1000),
      ]),
    );
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/a': OverlayType.set,
      'coll/b': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>['coll/a', 'coll/b']);
    qry = query('coll').filter(
      filter('key', 'not-in', <Object?>[
        BsonTimestamp(1000, 1000),
        BsonTimestamp(1001, 1000),
      ]),
    );
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 1, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{'coll/c': OverlayType.set});
    _expectQueryReturnedInOrder(qry, <String>['coll/c']);
  }

  // JS: local_store_indexeddb.test.ts, "Indexes BSON Binary Data fields".
  @testMethod
  Future<void> testJsIndexesBSONBinaryDataFields() async {
    final FieldIndex index = fieldIndex(
      'coll',
      indexId: 0,
      indexState: FieldIndex.initialState,
      fieldsAndKinds: <Object>['key', SegmentKind.ascending],
    );
    await _configureFieldIndexes(<FieldIndex>[index]);
    await _writeMutation(
      setMutation(
        'coll/a',
        map(<dynamic>[
          'key',
          Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2, 3])),
        ]),
      ),
    );
    await _writeMutation(
      setMutation(
        'coll/b',
        map(<dynamic>[
          'key',
          Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2])),
        ]),
      ),
    );
    await _writeMutation(
      setMutation(
        'coll/c',
        map(<dynamic>[
          'key',
          Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2, 4])),
        ]),
      ),
    );
    await _writeMutation(
      setMutation(
        'coll/d',
        map(<dynamic>[
          'key',
          Blob.bsonBinary(2, Uint8List.fromList(<int>[1, 2])),
        ]),
      ),
    );
    await _backfillIndexes();
    Query qry = query('coll').orderBy(orderBy('key', 'asc'));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 4, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/a': OverlayType.set,
      'coll/b': OverlayType.set,
      'coll/c': OverlayType.set,
      'coll/d': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>[
      'coll/b',
      'coll/a',
      'coll/c',
      'coll/d',
    ]);
    qry = query('coll').filter(
      filter(
        'key',
        '==',
        Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2, 3])),
      ),
    );
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 1, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{'coll/a': OverlayType.set});
    _expectQueryReturnedInOrder(qry, <String>['coll/a']);
    qry = query('coll').filter(
      filter(
        'key',
        '!=',
        Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2, 3])),
      ),
    );
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 3, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/b': OverlayType.set,
      'coll/c': OverlayType.set,
      'coll/d': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>['coll/b', 'coll/c', 'coll/d']);
    qry = query('coll').filter(
      filter(
        'key',
        '>=',
        Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2, 3])),
      ),
    );
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 3, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/a': OverlayType.set,
      'coll/c': OverlayType.set,
      'coll/d': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>['coll/a', 'coll/c', 'coll/d']);
    qry = query('coll').filter(
      filter('key', '<', Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2]))),
    );
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 0, byCollection: 0);
    _expectQueryReturnedInOrder(qry, <String>[]);
    qry = query('coll').filter(
      filter('key', 'in', <Object?>[
        Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2, 3])),
        Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2])),
      ]),
    );
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/a': OverlayType.set,
      'coll/b': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>['coll/a', 'coll/b']);
    qry = query('coll').filter(
      filter('key', 'not-in', <Object?>[
        Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2, 3])),
        Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2])),
      ]),
    );
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/c': OverlayType.set,
      'coll/d': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>['coll/c', 'coll/d']);
  }

  // JS: local_store_indexeddb.test.ts, "Indexes BSON Int32 fields".
  @testMethod
  Future<void> testJsIndexesBSONInt32Fields() async {
    final FieldIndex index = fieldIndex(
      'coll',
      indexId: 0,
      indexState: FieldIndex.initialState,
      fieldsAndKinds: <Object>['key', SegmentKind.ascending],
    );
    await _configureFieldIndexes(<FieldIndex>[index]);
    await _writeMutation(
      setMutation('coll/a', map(<dynamic>['key', Int32Value(-1)])),
    );
    await _writeMutation(
      setMutation('coll/b', map(<dynamic>['key', Int32Value(0)])),
    );
    await _writeMutation(
      setMutation('coll/c', map(<dynamic>['key', Int32Value(1)])),
    );
    await _backfillIndexes();
    Query qry = query('coll').orderBy(orderBy('key', 'asc'));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 3, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/a': OverlayType.set,
      'coll/b': OverlayType.set,
      'coll/c': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>['coll/a', 'coll/b', 'coll/c']);
    qry = query('coll').filter(filter('key', '==', Int32Value(0)));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 1, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{'coll/b': OverlayType.set});
    _expectQueryReturnedInOrder(qry, <String>['coll/b']);
    qry = query('coll').filter(filter('key', '!=', Int32Value(0)));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/a': OverlayType.set,
      'coll/c': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>['coll/a', 'coll/c']);
    qry = query('coll').filter(filter('key', '>=', Int32Value(0)));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/b': OverlayType.set,
      'coll/c': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>['coll/b', 'coll/c']);
    qry = query('coll').filter(filter('key', '<', Int32Value(-1)));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 0, byCollection: 0);
    _expectQueryReturnedInOrder(qry, <String>[]);
    qry = query(
      'coll',
    ).filter(filter('key', 'in', <Object?>[Int32Value(0), Int32Value(1)]));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/b': OverlayType.set,
      'coll/c': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>['coll/b', 'coll/c']);
    qry = query(
      'coll',
    ).filter(filter('key', 'not-in', <Object?>[Int32Value(0), Int32Value(1)]));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 1, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{'coll/a': OverlayType.set});
    _expectQueryReturnedInOrder(qry, <String>['coll/a']);
  }

  // JS: local_store_indexeddb.test.ts, "Indexes BSON Decimal128 fields".
  @testMethod
  Future<void> testJsIndexesBSONDecimal128Fields() async {
    final FieldIndex index = fieldIndex(
      'coll',
      indexId: 0,
      indexState: FieldIndex.initialState,
      fieldsAndKinds: <Object>['key', SegmentKind.ascending],
    );
    await _configureFieldIndexes(<FieldIndex>[index]);
    await _writeMutation(
      setMutation('coll/a', map(<dynamic>['key', Decimal128Value('-1.2e3')])),
    );
    await _writeMutation(
      setMutation('coll/b', map(<dynamic>['key', Decimal128Value('0')])),
    );
    await _writeMutation(
      setMutation('coll/c', map(<dynamic>['key', Decimal128Value('1.2e3')])),
    );
    await _backfillIndexes();
    Query qry = query('coll').orderBy(orderBy('key', 'asc'));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 3, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/a': OverlayType.set,
      'coll/b': OverlayType.set,
      'coll/c': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>['coll/a', 'coll/b', 'coll/c']);
    qry = query('coll').filter(filter('key', '==', Decimal128Value('-1200')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 1, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{'coll/a': OverlayType.set});
    _expectQueryReturnedInOrder(qry, <String>['coll/a']);
    qry = query('coll').filter(filter('key', '!=', Decimal128Value('0.0')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/a': OverlayType.set,
      'coll/c': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>['coll/a', 'coll/c']);
    qry = query('coll').filter(filter('key', '>=', Decimal128Value('-0')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/b': OverlayType.set,
      'coll/c': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>['coll/b', 'coll/c']);
    qry = query('coll').filter(filter('key', '<=', Decimal128Value('-0.0')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/a': OverlayType.set,
      'coll/b': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>['coll/a', 'coll/b']);
    qry = query('coll').filter(filter('key', '>', Decimal128Value('1.2e3')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 0, byCollection: 0);
    _expectQueryReturnedInOrder(qry, <String>[]);
    qry = query('coll').filter(filter('key', '<', Decimal128Value('-1.2e3')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 0, byCollection: 0);
    _expectQueryReturnedInOrder(qry, <String>[]);
    qry = query('coll').filter(
      filter('key', 'in', <Object?>[
        Decimal128Value('-1.2e3'),
        Decimal128Value('0'),
      ]),
    );
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/a': OverlayType.set,
      'coll/b': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>['coll/a', 'coll/b']);
    qry = query('coll').filter(
      filter('key', 'not-in', <Object?>[
        Decimal128Value('-1200'),
        Decimal128Value('0.0'),
      ]),
    );
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 1, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{'coll/c': OverlayType.set});
    _expectQueryReturnedInOrder(qry, <String>['coll/c']);
  }

  // JS: local_store_indexeddb.test.ts, "Indexes BSON Decimal128 fields with precision loss".
  @testMethod
  Future<void> testJsIndexesBSONDecimal128FieldsWithPrecisionLoss() async {
    final FieldIndex index = fieldIndex(
      'coll',
      indexId: 0,
      indexState: FieldIndex.initialState,
      fieldsAndKinds: <Object>['key', SegmentKind.ascending],
    );
    await _configureFieldIndexes(<FieldIndex>[index]);
    await _writeMutation(
      setMutation(
        'coll/a',
        map(<dynamic>['key', Decimal128Value('-0.1234567890123456789')]),
      ),
    );
    await _writeMutation(
      setMutation('coll/b', map(<dynamic>['key', Decimal128Value('0')])),
    );
    await _writeMutation(
      setMutation(
        'coll/c',
        map(<dynamic>['key', Decimal128Value('0.1234567890123456789')]),
      ),
    );
    await _backfillIndexes();
    Query qry = query('coll').orderBy(orderBy('key', 'asc'));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 3, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/a': OverlayType.set,
      'coll/b': OverlayType.set,
      'coll/c': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>['coll/a', 'coll/b', 'coll/c']);
    qry = query(
      'coll',
    ).filter(filter('key', '==', Decimal128Value('0.1234567890123456789')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 1, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{'coll/c': OverlayType.set});
    _expectQueryReturnedInOrder(qry, <String>['coll/c']);
    qry = query(
      'coll',
    ).filter(filter('key', '==', Decimal128Value('0.12345678901234568')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 1, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{'coll/c': OverlayType.set});
    _expectQueryReturnedInOrder(qry, <String>[]);
    qry = query('coll').filter(filter('key', '!=', Decimal128Value('0.0')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/a': OverlayType.set,
      'coll/c': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>['coll/a', 'coll/c']);
    qry = query('coll').filter(filter('key', '>=', Decimal128Value('1.23e-1')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 1, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{'coll/c': OverlayType.set});
    _expectQueryReturnedInOrder(qry, <String>['coll/c']);
    qry = query(
      'coll',
    ).filter(filter('key', '<=', Decimal128Value('-1.23e-1')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 1, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{'coll/a': OverlayType.set});
    _expectQueryReturnedInOrder(qry, <String>['coll/a']);
    qry = query('coll').filter(filter('key', '>', Decimal128Value('1.2e3')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 0, byCollection: 0);
    _expectQueryReturnedInOrder(qry, <String>[]);
    qry = query('coll').filter(filter('key', '<', Decimal128Value('-1.2e3')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 0, byCollection: 0);
    _expectQueryReturnedInOrder(qry, <String>[]);
  }

  // JS: local_store_indexeddb.test.ts, "Indexes BSON Regex fields".
  @testMethod
  Future<void> testJsIndexesBSONRegexFields() async {
    final FieldIndex index = fieldIndex(
      'coll',
      indexId: 0,
      indexState: FieldIndex.initialState,
      fieldsAndKinds: <Object>['key', SegmentKind.ascending],
    );
    await _configureFieldIndexes(<FieldIndex>[index]);
    await _writeMutation(
      setMutation('coll/a', map(<dynamic>['key', RegexValue('a', 'i')])),
    );
    await _writeMutation(
      setMutation('coll/b', map(<dynamic>['key', RegexValue('a', 'm')])),
    );
    await _writeMutation(
      setMutation('coll/c', map(<dynamic>['key', RegexValue('b', 'i')])),
    );
    await _backfillIndexes();
    Query qry = query('coll').orderBy(orderBy('key', 'asc'));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 3, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/a': OverlayType.set,
      'coll/b': OverlayType.set,
      'coll/c': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>['coll/a', 'coll/b', 'coll/c']);
    qry = query('coll').filter(filter('key', '==', RegexValue('a', 'i')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 1, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{'coll/a': OverlayType.set});
    _expectQueryReturnedInOrder(qry, <String>['coll/a']);
    qry = query('coll').filter(filter('key', '!=', RegexValue('a', 'i')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/b': OverlayType.set,
      'coll/c': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>['coll/b', 'coll/c']);
    qry = query('coll').filter(filter('key', '>=', RegexValue('a', 'm')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/b': OverlayType.set,
      'coll/c': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>['coll/b', 'coll/c']);
    qry = query('coll').filter(filter('key', '<', RegexValue('a', 'i')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 0, byCollection: 0);
    _expectQueryReturnedInOrder(qry, <String>[]);
    qry = query('coll').filter(
      filter('key', 'in', <Object?>[
        RegexValue('a', 'i'),
        RegexValue('a', 'm'),
      ]),
    );
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/a': OverlayType.set,
      'coll/b': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>['coll/a', 'coll/b']);
    qry = query('coll').filter(
      filter('key', 'not-in', <Object?>[
        RegexValue('a', 'i'),
        RegexValue('a', 'm'),
      ]),
    );
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 1, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{'coll/c': OverlayType.set});
    _expectQueryReturnedInOrder(qry, <String>['coll/c']);
  }

  // JS: local_store_indexeddb.test.ts, "Indexes BSON minKey fields".
  @testMethod
  Future<void> testJsIndexesBSONMinKeyFields() async {
    final FieldIndex index = fieldIndex(
      'coll',
      indexId: 0,
      indexState: FieldIndex.initialState,
      fieldsAndKinds: <Object>['key', SegmentKind.ascending],
    );
    await _configureFieldIndexes(<FieldIndex>[index]);
    await _writeMutation(
      setMutation('coll/a', map(<dynamic>['key', MinKey.instance])),
    );
    await _writeMutation(
      setMutation('coll/b', map(<dynamic>['key', MinKey.instance])),
    );
    await _writeMutation(setMutation('coll/c', map(<dynamic>['key', null])));
    await _writeMutation(setMutation('coll/d', map(<dynamic>['key', 1])));
    await _writeMutation(
      setMutation('coll/e', map(<dynamic>['key', MaxKey.instance])),
    );
    await _backfillIndexes();
    Query qry = query('coll').orderBy(orderBy('key', 'asc'));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 5, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/a': OverlayType.set,
      'coll/b': OverlayType.set,
      'coll/c': OverlayType.set,
      'coll/d': OverlayType.set,
      'coll/e': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>[
      'coll/c',
      'coll/a',
      'coll/b',
      'coll/d',
      'coll/e',
    ]);
    qry = query('coll').filter(filter('key', '==', MinKey.instance));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/a': OverlayType.set,
      'coll/b': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>['coll/a', 'coll/b']);
    qry = query('coll').filter(filter('key', '!=', MinKey.instance));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/d': OverlayType.set,
      'coll/e': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>['coll/d', 'coll/e']);
    qry = query('coll').filter(filter('key', '>=', MinKey.instance));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/a': OverlayType.set,
      'coll/b': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>['coll/a', 'coll/b']);
    qry = query('coll').filter(filter('key', '<', MinKey.instance));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 0, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{});
    _expectQueryReturnedInOrder(qry, <String>[]);
    qry = query('coll').filter(filter('key', 'in', <Object?>[MinKey.instance]));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/a': OverlayType.set,
      'coll/b': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>['coll/a', 'coll/b']);
    qry = query(
      'coll',
    ).filter(filter('key', 'not-in', <Object?>[MinKey.instance]));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/d': OverlayType.set,
      'coll/e': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>['coll/d', 'coll/e']);
  }

  // JS: local_store_indexeddb.test.ts, "Indexes BSON maxKey fields".
  @testMethod
  Future<void> testJsIndexesBSONMaxKeyFields() async {
    final FieldIndex index = fieldIndex(
      'coll',
      indexId: 0,
      indexState: FieldIndex.initialState,
      fieldsAndKinds: <Object>['key', SegmentKind.ascending],
    );
    await _configureFieldIndexes(<FieldIndex>[index]);
    await _writeMutation(
      setMutation('coll/a', map(<dynamic>['key', MaxKey.instance])),
    );
    await _writeMutation(
      setMutation('coll/b', map(<dynamic>['key', MaxKey.instance])),
    );
    await _writeMutation(setMutation('coll/c', map(<dynamic>['key', null])));
    await _writeMutation(setMutation('coll/d', map(<dynamic>['key', 1])));
    await _writeMutation(
      setMutation('coll/e', map(<dynamic>['key', MinKey.instance])),
    );
    await _backfillIndexes();
    Query qry = query('coll').orderBy(orderBy('key', 'asc'));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 5, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/a': OverlayType.set,
      'coll/b': OverlayType.set,
      'coll/c': OverlayType.set,
      'coll/d': OverlayType.set,
      'coll/e': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>[
      'coll/c',
      'coll/e',
      'coll/d',
      'coll/a',
      'coll/b',
    ]);
    qry = query('coll').filter(filter('key', '==', MaxKey.instance));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/a': OverlayType.set,
      'coll/b': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>['coll/a', 'coll/b']);
    qry = query('coll').filter(filter('key', '!=', MaxKey.instance));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/d': OverlayType.set,
      'coll/e': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>['coll/e', 'coll/d']);
    qry = query('coll').filter(filter('key', '<=', MaxKey.instance));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/a': OverlayType.set,
      'coll/b': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>['coll/a', 'coll/b']);
    qry = query('coll').filter(filter('key', '>', MaxKey.instance));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 0, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{});
    _expectQueryReturnedInOrder(qry, <String>[]);
    qry = query('coll').filter(filter('key', '<', MaxKey.instance));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 0, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{});
    _expectQueryReturnedInOrder(qry, <String>[]);
    qry = query('coll').filter(filter('key', 'in', <Object?>[MaxKey.instance]));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/a': OverlayType.set,
      'coll/b': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>['coll/a', 'coll/b']);
    qry = query(
      'coll',
    ).filter(filter('key', 'not-in', <Object?>[MaxKey.instance]));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/d': OverlayType.set,
      'coll/e': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>['coll/e', 'coll/d']);
  }

  // JS: local_store_indexeddb.test.ts, "Indexes multiple BSON types together".
  @testMethod
  Future<void> testJsIndexesMultipleBSONTypesTogether() async {
    final FieldIndex index = fieldIndex(
      'coll',
      indexId: 0,
      indexState: FieldIndex.initialState,
      fieldsAndKinds: <Object>['key', SegmentKind.descending],
    );
    await _configureFieldIndexes(<FieldIndex>[index]);
    await _writeMutation(
      setMutation('coll/a', map(<dynamic>['key', MinKey.instance])),
    );
    await _writeMutation(
      setMutation('coll/b', map(<dynamic>['key', Int32Value(2)])),
    );
    await _writeMutation(
      setMutation('coll/c', map(<dynamic>['key', Int32Value(-1)])),
    );
    await _writeMutation(
      setMutation('coll/d', map(<dynamic>['key', Decimal128Value('1.2e3')])),
    );
    await _writeMutation(
      setMutation('coll/e', map(<dynamic>['key', Decimal128Value('-0')])),
    );
    await _writeMutation(
      setMutation('coll/f', map(<dynamic>['key', BsonTimestamp(1000, 1001)])),
    );
    await _writeMutation(
      setMutation('coll/g', map(<dynamic>['key', BsonTimestamp(1000, 1000)])),
    );
    await _writeMutation(
      setMutation(
        'coll/h',
        map(<dynamic>[
          'key',
          Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2, 4])),
        ]),
      ),
    );
    await _writeMutation(
      setMutation(
        'coll/i',
        map(<dynamic>[
          'key',
          Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2, 3])),
        ]),
      ),
    );
    await _writeMutation(
      setMutation(
        'coll/j',
        map(<dynamic>['key', BsonObjectId('507f191e810c19729de860eb')]),
      ),
    );
    await _writeMutation(
      setMutation(
        'coll/k',
        map(<dynamic>['key', BsonObjectId('507f191e810c19729de860ea')]),
      ),
    );
    await _writeMutation(
      setMutation('coll/l', map(<dynamic>['key', RegexValue('^bar', 'm')])),
    );
    await _writeMutation(
      setMutation('coll/m', map(<dynamic>['key', RegexValue('^bar', 'i')])),
    );
    await _writeMutation(
      setMutation('coll/n', map(<dynamic>['key', MaxKey.instance])),
    );
    await _backfillIndexes();
    Query qry = query('coll').orderBy(orderBy('key', 'desc'));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 14, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/a': OverlayType.set,
      'coll/b': OverlayType.set,
      'coll/c': OverlayType.set,
      'coll/d': OverlayType.set,
      'coll/e': OverlayType.set,
      'coll/f': OverlayType.set,
      'coll/g': OverlayType.set,
      'coll/h': OverlayType.set,
      'coll/i': OverlayType.set,
      'coll/j': OverlayType.set,
      'coll/k': OverlayType.set,
      'coll/l': OverlayType.set,
      'coll/m': OverlayType.set,
      'coll/n': OverlayType.set,
    });
    _expectQueryReturnedInOrder(qry, <String>[
      'coll/n',
      'coll/l',
      'coll/m',
      'coll/j',
      'coll/k',
      'coll/h',
      'coll/i',
      'coll/f',
      'coll/g',
      'coll/d',
      'coll/b',
      'coll/e',
      'coll/c',
      'coll/a',
    ]);
  }

  /// `assertQueryReturned` of local_store_indexeddb.test.ts of the JS SDK: unlike [_expectQueryReturned] (Android's
  /// `assertQueryReturned`), the order counts: the documents sorted by the comparator of [query] must be [keys].
  void _expectQueryReturnedInOrder(Query query, List<String> keys) {
    expect(_lastQueryResult, isNotNull);
    final List<Document> documents = <Document>[
      for (final MapEntry<DocumentKey, Document> entry
          in _lastQueryResult!.documents)
        entry.value,
    ]..sort(query.comparator);
    expect(documents.map((Document d) => d.key.path.toString()).toList(), keys);
  }

  void _expectQueryReturned(List<String> keys) {
    expect(_lastQueryResult, isNotNull);
    final ImmutableSortedMap<DocumentKey, Document> documents =
        _lastQueryResult!.documents;
    for (String k in keys) {
      expect(
        documents.containsKey(key(k)),
        isTrue,
        reason: 'Expected query to return: $k',
      );
    }
    expect(documents.length, keys.length);
  }

  /// Asserts the expected numbers of mutations read by the query engine's [MutationQueue] since the last call to
  /// [_resetPersistenceStats].
  void _expectMutationsReadByEngine({
    required int byKey,
    required int byQuery,
  }) {
    expect(
      _queryEngine.mutationsReadByQuery,
      byQuery,
      reason: 'Mutations read (by query)',
    );
    expect(
      _queryEngine.mutationsReadByKey,
      byKey,
      reason: 'Mutations read (by key)',
    );
  }

  /// Asserts the expected numbers of overlays read by the query engine's [DocumentOverlayCache] since the last call to
  /// [_resetPersistenceStats].
  void _expectOverlaysReadByEngine({
    required int byKey,
    required int byCollection,
  }) {
    expect(
      _queryEngine.overlaysReadByCollection,
      byCollection,
      reason: 'Overlays read (by collection)',
    );
    expect(
      _queryEngine.overlaysReadByKey,
      byKey,
      reason: 'Overlays read (by key)',
    );
  }

  /// Asserts the expected numbers of documents read by the query engine's [RemoteDocumentCache] since the last call
  /// to [_resetPersistenceStats].
  void _expectRemoteDocumentsReadByEngine({
    required int byKey,
    required int byQuery,
  }) {
    expect(
      _queryEngine.documentsReadByQuery,
      byQuery,
      reason: 'Remote documents read (by query)',
    );
    expect(
      _queryEngine.documentsReadByKey,
      byKey,
      reason: 'Remote documents read (by key)',
    );
  }

  Future<int> _allocateQuery(Query query) async {
    final QueryData queryData = await _localStore.allocateTarget(
      query.toTarget(),
    );
    _lastTargetId = queryData.targetId;
    return queryData.targetId;
  }

  Future<void> _releaseQuery(Query query) async {
    final QueryData? queryData = await _persistence.queryCache.getQueryData(
      query.toTarget(),
    );
    await _localStore.releaseTarget(queryData!.targetId);
  }

  /// Asserts that the last target ID is the given number.
  void _expectTargetId(int targetId) {
    expect(_lastTargetId, targetId);
  }

  /// Asserts that a the [_lastChanges] contain the docs in the given array.
  void _expectChanged([
    List<MaybeDocument> expected = const <MaybeDocument>[],
  ]) {
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

    await _applyRemoteEvent(
      addedRemoteEvent(doc('foo/bar', 1, map(<String>['val', 'old'])), <int>[
        2,
      ], <int>[]),
    );
    _expectChanged(<Document>[
      doc('foo/bar', 1, map(<String>['val', 'old'])),
    ]);
    await _expectContains(doc('foo/bar', 1, map(<String>['val', 'old'])));

    await _applyRemoteEvent(
      _addedRemoteEvents(
        <MaybeDocument>[
          doc('foo/bar', 1, map(<String>['val', 'new'])),
          doc('foo/baz', 2, map(<String>['val', 'new'])),
        ],
        <int>[2],
      ),
    );

    _expectChanged(<Document>[
      doc('foo/baz', 2, map(<String>['val', 'new'])),
    ]);
    // The update for foo/bar is ignored.
    await _expectContains(doc('foo/bar', 1, map(<String>['val', 'old'])));
    await _expectContains(doc('foo/baz', 2, map(<String>['val', 'new'])));
  }

  @testMethod
  Future<void> testRemovesManufacturedNoDocumentsFromTheCache() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    final int targetId = await _allocateQuery(query);

    await _applyRemoteEvent(
      addedRemoteEvent(doc('foo/bar', 1, map(<String>['val', 'old'])), <int>[
        targetId,
      ], <int>[]),
    );
    await _expectContains(doc('foo/bar', 1, map(<String>['val', 'old'])));

    // A failed limbo resolution manufactures a NoDocument with a version of NONE. It must remove the document from
    // the cache, even though its version is older than the cached one.
    final NoDocument manufactured = deletedDoc('foo/bar', 0);
    await _applyRemoteEvent(
      RemoteEvent(
        documentUpdates: <DocumentKey, MaybeDocument>{
          manufactured.key: manufactured,
        },
        resolvedLimboDocuments: <DocumentKey>{manufactured.key},
      ),
    );
    _expectRemoved(<String>['foo/bar']);
    await _expectNotContains('foo/bar');
  }

  @testMethod
  Future<void> testClearsResumeTokenOnExistenceFilterMismatch() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    final int targetId = await _allocateQuery(query);

    // Persist a resume token for the target.
    await _applyRemoteEvent(
      RemoteEvent(
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
          ),
        },
      ),
    );
    QueryData? cached = await _persistence.queryCache.getQueryData(
      query.toTarget(),
    );
    expect(cached!.resumeToken, resumeToken(10));
    expect(cached.snapshotVersion, version(10));

    // An existence filter mismatch invalidates the target: the resume token must be cleared, also in the cache.
    await _applyRemoteEvent(
      RemoteEvent(
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
          ),
        },
        targetMismatches: <int, QueryPurpose>{
          targetId: QueryPurpose.existenceFilterMismatch,
        },
      ),
    );
    cached = await _persistence.queryCache.getQueryData(query.toTarget());
    expect(cached!.resumeToken, isEmpty);
    expect(cached.snapshotVersion, SnapshotVersion.none);
  }

  @testMethod
  Future<void> testUpdateOnRemoteDocLeadsToUpdateOverlay() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    await _allocateQuery(query);

    await _applyRemoteEvent(
      updateRemoteEvent(doc('foo/baz', 10, map(<dynamic>['a', 1])), <int>[
        2,
      ], <int>[]),
    );
    await _applyRemoteEvent(
      updateRemoteEvent(doc('foo/bar', 20, map()), <int>[2], <int>[]),
    );
    await _writeMutation(patchMutation('foo/baz', map(<dynamic>['b', 2])));

    await _executeQuery(query);
    _expectRemoteDocumentsReadByEngine(byKey: 0, byQuery: 2);
    _expectOverlaysReadByEngine(byKey: 0, byCollection: 1);
    _expectOverlayTypes(<String, OverlayType>{'foo/baz': OverlayType.patch});
  }

  /// Port of the JS SDK's `add then update while offline` (local_store.test.ts).
  @testMethod
  Future<void> testAddThenUpdateWhileOffline() async {
    await _writeMutations(<Mutation>[
      setMutation('foo/bar', map(<dynamic>['foo', 'foo-value', 'bar', 1])),
    ]);
    await _expectContains(
      doc(
        'foo/bar',
        0,
        map(<dynamic>['foo', 'foo-value', 'bar', 1]),
        DocumentState.localMutations,
      ),
    );

    await _writeMutations(<Mutation>[
      patchMutation('foo/bar', map(<dynamic>['bar', 2])),
    ]);
    await _expectContains(
      doc(
        'foo/bar',
        0,
        map(<dynamic>['foo', 'foo-value', 'bar', 2]),
        DocumentState.localMutations,
      ),
    );
  }

  @testMethod
  Future<void> testGetHighestUnacknowledgedBatchId() async {
    expect(
      await _localStore.getHighestUnacknowledgedBatchId(),
      MutationBatch.unknown,
    );

    await _writeMutation(setMutation('foo/bar', map(<dynamic>['abc', 123])));
    expect(await _localStore.getHighestUnacknowledgedBatchId(), 1);

    await _writeMutation(patchMutation('foo/bar', map(<dynamic>['abc', 321])));
    expect(await _localStore.getHighestUnacknowledgedBatchId(), 2);

    await _acknowledgeMutation(1);
    expect(await _localStore.getHighestUnacknowledgedBatchId(), 2);

    await _rejectMutation();
    expect(
      await _localStore.getHighestUnacknowledgedBatchId(),
      MutationBatch.unknown,
    );
  }

  RemoteEvent _addedRemoteEvents(
    List<MaybeDocument> docs,
    List<int> updatedInTargets,
  ) {
    final WatchChangeAggregator aggregator = WatchChangeAggregator(
      TargetMetadataProvider(
        getRemoteKeysForTarget: (int targetId) => DocumentKey.emptyKeySet,
        getDatabaseId: () => DatabaseId.forDatabase('p', 'd'),
        getQueryDataForTarget: (int targetId) =>
            queryData(targetId, QueryPurpose.listen, 'foo'),
      ),
    );
    addWatchTargets(aggregator, <List<int>>[updatedInTargets]);
    SnapshotVersion snapshotVersion = SnapshotVersion.none;
    for (MaybeDocument doc in docs) {
      aggregator.handleDocumentChange(
        WatchChangeDocumentChange(updatedInTargets, <int>[], doc.key, doc),
      );
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

  // Field indexes: the index cases of SQLiteLocalStoreTest of the Android SDK. They only run with SQLite persistence.

  Future<void> _configureFieldIndexes(List<FieldIndex> fieldIndexes) {
    return _localStore.configureFieldIndexes(fieldIndexes);
  }

  Future<void> _backfillIndexes() async {
    final IndexBackfiller backfiller = IndexBackfiller(
      _persistence,
      _localStore,
    );
    final int? maxDocumentsToProcess = _backfillerMaxDocumentsToProcess;
    if (maxDocumentsToProcess != null) {
      backfiller.maxDocumentsToProcess = maxDocumentsToProcess;
    }
    await backfiller.backfill();
  }

  /// Asserts the type of every overlay that the query engine read since the last call to [_resetPersistenceStats].
  void _expectOverlayTypes(Map<String, OverlayType> expected) {
    expect(_queryEngine.overlayTypes, <DocumentKey, OverlayType>{
      for (final MapEntry<String, OverlayType> entry in expected.entries)
        key(entry.key): entry.value,
    });
  }

  @testMethod
  Future<void> testAddsIndexes() async {
    final FieldIndex indexA = fieldIndex(
      'coll',
      indexId: 0,
      indexState: FieldIndex.initialState,
      fieldsAndKinds: <Object>['a', SegmentKind.ascending],
    );
    final FieldIndex indexB = fieldIndex(
      'coll',
      indexId: 1,
      indexState: FieldIndex.initialState,
      fieldsAndKinds: <Object>['b', SegmentKind.descending],
    );
    final FieldIndex indexC = fieldIndex(
      'coll',
      indexId: 2,
      indexState: FieldIndex.initialState,
      fieldsAndKinds: <Object>[
        'c1',
        SegmentKind.ascending,
        'c2',
        SegmentKind.contains,
      ],
    );

    await _configureFieldIndexes(<FieldIndex>[indexA, indexB]);
    List<FieldIndex> fieldIndexes = _localStore.getFieldIndexes();
    expect(fieldIndexes, unorderedEquals(<FieldIndex>[indexA, indexB]));

    await _configureFieldIndexes(<FieldIndex>[indexA, indexC]);
    fieldIndexes = _localStore.getFieldIndexes();
    expect(fieldIndexes, unorderedEquals(<FieldIndex>[indexA, indexC]));
  }

  @testMethod
  Future<void> testRemovesIndexes() async {
    final FieldIndex indexA = fieldIndex(
      'coll',
      indexId: 0,
      indexState: FieldIndex.initialState,
      fieldsAndKinds: <Object>['a', SegmentKind.ascending],
    );
    final FieldIndex indexB = fieldIndex(
      'coll',
      indexId: 1,
      indexState: FieldIndex.initialState,
      fieldsAndKinds: <Object>['b', SegmentKind.descending],
    );

    await _configureFieldIndexes(<FieldIndex>[indexA, indexB]);
    List<FieldIndex> fieldIndexes = _localStore.getFieldIndexes();
    expect(fieldIndexes, unorderedEquals(<FieldIndex>[indexA, indexB]));

    await _configureFieldIndexes(<FieldIndex>[indexA]);
    fieldIndexes = _localStore.getFieldIndexes();
    expect(fieldIndexes, unorderedEquals(<FieldIndex>[indexA]));
  }

  @testMethod
  Future<void> testDoesNotResetIndexWhenSameIndexIsAdded() async {
    final FieldIndex indexA = fieldIndex(
      'coll',
      indexId: 0,
      indexState: FieldIndex.initialState,
      fieldsAndKinds: <Object>['a', SegmentKind.ascending],
    );

    await _configureFieldIndexes(<FieldIndex>[indexA]);
    List<FieldIndex> fieldIndexes = _localStore.getFieldIndexes();
    expect(fieldIndexes, unorderedEquals(<FieldIndex>[indexA]));

    Query qry = query('coll').filter(filter('a', '==', 1));
    final int targetId = await _allocateQuery(qry);
    await _applyRemoteEvent(
      addedRemoteEvent(doc('coll/a', 10, map(<dynamic>['a', 1])), <int>[
        targetId,
      ], <int>[]),
    );

    await _backfillIndexes();
    final FieldIndex updatedIndexA = fieldIndex(
      'coll',
      indexId: 0,
      indexState: IndexState(1, IndexOffset(version(10), key('coll/a'), -1)),
      fieldsAndKinds: <Object>['a', SegmentKind.ascending],
    );

    fieldIndexes = _localStore.getFieldIndexes();
    expect(fieldIndexes, unorderedEquals(<FieldIndex>[updatedIndexA]));

    // Re-add the same index. We do not reset the index to its initial state.
    await _configureFieldIndexes(<FieldIndex>[indexA]);
    fieldIndexes = _localStore.getFieldIndexes();
    expect(fieldIndexes, unorderedEquals(<FieldIndex>[updatedIndexA]));
  }

  @testMethod
  Future<void> testDeletedDocumentRemovesIndex() async {
    final FieldIndex index = fieldIndex(
      'coll',
      indexId: 0,
      indexState: FieldIndex.initialState,
      fieldsAndKinds: <Object>['matches', SegmentKind.ascending],
    );
    await _configureFieldIndexes(<FieldIndex>[index]);

    Query qry = query('coll').filter(filter('matches', '==', true));
    final int targetId = await _allocateQuery(qry);

    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('coll/a', 10, map(<dynamic>['matches', true])),
        <int>[targetId],
        <int>[],
      ),
    );

    // Add the document to the index
    await _backfillIndexes();

    await _executeQuery(qry);
    _expectRemoteDocumentsReadByEngine(byKey: 1, byQuery: 0);
    _expectQueryReturned(<String>['coll/a']);

    await _applyRemoteEvent(
      updateRemoteEvent(deletedDoc('coll/a', 0), <int>[targetId], <int>[]),
    );

    // No backfill needed for deleted document.
    await _executeQuery(qry);
    _expectRemoteDocumentsReadByEngine(byKey: 0, byQuery: 0);
    _expectQueryReturned(<String>[]);
  }

  @testMethod
  Future<void> testUsesIndexes() async {
    final FieldIndex index = fieldIndex(
      'coll',
      indexId: 0,
      indexState: FieldIndex.initialState,
      fieldsAndKinds: <Object>['matches', SegmentKind.ascending],
    );
    await _configureFieldIndexes(<FieldIndex>[index]);

    Query qry = query('coll').filter(filter('matches', '==', true));
    final int targetId = await _allocateQuery(qry);

    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('coll/a', 10, map(<dynamic>['matches', true])),
        <int>[targetId],
        <int>[],
      ),
    );

    await _backfillIndexes();

    await _executeQuery(qry);
    _expectRemoteDocumentsReadByEngine(byKey: 1, byQuery: 0);
    _expectQueryReturned(<String>['coll/a']);
  }

  @testMethod
  Future<void> testUsesPartiallyIndexedRemoteDocumentsWhenAvailable() async {
    final FieldIndex index = fieldIndex(
      'coll',
      indexId: 0,
      indexState: FieldIndex.initialState,
      fieldsAndKinds: <Object>['matches', SegmentKind.ascending],
    );
    await _configureFieldIndexes(<FieldIndex>[index]);

    Query qry = query('coll').filter(filter('matches', '==', true));
    final int targetId = await _allocateQuery(qry);

    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('coll/a', 10, map(<dynamic>['matches', true])),
        <int>[targetId],
        <int>[],
      ),
    );
    await _backfillIndexes();

    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('coll/b', 20, map(<dynamic>['matches', true])),
        <int>[targetId],
        <int>[],
      ),
    );

    await _executeQuery(qry);
    _expectRemoteDocumentsReadByEngine(byKey: 1, byQuery: 1);
    _expectQueryReturned(<String>['coll/a', 'coll/b']);
  }

  @testMethod
  Future<void> testUsesPartiallyIndexedOverlaysWhenAvailable() async {
    final FieldIndex index = fieldIndex(
      'coll',
      indexId: 0,
      indexState: FieldIndex.initialState,
      fieldsAndKinds: <Object>['matches', SegmentKind.ascending],
    );
    await _configureFieldIndexes(<FieldIndex>[index]);

    await _writeMutation(
      setMutation('coll/a', map(<dynamic>['matches', true])),
    );
    await _backfillIndexes();

    await _writeMutation(
      setMutation('coll/b', map(<dynamic>['matches', true])),
    );

    Query qry = query('coll').filter(filter('matches', '==', true));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 1, byCollection: 1);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/a': OverlayType.set,
      'coll/b': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/a', 'coll/b']);
  }

  @testMethod
  Future<void> testDoesNotUseLimitWhenIndexIsOutdated() async {
    final FieldIndex index = fieldIndex(
      'coll',
      indexId: 0,
      indexState: FieldIndex.initialState,
      fieldsAndKinds: <Object>['count', SegmentKind.ascending],
    );
    await _configureFieldIndexes(<FieldIndex>[index]);

    Query qry = query('coll').orderBy(orderBy('count')).limitToFirst(2);
    final int targetId = await _allocateQuery(qry);

    await _applyRemoteEvent(
      addedRemoteEvents(
        <MaybeDocument>[
          doc('coll/a', 10, map(<dynamic>['count', 1])),
          doc('coll/b', 10, map(<dynamic>['count', 2])),
          doc('coll/c', 10, map(<dynamic>['count', 3])),
        ],
        <int>[targetId],
        <int>[],
      ),
    );
    await _backfillIndexes();

    await _writeMutation(deleteMutation('coll/b'));

    await _executeQuery(qry);

    // The qry engine first reads the documents by key and then re-runs the qry without limit.
    _expectRemoteDocumentsReadByEngine(byKey: 5, byQuery: 0);
    // PORTING NOTE: byKey is 5 upstream, whose CountingQueryEngine counts the keys that are looked up (2 + 3). The one
    // of the port counts the overlays that are found: the delete of coll/b, once per run.
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 1);
    _expectOverlayTypes(<String, OverlayType>{'coll/b': OverlayType.delete});
    _expectQueryReturned(<String>['coll/a', 'coll/c']);
  }

  @testMethod
  Future<void> testUsesIndexForLimitQueryWhenIndexIsUpdated() async {
    final FieldIndex index = fieldIndex(
      'coll',
      indexId: 0,
      indexState: FieldIndex.initialState,
      fieldsAndKinds: <Object>['count', SegmentKind.ascending],
    );
    await _configureFieldIndexes(<FieldIndex>[index]);

    Query qry = query('coll').orderBy(orderBy('count')).limitToFirst(2);
    final int targetId = await _allocateQuery(qry);

    await _applyRemoteEvent(
      addedRemoteEvents(
        <MaybeDocument>[
          doc('coll/a', 10, map(<dynamic>['count', 1])),
          doc('coll/b', 10, map(<dynamic>['count', 2])),
          doc('coll/c', 10, map(<dynamic>['count', 3])),
        ],
        <int>[targetId],
        <int>[],
      ),
    );
    await _writeMutation(deleteMutation('coll/b'));
    await _backfillIndexes();

    await _executeQuery(qry);
    _expectRemoteDocumentsReadByEngine(byKey: 2, byQuery: 0);
    // PORTING NOTE: byKey is 2 upstream (keys looked up); the port counts the overlays found, and coll/a and coll/c have
    // none.
    _expectOverlaysReadByEngine(byKey: 0, byCollection: 0);
    _expectQueryReturned(<String>['coll/a', 'coll/c']);
  }

  @testMethod
  Future<void> testIndexesVectorValues() async {
    final FieldIndex index = fieldIndex(
      'coll',
      indexId: 0,
      indexState: FieldIndex.initialState,
      fieldsAndKinds: <Object>['embedding', SegmentKind.ascending],
    );
    await _configureFieldIndexes(<FieldIndex>[index]);

    await _writeMutation(
      setMutation(
        'coll/arr1',
        map(<dynamic>[
          'embedding',
          <Object?>[0.1, 0.2, 0.3],
        ]),
      ),
    );
    await _writeMutation(
      setMutation('coll/map2', map(<dynamic>['embedding', map()])),
    );
    await _writeMutation(
      setMutation(
        'coll/doc3',
        map(<dynamic>[
          'embedding',
          VectorValue(<double>[4, 5, 6]),
        ]),
      ),
    );
    await _writeMutation(
      setMutation(
        'coll/doc4',
        map(<dynamic>[
          'embedding',
          VectorValue(<double>[5]),
        ]),
      ),
    );

    Query qry = query('coll').orderBy(orderBy('embedding', 'asc'));
    await _executeQuery(qry);
    _expectQueryReturned(<String>[
      'coll/arr1',
      'coll/doc4',
      'coll/doc3',
      'coll/map2',
    ]);

    qry = query(
      'coll',
    ).filter(filter('embedding', '==', VectorValue(<double>[4, 5, 6])));
    await _executeQuery(qry);
    _expectQueryReturned(<String>['coll/doc3']);

    qry = query(
      'coll',
    ).filter(filter('embedding', '>', VectorValue(<double>[4, 5, 6])));
    await _executeQuery(qry);
    _expectQueryReturned(<String>[]);

    qry = query(
      'coll',
    ).filter(filter('embedding', '>=', VectorValue(<double>[4])));
    await _executeQuery(qry);
    _expectQueryReturned(<String>['coll/doc4', 'coll/doc3']);

    await _backfillIndexes();

    qry = query('coll').orderBy(orderBy('embedding', 'asc'));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 4, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/arr1': OverlayType.set,
      'coll/map2': OverlayType.set,
      'coll/doc3': OverlayType.set,
      'coll/doc4': OverlayType.set,
    });
    _expectQueryReturned(<String>[
      'coll/arr1',
      'coll/doc4',
      'coll/doc3',
      'coll/map2',
    ]);

    qry = query(
      'coll',
    ).filter(filter('embedding', '==', VectorValue(<double>[4, 5, 6])));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 1, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{'coll/doc3': OverlayType.set});
    _expectQueryReturned(<String>['coll/doc3']);

    qry = query(
      'coll',
    ).filter(filter('embedding', '>', VectorValue(<double>[4, 5, 6])));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 0, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{});
    _expectQueryReturned(<String>[]);

    qry = query(
      'coll',
    ).filter(filter('embedding', '>=', VectorValue(<double>[4])));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc4': OverlayType.set,
      'coll/doc3': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/doc4', 'coll/doc3']);
  }

  @testMethod
  Future<void> testIndexesBsonObjectId() async {
    final FieldIndex index = fieldIndex(
      'coll',
      indexId: 0,
      indexState: FieldIndex.initialState,
      fieldsAndKinds: <Object>['key', SegmentKind.ascending],
    );
    await _configureFieldIndexes(<FieldIndex>[index]);

    await _writeMutation(
      setMutation(
        'coll/doc1',
        map(<dynamic>['key', BsonObjectId('507f191e810c19729de860ea')]),
      ),
    );
    await _writeMutation(
      setMutation(
        'coll/doc2',
        map(<dynamic>['key', BsonObjectId('507f191e810c19729de860eb')]),
      ),
    );
    await _writeMutation(
      setMutation(
        'coll/doc3',
        map(<dynamic>['key', BsonObjectId('507f191e810c19729de860ec')]),
      ),
    );

    await _backfillIndexes();

    Query qry = query('coll').orderBy(orderBy('key', 'asc'));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 3, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc1': OverlayType.set,
      'coll/doc2': OverlayType.set,
      'coll/doc3': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/doc1', 'coll/doc2', 'coll/doc3']);

    qry = query(
      'coll',
    ).filter(filter('key', '==', BsonObjectId('507f191e810c19729de860ea')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 1, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{'coll/doc1': OverlayType.set});
    _expectQueryReturned(<String>['coll/doc1']);

    qry = query(
      'coll',
    ).filter(filter('key', '!=', BsonObjectId('507f191e810c19729de860ea')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc2': OverlayType.set,
      'coll/doc3': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/doc2', 'coll/doc3']);

    qry = query(
      'coll',
    ).filter(filter('key', '>=', BsonObjectId('507f191e810c19729de860eb')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc2': OverlayType.set,
      'coll/doc3': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/doc2', 'coll/doc3']);

    qry = query(
      'coll',
    ).filter(filter('key', '<=', BsonObjectId('507f191e810c19729de860eb')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc1': OverlayType.set,
      'coll/doc2': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/doc1', 'coll/doc2']);

    qry = query(
      'coll',
    ).filter(filter('key', '>', BsonObjectId('507f191e810c19729de860ec')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 0, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{});
    _expectQueryReturned(<String>[]);

    qry = query(
      'coll',
    ).filter(filter('key', '<', BsonObjectId('507f191e810c19729de860ea')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 0, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{});
    _expectQueryReturned(<String>[]);

    qry = query('coll').filter(
      filter('key', 'in', <Object?>[
        BsonObjectId('507f191e810c19729de860ea'),
        BsonObjectId('507f191e810c19729de860eb'),
      ]),
    );
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc1': OverlayType.set,
      'coll/doc2': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/doc1', 'coll/doc2']);
  }

  @testMethod
  Future<void> testIndexesBsonTimestamp() async {
    final FieldIndex index = fieldIndex(
      'coll',
      indexId: 0,
      indexState: FieldIndex.initialState,
      fieldsAndKinds: <Object>['key', SegmentKind.ascending],
    );
    await _configureFieldIndexes(<FieldIndex>[index]);

    await _writeMutation(
      setMutation(
        'coll/doc1',
        map(<dynamic>['key', BsonTimestamp(1000, 1000)]),
      ),
    );
    await _writeMutation(
      setMutation(
        'coll/doc2',
        map(<dynamic>['key', BsonTimestamp(1001, 1000)]),
      ),
    );
    await _writeMutation(
      setMutation(
        'coll/doc3',
        map(<dynamic>['key', BsonTimestamp(1000, 1001)]),
      ),
    );

    await _backfillIndexes();

    Query qry = query('coll').orderBy(orderBy('key', 'asc'));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 3, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc1': OverlayType.set,
      'coll/doc2': OverlayType.set,
      'coll/doc3': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/doc1', 'coll/doc3', 'coll/doc2']);

    qry = query('coll').filter(filter('key', '==', BsonTimestamp(1000, 1000)));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 1, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{'coll/doc1': OverlayType.set});
    _expectQueryReturned(<String>['coll/doc1']);

    qry = query('coll').filter(filter('key', '!=', BsonTimestamp(1000, 1000)));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc2': OverlayType.set,
      'coll/doc3': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/doc3', 'coll/doc2']);

    qry = query('coll').filter(filter('key', '>=', BsonTimestamp(1000, 1001)));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc2': OverlayType.set,
      'coll/doc3': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/doc3', 'coll/doc2']);

    qry = query('coll').filter(filter('key', '<=', BsonTimestamp(1000, 1001)));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc1': OverlayType.set,
      'coll/doc3': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/doc1', 'coll/doc3']);

    qry = query('coll').filter(filter('key', '>', BsonTimestamp(1001, 1000)));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 0, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{});
    _expectQueryReturned(<String>[]);

    qry = query('coll').filter(filter('key', '<', BsonTimestamp(1000, 1000)));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 0, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{});
    _expectQueryReturned(<String>[]);

    qry = query('coll').filter(
      filter('key', 'in', <Object?>[
        BsonTimestamp(1000, 1000),
        BsonTimestamp(1000, 1001),
      ]),
    );
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc1': OverlayType.set,
      'coll/doc3': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/doc1', 'coll/doc3']);
  }

  @testMethod
  Future<void> testIndexesBsonBinary() async {
    final FieldIndex index = fieldIndex(
      'coll',
      indexId: 0,
      indexState: FieldIndex.initialState,
      fieldsAndKinds: <Object>['key', SegmentKind.ascending],
    );
    await _configureFieldIndexes(<FieldIndex>[index]);

    await _writeMutation(
      setMutation(
        'coll/doc1',
        map(<dynamic>[
          'key',
          Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2, 3])),
        ]),
      ),
    );
    await _writeMutation(
      setMutation(
        'coll/doc2',
        map(<dynamic>[
          'key',
          Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2])),
        ]),
      ),
    );
    await _writeMutation(
      setMutation(
        'coll/doc3',
        map(<dynamic>[
          'key',
          Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2, 4])),
        ]),
      ),
    );
    await _writeMutation(
      setMutation(
        'coll/doc4',
        map(<dynamic>[
          'key',
          Blob.bsonBinary(2, Uint8List.fromList(<int>[1, 2])),
        ]),
      ),
    );

    await _backfillIndexes();

    Query qry = query('coll').orderBy(orderBy('key', 'asc'));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 4, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc1': OverlayType.set,
      'coll/doc2': OverlayType.set,
      'coll/doc3': OverlayType.set,
      'coll/doc4': OverlayType.set,
    });
    _expectQueryReturned(<String>[
      'coll/doc2',
      'coll/doc1',
      'coll/doc3',
      'coll/doc4',
    ]);

    qry = query('coll').filter(
      filter(
        'key',
        '==',
        Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2, 3])),
      ),
    );
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 1, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{'coll/doc1': OverlayType.set});
    _expectQueryReturned(<String>['coll/doc1']);

    qry = query('coll').filter(
      filter(
        'key',
        '!=',
        Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2, 3])),
      ),
    );
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 3, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc2': OverlayType.set,
      'coll/doc3': OverlayType.set,
      'coll/doc4': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/doc2', 'coll/doc3', 'coll/doc4']);

    qry = query('coll').filter(
      filter(
        'key',
        '>=',
        Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2, 3])),
      ),
    );
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 3, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc1': OverlayType.set,
      'coll/doc3': OverlayType.set,
      'coll/doc4': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/doc1', 'coll/doc3', 'coll/doc4']);

    qry = query('coll').filter(
      filter(
        'key',
        '<=',
        Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2, 3])),
      ),
    );
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc1': OverlayType.set,
      'coll/doc2': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/doc2', 'coll/doc1']);

    qry = query('coll').filter(
      filter('key', '>', Blob.bsonBinary(2, Uint8List.fromList(<int>[1, 2]))),
    );
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 0, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{});
    _expectQueryReturned(<String>[]);

    qry = query('coll').filter(
      filter('key', '<', Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2]))),
    );
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 0, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{});
    _expectQueryReturned(<String>[]);

    qry = query('coll').filter(
      filter('key', 'in', <Object?>[
        Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2, 3])),
        Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2])),
      ]),
    );
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc1': OverlayType.set,
      'coll/doc2': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/doc1', 'coll/doc2']);
  }

  @testMethod
  Future<void> testIndexesRegex() async {
    final FieldIndex index = fieldIndex(
      'coll',
      indexId: 0,
      indexState: FieldIndex.initialState,
      fieldsAndKinds: <Object>['key', SegmentKind.ascending],
    );
    await _configureFieldIndexes(<FieldIndex>[index]);

    await _writeMutation(
      setMutation('coll/doc1', map(<dynamic>['key', RegexValue('^bar', 'i')])),
    );
    await _writeMutation(
      setMutation('coll/doc2', map(<dynamic>['key', RegexValue('^bar', 'm')])),
    );
    await _writeMutation(
      setMutation('coll/doc3', map(<dynamic>['key', RegexValue('^foo', 'i')])),
    );

    await _backfillIndexes();

    Query qry = query('coll').orderBy(orderBy('key', 'asc'));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 3, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc1': OverlayType.set,
      'coll/doc2': OverlayType.set,
      'coll/doc3': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/doc1', 'coll/doc2', 'coll/doc3']);

    qry = query('coll').filter(filter('key', '==', RegexValue('^bar', 'i')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 1, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{'coll/doc1': OverlayType.set});
    _expectQueryReturned(<String>['coll/doc1']);

    qry = query('coll').filter(filter('key', '!=', RegexValue('^bar', 'i')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc2': OverlayType.set,
      'coll/doc3': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/doc2', 'coll/doc3']);

    qry = query('coll').filter(filter('key', '>', RegexValue('^foo', 'i')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 0, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{});
    _expectQueryReturned(<String>[]);

    qry = query('coll').filter(filter('key', '<', RegexValue('^bar', 'i')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 0, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{});
    _expectQueryReturned(<String>[]);

    qry = query('coll').filter(
      filter('key', 'in', <Object?>[
        RegexValue('^bar', 'i'),
        RegexValue('^foo', 'i'),
      ]),
    );
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc1': OverlayType.set,
      'coll/doc3': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/doc1', 'coll/doc3']);
  }

  @testMethod
  Future<void> testIndexesInt32() async {
    final FieldIndex index = fieldIndex(
      'coll',
      indexId: 0,
      indexState: FieldIndex.initialState,
      fieldsAndKinds: <Object>['key', SegmentKind.ascending],
    );
    await _configureFieldIndexes(<FieldIndex>[index]);
    await _writeMutation(
      setMutation('coll/doc1', map(<dynamic>['key', Int32Value(-1)])),
    );
    await _writeMutation(
      setMutation('coll/doc2', map(<dynamic>['key', Int32Value(0)])),
    );
    await _writeMutation(
      setMutation('coll/doc3', map(<dynamic>['key', Int32Value(1)])),
    );

    await _backfillIndexes();

    Query qry = query('coll').orderBy(orderBy('key', 'asc'));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 3, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc1': OverlayType.set,
      'coll/doc2': OverlayType.set,
      'coll/doc3': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/doc1', 'coll/doc2', 'coll/doc3']);

    qry = query('coll').filter(filter('key', '==', Int32Value(-1)));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 1, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{'coll/doc1': OverlayType.set});
    _expectQueryReturned(<String>['coll/doc1']);

    qry = query('coll').filter(filter('key', '!=', Int32Value(-1)));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc2': OverlayType.set,
      'coll/doc3': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/doc2', 'coll/doc3']);

    qry = query('coll').filter(filter('key', '>=', Int32Value(0)));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc2': OverlayType.set,
      'coll/doc3': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/doc2', 'coll/doc3']);

    qry = query('coll').filter(filter('key', '<=', Int32Value(0)));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc1': OverlayType.set,
      'coll/doc2': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/doc1', 'coll/doc2']);

    qry = query('coll').filter(filter('key', '>', Int32Value(1)));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 0, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{});
    _expectQueryReturned(<String>[]);

    qry = query('coll').filter(filter('key', '<', Int32Value(-1)));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 0, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{});
    _expectQueryReturned(<String>[]);

    qry = query(
      'coll',
    ).filter(filter('key', 'in', <Object?>[Int32Value(-1), Int32Value(0)]));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc1': OverlayType.set,
      'coll/doc2': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/doc1', 'coll/doc2']);
  }

  @testMethod
  Future<void> testIndexesDecimal128Value() async {
    final FieldIndex index = fieldIndex(
      'coll',
      indexId: 0,
      indexState: FieldIndex.initialState,
      fieldsAndKinds: <Object>['key', SegmentKind.ascending],
    );
    await _configureFieldIndexes(<FieldIndex>[index]);
    await _writeMutation(
      setMutation(
        'coll/doc1',
        map(<dynamic>['key', Decimal128Value('-1.2e3')]),
      ),
    );
    await _writeMutation(
      setMutation('coll/doc2', map(<dynamic>['key', Decimal128Value('0')])),
    );
    await _writeMutation(
      setMutation('coll/doc3', map(<dynamic>['key', Decimal128Value('1.2e3')])),
    );

    await _backfillIndexes();

    Query qry = query('coll').orderBy(orderBy('key', 'asc'));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 3, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc1': OverlayType.set,
      'coll/doc2': OverlayType.set,
      'coll/doc3': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/doc1', 'coll/doc2', 'coll/doc3']);

    qry = query('coll').filter(filter('key', '==', Decimal128Value('-1200')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 1, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{'coll/doc1': OverlayType.set});
    _expectQueryReturned(<String>['coll/doc1']);

    qry = query('coll').filter(filter('key', '!=', Decimal128Value('0.0')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc1': OverlayType.set,
      'coll/doc3': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/doc1', 'coll/doc3']);

    qry = query('coll').filter(filter('key', '>=', Decimal128Value('-0')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc2': OverlayType.set,
      'coll/doc3': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/doc2', 'coll/doc3']);

    // This will fail if the negative 0s are not converted to positive 0 in `writeIndexValue`
    // function
    qry = query('coll').filter(filter('key', '<=', Decimal128Value('-0.0')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc1': OverlayType.set,
      'coll/doc2': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/doc1', 'coll/doc2']);

    qry = query('coll').filter(filter('key', '>', Decimal128Value('1.2e3')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 0, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{});
    _expectQueryReturned(<String>[]);

    qry = query('coll').filter(filter('key', '<', Decimal128Value('-1.2e3')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 0, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{});
    _expectQueryReturned(<String>[]);

    qry = query('coll').filter(
      filter('key', 'in', <Object?>[
        Decimal128Value('-1.2e3'),
        Decimal128Value('0'),
      ]),
    );
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc1': OverlayType.set,
      'coll/doc2': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/doc1', 'coll/doc2']);
  }

  @testMethod
  Future<void> testIndexesDecimal128ValueWithPrecisionLoss() async {
    final FieldIndex index = fieldIndex(
      'coll',
      indexId: 0,
      indexState: FieldIndex.initialState,
      fieldsAndKinds: <Object>['key', SegmentKind.ascending],
    );
    await _configureFieldIndexes(<FieldIndex>[index]);
    await _writeMutation(
      setMutation(
        'coll/doc1',
        map(<dynamic>['key', Decimal128Value('-0.1234567890123456789')]),
      ),
    ); // will be rounded to -0.12345678901234568
    await _writeMutation(
      setMutation('coll/doc2', map(<dynamic>['key', Decimal128Value('0')])),
    );
    await _writeMutation(
      setMutation(
        'coll/doc3',
        map(<dynamic>['key', Decimal128Value('0.1234567890123456789')]),
      ),
    ); // will be rounded to 0.12345678901234568

    await _backfillIndexes();

    Query qry = query('coll').orderBy(orderBy('key', 'asc'));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 3, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc1': OverlayType.set,
      'coll/doc2': OverlayType.set,
      'coll/doc3': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/doc1', 'coll/doc2', 'coll/doc3']);

    qry = query(
      'coll',
    ).filter(filter('key', '==', Decimal128Value('0.1234567890123456789')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 1, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{'coll/doc3': OverlayType.set});
    _expectQueryReturned(<String>['coll/doc3']);

    // Mismatch behaviour caused by rounding error. Firestore fetches the doc3 from SQLite DB as
    // doc3 rounds to the same number, but, it is not presented on the final qry result.
    qry = query(
      'coll',
    ).filter(filter('key', '==', Decimal128Value('0.12345678901234568')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 1, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{'coll/doc3': OverlayType.set});
    _expectQueryReturned(<String>[]);

    // Operations that doesn't go up to 17 decimal digits of precision wouldn't be affected by
    // this rounding errors.
    qry = query('coll').filter(filter('key', '!=', Decimal128Value('0.0')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc1': OverlayType.set,
      'coll/doc3': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/doc1', 'coll/doc3']);

    qry = query('coll').filter(filter('key', '>=', Decimal128Value('1.23e-1')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 1, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{'coll/doc3': OverlayType.set});
    _expectQueryReturned(<String>['coll/doc3']);

    qry = query(
      'coll',
    ).filter(filter('key', '<=', Decimal128Value('-1.23e-1')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 1, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{'coll/doc1': OverlayType.set});
    _expectQueryReturned(<String>['coll/doc1']);

    qry = query('coll').filter(filter('key', '>', Decimal128Value('1.2e3')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 0, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{});
    _expectQueryReturned(<String>[]);

    qry = query('coll').filter(filter('key', '<', Decimal128Value('-1.2e3')));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 0, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{});
    _expectQueryReturned(<String>[]);
  }

  @testMethod
  Future<void> testIndexesMinKey() async {
    final FieldIndex index = fieldIndex(
      'coll',
      indexId: 0,
      indexState: FieldIndex.initialState,
      fieldsAndKinds: <Object>['key', SegmentKind.ascending],
    );
    await _configureFieldIndexes(<FieldIndex>[index]);

    await _writeMutation(setMutation('coll/doc1', map(<dynamic>['key', null])));
    await _writeMutation(
      setMutation('coll/doc2', map(<dynamic>['key', MinKey.instance])),
    );
    await _writeMutation(
      setMutation('coll/doc3', map(<dynamic>['key', MinKey.instance])),
    );
    await _writeMutation(setMutation('coll/doc4', map(<dynamic>['key', 1])));
    await _writeMutation(
      setMutation('coll/doc5', map(<dynamic>['key', MaxKey.instance])),
    );

    await _backfillIndexes();

    Query qry = query('coll').orderBy(orderBy('key', 'asc'));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 5, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc1': OverlayType.set,
      'coll/doc2': OverlayType.set,
      'coll/doc3': OverlayType.set,
      'coll/doc4': OverlayType.set,
      'coll/doc5': OverlayType.set,
    });
    _expectQueryReturned(<String>[
      'coll/doc1',
      'coll/doc2',
      'coll/doc3',
      'coll/doc4',
      'coll/doc5',
    ]);

    qry = query('coll').filter(filter('key', '==', MinKey.instance));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc2': OverlayType.set,
      'coll/doc3': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/doc2', 'coll/doc3']);

    qry = query('coll').filter(filter('key', '!=', MinKey.instance));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc4': OverlayType.set,
      'coll/doc5': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/doc4', 'coll/doc5']);

    qry = query('coll').filter(filter('key', '>=', MinKey.instance));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc2': OverlayType.set,
      'coll/doc3': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/doc2', 'coll/doc3']);

    qry = query('coll').filter(filter('key', '<=', MinKey.instance));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc2': OverlayType.set,
      'coll/doc3': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/doc2', 'coll/doc3']);

    qry = query('coll').filter(filter('key', '>', MinKey.instance));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 0, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{});
    _expectQueryReturned(<String>[]);

    qry = query('coll').filter(filter('key', '<', MinKey.instance));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 0, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{});
    _expectQueryReturned(<String>[]);

    qry = query(
      'coll',
    ).filter(filter('key', 'in', <Object?>[MinKey.instance, MaxKey.instance]));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 3, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc2': OverlayType.set,
      'coll/doc3': OverlayType.set,
      'coll/doc5': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/doc2', 'coll/doc3', 'coll/doc5']);
  }

  @testMethod
  Future<void> testIndexesMaxKey() async {
    final FieldIndex index = fieldIndex(
      'coll',
      indexId: 0,
      indexState: FieldIndex.initialState,
      fieldsAndKinds: <Object>['key', SegmentKind.ascending],
    );
    await _configureFieldIndexes(<FieldIndex>[index]);

    await _writeMutation(setMutation('coll/doc1', map(<dynamic>['key', null])));
    await _writeMutation(
      setMutation('coll/doc2', map(<dynamic>['key', MinKey.instance])),
    );
    await _writeMutation(setMutation('coll/doc3', map(<dynamic>['key', 1])));
    await _writeMutation(
      setMutation('coll/doc4', map(<dynamic>['key', MaxKey.instance])),
    );
    await _writeMutation(
      setMutation('coll/doc5', map(<dynamic>['key', MaxKey.instance])),
    );

    await _backfillIndexes();

    Query qry = query('coll').orderBy(orderBy('key', 'asc'));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 5, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc1': OverlayType.set,
      'coll/doc2': OverlayType.set,
      'coll/doc3': OverlayType.set,
      'coll/doc4': OverlayType.set,
      'coll/doc5': OverlayType.set,
    });
    _expectQueryReturned(<String>[
      'coll/doc1',
      'coll/doc2',
      'coll/doc3',
      'coll/doc4',
      'coll/doc5',
    ]);

    qry = query('coll').filter(filter('key', '==', MaxKey.instance));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc4': OverlayType.set,
      'coll/doc5': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/doc4', 'coll/doc5']);

    qry = query('coll').filter(filter('key', '!=', MaxKey.instance));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc2': OverlayType.set,
      'coll/doc3': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/doc2', 'coll/doc3']);

    qry = query('coll').filter(filter('key', '>=', MaxKey.instance));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc4': OverlayType.set,
      'coll/doc5': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/doc4', 'coll/doc5']);

    qry = query('coll').filter(filter('key', '<=', MaxKey.instance));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 2, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc4': OverlayType.set,
      'coll/doc5': OverlayType.set,
    });
    _expectQueryReturned(<String>['coll/doc4', 'coll/doc5']);

    qry = query('coll').filter(filter('key', '>', MaxKey.instance));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 0, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{});
    _expectQueryReturned(<String>[]);

    qry = query('coll').filter(filter('key', '<', MaxKey.instance));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 0, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{});
    _expectQueryReturned(<String>[]);
  }

  @testMethod
  Future<void> testIndexesAllBsonTypesTogether() async {
    final FieldIndex index = fieldIndex(
      'coll',
      indexId: 0,
      indexState: FieldIndex.initialState,
      fieldsAndKinds: <Object>['key', SegmentKind.descending],
    );
    await _configureFieldIndexes(<FieldIndex>[index]);

    await _writeMutation(
      setMutation('coll/doc1', map(<dynamic>['key', MinKey.instance])),
    );
    await _writeMutation(
      setMutation('coll/doc2', map(<dynamic>['key', Int32Value(2)])),
    );
    await _writeMutation(
      setMutation('coll/doc3', map(<dynamic>['key', Int32Value(-1)])),
    );
    await _writeMutation(
      setMutation('coll/doc4', map(<dynamic>['key', Decimal128Value('1.2e3')])),
    );
    await _writeMutation(
      setMutation('coll/doc5', map(<dynamic>['key', Decimal128Value('-0.0')])),
    );
    await _writeMutation(
      setMutation(
        'coll/doc6',
        map(<dynamic>['key', BsonTimestamp(1000, 1001)]),
      ),
    );
    await _writeMutation(
      setMutation(
        'coll/doc7',
        map(<dynamic>['key', BsonTimestamp(1000, 1000)]),
      ),
    );
    await _writeMutation(
      setMutation(
        'coll/doc8',
        map(<dynamic>[
          'key',
          Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2, 4])),
        ]),
      ),
    );
    await _writeMutation(
      setMutation(
        'coll/doc9',
        map(<dynamic>[
          'key',
          Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2, 3])),
        ]),
      ),
    );
    await _writeMutation(
      setMutation(
        'coll/doc10',
        map(<dynamic>['key', BsonObjectId('507f191e810c19729de860eb')]),
      ),
    );
    await _writeMutation(
      setMutation(
        'coll/doc11',
        map(<dynamic>['key', BsonObjectId('507f191e810c19729de860ea')]),
      ),
    );
    await _writeMutation(
      setMutation('coll/doc12', map(<dynamic>['key', RegexValue('^bar', 'm')])),
    );
    await _writeMutation(
      setMutation('coll/doc13', map(<dynamic>['key', RegexValue('^bar', 'i')])),
    );
    await _writeMutation(
      setMutation('coll/doc14', map(<dynamic>['key', MaxKey.instance])),
    );

    await _backfillIndexes();

    Query qry = query('coll').orderBy(orderBy('key', 'desc'));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 14, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc1': OverlayType.set,
      'coll/doc2': OverlayType.set,
      'coll/doc3': OverlayType.set,
      'coll/doc4': OverlayType.set,
      'coll/doc5': OverlayType.set,
      'coll/doc6': OverlayType.set,
      'coll/doc7': OverlayType.set,
      'coll/doc8': OverlayType.set,
      'coll/doc9': OverlayType.set,
      'coll/doc10': OverlayType.set,
      'coll/doc11': OverlayType.set,
      'coll/doc12': OverlayType.set,
      'coll/doc13': OverlayType.set,
      'coll/doc14': OverlayType.set,
    });
    _expectQueryReturned(<String>[
      'coll/doc14', // maxKey
      'coll/doc12', // regex m
      'coll/doc13', // regex i
      'coll/doc10', // objectId eb
      'coll/doc11', // objectId ea
      'coll/doc8', // binary [1,2,4]
      'coll/doc9', // binary [1,2,3]
      'coll/doc6', // timestamp 1, 2
      'coll/doc7', // timestamp 1, 1
      'coll/doc4', // decimal128 1200
      'coll/doc2', // int32 2
      'coll/doc5', // decimal128 -0.0
      'coll/doc3', // int32 -1
      'coll/doc1', // minKey
    ]);
  }

  @testMethod
  Future<void> testIndexesAllTypesTogether() async {
    final FieldIndex index = fieldIndex(
      'coll',
      indexId: 0,
      indexState: FieldIndex.initialState,
      fieldsAndKinds: <Object>['key', SegmentKind.ascending],
    );
    await _configureFieldIndexes(<FieldIndex>[index]);

    await _writeMutation(setMutation('coll/doc1', map(<dynamic>['key', null])));
    await _writeMutation(
      setMutation('coll/doc2', map(<dynamic>['key', MinKey.instance])),
    );
    await _writeMutation(setMutation('coll/doc3', map(<dynamic>['key', true])));
    await _writeMutation(
      setMutation('coll/doc4', map(<dynamic>['key', double.nan])),
    );
    await _writeMutation(
      setMutation('coll/doc5', map(<dynamic>['key', Int32Value(1)])),
    );
    await _writeMutation(setMutation('coll/doc6', map(<dynamic>['key', 2.0])));
    await _writeMutation(setMutation('coll/doc7', map(<dynamic>['key', 3])));
    await _writeMutation(
      setMutation('coll/doc8', map(<dynamic>['key', Decimal128Value('1.2e3')])),
    );
    await _writeMutation(
      setMutation(
        'coll/doc9',
        map(<dynamic>['key', Timestamp(100, 123456000)]),
      ),
    );
    await _writeMutation(
      setMutation('coll/doc10', map(<dynamic>['key', BsonTimestamp(1, 2)])),
    );
    await _writeMutation(
      setMutation('coll/doc11', map(<dynamic>['key', 'string'])),
    );
    await _writeMutation(
      setMutation(
        'coll/doc12',
        map(<dynamic>[
          'key',
          blob(<int>[1, 2, 3]),
        ]),
      ),
    );
    await _writeMutation(
      setMutation(
        'coll/doc13',
        map(<dynamic>[
          'key',
          Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2, 3])),
        ]),
      ),
    );
    await _writeMutation(
      setMutation('coll/doc14', map(<dynamic>['key', ref('foo/bar')])),
    );
    await _writeMutation(
      setMutation(
        'coll/doc15',
        map(<dynamic>['key', BsonObjectId('507f191e810c19729de860ea')]),
      ),
    );
    await _writeMutation(
      setMutation('coll/doc16', map(<dynamic>['key', GeoPoint(1, 2)])),
    );
    await _writeMutation(
      setMutation('coll/doc17', map(<dynamic>['key', RegexValue('^bar', 'm')])),
    );
    await _writeMutation(
      setMutation(
        'coll/doc18',
        map(<dynamic>[
          'key',
          <Object?>[2, 'foo'],
        ]),
      ),
    );
    await _writeMutation(
      setMutation(
        'coll/doc19',
        map(<dynamic>[
          'key',
          VectorValue(<double>[1, 2, 3]),
        ]),
      ),
    );
    await _writeMutation(
      setMutation(
        'coll/doc20',
        map(<dynamic>[
          'key',
          map(<dynamic>['bar', 1, 'foo', 2]),
        ]),
      ),
    );
    await _writeMutation(
      setMutation('coll/doc21', map(<dynamic>['key', MaxKey.instance])),
    );

    await _backfillIndexes();

    Query qry = query('coll').orderBy(orderBy('key', 'asc'));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 21, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{
      'coll/doc1': OverlayType.set,
      'coll/doc2': OverlayType.set,
      'coll/doc3': OverlayType.set,
      'coll/doc4': OverlayType.set,
      'coll/doc5': OverlayType.set,
      'coll/doc6': OverlayType.set,
      'coll/doc7': OverlayType.set,
      'coll/doc8': OverlayType.set,
      'coll/doc9': OverlayType.set,
      'coll/doc10': OverlayType.set,
      'coll/doc11': OverlayType.set,
      'coll/doc12': OverlayType.set,
      'coll/doc13': OverlayType.set,
      'coll/doc14': OverlayType.set,
      'coll/doc15': OverlayType.set,
      'coll/doc16': OverlayType.set,
      'coll/doc17': OverlayType.set,
      'coll/doc18': OverlayType.set,
      'coll/doc19': OverlayType.set,
      'coll/doc20': OverlayType.set,
      'coll/doc21': OverlayType.set,
    });
    _expectQueryReturned(<String>[
      'coll/doc1',
      'coll/doc2',
      'coll/doc3',
      'coll/doc4',
      'coll/doc5',
      'coll/doc6',
      'coll/doc7',
      'coll/doc8',
      'coll/doc9',
      'coll/doc10',
      'coll/doc11',
      'coll/doc12',
      'coll/doc13',
      'coll/doc14',
      'coll/doc15',
      'coll/doc16',
      'coll/doc17',
      'coll/doc18',
      'coll/doc19',
      'coll/doc20',
      'coll/doc21',
    ]);
  }

  @testMethod
  Future<void> testIndexesServerTimestamps() async {
    final FieldIndex index = fieldIndex(
      'coll',
      indexId: 0,
      indexState: FieldIndex.initialState,
      fieldsAndKinds: <Object>['time', SegmentKind.ascending],
    );
    await _configureFieldIndexes(<FieldIndex>[index]);

    // PORTING NOTE: the `setMutation` helper of the port does not take sentinels, so the mutation is built the way the
    // public API builds it.
    await _writeMutation(
      UserDataConverter(DatabaseId.forProject('project'))
          .parseSetData(<String, Object?>{'time': FieldValue.serverTimestamp()})
          .toMutation(key('coll/a'), Precondition.none),
    );
    await _backfillIndexes();

    Query qry = query('coll').orderBy(orderBy('time', 'asc'));
    await _executeQuery(qry);
    _expectOverlaysReadByEngine(byKey: 1, byCollection: 0);
    _expectOverlayTypes(<String, OverlayType>{'coll/a': OverlayType.set});
    _expectQueryReturned(<String>['coll/a']);
  }

  // Automatic index creation: the cases of SQLiteLocalStoreTest of the Android SDK.

  @testMethod
  Future<void> testCanAutoCreateIndexes() async {
    Query qry = query('coll').filter(filter('matches', '==', true));
    final int targetId = await _allocateQuery(qry);

    _localStore.indexAutoCreationEnabled = true;
    _defaultEngine.indexAutoCreationMinCollectionSize = 0;
    _defaultEngine.relativeIndexReadCostPerDocument = 2;

    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('coll/a', 10, map(<dynamic>['matches', true])),
        <int>[targetId],
        <int>[],
      ),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('coll/b', 10, map(<dynamic>['matches', false])),
        <int>[targetId],
        <int>[],
      ),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('coll/c', 10, map(<dynamic>['matches', false])),
        <int>[targetId],
        <int>[],
      ),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('coll/d', 10, map(<dynamic>['matches', false])),
        <int>[targetId],
        <int>[],
      ),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('coll/e', 10, map(<dynamic>['matches', true])),
        <int>[targetId],
        <int>[],
      ),
    );

    // First time qry runs without indexes.
    // Based on current heuristic, collection document counts (5) > 2 * resultSize (2).
    // Full matched index should be created.
    await _executeQuery(qry);
    _expectRemoteDocumentsReadByEngine(byKey: 0, byQuery: 2);
    _expectQueryReturned(<String>['coll/a', 'coll/e']);

    await _backfillIndexes();

    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('coll/f', 20, map(<dynamic>['matches', true])),
        <int>[targetId],
        <int>[],
      ),
    );

    await _executeQuery(qry);
    _expectRemoteDocumentsReadByEngine(byKey: 2, byQuery: 1);
    _expectQueryReturned(<String>['coll/a', 'coll/e', 'coll/f']);
  }

  @testMethod
  Future<void> testCanAutoCreateIndexesWorksWithOrQuery() async {
    Query qry = query('coll').filter(
      orFilters(<Filter>[filter('a', '==', 3), filter('b', '==', true)]),
    );
    final int targetId = await _allocateQuery(qry);

    _localStore.indexAutoCreationEnabled = true;
    _defaultEngine.indexAutoCreationMinCollectionSize = 0;
    _defaultEngine.relativeIndexReadCostPerDocument = 2;

    await _applyRemoteEvent(
      addedRemoteEvent(doc('coll/a', 10, map(<dynamic>['b', true])), <int>[
        targetId,
      ], <int>[]),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(doc('coll/b', 10, map(<dynamic>['b', false])), <int>[
        targetId,
      ], <int>[]),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('coll/c', 10, map(<dynamic>['a', 5, 'b', false])),
        <int>[targetId],
        <int>[],
      ),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(doc('coll/d', 10, map(<dynamic>['a', true])), <int>[
        targetId,
      ], <int>[]),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('coll/e', 10, map(<dynamic>['a', 3, 'b', true])),
        <int>[targetId],
        <int>[],
      ),
    );

    // First time qry runs without indexes.
    // Based on current heuristic, collection document counts (5) > 2 * resultSize (2).
    // Full matched index should be created.
    await _executeQuery(qry);
    _expectRemoteDocumentsReadByEngine(byKey: 0, byQuery: 2);
    _expectQueryReturned(<String>['coll/a', 'coll/e']);

    await _backfillIndexes();

    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('coll/f', 20, map(<dynamic>['a', 3, 'b', false])),
        <int>[targetId],
        <int>[],
      ),
    );

    await _executeQuery(qry);
    _expectRemoteDocumentsReadByEngine(byKey: 2, byQuery: 1);
    _expectQueryReturned(<String>['coll/a', 'coll/e', 'coll/f']);
  }

  @testMethod
  Future<void> testDoesNotAutoCreateIndexesForSmallCollections() async {
    Query qry = query(
      'coll',
    ).filter(filter('foo', '==', 9)).filter(filter('count', '>=', 3));
    final int targetId = await _allocateQuery(qry);

    _localStore.indexAutoCreationEnabled = true;
    _defaultEngine.relativeIndexReadCostPerDocument = 2;

    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('coll/a', 10, map(<dynamic>['foo', 9, 'count', 5])),
        <int>[targetId],
        <int>[],
      ),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('coll/b', 10, map(<dynamic>['foo', 8, 'count', 6])),
        <int>[targetId],
        <int>[],
      ),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('coll/c', 10, map(<dynamic>['foo', 9, 'count', 0])),
        <int>[targetId],
        <int>[],
      ),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(doc('coll/d', 10, map(<dynamic>['count', 4])), <int>[
        targetId,
      ], <int>[]),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('coll/e', 10, map(<dynamic>['foo', 9, 'count', 3])),
        <int>[targetId],
        <int>[],
      ),
    );

    // SDK will not create indexes since collection size is too small.
    await _executeQuery(qry);
    _expectRemoteDocumentsReadByEngine(byKey: 0, byQuery: 2);
    _expectQueryReturned(<String>['coll/e', 'coll/a']);

    await _backfillIndexes();

    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('coll/f', 20, map(<dynamic>['foo', 9, 'count', 4])),
        <int>[targetId],
        <int>[],
      ),
    );

    await _executeQuery(qry);
    _expectRemoteDocumentsReadByEngine(byKey: 0, byQuery: 3);
    _expectQueryReturned(<String>['coll/e', 'coll/f', 'coll/a']);
  }

  @testMethod
  Future<void> testDoesNotAutoCreateIndexesWhenIndexLookUpIsExpensive() async {
    Query qry = query(
      'coll',
    ).filter(filter('array', 'array-contains-any', <Object?>[0, 7]));
    final int targetId = await _allocateQuery(qry);

    _localStore.indexAutoCreationEnabled = true;
    _defaultEngine.indexAutoCreationMinCollectionSize = 0;
    _defaultEngine.relativeIndexReadCostPerDocument = 5;

    await _applyRemoteEvent(
      addedRemoteEvent(
        doc(
          'coll/a',
          10,
          map(<dynamic>[
            'array',
            <Object?>[2, 7],
          ]),
        ),
        <int>[targetId],
        <int>[],
      ),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('coll/b', 10, map(<dynamic>['array', <int>[]])),
        <int>[targetId],
        <int>[],
      ),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(
        doc(
          'coll/c',
          10,
          map(<dynamic>[
            'array',
            <Object?>[3],
          ]),
        ),
        <int>[targetId],
        <int>[],
      ),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(
        doc(
          'coll/d',
          10,
          map(<dynamic>[
            'array',
            <Object?>[2, 10, 20],
          ]),
        ),
        <int>[targetId],
        <int>[],
      ),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(
        doc(
          'coll/e',
          10,
          map(<dynamic>[
            'array',
            <Object?>[2, 0, 8],
          ]),
        ),
        <int>[targetId],
        <int>[],
      ),
    );

    // SDK will not create indexes since relative read cost is too large.
    await _executeQuery(qry);
    _expectRemoteDocumentsReadByEngine(byKey: 0, byQuery: 2);
    _expectQueryReturned(<String>['coll/a', 'coll/e']);

    await _backfillIndexes();

    await _applyRemoteEvent(
      addedRemoteEvent(
        doc(
          'coll/f',
          20,
          map(<dynamic>[
            'array',
            <Object?>[0],
          ]),
        ),
        <int>[targetId],
        <int>[],
      ),
    );

    await _executeQuery(qry);
    _expectRemoteDocumentsReadByEngine(byKey: 0, byQuery: 3);
    _expectQueryReturned(<String>['coll/a', 'coll/e', 'coll/f']);
  }

  @testMethod
  Future<void> testIndexAutoCreationWorksWhenBackfillerRunsHalfway() async {
    Query qry = query(
      'coll',
    ).filter(filter('matches', '==', 'foo')).filter(filter('count', '>', 10));
    final int targetId = await _allocateQuery(qry);

    _localStore.indexAutoCreationEnabled = true;
    _defaultEngine.indexAutoCreationMinCollectionSize = 0;
    _defaultEngine.relativeIndexReadCostPerDocument = 2;

    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('coll/a', 10, map(<dynamic>['matches', 'foo', 'count', 11])),
        <int>[targetId],
        <int>[],
      ),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('coll/b', 10, map(<dynamic>['matches', 'foo', 'count', 9])),
        <int>[targetId],
        <int>[],
      ),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('coll/c', 10, map(<dynamic>['matches', 'foo'])),
        <int>[targetId],
        <int>[],
      ),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('coll/d', 10, map(<dynamic>['matches', 7, 'count', 11])),
        <int>[targetId],
        <int>[],
      ),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('coll/e', 10, map(<dynamic>['matches', 'foo', 'count', 21])),
        <int>[targetId],
        <int>[],
      ),
    );

    // First time qry is running without indexes.
    // Based on current heuristic, collection document counts (5) > 2 * resultSize (2).
    // Full matched index should be created.
    await _executeQuery(qry);
    _expectRemoteDocumentsReadByEngine(byKey: 0, byQuery: 2);
    _expectQueryReturned(<String>['coll/a', 'coll/e']);

    _backfillerMaxDocumentsToProcess = 2;
    await _backfillIndexes();

    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('coll/f', 20, map(<dynamic>['matches', 'foo', 'count', 15])),
        <int>[targetId],
        <int>[],
      ),
    );

    await _executeQuery(qry);
    _expectRemoteDocumentsReadByEngine(byKey: 1, byQuery: 2);
    _expectQueryReturned(<String>['coll/a', 'coll/f', 'coll/e']);
  }

  @testMethod
  Future<void>
  testIndexCreatedByIndexAutoCreationExistsAfterTurnOffAutoCreation() async {
    Query qry = query('coll').filter(filter('value', 'not-in', <Object?>[3]));
    final int targetId = await _allocateQuery(qry);

    _localStore.indexAutoCreationEnabled = true;
    _defaultEngine.indexAutoCreationMinCollectionSize = 0;
    _defaultEngine.relativeIndexReadCostPerDocument = 2;

    await _applyRemoteEvent(
      addedRemoteEvent(doc('coll/a', 10, map(<dynamic>['value', 5])), <int>[
        targetId,
      ], <int>[]),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(doc('coll/b', 10, map(<dynamic>['value', 3])), <int>[
        targetId,
      ], <int>[]),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(doc('coll/c', 10, map(<dynamic>['value', 3])), <int>[
        targetId,
      ], <int>[]),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(doc('coll/d', 10, map(<dynamic>['value', 3])), <int>[
        targetId,
      ], <int>[]),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(doc('coll/e', 10, map(<dynamic>['value', 2])), <int>[
        targetId,
      ], <int>[]),
    );

    // First time qry runs without indexes.
    // Based on current heuristic, collection document counts (5) > 2 * resultSize (2).
    // Full matched index should be created.
    await _executeQuery(qry);
    _expectRemoteDocumentsReadByEngine(byKey: 0, byQuery: 2);
    _expectQueryReturned(<String>['coll/e', 'coll/a']);

    _localStore.indexAutoCreationEnabled = false;

    await _backfillIndexes();

    await _applyRemoteEvent(
      addedRemoteEvent(doc('coll/f', 20, map(<dynamic>['value', 7])), <int>[
        targetId,
      ], <int>[]),
    );

    await _executeQuery(qry);
    _expectRemoteDocumentsReadByEngine(byKey: 2, byQuery: 1);
    _expectQueryReturned(<String>['coll/e', 'coll/a', 'coll/f']);
  }

  @testMethod
  Future<void> testDisableIndexAutoCreationWorks() async {
    Query query1 = query('coll').filter(filter('value', 'in', <Object?>[0, 1]));
    int targetId1 = await _allocateQuery(query1);

    _localStore.indexAutoCreationEnabled = true;
    _defaultEngine.indexAutoCreationMinCollectionSize = 0;
    _defaultEngine.relativeIndexReadCostPerDocument = 2;

    await _applyRemoteEvent(
      addedRemoteEvent(doc('coll/a', 10, map(<dynamic>['value', 1])), <int>[
        targetId1,
      ], <int>[]),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(doc('coll/b', 10, map(<dynamic>['value', 8])), <int>[
        targetId1,
      ], <int>[]),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('coll/c', 10, map(<dynamic>['value', 'string'])),
        <int>[targetId1],
        <int>[],
      ),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(doc('coll/d', 10, map(<dynamic>['value', false])), <int>[
        targetId1,
      ], <int>[]),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(doc('coll/e', 10, map(<dynamic>['value', 0])), <int>[
        targetId1,
      ], <int>[]),
    );

    // First time qry is running without indexes.
    // Based on current heuristic, collection document counts (5) > 2 * resultSize (2).
    // Full matched index should be created.
    await _executeQuery(query1);
    _expectRemoteDocumentsReadByEngine(byKey: 0, byQuery: 2);
    _expectQueryReturned(<String>['coll/a', 'coll/e']);

    _localStore.indexAutoCreationEnabled = false;

    await _backfillIndexes();

    await _executeQuery(query1);
    _expectRemoteDocumentsReadByEngine(byKey: 2, byQuery: 0);
    _expectQueryReturned(<String>['coll/a', 'coll/e']);

    Query query2 = query('foo').filter(filter('value', '!=', double.nan));
    int targetId2 = await _allocateQuery(query2);

    await _applyRemoteEvent(
      addedRemoteEvent(doc('foo/a', 10, map(<dynamic>['value', 5])), <int>[
        targetId2,
      ], <int>[]),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('foo/b', 10, map(<dynamic>['value', double.nan])),
        <int>[targetId2],
        <int>[],
      ),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('foo/c', 10, map(<dynamic>['value', double.nan])),
        <int>[targetId2],
        <int>[],
      ),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('foo/d', 10, map(<dynamic>['value', double.nan])),
        <int>[targetId2],
        <int>[],
      ),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('foo/e', 10, map(<dynamic>['value', 'string'])),
        <int>[targetId2],
        <int>[],
      ),
    );

    await _executeQuery(query2);
    _expectRemoteDocumentsReadByEngine(byKey: 0, byQuery: 2);
    _expectQueryReturned(<String>['foo/a', 'foo/e']);

    await _backfillIndexes();

    // Run the qry in second time, test index won't be created
    await _executeQuery(query2);
    _expectRemoteDocumentsReadByEngine(byKey: 0, byQuery: 2);
    _expectQueryReturned(<String>['foo/a', 'foo/e']);
  }

  @testMethod
  Future<void> testDeleteAllIndexesWorksWithIndexAutoCreation() async {
    Query qry = query('coll').filter(filter('value', '==', 'match'));
    final int targetId = await _allocateQuery(qry);

    _localStore.indexAutoCreationEnabled = true;
    _defaultEngine.indexAutoCreationMinCollectionSize = 0;
    _defaultEngine.relativeIndexReadCostPerDocument = 2;

    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('coll/a', 10, map(<dynamic>['value', 'match'])),
        <int>[targetId],
        <int>[],
      ),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('coll/b', 10, map(<dynamic>['value', double.nan])),
        <int>[targetId],
        <int>[],
      ),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(doc('coll/c', 10, map(<dynamic>['value', null])), <int>[
        targetId,
      ], <int>[]),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('coll/d', 10, map(<dynamic>['value', 'mismatch'])),
        <int>[targetId],
        <int>[],
      ),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('coll/e', 10, map(<dynamic>['value', 'match'])),
        <int>[targetId],
        <int>[],
      ),
    );

    // First time qry is running without indexes.
    // Based on current heuristic, collection document counts (5) > 2 * resultSize (2).
    // Full matched index should be created.
    await _executeQuery(qry);
    _expectRemoteDocumentsReadByEngine(byKey: 0, byQuery: 2);
    _expectQueryReturned(<String>['coll/a', 'coll/e']);

    await _backfillIndexes();

    await _executeQuery(qry);
    _expectRemoteDocumentsReadByEngine(byKey: 2, byQuery: 0);
    _expectQueryReturned(<String>['coll/a', 'coll/e']);

    await _localStore.deleteAllFieldIndexes();

    await _executeQuery(qry);
    _expectRemoteDocumentsReadByEngine(byKey: 0, byQuery: 2);
    _expectQueryReturned(<String>['coll/a', 'coll/e']);

    // Field index is created again.
    await _backfillIndexes();

    await _executeQuery(qry);
    _expectRemoteDocumentsReadByEngine(byKey: 2, byQuery: 0);
    _expectQueryReturned(<String>['coll/a', 'coll/e']);
  }

  @testMethod
  Future<void> testDeleteAllIndexesWorksWithManualAddedIndexes() async {
    final FieldIndex index = fieldIndex(
      'coll',
      indexId: 0,
      indexState: FieldIndex.initialState,
      fieldsAndKinds: <Object>['matches', SegmentKind.ascending],
    );
    await _configureFieldIndexes(<FieldIndex>[index]);

    Query qry = query('coll').filter(filter('matches', '==', true));
    final int targetId = await _allocateQuery(qry);

    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('coll/a', 10, map(<dynamic>['matches', true])),
        <int>[targetId],
        <int>[],
      ),
    );

    await _backfillIndexes();

    await _executeQuery(qry);
    _expectRemoteDocumentsReadByEngine(byKey: 1, byQuery: 0);
    _expectQueryReturned(<String>['coll/a']);

    await _localStore.deleteAllFieldIndexes();

    await _executeQuery(qry);
    _expectRemoteDocumentsReadByEngine(byKey: 0, byQuery: 1);
    _expectQueryReturned(<String>['coll/a']);
  }

  @testMethod
  Future<void> testIndexAutoCreationWorksWithMutation() async {
    Query qry = query(
      'coll',
    ).filter(filter('value', 'array-contains-any', <Object?>[8, 1, 'string']));
    final int targetId = await _allocateQuery(qry);

    _localStore.indexAutoCreationEnabled = true;
    _defaultEngine.indexAutoCreationMinCollectionSize = 0;
    _defaultEngine.relativeIndexReadCostPerDocument = 2;

    await _applyRemoteEvent(
      addedRemoteEvent(
        doc(
          'coll/a',
          10,
          map(<dynamic>[
            'value',
            <Object?>[8, 1, 'string'],
          ]),
        ),
        <int>[targetId],
        <int>[],
      ),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('coll/b', 10, map(<dynamic>['value', <int>[]])),
        <int>[targetId],
        <int>[],
      ),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(
        doc(
          'coll/c',
          10,
          map(<dynamic>[
            'value',
            <Object?>[3],
          ]),
        ),
        <int>[targetId],
        <int>[],
      ),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(
        doc(
          'coll/d',
          10,
          map(<dynamic>[
            'value',
            <Object?>[0, 5],
          ]),
        ),
        <int>[targetId],
        <int>[],
      ),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(
        doc(
          'coll/e',
          10,
          map(<dynamic>[
            'value',
            <Object?>['string'],
          ]),
        ),
        <int>[targetId],
        <int>[],
      ),
    );

    await _executeQuery(qry);
    _expectRemoteDocumentsReadByEngine(byKey: 0, byQuery: 2);
    _expectQueryReturned(<String>['coll/a', 'coll/e']);

    await _writeMutation(deleteMutation('coll/e'));

    await _backfillIndexes();

    await _writeMutation(
      setMutation(
        'coll/f',
        map(<dynamic>[
          'value',
          <Object?>[1],
        ]),
      ),
    );

    await _executeQuery(qry);
    _expectRemoteDocumentsReadByEngine(byKey: 1, byQuery: 0);
    // PORTING NOTE: byKey is 1 upstream (keys looked up: coll/a from the index); the port counts the overlays found,
    // and coll/a has none.
    _expectOverlaysReadByEngine(byKey: 0, byCollection: 1);
    _expectQueryReturned(<String>['coll/a', 'coll/f']);
  }

  @testMethod
  Future<void> testIndexAutoCreationDoesnotWorkWithMultipleInequality() async {
    Query qry = query(
      'coll',
    ).filter(filter('field1', '<', 5)).filter(filter('field2', '<', 5));
    final int targetId = await _allocateQuery(qry);

    _localStore.indexAutoCreationEnabled = true;
    _defaultEngine.indexAutoCreationMinCollectionSize = 0;
    _defaultEngine.relativeIndexReadCostPerDocument = 2;

    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('coll/a', 10, map(<dynamic>['field1', 1, 'field2', 2])),
        <int>[targetId],
        <int>[],
      ),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('coll/b', 10, map(<dynamic>['field1', 8, 'field2', 2])),
        <int>[targetId],
        <int>[],
      ),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('coll/c', 10, map(<dynamic>['field1', 'string', 'field2', 2])),
        <int>[targetId],
        <int>[],
      ),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(doc('coll/d', 10, map(<dynamic>['field1', 2])), <int>[
        targetId,
      ], <int>[]),
    );
    await _applyRemoteEvent(
      addedRemoteEvent(
        doc('coll/e', 10, map(<dynamic>['field1', 4, 'field2', 4])),
        <int>[targetId],
        <int>[],
      ),
    );

    // First time qry is running without indexes.
    // Based on current heuristic, collection document counts (5) > 2 * resultSize (2).
    // Full matched index will not be created since FieldIndex does not support multiple inequality.
    await _executeQuery(qry);
    _expectRemoteDocumentsReadByEngine(byKey: 0, byQuery: 2);
    _expectQueryReturned(<String>['coll/a', 'coll/e']);

    await _backfillIndexes();

    await _executeQuery(qry);
    _expectRemoteDocumentsReadByEngine(byKey: 0, byQuery: 2);
    _expectQueryReturned(<String>['coll/a', 'coll/e']);
  }

  /// Upstream runs this on a thread with a small stack to prove that 1000 server timestamp transforms on one field do
  /// not nest 1000 deep. Dart has no way to limit the stack, so the port checks the cause directly: the previous
  /// value of the pending timestamp is never itself a pending timestamp.
  ///
  /// PORTING NOTE: upstream also puts a nested server timestamp into the value of the patch. A pending server
  /// timestamp is not a value the port can write (the serializer rejects it), and its constructor cannot nest, so the
  /// patch here only carries the transform, which sees the pending timestamp of the previous mutation.
  @testMethod
  Future<void> testDeeplyNestedServerTimestamps() async {
    final FieldPath path = FieldPath.fromSingleSegment('timestamp');
    final List<FieldTransform> fieldTransforms = <FieldTransform>[
      FieldTransform(path, ServerTimestampOperation()),
    ];
    final DocumentKey key = DocumentKey.fromPathString('some/object/for/test');
    await _writeMutation(
      setMutation(key.path.toString(), map(<Object>['timestamp', 42])),
    );

    for (int i = 0; i < 1000; ++i) {
      await _writeMutation(
        PatchMutation(
          key,
          model.ObjectValue.empty,
          FieldMask.empty,
          Precondition.none,
          fieldTransforms,
        ),
      );
    }

    final MaybeDocument? document = await _localStore.readDocument(key);
    final model.FieldValue? value = (document! as Document).getField(path);
    expect(value, isA<model.ServerTimestampValue>());
    expect(
      (value! as model.ServerTimestampValue).previousFieldValue,
      model.IntegerValue.valueOf(42),
    );
  }

  // The "document_type" cases of SQLiteLocalStoreTest of the Android SDK (#7295). SQLite only.

  @testMethod
  Future<void> testDocumentTypeIsSetToFoundWhenFoundDocumentAdded() async {
    final Mutation mutation = setMutation(
      'coll/a',
      map(<String>['foo', 'bar']),
    );
    await _writeMutation(mutation);
    await _acknowledgeMutation(1);

    final Map<ResourcePath, int?> expected = <ResourcePath, int?>{
      mutation.key.path: 2, // 2 is a "found" document
    };
    expect(await _getDocumentTypeByPathFromRemoteDocumentsTable(), expected);
  }

  @testMethod
  Future<void>
  testDocumentTypeIsSetToNoDocumentWhenUnknownDocumentDeleted() async {
    final Mutation mutation = deleteMutation('coll/a');
    await _writeMutation(mutation);
    await _acknowledgeMutation(1);

    final Map<ResourcePath, int?> expected = <ResourcePath, int?>{
      mutation.key.path: 1, // 1 is a "no" document
    };
    expect(await _getDocumentTypeByPathFromRemoteDocumentsTable(), expected);
  }

  @testMethod
  Future<void>
  testDocumentTypeIsUpdatedToNoDocumentWhenFoundDocumentDeleted() async {
    final Mutation mutation = setMutation(
      'coll/a',
      map(<String>['foo', 'bar']),
    );
    await _writeMutation(mutation);
    await _acknowledgeMutation(1);
    await _writeMutation(deleteMutation('coll/a'));
    await _acknowledgeMutation(2);

    final Map<ResourcePath, int?> expected = <ResourcePath, int?>{
      mutation.key.path: 1, // 1 is a "no" document
    };
    expect(await _getDocumentTypeByPathFromRemoteDocumentsTable(), expected);
  }

  @testMethod
  Future<void>
  testDocumentTypeIsSetToUnknownWhenApplyingPatchMutationWithNoBaseDocument() async {
    final Mutation mutation = patchMutation(
      'coll/a',
      map(<String>['foo', 'bar']),
    );
    await _writeMutation(mutation);
    await _acknowledgeMutation(1);

    final Map<ResourcePath, int?> expected = <ResourcePath, int?>{
      mutation.key.path: 3, // 3 is a "unknown" document
    };
    expect(await _getDocumentTypeByPathFromRemoteDocumentsTable(), expected);
  }

  @testMethod
  Future<void> testQueryBackfillsRowsWithNullDocumentType() async {
    final Mutation foundDocMutation = setMutation(
      'coll/a',
      map(<String>['foo', 'bar']),
    );
    await _writeMutation(foundDocMutation);
    await _acknowledgeMutation(1);
    final Mutation noDocMutation = deleteMutation('coll/b');
    await _writeMutation(noDocMutation);
    await _acknowledgeMutation(1);
    final Mutation unknownDocMutation = patchMutation(
      'coll/c',
      map(<String>['foo', 'bar']),
    );
    await _writeMutation(unknownDocMutation);
    await _acknowledgeMutation(1);
    await (_persistence as SQLitePersistence).execute(
      'UPDATE remote_documents SET document_type = NULL',
    );
    expect(
      (await _getDocumentTypeByPathFromRemoteDocumentsTable()).values,
      <int?>[null, null, null],
      reason: 'precondition check: all rows have null document type',
    );

    await _executeQuery(query('coll'));

    final Map<ResourcePath, int?> expected = <ResourcePath, int?>{
      foundDocMutation.key.path: 2,
      noDocMutation.key.path: 1,
      unknownDocMutation.key.path: 3,
    };
    expect(await _getDocumentTypeByPathFromRemoteDocumentsTable(), expected);
  }

  @testMethod
  Future<void> testQueryResultsIncludeRowsWithNullDocumentType() async {
    await _writeMutation(setMutation('coll/a', map(<String>['foo', 'bar'])));
    await _acknowledgeMutation(1);
    await _writeMutation(deleteMutation('coll/b'));
    await _acknowledgeMutation(1);
    await _writeMutation(patchMutation('coll/c', map(<String>['foo', 'bar'])));
    await _acknowledgeMutation(1);
    await (_persistence as SQLitePersistence).execute(
      'UPDATE remote_documents SET document_type = NULL',
    );
    expect(
      (await _getDocumentTypeByPathFromRemoteDocumentsTable()).values,
      <int?>[null, null, null],
      reason: 'precondition check: all rows have null document type',
    );

    await _executeQuery(query('coll'));

    _expectQueryReturned(<String>['coll/a']);
  }

  /// Scans the entire "remote documents" sqlite table and returns the value of the "document type" column for each
  /// row, keyed by the value of the "path" column of the corresponding row. Note that the values of the returned map
  /// may be `null`, if the column value for that row is null.
  Future<Map<ResourcePath, int?>>
  _getDocumentTypeByPathFromRemoteDocumentsTable() async {
    final List<Map<String, dynamic>> rows =
        await (_persistence as SQLitePersistence).query(
          'SELECT path, document_type FROM remote_documents',
        );
    return <ResourcePath, int?>{
      for (final Map<String, dynamic> row in rows)
        EncodedPath.decodeResourcePath(row['path'] as String):
            row['document_type'] as int?,
    };
  }
}
