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

import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/explain_options.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/expression.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/pipeline.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/pipeline_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/stage.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/transaction.dart';
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;

const Set<String> _writeStages = <String>{
  'delete',
  'update',
  'insert',
  'upsert',
};

/// Adds [execute] to [Transaction]. Importing
/// `package:cloud_firestore_dart/pipelines.dart` makes it available.
extension TransactionPipelines on Transaction {
  /// Executes [pipeline] on the server inside this transaction. Only in a
  /// read-only transaction (`TransactionOptions(readOnly: true)`): the
  /// pipeline reads the snapshot of the database that every read of the
  /// transaction sees.
  ///
  /// In a read-write transaction the returned Future fails with a
  /// `FirestoreError` with code `invalidArgument`, as for
  /// `Transaction.getQuery`: such a transaction verifies at commit that the
  /// documents it read did not change, which is not possible for the results
  /// of a pipeline. A pipeline with a write stage (`delete`, `update`,
  /// `insert`, `upsert`) fails the same way: a read-only transaction cannot
  /// write. (The Enterprise emulator v1.22.0 would apply such a pipeline
  /// inside a read-only transaction, so the SDK checks it.)
  ///
  /// [indexMode], [explainOptions] and [rawOptions] are as for
  /// `Pipeline.execute`.
  ///
  /// PORTING NOTE: the JS and Android client SDKs have no pipelines in
  /// transactions; the Node.js server SDK has `Transaction.execute(pipeline)`.
  Future<PipelineSnapshot> execute(
    Pipeline pipeline, {
    PipelineIndexMode? indexMode,
    PipelineExplainOptions? explainOptions,
    Map<String, Object?>? rawOptions,
  }) async {
    if (pipeline.firestore != firestore) {
      throw ArgumentError(
        'Provided pipeline is from a different Cloud Firestore instance.',
      );
    }
    pipeline.checkExecutable();
    for (final Stage stage in pipeline.stages) {
      if (_writeStages.contains(stage.name)) {
        throw FirestoreError(
          'A pipeline with a ${stage.name} stage cannot run in a transaction: '
          'read-only transactions cannot write.',
          FirestoreErrorCode.invalidArgument,
        );
      }
    }
    final PipelineEncoder encoder = PipelineEncoder(firestore.modelDatabaseId);
    final proto.ExecutePipelineRequest request = pipeline.toExecuteRequest(
      encoder,
      indexMode: indexMode,
      explainOptions: explainOptions,
      rawOptions: rawOptions,
    );
    final List<proto.ExecutePipelineResponse> responses = await coreTransaction
        .executePipeline(request);
    return decodePipelineResponses(
      pipeline,
      firestore,
      encoder.serializer,
      responses,
    );
  }
}
