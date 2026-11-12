// This is a generated file - do not edit.
//
// Generated from firebase/firestore/proto/mutation.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart'
    as $1;

import '../../../google/firestore/v1/write.pb.dart' as $0;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// Each user gets a single queue of WriteBatches to apply to the server.
/// MutationQueue tracks the metadata about the queue.
class MutationQueue extends $pb.GeneratedMessage {
  factory MutationQueue({
    $core.int? lastAcknowledgedBatchId,
    $core.List<$core.int>? lastStreamToken,
  }) {
    final result = MutationQueue._();
    if (lastAcknowledgedBatchId != null)
      result.lastAcknowledgedBatchId = lastAcknowledgedBatchId;
    if (lastStreamToken != null) result.lastStreamToken = lastStreamToken;
    return result;
  }

  MutationQueue._();

  factory MutationQueue.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MutationQueue()..mergeFromBuffer(data, registry);
  factory MutationQueue.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MutationQueue()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MutationQueue',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'firestore.client'),
      createEmptyInstance: MutationQueue.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'lastAcknowledgedBatchId')
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'lastStreamToken', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MutationQueue clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MutationQueue copyWith(void Function(MutationQueue) updates) =>
      super.copyWith((message) => updates(message as MutationQueue))
          as MutationQueue;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use MutationQueue() / MutationQueue.new instead')
  static MutationQueue create() => MutationQueue._();
  static $pb.GeneratedMessage $_createMessage() => MutationQueue._();
  @$core.override
  MutationQueue createEmptyInstance() => MutationQueue._();
  @$core.pragma('dart2js:noInline')
  static MutationQueue getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MutationQueue>(
          MutationQueue.$_createMessage);
  static MutationQueue? _defaultInstance;

  /// An identifier for the highest numbered batch that has been acknowledged by
  /// the server. All WriteBatches in this queue with batch_ids less than or
  /// equal to this value are considered to have been acknowledged by the
  /// server.
  @$pb.TagNumber(1)
  $core.int get lastAcknowledgedBatchId => $_getIZ(0);
  @$pb.TagNumber(1)
  set lastAcknowledgedBatchId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLastAcknowledgedBatchId() => $_has(0);
  @$pb.TagNumber(1)
  void clearLastAcknowledgedBatchId() => $_clearField(1);

  /// A stream token that was previously sent by the server.
  ///
  /// See StreamingWriteRequest in datastore.proto for more details about usage.
  ///
  /// After sending this token, earlier tokens may not be used anymore so only a
  /// single stream token is retained.
  @$pb.TagNumber(2)
  $core.List<$core.int> get lastStreamToken => $_getN(1);
  @$pb.TagNumber(2)
  set lastStreamToken($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLastStreamToken() => $_has(1);
  @$pb.TagNumber(2)
  void clearLastStreamToken() => $_clearField(2);
}

/// Message containing a batch of user-level writes intended to be sent to
/// the server in a single call. Each user-level batch gets a separate
/// WriteBatch with a new batch_id.
class WriteBatch extends $pb.GeneratedMessage {
  factory WriteBatch({
    $core.int? batchId,
    $core.Iterable<$0.Write>? writes,
    $1.Timestamp? localWriteTime,
    $core.Iterable<$0.Write>? baseWrites,
  }) {
    final result = WriteBatch._();
    if (batchId != null) result.batchId = batchId;
    if (writes != null) result.writes.addAll(writes);
    if (localWriteTime != null) result.localWriteTime = localWriteTime;
    if (baseWrites != null) result.baseWrites.addAll(baseWrites);
    return result;
  }

  WriteBatch._();

  factory WriteBatch.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WriteBatch()..mergeFromBuffer(data, registry);
  factory WriteBatch.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WriteBatch()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WriteBatch',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'firestore.client'),
      createEmptyInstance: WriteBatch.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'batchId')
    ..pPM<$0.Write>(2, _omitFieldNames ? '' : 'writes',
        subBuilder: $0.Write.$_createMessage)
    ..aOM<$1.Timestamp>(3, _omitFieldNames ? '' : 'localWriteTime',
        subBuilder: $1.Timestamp.$_createMessage)
    ..pPM<$0.Write>(4, _omitFieldNames ? '' : 'baseWrites',
        subBuilder: $0.Write.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WriteBatch clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WriteBatch copyWith(void Function(WriteBatch) updates) =>
      super.copyWith((message) => updates(message as WriteBatch)) as WriteBatch;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use WriteBatch() / WriteBatch.new instead')
  static WriteBatch create() => WriteBatch._();
  static $pb.GeneratedMessage $_createMessage() => WriteBatch._();
  @$core.override
  WriteBatch createEmptyInstance() => WriteBatch._();
  @$core.pragma('dart2js:noInline')
  static WriteBatch getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<WriteBatch>(WriteBatch.$_createMessage);
  static WriteBatch? _defaultInstance;

  /// An identifier for this batch, allocated by the mutation queue in a
  /// monotonically increasing manner.
  @$pb.TagNumber(1)
  $core.int get batchId => $_getIZ(0);
  @$pb.TagNumber(1)
  set batchId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasBatchId() => $_has(0);
  @$pb.TagNumber(1)
  void clearBatchId() => $_clearField(1);

  /// A list of writes to apply. All writes will be applied atomically.
  @$pb.TagNumber(2)
  $pb.PbList<$0.Write> get writes => $_getList(1);

  /// The local time at which the write batch was initiated.
  @$pb.TagNumber(3)
  $1.Timestamp get localWriteTime => $_getN(2);
  @$pb.TagNumber(3)
  set localWriteTime($1.Timestamp value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasLocalWriteTime() => $_has(2);
  @$pb.TagNumber(3)
  void clearLocalWriteTime() => $_clearField(3);
  @$pb.TagNumber(3)
  $1.Timestamp ensureLocalWriteTime() => $_ensure(2);

  /// A list of pseudo-writes that represent a partial base state from when this
  /// write batch was initially created. When computing the local view batch,
  /// these base_writes are applied prior to the real writes in order to
  /// override certain document fields from the remote document cache. This is
  /// necessary in the case of non-idempotent writes (e.g. increment
  /// transforms) to make sure that the local view of the modified documents
  /// doesn't flicker if the remote document cache receives the result of the
  /// non-idempotent write before the write is removed from the queue.
  ///
  /// These writes are never sent to the backend.
  @$pb.TagNumber(4)
  $pb.PbList<$0.Write> get baseWrites => $_getList(3);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
