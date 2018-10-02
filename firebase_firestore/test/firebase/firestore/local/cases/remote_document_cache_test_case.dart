// File created by
// Lung Razvan <long1eu>
// on 02/10/2018

import 'dart:async';

import 'package:firebase_firestore/src/firebase/firestore/local/persistence.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/remote_document_cache.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';

import '../../../../util/test_util.dart';

class RemoteDocumentCacheTestCase {
  final Persistence persistence;
  RemoteDocumentCache remoteDocumentCache;

  RemoteDocumentCacheTestCase(this.persistence);

  void setUp() {
    remoteDocumentCache = persistence.remoteDocumentCache;
  }

  Future<void> tearDown() async => persistence.shutdown();

  Future<Document> addTestDocumentAtPath(String path) async {
    final Document doc = TestUtil.doc(path, 42, map(<dynamic>['data', 2]));
    await add(doc);
    return doc;
  }

  Future<void> add(MaybeDocument doc) async {
    await persistence.runTransaction(
        'add entry', () => remoteDocumentCache.add(doc));
  }

  Future<MaybeDocument> get(String path) {
    return remoteDocumentCache.get(key(path));
  }

  Future<void> remove(String path) async {
    await persistence.runTransaction(
        'remove entry', () => remoteDocumentCache.remove(key(path)));
  }
}

// ignore: always_specify_types
const key = TestUtil.key;
// ignore: always_specify_types
const map = TestUtil.map;
