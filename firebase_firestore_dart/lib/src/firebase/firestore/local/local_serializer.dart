// File created by
// Lung Razvan <long1eu>
// on 23/09/2018

import 'dart:typed_data';

import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_data.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_purpose.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/no_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/unknown_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/object_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:firebase_firestore/src/firebase/timestamp.dart';
import 'package:firebase_firestore/src/proto/index.dart' as proto;
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
        ..document = document.proto ?? _encodeDocument(document)
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
    final proto.Document builder = proto.Document.create()..name = rpcSerializer.encodeKey(document.key);

    final ObjectValue value = document.data;
    for (MapEntry<String, FieldValue> entry in value.internalValue) {
      builder.fields[entry.key] = rpcSerializer.encodeValue(entry.value);
    }

    final Timestamp updateTime = document.version.timestamp;
    builder.updateTime = rpcSerializer.encodeTimestamp(updateTime);
    return builder..freeze();
  }

  /// Decodes a Document proto to the equivalent model.
  Document _decodeDocument(proto.Document document, bool hasCommittedMutations) {
    final DocumentKey key = rpcSerializer.decodeKey(document.name);
    final ObjectValue value = rpcSerializer.decodeDocumentFields(document.fields);
    final SnapshotVersion version = rpcSerializer.decodeVersion(document.updateTime);
    return Document(
      key,
      version,
      value,
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
    for (Mutation mutation in batch.mutations) {
      result.writes.add(rpcSerializer.encodeMutation(mutation));
    }
    return result..freeze();
  }

  /// Decodes a [WriteBatch] proto into a MutationBatch model. */
  MutationBatch decodeMutationBatch(proto.WriteBatch batch) {
    final int batchId = batch.batchId;
    final Timestamp localWriteTime = rpcSerializer.decodeTimestamp(batch.localWriteTime);

    final int count = batch.writes.length;
    final List<Mutation> mutations = List<Mutation>(count);
    for (int i = 0; i < count; i++) {
      mutations[i] = rpcSerializer.decodeMutation(batch.writes[i]);
    }

    return MutationBatch(batchId, localWriteTime, mutations);
  }

  proto.Target encodeQueryData(QueryData queryData) {
    hardAssert(
        queryData.purpose == QueryPurpose.listen,
        'Only queries with purpose ${QueryPurpose.listen} '
        'may be stored, got ${queryData.purpose}');

    final proto.Target result = proto.Target.create()
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

    return result..freeze();
  }

  QueryData decodeQueryData(proto.Target target) {
    final int targetId = target.targetId;

    final SnapshotVersion version = rpcSerializer.decodeVersion(target.snapshotVersion);
    final Uint8List resumeToken = Uint8List.fromList(target.resumeToken);
    final int sequenceNumber = target.lastListenSequenceNumber.toInt();

    Query query;

    if (target.hasDocuments()) {
      query = rpcSerializer.decodeDocumentsTarget(target.documents);
    } else if (target.hasQuery()) {
      query = rpcSerializer.decodeQueryTarget(target.query);
    } else {
      throw fail('Unknown targetType $target}');
    }

    return QueryData(
      query,
      targetId,
      sequenceNumber,
      QueryPurpose.listen,
      version,
      resumeToken,
    );
  }
}
