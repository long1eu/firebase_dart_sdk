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

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_write_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_event.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:test/test.dart';


/// A small, self-contained driver around [LocalStore] for tests that need to
/// write mutations, apply remote events and assert on the resulting changes
/// and cached documents (the same role as the private helpers of
/// LocalStoreTestCase).
class LocalStoreDriver {
  LocalStoreDriver(this.persistence);

  final Persistence persistence;

  final List<MutationBatch> batches = <MutationBatch>[];
  ImmutableSortedMap<DocumentKey, MaybeDocument>? lastChanges;
  int lastTargetId = 0;
  late LocalStore localStore;

  Future<void> start() async {
    localStore = LocalStore(persistence, User.unauthenticated);
    await localStore.start();
  }

  Future<void> shutdown() => persistence.shutdown();

  Future<void> writeMutation(Mutation mutation) =>
      writeMutations(<Mutation>[mutation]);

  Future<void> writeMutations(List<Mutation> mutations) async {
    final LocalWriteResult result = await localStore.writeLocally(mutations);
    batches.add(MutationBatch(
      batchId: result.batchId,
      localWriteTime: Timestamp.now(),
      baseMutations: <Mutation>[],
      mutations: mutations,
    ));
    lastChanges = result.changes;
  }

  Future<void> applyRemoteEvent(RemoteEvent event) async {
    lastChanges = await localStore.applyRemoteEvent(event);
  }

  Future<void> rejectMutation() async {
    final MutationBatch batch = batches.removeAt(0);
    lastChanges = await localStore.rejectBatch(batch.batchId);
  }

  Future<int> allocateQuery(Query query) async {
    final QueryData queryData = await localStore.allocateTarget(query.toTarget());
    lastTargetId = queryData.targetId;
    return queryData.targetId;
  }

  void expectTargetId(int targetId) => expect(lastTargetId, targetId);

  void expectChanged(List<MaybeDocument> expected) {
    expect(lastChanges, isNotNull);
    final List<MaybeDocument> actual = lastChanges!
        .map((MapEntry<DocumentKey, MaybeDocument> entry) => entry.value)
        .toList();
    expect(actual, expected);
    lastChanges = null;
  }

  Future<void> expectContains(MaybeDocument expected) async {
    expect(await localStore.readDocument(expected.key), expected);
  }
}
