///
//  Generated code. Do not modify.
//  source: firestore/local/mutation.proto
///
// ignore_for_file: non_constant_identifier_names,library_prefixes,unused_import

// ignore: UNUSED_SHOWN_NAME
import 'dart:core' show int, bool, double, String, List, override;

import 'package:protobuf/protobuf.dart' as $pb;

import '../../google/firestore/v1beta1/write.pb.dart' as $0;
import '../../google/protobuf/timestamp.pb.dart' as $1;

class MutationQueue extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('MutationQueue', package: const $pb.PackageName('firestore.client'))
    ..a<int>(1, 'lastAcknowledgedBatchId', $pb.PbFieldType.O3)
    ..a<List<int>>(2, 'lastStreamToken', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  MutationQueue() : super();
  MutationQueue.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  MutationQueue.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  MutationQueue clone() => new MutationQueue()..mergeFromMessage(this);
  MutationQueue copyWith(void Function(MutationQueue) updates) => super.copyWith((message) => updates(message as MutationQueue));
  $pb.BuilderInfo get info_ => _i;
  static MutationQueue create() => new MutationQueue();
  static $pb.PbList<MutationQueue> createRepeated() => new $pb.PbList<MutationQueue>();
  static MutationQueue getDefault() => _defaultInstance ??= create()..freeze();
  static MutationQueue _defaultInstance;
  static void $checkItem(MutationQueue v) {
    if (v is! MutationQueue) $pb.checkItemFailed(v, _i.messageName);
  }

  int get lastAcknowledgedBatchId => $_get(0, 0);
  set lastAcknowledgedBatchId(int v) { $_setSignedInt32(0, v); }
  bool hasLastAcknowledgedBatchId() => $_has(0);
  void clearLastAcknowledgedBatchId() => clearField(1);

  List<int> get lastStreamToken => $_getN(1);
  set lastStreamToken(List<int> v) { $_setBytes(1, v); }
  bool hasLastStreamToken() => $_has(1);
  void clearLastStreamToken() => clearField(2);
}

class WriteBatch extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('WriteBatch', package: const $pb.PackageName('firestore.client'))
    ..a<int>(1, 'batchId', $pb.PbFieldType.O3)
    ..pp<$0.Write>(2, 'writes', $pb.PbFieldType.PM, $0.Write.$checkItem, $0.Write.create)
    ..a<$1.Timestamp>(3, 'localWriteTime', $pb.PbFieldType.OM, $1.Timestamp.getDefault, $1.Timestamp.create)
    ..hasRequiredFields = false
  ;

  WriteBatch() : super();
  WriteBatch.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  WriteBatch.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  WriteBatch clone() => new WriteBatch()..mergeFromMessage(this);
  WriteBatch copyWith(void Function(WriteBatch) updates) => super.copyWith((message) => updates(message as WriteBatch));
  $pb.BuilderInfo get info_ => _i;
  static WriteBatch create() => new WriteBatch();
  static $pb.PbList<WriteBatch> createRepeated() => new $pb.PbList<WriteBatch>();
  static WriteBatch getDefault() => _defaultInstance ??= create()..freeze();
  static WriteBatch _defaultInstance;
  static void $checkItem(WriteBatch v) {
    if (v is! WriteBatch) $pb.checkItemFailed(v, _i.messageName);
  }

  int get batchId => $_get(0, 0);
  set batchId(int v) { $_setSignedInt32(0, v); }
  bool hasBatchId() => $_has(0);
  void clearBatchId() => clearField(1);

  List<$0.Write> get writes => $_getList(1);

  $1.Timestamp get localWriteTime => $_getN(2);
  set localWriteTime($1.Timestamp v) { setField(3, v); }
  bool hasLocalWriteTime() => $_has(2);
  void clearLocalWriteTime() => clearField(3);
}

