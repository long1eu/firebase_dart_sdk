// File created by
// Lung Razvan <long1eu>
// on 29/09/2018

import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_firestore/src/firebase/firestore/auth/user.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/lru_delegate.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/mutation_queue.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/persistence.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_cache.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_data.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_purpose.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/reference_set.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/remote_document_cache.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/set_mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/object_value.dart';

import '../../../../../util/test_util.dart';

class LruGarbageCollectorTestCase {
  Persistence persistence;
  QueryCache queryCache;
  MutationQueue mutationQueue;
  RemoteDocumentCache documentCache;
  LruGarbageCollector garbageCollector;
  int previousTargetId;
  int previousDocNum;
  int initialSequenceNumber;
  ObjectValue testValue;

  Future<Persistence> Function() getPersistence;

  LruGarbageCollectorTestCase(this.getPersistence);

  Future<void> setUp() async {
    previousTargetId = 500;
    previousDocNum = 10;
    final Map<String, Object> dataMap = <String, Object>{
      'test': 'data',
      'foo': true,
      'bar': 3,
    };

    testValue = wrapMap(dataMap);
    await newTestResources();
  }

  Future<void> tearDown() => persistence.shutdown();

  Future<void> newTestResources() async {
    persistence = await getPersistence();

    persistence.referenceDelegate.inMemoryPins = ReferenceSet();
    queryCache = persistence.queryCache;
    documentCache = persistence.remoteDocumentCache;
    const User user = User('user');
    mutationQueue = persistence.getMutationQueue(user);
    await mutationQueue.start();

    initialSequenceNumber = queryCache.highestListenSequenceNumber;
    // ignore: avoid_as
    final LruDelegate delegate = persistence.referenceDelegate as LruDelegate;
    garbageCollector = delegate.garbageCollector;
  }

  QueryData nextQueryData() {
    final int targetId = ++previousTargetId;
    final int sequenceNumber =
        persistence.referenceDelegate.currentSequenceNumber;
    final Query _query = query('path$targetId');
    return QueryData.init(
        _query, targetId, sequenceNumber, QueryPurpose.listen);
  }

  Future<void> updateTargetInTransaction(QueryData queryData) async {
    final SnapshotVersion _version = version(2);
    final Uint8List _resumeToken = resumeToken(2);
    final QueryData updated = queryData.copyWith(
      sequenceNumber: persistence.referenceDelegate.currentSequenceNumber,
      snapshotVersion: _version,
      resumeToken: _resumeToken,
    );
    await queryCache.updateQueryData(updated);
  }

  Future<QueryData> addNextQueryInTransaction() async {
    final QueryData queryData = nextQueryData();
    await queryCache.addQueryData(queryData);
    return queryData;
  }

  Future<QueryData> addNextQuery() {
    return persistence.runTransactionAndReturn(
        'Add query', addNextQueryInTransaction);
  }

  DocumentKey nextTestDocumentKey() {
    return DocumentKey.fromPathString('docs/doc_${++previousDocNum}');
  }

  Document nextTestDocument() {
    final DocumentKey key = nextTestDocumentKey();
    const int version = 1;
    final Map<String, Object> data = <String, Object>{
      'baz': true,
      'ok': 'fine',
    };

    return doc(key, version, data);
  }

  Future<Document> cacheADocumentInTransaction() async {
    final Document doc = nextTestDocument();
    await documentCache.add(doc);
    return doc;
  }

  Future<void> markDocumentEligibleForGcInTransaction(DocumentKey key) async {
    await persistence.referenceDelegate.removeMutationReference(key);
  }

  Future<void> markDocumentEligibleForGc(DocumentKey key) async {
    await persistence.runTransaction('Removing mutation reference',
        () => markDocumentEligibleForGcInTransaction(key));
  }

  Future<void> markADocumentEligibleForGc() async {
    final DocumentKey key = nextTestDocumentKey();
    await markDocumentEligibleForGc(key);
  }

  Future<void> markADocumentEligibleForGcInTransaction() async {
    final DocumentKey key = nextTestDocumentKey();
    await markDocumentEligibleForGcInTransaction(key);
  }

  Future<void> addDocumentToTarget(DocumentKey key, int targetId) async {
    await queryCache.addMatchingKeys(keySet(<DocumentKey>[key]), targetId);
  }

  Future<void> removeDocumentFromTarget(DocumentKey key, int targetId) async {
    await queryCache.removeMatchingKeys(keySet(<DocumentKey>[key]), targetId);
  }

  Future<int> removeTargets(int upperBound, Set<int> activeTargetIds) {
    return persistence.runTransactionAndReturn('Remove queries',
        () => garbageCollector.removeTargets(upperBound, activeTargetIds));
  }

  SetMutation mutation(DocumentKey key) {
    return SetMutation(key, testValue, Precondition.none);
  }
}
