///
//  Generated code. Do not modify.
//  source: google/firebase/firestore/proto/mutation.proto
///
// ignore_for_file: camel_case_types,non_constant_identifier_names,library_prefixes,unused_import,unused_shown_name

import 'dart:core' as $core show bool, Deprecated, double, int, List, Map, override, pragma, String;

import 'package:protobuf/protobuf.dart' as $pb;

import '../../../firestore/v1beta1/write.pb.dart' as $2;
import '../../../protobuf/timestamp.pb.dart' as $0;

class MutationQueue extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo('MutationQueue', package: const $pb.PackageName('firestore.client'))
    ..a<$core.int>(1, 'lastAcknowledgedBatchId', $pb.PbFieldType.O3)
    ..a<$core.List<$core.int>>(2, 'lastStreamToken', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  MutationQueue._() : super();
  factory MutationQueue() => create();
  factory MutationQueue.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MutationQueue.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  MutationQueue clone() => MutationQueue()..mergeFromMessage(this);
  MutationQueue copyWith(void Function(MutationQueue) updates) => super.copyWith((message) => updates(message as MutationQueue));
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static MutationQueue create() => MutationQueue._();
  MutationQueue createEmptyInstance() => create();
  static $pb.PbList<MutationQueue> createRepeated() => $pb.PbList<MutationQueue>();
  static MutationQueue getDefault() => _defaultInstance ??= create()..freeze();
  static MutationQueue _defaultInstance;

  $core.int get lastAcknowledgedBatchId => $_get(0, 0);
  set lastAcknowledgedBatchId($core.int v) { $_setSignedInt32(0, v); }
  $core.bool hasLastAcknowledgedBatchId() => $_has(0);
  void clearLastAcknowledgedBatchId() => clearField(1);

  $core.List<$core.int> get lastStreamToken => $_getN(1);
  set lastStreamToken($core.List<$core.int> v) { $_setBytes(1, v); }
  $core.bool hasLastStreamToken() => $_has(1);
  void clearLastStreamToken() => clearField(2);
}

class WriteBatch extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo('WriteBatch', package: const $pb.PackageName('firestore.client'))
    ..a<$core.int>(1, 'batchId', $pb.PbFieldType.O3)
    ..pc<$2.Write>(2, 'writes', $pb.PbFieldType.PM,$2.Write.create)
    ..a<$0.Timestamp>(3, 'localWriteTime', $pb.PbFieldType.OM, $0.Timestamp.getDefault, $0.Timestamp.create)
    ..hasRequiredFields = false
  ;

  WriteBatch._() : super();
  factory WriteBatch() => create();
  factory WriteBatch.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory WriteBatch.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  WriteBatch clone() => WriteBatch()..mergeFromMessage(this);
  WriteBatch copyWith(void Function(WriteBatch) updates) => super.copyWith((message) => updates(message as WriteBatch));
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static WriteBatch create() => WriteBatch._();
  WriteBatch createEmptyInstance() => create();
  static $pb.PbList<WriteBatch> createRepeated() => $pb.PbList<WriteBatch>();
  static WriteBatch getDefault() => _defaultInstance ??= create()..freeze();
  static WriteBatch _defaultInstance;

  $core.int get batchId => $_get(0, 0);
  set batchId($core.int v) { $_setSignedInt32(0, v); }
  $core.bool hasBatchId() => $_has(0);
  void clearBatchId() => clearField(1);

  $core.List<$2.Write> get writes => $_getList(1);

  $0.Timestamp get localWriteTime => $_getN(2);
  set localWriteTime($0.Timestamp v) { setField(3, v); }
  $core.bool hasLocalWriteTime() => $_has(2);
  void clearLocalWriteTime() => clearField(3);
}

