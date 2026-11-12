//
//  Generated code. Do not modify.
//  source: firebase/firestore/proto/mutation.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import '../../../google/firestore/v1/write.pb.dart' as $10;
import '../../../google/protobuf/timestamp.pb.dart' as $3;

/// Each user gets a single queue of WriteBatches to apply to the server.
/// MutationQueue tracks the metadata about the queue.
class MutationQueue extends $pb.GeneratedMessage {
  factory MutationQueue({
    $core.int? lastAcknowledgedBatchId,
    $core.List<$core.int>? lastStreamToken,
  }) {
    final $result = create();
    if (lastAcknowledgedBatchId != null) {
      $result.lastAcknowledgedBatchId = lastAcknowledgedBatchId;
    }
    if (lastStreamToken != null) {
      $result.lastStreamToken = lastStreamToken;
    }
    return $result;
  }
  MutationQueue._() : super();
  factory MutationQueue.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MutationQueue.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'MutationQueue', package: const $pb.PackageName(_omitMessageNames ? '' : 'firestore.client'), createEmptyInstance: create)
    ..a<$core.int>(1, _omitFieldNames ? '' : 'lastAcknowledgedBatchId', $pb.PbFieldType.O3)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'lastStreamToken', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  MutationQueue clone() => MutationQueue()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  MutationQueue copyWith(void Function(MutationQueue) updates) => super.copyWith((message) => updates(message as MutationQueue)) as MutationQueue;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MutationQueue create() => MutationQueue._();
  MutationQueue createEmptyInstance() => create();
  static $pb.PbList<MutationQueue> createRepeated() => $pb.PbList<MutationQueue>();
  @$core.pragma('dart2js:noInline')
  static MutationQueue getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MutationQueue>(create);
  static MutationQueue? _defaultInstance;

  /// An identifier for the highest numbered batch that has been acknowledged by
  /// the server. All WriteBatches in this queue with batch_ids less than or
  /// equal to this value are considered to have been acknowledged by the
  /// server.
  @$pb.TagNumber(1)
  $core.int get lastAcknowledgedBatchId => $_getIZ(0);
  @$pb.TagNumber(1)
  set lastAcknowledgedBatchId($core.int v) { $_setSignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasLastAcknowledgedBatchId() => $_has(0);
  @$pb.TagNumber(1)
  void clearLastAcknowledgedBatchId() => clearField(1);

  ///  A stream token that was previously sent by the server.
  ///
  ///  See StreamingWriteRequest in datastore.proto for more details about usage.
  ///
  ///  After sending this token, earlier tokens may not be used anymore so only a
  ///  single stream token is retained.
  @$pb.TagNumber(2)
  $core.List<$core.int> get lastStreamToken => $_getN(1);
  @$pb.TagNumber(2)
  set lastStreamToken($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasLastStreamToken() => $_has(1);
  @$pb.TagNumber(2)
  void clearLastStreamToken() => clearField(2);
}

/// Message containing a batch of user-level writes intended to be sent to
/// the server in a single call. Each user-level batch gets a separate
/// WriteBatch with a new batch_id.
class WriteBatch extends $pb.GeneratedMessage {
  factory WriteBatch({
    $core.int? batchId,
    $core.Iterable<$10.Write>? writes,
    $3.Timestamp? localWriteTime,
    $core.Iterable<$10.Write>? baseWrites,
  }) {
    final $result = create();
    if (batchId != null) {
      $result.batchId = batchId;
    }
    if (writes != null) {
      $result.writes.addAll(writes);
    }
    if (localWriteTime != null) {
      $result.localWriteTime = localWriteTime;
    }
    if (baseWrites != null) {
      $result.baseWrites.addAll(baseWrites);
    }
    return $result;
  }
  WriteBatch._() : super();
  factory WriteBatch.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory WriteBatch.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'WriteBatch', package: const $pb.PackageName(_omitMessageNames ? '' : 'firestore.client'), createEmptyInstance: create)
    ..a<$core.int>(1, _omitFieldNames ? '' : 'batchId', $pb.PbFieldType.O3)
    ..pc<$10.Write>(2, _omitFieldNames ? '' : 'writes', $pb.PbFieldType.PM, subBuilder: $10.Write.create)
    ..aOM<$3.Timestamp>(3, _omitFieldNames ? '' : 'localWriteTime', subBuilder: $3.Timestamp.create)
    ..pc<$10.Write>(4, _omitFieldNames ? '' : 'baseWrites', $pb.PbFieldType.PM, subBuilder: $10.Write.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  WriteBatch clone() => WriteBatch()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  WriteBatch copyWith(void Function(WriteBatch) updates) => super.copyWith((message) => updates(message as WriteBatch)) as WriteBatch;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static WriteBatch create() => WriteBatch._();
  WriteBatch createEmptyInstance() => create();
  static $pb.PbList<WriteBatch> createRepeated() => $pb.PbList<WriteBatch>();
  @$core.pragma('dart2js:noInline')
  static WriteBatch getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<WriteBatch>(create);
  static WriteBatch? _defaultInstance;

  /// An identifier for this batch, allocated by the mutation queue in a
  /// monotonically increasing manner.
  @$pb.TagNumber(1)
  $core.int get batchId => $_getIZ(0);
  @$pb.TagNumber(1)
  set batchId($core.int v) { $_setSignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasBatchId() => $_has(0);
  @$pb.TagNumber(1)
  void clearBatchId() => clearField(1);

  /// A list of writes to apply. All writes will be applied atomically.
  @$pb.TagNumber(2)
  $core.List<$10.Write> get writes => $_getList(1);

  /// The local time at which the write batch was initiated.
  @$pb.TagNumber(3)
  $3.Timestamp get localWriteTime => $_getN(2);
  @$pb.TagNumber(3)
  set localWriteTime($3.Timestamp v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasLocalWriteTime() => $_has(2);
  @$pb.TagNumber(3)
  void clearLocalWriteTime() => clearField(3);
  @$pb.TagNumber(3)
  $3.Timestamp ensureLocalWriteTime() => $_ensure(2);

  ///  A list of pseudo-writes that represent a partial base state from when this
  ///  write batch was initially created. When computing the local view batch,
  ///  these base_writes are applied prior to the real writes in order to
  ///  override certain document fields from the remote document cache. This is
  ///  necessary in the case of non-idempotent writes (e.g. increment
  ///  transforms) to make sure that the local view of the modified documents
  ///  doesn't flicker if the remote document cache receives the result of the
  ///  non-idempotent write before the write is removed from the queue.
  ///
  ///  These writes are never sent to the backend.
  @$pb.TagNumber(4)
  $core.List<$10.Write> get baseWrites => $_getList(3);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
