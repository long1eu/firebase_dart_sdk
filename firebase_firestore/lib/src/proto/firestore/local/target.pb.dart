///
//  Generated code. Do not modify.
//  source: firestore/local/target.proto
///
// ignore_for_file: non_constant_identifier_names,library_prefixes,unused_import

// ignore: UNUSED_SHOWN_NAME
import 'dart:core' show int, bool, double, String, List, override;

import 'package:fixnum/fixnum.dart';
import 'package:protobuf/protobuf.dart' as $pb;

import '../../google/protobuf/timestamp.pb.dart' as $0;
import '../../google/firestore/v1beta1/firestore.pb.dart' as $1;

class Target extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('Target', package: const $pb.PackageName('firestore.client'))
    ..a<int>(1, 'targetId', $pb.PbFieldType.O3)
    ..a<$0.Timestamp>(2, 'snapshotVersion', $pb.PbFieldType.OM, $0.Timestamp.getDefault, $0.Timestamp.create)
    ..a<List<int>>(3, 'resumeToken', $pb.PbFieldType.OY)
    ..aInt64(4, 'lastListenSequenceNumber')
    ..a<$1.Target_QueryTarget>(5, 'query', $pb.PbFieldType.OM, $1.Target_QueryTarget.getDefault, $1.Target_QueryTarget.create)
    ..a<$1.Target_DocumentsTarget>(6, 'documents', $pb.PbFieldType.OM, $1.Target_DocumentsTarget.getDefault, $1.Target_DocumentsTarget.create)
    ..hasRequiredFields = false
  ;

  Target() : super();
  Target.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  Target.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  Target clone() => new Target()..mergeFromMessage(this);
  Target copyWith(void Function(Target) updates) => super.copyWith((message) => updates(message as Target));
  $pb.BuilderInfo get info_ => _i;
  static Target create() => new Target();
  static $pb.PbList<Target> createRepeated() => new $pb.PbList<Target>();
  static Target getDefault() => _defaultInstance ??= create()..freeze();
  static Target _defaultInstance;
  static void $checkItem(Target v) {
    if (v is! Target) $pb.checkItemFailed(v, _i.messageName);
  }

  int get targetId => $_get(0, 0);
  set targetId(int v) { $_setSignedInt32(0, v); }
  bool hasTargetId() => $_has(0);
  void clearTargetId() => clearField(1);

  $0.Timestamp get snapshotVersion => $_getN(1);
  set snapshotVersion($0.Timestamp v) { setField(2, v); }
  bool hasSnapshotVersion() => $_has(1);
  void clearSnapshotVersion() => clearField(2);

  List<int> get resumeToken => $_getN(2);
  set resumeToken(List<int> v) { $_setBytes(2, v); }
  bool hasResumeToken() => $_has(2);
  void clearResumeToken() => clearField(3);

  Int64 get lastListenSequenceNumber => $_getI64(3);
  set lastListenSequenceNumber(Int64 v) { $_setInt64(3, v); }
  bool hasLastListenSequenceNumber() => $_has(3);
  void clearLastListenSequenceNumber() => clearField(4);

  $1.Target_QueryTarget get query => $_getN(4);
  set query($1.Target_QueryTarget v) { setField(5, v); }
  bool hasQuery() => $_has(4);
  void clearQuery() => clearField(5);

  $1.Target_DocumentsTarget get documents => $_getN(5);
  set documents($1.Target_DocumentsTarget v) { setField(6, v); }
  bool hasDocuments() => $_has(5);
  void clearDocuments() => clearField(6);
}

class TargetGlobal extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('TargetGlobal', package: const $pb.PackageName('firestore.client'))
    ..a<int>(1, 'highestTargetId', $pb.PbFieldType.O3)
    ..aInt64(2, 'highestListenSequenceNumber')
    ..a<$0.Timestamp>(3, 'lastRemoteSnapshotVersion', $pb.PbFieldType.OM, $0.Timestamp.getDefault, $0.Timestamp.create)
    ..a<int>(4, 'targetCount', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  TargetGlobal() : super();
  TargetGlobal.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  TargetGlobal.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  TargetGlobal clone() => new TargetGlobal()..mergeFromMessage(this);
  TargetGlobal copyWith(void Function(TargetGlobal) updates) => super.copyWith((message) => updates(message as TargetGlobal));
  $pb.BuilderInfo get info_ => _i;
  static TargetGlobal create() => new TargetGlobal();
  static $pb.PbList<TargetGlobal> createRepeated() => new $pb.PbList<TargetGlobal>();
  static TargetGlobal getDefault() => _defaultInstance ??= create()..freeze();
  static TargetGlobal _defaultInstance;
  static void $checkItem(TargetGlobal v) {
    if (v is! TargetGlobal) $pb.checkItemFailed(v, _i.messageName);
  }

  int get highestTargetId => $_get(0, 0);
  set highestTargetId(int v) { $_setSignedInt32(0, v); }
  bool hasHighestTargetId() => $_has(0);
  void clearHighestTargetId() => clearField(1);

  Int64 get highestListenSequenceNumber => $_getI64(1);
  set highestListenSequenceNumber(Int64 v) { $_setInt64(1, v); }
  bool hasHighestListenSequenceNumber() => $_has(1);
  void clearHighestListenSequenceNumber() => clearField(2);

  $0.Timestamp get lastRemoteSnapshotVersion => $_getN(2);
  set lastRemoteSnapshotVersion($0.Timestamp v) { setField(3, v); }
  bool hasLastRemoteSnapshotVersion() => $_has(2);
  void clearLastRemoteSnapshotVersion() => clearField(3);

  int get targetCount => $_get(3, 0);
  set targetCount(int v) { $_setSignedInt32(3, v); }
  bool hasTargetCount() => $_has(3);
  void clearTargetCount() => clearField(4);
}

