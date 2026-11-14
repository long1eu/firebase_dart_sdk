// File created by
// Lung Razvan <long1eu>
// on 23/09/2018

import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundled_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/target.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_purpose.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/patch_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/set_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/no_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/unknown_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/admin/v1/index.dart'
    as admin;
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
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
    final proto.Document builder = proto.Document.create()
      ..name = rpcSerializer.encodeKey(document.key);

    final ObjectValue value = document.data;
    for (MapEntry<String, FieldValue> entry in value.internalValue) {
      builder.fields[entry.key] = rpcSerializer.encodeValue(entry.value);
    }

    final Timestamp updateTime = document.version.timestamp;
    builder.updateTime = rpcSerializer.encodeTimestamp(updateTime);
    return builder..freeze();
  }

  /// Decodes a Document proto to the equivalent model.
  Document _decodeDocument(
    proto.Document document,
    bool hasCommittedMutations,
  ) {
    final DocumentKey key = rpcSerializer.decodeKey(document.name);

    final SnapshotVersion version = rpcSerializer.decodeVersion(
      document.updateTime,
    );
    return Document.fromProto(
      key,
      version,
      hasCommittedMutations
          ? DocumentState.committedMutations
          : DocumentState.synced,
      document,
      rpcSerializer.decodeValue,
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
  NoDocument _decodeNoDocument(
    proto.NoDocument proto,
    bool hasCommittedMutations,
  ) {
    final DocumentKey key = rpcSerializer.decodeKey(proto.name);
    final SnapshotVersion version = rpcSerializer.decodeVersion(proto.readTime);
    return NoDocument(
      key,
      version,
      hasCommittedMutations: hasCommittedMutations,
    );
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

  /// Encodes the mutation of a document overlay for local storage.
  ///
  /// Unlike the mutations of a batch, overlay mutations hold the local view of the document, which can contain
  /// pending server timestamps ([ServerTimestampValue]). They are stored in the shape the Android SDK uses for them
  /// (a map with `__type__: 'server_timestamp'`, `__local_write_time__` and `__previous_value__`); overlays are never
  /// sent to the backend.
  proto.Write encodeOverlayMutation(Mutation mutation) {
    return rpcSerializer.encodeMutation(
      _mapOverlayValues(mutation, _encodeServerTimestamps),
    );
  }

  /// Decodes the mutation of a document overlay, see [encodeOverlayMutation].
  Mutation decodeOverlayMutation(proto.Write write) {
    return _mapOverlayValues(
      rpcSerializer.decodeMutation(write),
      _decodeServerTimestamps,
    );
  }

  static const String _typeKey = '__type__';
  static const String _serverTimestampType = 'server_timestamp';
  static const String _localWriteTimeKey = '__local_write_time__';
  static const String _previousValueKey = '__previous_value__';

  Mutation _mapOverlayValues(
    Mutation mutation,
    FieldValue Function(FieldValue) convert,
  ) {
    if (mutation is SetMutation) {
      return SetMutation(
        mutation.key,
        convert(mutation.value) as ObjectValue,
        mutation.precondition,
        mutation.fieldTransforms,
      );
    } else if (mutation is PatchMutation) {
      return PatchMutation(
        mutation.key,
        convert(mutation.value) as ObjectValue,
        mutation.mask,
        mutation.precondition,
        mutation.fieldTransforms,
      );
    }
    return mutation;
  }

  static FieldValue _encodeServerTimestamps(FieldValue value) {
    if (value is ServerTimestampValue) {
      final FieldValue? previousValue = value.previousFieldValue;
      return ObjectValue.fromMap(<String, FieldValue>{
        _typeKey: StringValue.valueOf(_serverTimestampType),
        _localWriteTimeKey: TimestampValue.valueOf(value.localWriteTime),
        if (previousValue != null)
          _previousValueKey: _encodeServerTimestamps(previousValue),
      });
    } else if (value is ObjectValue) {
      return ObjectValue.fromMap(<String, FieldValue>{
        for (MapEntry<String, FieldValue> entry in value.internalValue)
          entry.key: _encodeServerTimestamps(entry.value),
      });
    } else if (value is ArrayValue) {
      return ArrayValue.fromList(
        value.internalValue.map(_encodeServerTimestamps).toList(),
      );
    }
    return value;
  }

  static FieldValue _decodeServerTimestamps(FieldValue value) {
    if (value is ObjectValue) {
      final ImmutableSortedMap<String, FieldValue> fields = value.internalValue;
      final FieldValue? type = fields[_typeKey];
      final FieldValue? localWriteTime = fields[_localWriteTimeKey];
      if (type is StringValue &&
          type.value == _serverTimestampType &&
          localWriteTime is TimestampValue) {
        final FieldValue? previousValue = fields[_previousValueKey];
        return ServerTimestampValue(
          localWriteTime.value,
          previousValue == null ? null : _decodeServerTimestamps(previousValue),
        );
      }
      return ObjectValue.fromMap(<String, FieldValue>{
        for (MapEntry<String, FieldValue> entry in fields)
          entry.key: _decodeServerTimestamps(entry.value),
      });
    } else if (value is ArrayValue) {
      return ArrayValue.fromList(
        value.internalValue.map(_decodeServerTimestamps).toList(),
      );
    }
    return value;
  }

  /// Decodes the writes of a persisted batch. Batches written before field transforms were folded
  /// into set/patch writes (`Write.update_transforms`) contain a separate `transform` write after
  /// the set or patch it belongs to. Those are squashed into the preceding write so that the
  /// resulting mutations have the same shape as freshly created ones.
  List<Mutation> _decodeWrites(List<proto.Write> writes) {
    final List<Mutation> mutations = <Mutation>[];
    for (int i = 0; i < writes.length; i++) {
      final proto.Write write = writes[i];
      if (write.hasTransform()) {
        // A transform that does not follow a set or patch: it only ever applied to an existing
        // document, which is what a patch with an empty mask does.
        mutations.add(rpcSerializer.decodeMutation(_transformToPatch(write)));
        continue;
      }

      final bool nextIsTransform =
          write.hasUpdate() &&
          i + 1 < writes.length &&
          writes[i + 1].hasTransform();
      if (nextIsTransform) {
        final proto.Write joined = write.clone()
          ..updateTransforms.addAll(writes[i + 1].transform.fieldTransforms);
        mutations.add(rpcSerializer.decodeMutation(joined));
        i++;
      } else {
        mutations.add(rpcSerializer.decodeMutation(write));
      }
    }
    return mutations;
  }

  proto.Write _transformToPatch(proto.Write transformWrite) {
    final proto.Write patch = proto.Write.create()
      ..update = (proto.Document.create()
        ..name = transformWrite.transform.document)
      ..updateMask = proto.DocumentMask.create()
      ..updateTransforms.addAll(transformWrite.transform.fieldTransforms);
    if (transformWrite.hasCurrentDocument()) {
      patch.currentDocument = transformWrite.currentDocument;
    }
    return patch;
  }

  /// Decodes a [WriteBatch] proto into a MutationBatch model. */
  MutationBatch decodeMutationBatch(proto.WriteBatch batch) {
    final int batchId = batch.batchId;
    final Timestamp localWriteTime = rpcSerializer.decodeTimestamp(
      batch.localWriteTime,
    );

    final List<Mutation> baseMutations = _decodeWrites(batch.baseWrites);
    final List<Mutation> mutations = _decodeWrites(batch.writes);
    return MutationBatch(
      batchId: batchId,
      localWriteTime: localWriteTime,
      baseMutations: baseMutations,
      mutations: mutations,
    );
  }

  proto.Target encodeQueryData(QueryData queryData) {
    hardAssertLazy(
      queryData.purpose == QueryPurpose.listen,
      () =>
          'Only queries with purpose ${QueryPurpose.listen} '
          'may be stored, got ${queryData.purpose}',
    );

    final proto.Target result = proto.Target.create()
      ..targetId = queryData.targetId
      ..lastListenSequenceNumber = Int64(queryData.sequenceNumber)
      ..snapshotVersion = rpcSerializer.encodeVersion(queryData.snapshotVersion)
      ..lastLimboFreeSnapshotVersion = rpcSerializer.encodeVersion(
        queryData.lastLimboFreeSnapshotVersion,
      )
      ..resumeToken = queryData.resumeToken;

    final Target target = queryData.target;
    if (target.isDocumentQuery) {
      result.documents = rpcSerializer.encodeDocumentsTarget(target);
    } else {
      result.query = rpcSerializer.encodeQueryTarget(target);
    }

    return result..freeze();
  }

  QueryData decodeQueryData(proto.Target target) {
    final int targetId = target.targetId;

    final SnapshotVersion version = rpcSerializer.decodeVersion(
      target.snapshotVersion,
    );
    final SnapshotVersion lastLimboFreeSnapshotVersion = rpcSerializer
        .decodeVersion(target.lastLimboFreeSnapshotVersion);
    final Uint8List resumeToken = Uint8List.fromList(target.resumeToken);
    final int sequenceNumber = target.lastListenSequenceNumber.toInt();

    Target decodedTarget;

    if (target.hasDocuments()) {
      decodedTarget = rpcSerializer.decodeDocumentsTarget(target.documents);
    } else if (target.hasQuery()) {
      decodedTarget = rpcSerializer.decodeQueryTarget(target.query);
    } else {
      throw fail('Unknown targetType ${target.whichTargetType()}');
    }

    return QueryData(
      decodedTarget,
      targetId,
      sequenceNumber,
      QueryPurpose.listen,
      version,
      resumeToken,
      null,
      lastLimboFreeSnapshotVersion,
    );
  }

  /// Encodes a [BundledQuery] to the equivalent protocol buffer for local storage.
  proto.BundledQuery encodeBundledQuery(BundledQuery bundledQuery) {
    final proto.Target_QueryTarget queryTarget = rpcSerializer
        .encodeQueryTarget(bundledQuery.query.toTarget());

    final proto.BundledQuery result = proto.BundledQuery.create()
      ..limitType = bundledQuery.limitType == BundledQueryLimitType.first
          ? proto.BundledQuery_LimitType.FIRST
          : proto.BundledQuery_LimitType.LAST
      ..parent = queryTarget.parent
      ..structuredQuery = queryTarget.structuredQuery;

    return result..freeze();
  }

  /// Decodes a [proto.BundledQuery] proto to the equivalent model.
  BundledQuery decodeBundledQuery(proto.BundledQuery bundledQuery) {
    final BundledQueryLimitType limitType =
        bundledQuery.limitType == proto.BundledQuery_LimitType.FIRST
        ? BundledQueryLimitType.first
        : BundledQueryLimitType.last;
    final Target target = rpcSerializer.decodeQueryTarget(
      proto.Target_QueryTarget.create()
        ..parent = bundledQuery.parent
        ..structuredQuery = bundledQuery.structuredQuery,
    );
    // The stored target keeps the order constraints as the user wrote them (not flipped for limitToLast).
    final Query query = Query(
      target.path,
      collectionGroup: target.collectionGroup,
      filters: target.filters,
      explicitSortOrder: target.orderBy,
      limit: target.limit,
      startAt: target.startAt,
      endAt: target.endAt,
    );

    return BundledQuery(query, limitType);
  }

  /// Encodes the segments of a field index as the admin `Index` message that is stored with the index configuration.
  admin.Index encodeFieldIndexSegments(List<IndexSegment> segments) {
    // The Mobile SDKs treat all indices as collection group indices, as we run all collection group queries against
    // each collection separately.
    final admin.Index index = admin.Index.create()
      ..queryScope = admin.Index_QueryScope.COLLECTION_GROUP;

    for (final IndexSegment segment in segments) {
      final admin.Index_IndexField indexField = admin.Index_IndexField.create()
        ..fieldPath = segment.fieldPath.canonicalString;
      if (segment.kind == SegmentKind.contains) {
        indexField.arrayConfig = admin.Index_IndexField_ArrayConfig.CONTAINS;
      } else if (segment.kind == SegmentKind.ascending) {
        indexField.order = admin.Index_IndexField_Order.ASCENDING;
      } else {
        indexField.order = admin.Index_IndexField_Order.DESCENDING;
      }
      index.fields.add(indexField);
    }

    return index;
  }

  List<IndexSegment> decodeFieldIndexSegments(admin.Index index) {
    final List<IndexSegment> result = <IndexSegment>[];
    for (final admin.Index_IndexField field in index.fields) {
      final FieldPath fieldPath = FieldPath.fromServerFormat(field.fieldPath);
      final SegmentKind kind =
          field.whichValueMode() == admin.Index_IndexField_ValueMode.arrayConfig
          ? SegmentKind.contains
          : (field.order == admin.Index_IndexField_Order.ASCENDING
                ? SegmentKind.ascending
                : SegmentKind.descending);
      result.add(IndexSegment(fieldPath, kind));
    }
    return result;
  }
}
