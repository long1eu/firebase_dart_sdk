// Copyright 2019 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Port of upstream RemoteDocumentCacheTestCase.testSetReadAndDeleteLotsOfDocuments
// (written upstream after the sync point). The port has no removeAll, so the
// documents are removed one by one inside a single transaction.

import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/remote_document_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../../../util/test_util.dart';
import 'persistence_test_helpers.dart';

void main() {
  final Map<String, Future<Persistence> Function()> variants =
      <String, Future<Persistence> Function()>{
    'memory': createEagerGCMemoryPersistence,
    'sqlite': () => createSQLitePersistence(
        'firebase/firestore/local/remote_document_cache_lots_test-${const Uuid().v4()}.db'),
  };

  for (final MapEntry<String, Future<Persistence> Function()> variant
      in variants.entries) {
    test('testSetReadAndDeleteLotsOfDocuments (${variant.key})', () async {
      final Persistence persistence = await variant.value();
      final RemoteDocumentCache cache = persistence.remoteDocumentCache;
      try {
        // Make sure to force the SQLite implementation to split the large query
        // into several smaller ones.
        const int lotsOfDocuments = 2000;
        final List<DocumentKey> keys = <DocumentKey>[];
        final Map<DocumentKey, MaybeDocument?> expected =
            <DocumentKey, MaybeDocument?>{};
        await persistence.runTransaction('add docs', () async {
          for (int i = 0; i < lotsOfDocuments; i++) {
            final DocumentKey k = key('foo/$i');
            final Document document =
                doc('foo/$i', 42, map(<dynamic>['data', 2]));
            keys.add(k);
            expected[k] = document;
            await cache.add(document);
          }
        });

        Map<DocumentKey, MaybeDocument?> read = await cache.getAll(keys);
        expect(read, expected);

        await persistence.runTransaction('remove docs', () async {
          for (final DocumentKey k in keys) {
            await cache.remove(k);
          }
        });

        read = await cache.getAll(keys);
        expect(read.values.whereType<Document>(), isEmpty);
      } finally {
        await persistence.shutdown();
      }
    });
  }
}
