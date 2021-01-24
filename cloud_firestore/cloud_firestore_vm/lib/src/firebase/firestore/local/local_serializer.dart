// File created by
// Lung Razvan <long1eu>
// on 23/09/2018

import 'dart:typed_data';

import 'package:cloud_firestore_vm/src/firebase/firestore/core/target.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/query_purpose.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistence/target_data.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/no_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/object_value.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/unknown_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_vm/src/firebase/timestamp.dart';
import 'package:cloud_firestore_vm/src/proto/index.dart' as proto;
import 'package:fixnum/fixnum.dart';

/// Serializer for values stored in the LocalStore.
class LocalSerializer {
  const LocalSerializer(this.rpcSerializer);

  final RemoteSerializer rpcSerializer;

  /// Encodes a MaybeDocument model to the equivalent protocol buffer for local storage.
  proto.MaybeDocument encodeMaybeDocument(MaybeDocument document) {
    final proto.MaybeDocument builder = proto.MaybeDocument.create();
    if (document is NoDocument) {
      builder
        ..noDocument = _encodeNoDocument(document)
        ..hasCommittedMutations = document.hasCommittedMutations;
    } else if (document is Document) {
      builder
        ..document = _encodeDocument(document)
        ..hasCommittedMutations = document.hasCommittedMutations;
    } else if (document is UnknownDocument) {
      builder
        ..unknownDocument = _encodeUnknownDocument(document)
        ..hasCommittedMutations = true;
    } else {
      throw fail('Unknown document type ${document.runtimeType}');
    }

    return builder..freeze();
  }

  /// Decodes a MaybeDocument proto to the equivalent model.
  MaybeDocument decodeMaybeDocument(proto.MaybeDocument data) {
    if (data.hasDocument()) {
      return _decodeDocument(data.document, data.hasCommittedMutations);
    } else if (data.hasNoDocument()) {
      return _decodeNoDocument(data.noDocument, data.hasCommittedMutations);
    } else if (data.hasUnknownDocument()) {
      return _decodeUnknownDocument(data.unknownDocument);
    } else {
      throw fail('Unknown MaybeDocument $data');
    }
  }

  /// Encodes a Document for local storage. This differs from the v1 RPC serializer for Documents in that it preserves
  /// the updateTime, which is considered an output only value by the server.
  proto.Document _encodeDocument(Document document) {
    final proto.Document builder = proto.Document.create() //
      ..name = rpcSerializer.encodeKey(document.key)
      ..fields.addAll(document.data.fields);

    final Timestamp updateTime = document.version.timestamp;
    builder.updateTime = rpcSerializer.encodeTimestamp(updateTime);
    return builder..freeze();
  }

  /// Decodes a Document proto to the equivalent model.
  Document _decodeDocument(proto.Document document, bool hasCommittedMutations) {
    final DocumentKey key = rpcSerializer.decodeKey(document.name);

    final SnapshotVersion version = rpcSerializer.decodeVersion(document.updateTime);
    return Document(
      key,
      version,
      ObjectValue.fromMap(document.fields),
      hasCommittedMutations ? DocumentState.committedMutations : DocumentState.synced,
    );
  }

  /// Encodes a NoDocument value to the equivalent proto.
  proto.NoDocument _encodeNoDocument(NoDocument document) {
    return proto.NoDocument.create()
      ..name = rpcSerializer.encodeKey(document.key)
      ..readTime = rpcSerializer.encodeTimestamp(document.version.timestamp)
      ..freeze();
  }

  /// Decodes a NoDocument proto to the equivalent model.
  NoDocument _decodeNoDocument(proto.NoDocument proto, bool hasCommittedMutations) {
    final DocumentKey key = rpcSerializer.decodeKey(proto.name);
    final SnapshotVersion version = rpcSerializer.decodeVersion(proto.readTime);
    return NoDocument(key, version, hasCommittedMutations: hasCommittedMutations);
  }

  /// Encodes a [UnknownDocument] value to the equivalent proto.
  proto.UnknownDocument _encodeUnknownDocument(UnknownDocument document) {
    final proto.UnknownDocument builder = proto.UnknownDocument.create()
      ..name = rpcSerializer.encodeKey(document.key)
      ..version = rpcSerializer.encodeTimestamp(document.version.timestamp);

    return builder..freeze();
  }

  /// Decodes a [UnknownDocument] proto to the equivalent model.
  UnknownDocument _decodeUnknownDocument(proto.UnknownDocument proto) {
    final DocumentKey key = rpcSerializer.decodeKey(proto.name);
    final SnapshotVersion version = rpcSerializer.decodeVersion(proto.version);
    return UnknownDocument(key, version);
  }

  /// Encodes a MutationBatch model for local storage in the mutation queue.
  proto.WriteBatch encodeMutationBatch(MutationBatch batch) {
    final proto.WriteBatch result = proto.WriteBatch.create()
      ..batchId = batch.batchId
      ..localWriteTime = rpcSerializer.encodeTimestamp(batch.localWriteTime);
    for (Mutation mutation in batch.baseMutations) {
      result.baseWrites.add(rpcSerializer.encodeMutation(mutation));
    }
    for (Mutation mutation in batch.mutations) {
      result.writes.add(rpcSerializer.encodeMutation(mutation));
    }
    return result..freeze();
  }

  /// Decodes a [WriteBatch] proto into a MutationBatch model. */
  MutationBatch decodeMutationBatch(proto.WriteBatch batch) {
    final int batchId = batch.batchId;
    final Timestamp localWriteTime = rpcSerializer.decodeTimestamp(batch.localWriteTime);

    final int baseMutationsCount = batch.baseWrites.length;
    final List<Mutation> baseMutations = List<Mutation>(baseMutationsCount);
    for (int i = 0; i < baseMutationsCount; i++) {
      baseMutations[i] = rpcSerializer.decodeMutation(batch.baseWrites[i]);
    }
    final List<Mutation> mutations = <Mutation>[];
    // Squash old transform mutations into existing patch or set mutations. The replacement of
    // representing `transforms` with `update_transforms` on the SDK means that old `transform`
    // mutations stored in IndexedDB need to be updated to `update_transforms`.
    // TODO(b/174608374): Remove this code once we perform a schema migration.
    for (int i = batch.writes.length - 1; i >= 0; --i) {
      final proto.Write mutation = batch.writes[i];
      if (mutation.hasTransform()) {
        hardAssert(
          i >= 1 && !batch.writes[i - 1].hasTransform() && batch.writes[i - 1].hasUpdate(),
          'TransformMutation should be preceded by a patch or set mutation',
        );
        final proto.Write newMutationBuilder = batch.writes[i - 1].toBuilder();
        newMutationBuilder.updateTransforms.addAll(mutation.transform.fieldTransforms);

        mutations.add(rpcSerializer.decodeMutation(newMutationBuilder.freeze()));
        --i;
      } else {
        mutations.add(rpcSerializer.decodeMutation(mutation));
      }
    }

    return MutationBatch(
      batchId: batchId,
      localWriteTime: localWriteTime,
      baseMutations: baseMutations,
      // Reverse the mutations to preserve the original ordering since the above for-loop iterates in
      // reverse order. We use reverse() instead of prepending the elements into the mutations array
      // since prepending to a List is O(n).
      mutations: mutations.reversed.toList(),
    );
  }

  proto.Target encodeTargetData(TargetData targetData) {
    hardAssert(
      targetData.purpose == QueryPurpose.listen,
      'Only queries with purpose ${QueryPurpose.listen} may be stored, got ${targetData.purpose}',
    );

    final proto.Target result = proto.Target.create()
      ..targetId = targetData.targetId
      ..lastListenSequenceNumber = Int64(targetData.sequenceNumber)
      ..lastLimboFreeSnapshotVersion = rpcSerializer.encodeVersion(targetData.lastLimboFreeSnapshotVersion)
      ..snapshotVersion = rpcSerializer.encodeVersion(targetData.snapshotVersion)
      ..resumeToken = targetData.resumeToken;

    final Target target = targetData.target;
    if (target.isDocumentQuery) {
      result.documents = rpcSerializer.encodeDocumentsTarget(target);
    } else {
      result.query = rpcSerializer.encodeQueryTarget(target);
    }

    return result..freeze();
  }

  TargetData decodeTargetData(proto.Target targetProto) {
    final int targetId = targetProto.targetId;

    final SnapshotVersion version = rpcSerializer.decodeVersion(targetProto.snapshotVersion);
    final SnapshotVersion lastLimboFreeSnapshotVersion =
        rpcSerializer.decodeVersion(targetProto.lastLimboFreeSnapshotVersion);
    final Uint8List resumeToken = Uint8List.fromList(targetProto.resumeToken);
    final int sequenceNumber = targetProto.lastListenSequenceNumber.toInt();

    Target target;
    switch (targetProto.whichTargetType()) {
      case proto.Target_TargetType.documents:
        target = rpcSerializer.decodeDocumentsTarget(targetProto.documents);
        break;
      case proto.Target_TargetType.query:
        target = rpcSerializer.decodeQueryTarget(targetProto.query);
        break;
      default:
        throw fail('Unknown targetType $targetProto}');
    }

    return TargetData(
      target,
      targetId,
      sequenceNumber,
      QueryPurpose.listen,
      version,
      lastLimboFreeSnapshotVersion,
      resumeToken,
    );
  }
}
