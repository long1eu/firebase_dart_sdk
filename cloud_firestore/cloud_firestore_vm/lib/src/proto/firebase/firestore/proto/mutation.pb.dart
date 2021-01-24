///
//  Generated code. Do not modify.
//  source: firebase/firestore/proto/mutation.proto
//
// @dart = 2.7
// ignore_for_file: annotate_overrides,camel_case_types,unnecessary_const,non_constant_identifier_names,library_prefixes,unused_import,unused_shown_name,return_of_invalid_type,unnecessary_this,prefer_final_fields

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import '../../../google/firestore/v1/write.pb.dart' as $10;
import '../../../google/protobuf/timestamp.pb.dart' as $4;

class MutationQueue extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'MutationQueue', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'firestore.client'), createEmptyInstance: create)
    ..a<$core.int>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'lastAcknowledgedBatchId', $pb.PbFieldType.O3)
    ..a<$core.List<$core.int>>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'lastStreamToken', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  MutationQueue._() : super();
  factory MutationQueue({
    $core.int lastAcknowledgedBatchId,
    $core.List<$core.int> lastStreamToken,
  }) {
    final _result = create();
    if (lastAcknowledgedBatchId != null) {
      _result.lastAcknowledgedBatchId = lastAcknowledgedBatchId;
    }
    if (lastStreamToken != null) {
      _result.lastStreamToken = lastStreamToken;
    }
    return _result;
  }
  factory MutationQueue.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MutationQueue.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  MutationQueue clone() => MutationQueue()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  MutationQueue copyWith(void Function(MutationQueue) updates) => super.copyWith((message) => updates(message as MutationQueue)); // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static MutationQueue create() => MutationQueue._();
  MutationQueue createEmptyInstance() => create();
  static $pb.PbList<MutationQueue> createRepeated() => $pb.PbList<MutationQueue>();
  @$core.pragma('dart2js:noInline')
  static MutationQueue getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MutationQueue>(create);
  static MutationQueue _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get lastAcknowledgedBatchId => $_getIZ(0);
  @$pb.TagNumber(1)
  set lastAcknowledgedBatchId($core.int v) { $_setSignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasLastAcknowledgedBatchId() => $_has(0);
  @$pb.TagNumber(1)
  void clearLastAcknowledgedBatchId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get lastStreamToken => $_getN(1);
  @$pb.TagNumber(2)
  set lastStreamToken($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasLastStreamToken() => $_has(1);
  @$pb.TagNumber(2)
  void clearLastStreamToken() => clearField(2);
}

class WriteBatch extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'WriteBatch', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'firestore.client'), createEmptyInstance: create)
    ..a<$core.int>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'batchId', $pb.PbFieldType.O3)
    ..pc<$10.Write>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'writes', $pb.PbFieldType.PM, subBuilder: $10.Write.create)
    ..aOM<$4.Timestamp>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'localWriteTime', subBuilder: $4.Timestamp.create)
    ..pc<$10.Write>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'baseWrites', $pb.PbFieldType.PM, subBuilder: $10.Write.create)
    ..hasRequiredFields = false
  ;

  WriteBatch._() : super();
  factory WriteBatch({
    $core.int batchId,
    $core.Iterable<$10.Write> writes,
    $4.Timestamp localWriteTime,
    $core.Iterable<$10.Write> baseWrites,
  }) {
    final _result = create();
    if (batchId != null) {
      _result.batchId = batchId;
    }
    if (writes != null) {
      _result.writes.addAll(writes);
    }
    if (localWriteTime != null) {
      _result.localWriteTime = localWriteTime;
    }
    if (baseWrites != null) {
      _result.baseWrites.addAll(baseWrites);
    }
    return _result;
  }
  factory WriteBatch.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory WriteBatch.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  WriteBatch clone() => WriteBatch()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  WriteBatch copyWith(void Function(WriteBatch) updates) => super.copyWith((message) => updates(message as WriteBatch)); // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static WriteBatch create() => WriteBatch._();
  WriteBatch createEmptyInstance() => create();
  static $pb.PbList<WriteBatch> createRepeated() => $pb.PbList<WriteBatch>();
  @$core.pragma('dart2js:noInline')
  static WriteBatch getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<WriteBatch>(create);
  static WriteBatch _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get batchId => $_getIZ(0);
  @$pb.TagNumber(1)
  set batchId($core.int v) { $_setSignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasBatchId() => $_has(0);
  @$pb.TagNumber(1)
  void clearBatchId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$10.Write> get writes => $_getList(1);

  @$pb.TagNumber(3)
  $4.Timestamp get localWriteTime => $_getN(2);
  @$pb.TagNumber(3)
  set localWriteTime($4.Timestamp v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasLocalWriteTime() => $_has(2);
  @$pb.TagNumber(3)
  void clearLocalWriteTime() => clearField(3);
  @$pb.TagNumber(3)
  $4.Timestamp ensureLocalWriteTime() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.List<$10.Write> get baseWrites => $_getList(3);
}

