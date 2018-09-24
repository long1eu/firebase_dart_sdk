// File created by
// Lung Razvan <long1eu>
// on 23/09/2018

import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_data.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_purpose.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/object_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/no_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:firebase_firestore/src/firebase/timestamp.dart';
import 'package:firebase_firestore/src/proto/firestore/local/maybe_document.pb.dart'
    as proto;
import 'package:firebase_firestore/src/proto/firestore/local/mutation.pb.dart'
    as proto;
import 'package:firebase_firestore/src/proto/firestore/local/target.pb.dart'
    as proto;
import 'package:firebase_firestore/src/proto/google/firestore/v1beta1/common.pb.dart'
    as proto;
import 'package:firebase_firestore/src/proto/google/firestore/v1beta1/document.pb.dart'
    as proto;
import 'package:firebase_firestore/src/proto/google/firestore/v1beta1/firestore.pb.dart'
    as proto hide Target;
import 'package:firebase_firestore/src/proto/google/firestore/v1beta1/query.pb.dart'
    as proto;
import 'package:firebase_firestore/src/proto/google/firestore/v1beta1/write.pb.dart'
    as proto;
import 'package:firebase_firestore/src/proto/google/protobuf/struct.pb.dart'
    as proto show NullValue;
import 'package:firebase_firestore/src/proto/google/protobuf/timestamp.pb.dart'
    as proto;
import 'package:firebase_firestore/src/proto/google/protobuf/wrappers.pb.dart'
    as proto;
import 'package:firebase_firestore/src/proto/google/rpc/status.pb.dart'
    as proto;
import 'package:firebase_firestore/src/proto/google/type/latlng.pb.dart'
    as proto;
import 'package:fixnum/fixnum.dart';

/// Serializer for values stored in the LocalStore.
class LocalSerializer {
  final RemoteSerializer rpcSerializer;

  const LocalSerializer(this.rpcSerializer);

  /// Encodes a MaybeDocument model to the equivalent protocol buffer for local
  /// storage.
  proto.MaybeDocument encodeMaybeDocument(MaybeDocument document) {
    proto.MaybeDocument builder = proto.MaybeDocument.create();
    if (document is NoDocument) {
      builder.noDocument = encodeNoDocument(document);
    } else if (document is Document) {
      builder.document = encodeDocument(document);
    } else {
      throw Assert.fail('Unknown document type ${document.runtimeType}');
    }
    return builder.freeze();
  }

  /// Decodes a MaybeDocument proto to the equivalent model.
  MaybeDocument decodeMaybeDocument(proto.MaybeDocument data) {
    if (data.hasDocument()) {
      return decodeDocument(data.document);
    } else if (data.hasNoDocument()) {
      return decodeNoDocument(data.noDocument);
    } else {
      throw Assert.fail('Unknown MaybeDocument $data');
    }
  }

  /// Encodes a Document for local storage. This differs from the v1beta1 RPC
  /// serializer for Documents in that it preserves the updateTime, which is
  /// considered an output only value by the server.
  /*private*/
  proto.Document encodeDocument(Document document) {
    final proto.Document builder = proto.Document.create();
    builder.name = rpcSerializer.encodeKey(document.key);

    final ObjectValue value = document.data;
    for (MapEntry<String, FieldValue> entry in value.internalValue) {
      final proto.Document_FieldsEntry fieldsEntry =
          proto.Document_FieldsEntry.create()
            ..key = entry.key
            ..value = rpcSerializer.encodeValue(entry.value);
      builder.fields.add(fieldsEntry);
    }

    final Timestamp updateTime = document.version.timestamp;
    builder.updateTime = rpcSerializer.encodeTimestamp(updateTime);
    return builder.freeze();
  }

  /// Decodes a Document proto to the equivalent model.
  /*private*/
  Document decodeDocument(proto.Document document) {
    final DocumentKey key = rpcSerializer.decodeKey(document.name);
    final ObjectValue value = rpcSerializer.decodeFields(document.fields);
    final SnapshotVersion version =
        rpcSerializer.decodeVersion(document.updateTime);
    return new Document(key, version, value, false);
  }

  /// Encodes a NoDocument value to the equivalent proto.
  /*private*/
  proto.NoDocument encodeNoDocument(NoDocument document) {
    proto.NoDocument builder = proto.NoDocument.create();
    builder.name = rpcSerializer.encodeKey(document.key);
    builder.readTime =
        rpcSerializer.encodeTimestamp(document.version.timestamp);
    return builder.freeze();
  }

  /// Decodes a NoDocument proto to the equivalent model.
  /*private*/
  NoDocument decodeNoDocument(proto.NoDocument proto) {
    DocumentKey key = rpcSerializer.decodeKey(proto.name);
    SnapshotVersion version = rpcSerializer.decodeVersion(proto.readTime);
    return new NoDocument(key, version);
  }

  /// Encodes a MutationBatch model for local storage in the mutation queue.
  proto.WriteBatch encodeMutationBatch(MutationBatch batch) {
    final proto.WriteBatch result = proto.WriteBatch.create()
      ..batchId = batch.batchId
      ..localWriteTime = rpcSerializer.encodeTimestamp(batch.localWriteTime);
    for (Mutation mutation in batch.mutations) {
      result.writes.add(rpcSerializer.encodeMutation(mutation));
    }
    return result.freeze();
  }

  /** Decodes a WriteBatch proto into a MutationBatch model. */
  MutationBatch decodeMutationBatch(proto.WriteBatch batch) {
    final int batchId = batch.batchId;
    Timestamp localWriteTime =
        rpcSerializer.decodeTimestamp(batch.localWriteTime);

    final int count = batch.writes.length;
    List<Mutation> mutations = List<Mutation>(count);
    for (int i = 0; i < count; i++) {
      mutations.add(rpcSerializer.decodeMutation(batch.writes[i]));
    }

    return new MutationBatch(batchId, localWriteTime, mutations);
  }

  proto.Target encodeQueryData(QueryData queryData) {
    Assert.hardAssert(queryData.purpose == QueryPurpose.listen,
        "Only queries with purpose ${QueryPurpose.listen} may be stored, got ${queryData.purpose}");

    proto.Target result = proto.Target.create();

    result
      ..targetId = queryData.targetId
      ..lastListenSequenceNumber = Int64(queryData.sequenceNumber)
      ..snapshotVersion = rpcSerializer.encodeVersion(queryData.snapshotVersion)
      ..resumeToken = queryData.resumeToken;

    final Query query = queryData.query;
    if (query.isDocumentQuery) {
      result.documents = rpcSerializer.encodeDocumentsTarget(query);
    } else {
      result.query = rpcSerializer.encodeQueryTarget(query);
    }

    return result.freeze();
  }

  QueryData decodeQueryData(proto.Target target) {
    final int targetId = target.targetId;

    final SnapshotVersion version =
        rpcSerializer.decodeVersion(target.snapshotVersion);
    final List<int> resumeToken = target.resumeToken;
    final int sequenceNumber = target.lastListenSequenceNumber.toInt();

    Query query;

    if (target.hasDocuments()) {
      query = rpcSerializer.decodeDocumentsTarget(target.documents);
    } else if (target.hasQuery()) {
      query = rpcSerializer.decodeQueryTarget(target.query);
    } else {
      throw Assert.fail('Unknown targetType $target}');
    }

    return new QueryData(
      query,
      targetId,
      sequenceNumber,
      QueryPurpose.listen,
      version,
      resumeToken,
    );
  }
}
