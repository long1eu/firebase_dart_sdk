// Copyright 2026 Google LLC
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
import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/aggregate_field.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/datastore.dart';
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;

/// The [TransactionClient] of a Firestore Lite transaction: every request is
/// a call of its own of [Firestore.run]. It forwards every method of
/// [TransactionClient] (a new one there fails to compile here until it is
/// forwarded too).
///
/// So, as in the JS SDK, a transaction in progress does not hold off
/// [Firestore.terminate]: once the instance is terminated, the next read or
/// the commit of the transaction fails with `failedPrecondition`, and only
/// the request on the wire at that moment is waited for.
class LiteTransactionClient implements TransactionClient {
  /// A client that sends the requests of a transaction of [firestore].
  LiteTransactionClient(this._firestore);

  final Firestore _firestore;

  @override
  Future<List<MutationResult>> commit(List<Mutation> mutations) =>
      _firestore.run(
        (Datastore datastore) => datastore.transactionClient.commit(mutations),
      );

  @override
  Future<Uint8List> beginReadOnlyTransaction({SnapshotVersion? readTime}) =>
      _firestore.run(
        (Datastore datastore) => datastore.transactionClient
            .beginReadOnlyTransaction(readTime: readTime),
      );

  @override
  Future<void> rollback(Uint8List transaction) => _firestore.run(
    (Datastore datastore) => datastore.transactionClient.rollback(transaction),
  );

  @override
  Future<List<Document>> runQuery(Query query, Uint8List transaction) =>
      _firestore.run(
        (Datastore datastore) =>
            datastore.transactionClient.runQuery(query, transaction),
      );

  @override
  Future<Map<String, FieldValue>> runAggregateQuery(
    Query query,
    List<AggregateField> aggregateFields,
    Uint8List transaction,
  ) => _firestore.run(
    (Datastore datastore) => datastore.transactionClient.runAggregateQuery(
      query,
      aggregateFields,
      transaction,
    ),
  );

  @override
  Future<List<proto.ExecutePipelineResponse>> executePipeline(
    proto.ExecutePipelineRequest request,
    Uint8List transaction,
  ) => _firestore.run(
    (Datastore datastore) =>
        datastore.transactionClient.executePipeline(request, transaction),
  );

  @override
  Future<List<MaybeDocument>> lookup(
    List<DocumentKey> keys, {
    Uint8List? transaction,
  }) => _firestore.run(
    (Datastore datastore) =>
        datastore.transactionClient.lookup(keys, transaction: transaction),
  );
}
