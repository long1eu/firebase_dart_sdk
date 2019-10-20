// File created by
// Lung Razvan <long1eu>
// on 29/09/2018
import 'dart:async';

import 'package:firebase_database_collection/firebase_database_collection.dart';
import 'package:firebase_firestore/src/firebase/firestore/auth/user.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/local_store.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/local_view_changes.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/local_write_result.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/persistence.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_data.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/no_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/remote_event.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/write_stream.dart';
import 'package:firebase_firestore/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../../../util/test_util.dart';

class LocalStoreTestCase {
  LocalStoreTestCase(this.persistence, this.garbageCollectorIsEager);

  final Persistence persistence;
  final bool garbageCollectorIsEager;

  List<MutationBatch> _batches;
  ImmutableSortedMap<DocumentKey, MaybeDocument> _lastChanges;
  int _lastTargetId;
  LocalStore localStore;

  Future<void> setUp() async {
    localStore = LocalStore(persistence, User.unauthenticated);
    await localStore.start();

    _batches = <MutationBatch>[];
    _lastChanges = null;
    _lastTargetId = 0;
  }

  Future<void> tearDown() => persistence.shutdown();

  Future<void> writeMutation(Mutation mutation) async {
    await writeMutations(<Mutation>[mutation]);
  }

  Future<void> writeMutations(List<Mutation> mutations) async {
    final LocalWriteResult result = await localStore.writeLocally(mutations);
    _batches.add(MutationBatch(result.batchId, Timestamp.now(), mutations));
    _lastChanges = result.changes;
  }

  Future<void> applyRemoteEvent(RemoteEvent event) async {
    _lastChanges = await localStore.applyRemoteEvent(event);
  }

  Future<void> notifyLocalViewChanges(LocalViewChanges changes) async {
    await localStore.notifyLocalViewChanges(<LocalViewChanges>[changes]);
  }

  Future<void> acknowledgeMutation(int documentVersion) async {
    final MutationBatch batch = _batches.removeAt(0);
    final SnapshotVersion _version = version(documentVersion);
    final MutationResult mutationResult = MutationResult(_version, /*transformResults:*/ null);
    final MutationBatchResult result = MutationBatchResult.create(
        batch, _version, <MutationResult>[mutationResult], WriteStream.emptyStreamToken);
    _lastChanges = await localStore.acknowledgeBatch(result);
  }

  Future<void> rejectMutation() async {
    final MutationBatch batch = _batches.removeAt(0);
    _lastChanges = await localStore.rejectBatch(batch.batchId);
  }

  Future<int> allocateQuery(Query query) async {
    final QueryData queryData = await localStore.allocateQuery(query);
    _lastTargetId = queryData.targetId;
    return queryData.targetId;
  }

  Future<void> releaseQuery(Query query) async {
    await localStore.releaseQuery(query);
  }

  /// Asserts that the last target ID is the given number.
  void assertTargetId(int targetId) {
    expect(_lastTargetId, targetId);
  }

  /// Asserts that a the [_lastChanges] contain the docs in the given array.
  void assertChanged([List<MaybeDocument> expected = const <MaybeDocument>[]]) {
    expect(_lastChanges, isNotNull);

    final List<MaybeDocument> actualList =
        _lastChanges.map((MapEntry<DocumentKey, MaybeDocument> entry) => entry.value).toList();

    expect(actualList, expected);
    _lastChanges = null;
  }

  /// Asserts that the given keys were removed.
  void assertRemoved(List<String> keyPaths) {
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
  Future<void> assertContains(MaybeDocument expected) async {
    final MaybeDocument actual = await localStore.readDocument(expected.key);

    expect(actual, expected);
  }

  /// Asserts that the given local store does not contain the given document.
  Future<void> assertNotContains(String keyPathString) async {
    final DocumentKey key = DocumentKey.fromPathString(keyPathString);
    final MaybeDocument actual = await localStore.readDocument(key);
    expect(actual, isNull);
  }
}
