///
//  Generated code. Do not modify.
//  source: google/firebase/firestore/proto/target.proto
///
// ignore_for_file: camel_case_types,non_constant_identifier_names,library_prefixes,unused_import,unused_shown_name

import 'dart:core' as $core show bool, Deprecated, double, int, List, Map, override, pragma, String;

import 'package:fixnum/fixnum.dart';
import 'package:protobuf/protobuf.dart' as $pb;

import '../../../protobuf/timestamp.pb.dart' as $0;
import '../../../firestore/v1beta1/firestore.pb.dart' as $3;

enum Target_TargetType {
  query, 
  documents, 
  notSet
}

class Target extends $pb.GeneratedMessage {
  static const $core.Map<$core.int, Target_TargetType> _Target_TargetTypeByTag = {
    5 : Target_TargetType.query,
    6 : Target_TargetType.documents,
    0 : Target_TargetType.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo('Target', package: const $pb.PackageName('firestore.client'))
    ..oo(0, [5, 6])
    ..a<$core.int>(1, 'targetId', $pb.PbFieldType.O3)
    ..a<$0.Timestamp>(2, 'snapshotVersion', $pb.PbFieldType.OM, $0.Timestamp.getDefault, $0.Timestamp.create)
    ..a<$core.List<$core.int>>(3, 'resumeToken', $pb.PbFieldType.OY)
    ..aInt64(4, 'lastListenSequenceNumber')
    ..a<$3.Target_QueryTarget>(5, 'query', $pb.PbFieldType.OM, $3.Target_QueryTarget.getDefault, $3.Target_QueryTarget.create)
    ..a<$3.Target_DocumentsTarget>(6, 'documents', $pb.PbFieldType.OM, $3.Target_DocumentsTarget.getDefault, $3.Target_DocumentsTarget.create)
    ..hasRequiredFields = false
  ;

  Target._() : super();
  factory Target() => create();
  factory Target.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory Target.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  Target clone() => Target()..mergeFromMessage(this);
  Target copyWith(void Function(Target) updates) => super.copyWith((message) => updates(message as Target));
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static Target create() => Target._();
  Target createEmptyInstance() => create();
  static $pb.PbList<Target> createRepeated() => $pb.PbList<Target>();
  static Target getDefault() => _defaultInstance ??= create()..freeze();
  static Target _defaultInstance;

  Target_TargetType whichTargetType() => _Target_TargetTypeByTag[$_whichOneof(0)];
  void clearTargetType() => clearField($_whichOneof(0));

  $core.int get targetId => $_get(0, 0);
  set targetId($core.int v) { $_setSignedInt32(0, v); }
  $core.bool hasTargetId() => $_has(0);
  void clearTargetId() => clearField(1);

  $0.Timestamp get snapshotVersion => $_getN(1);
  set snapshotVersion($0.Timestamp v) { setField(2, v); }
  $core.bool hasSnapshotVersion() => $_has(1);
  void clearSnapshotVersion() => clearField(2);

  $core.List<$core.int> get resumeToken => $_getN(2);
  set resumeToken($core.List<$core.int> v) { $_setBytes(2, v); }
  $core.bool hasResumeToken() => $_has(2);
  void clearResumeToken() => clearField(3);

  Int64 get lastListenSequenceNumber => $_getI64(3);
  set lastListenSequenceNumber(Int64 v) { $_setInt64(3, v); }
  $core.bool hasLastListenSequenceNumber() => $_has(3);
  void clearLastListenSequenceNumber() => clearField(4);

  $3.Target_QueryTarget get query => $_getN(4);
  set query($3.Target_QueryTarget v) { setField(5, v); }
  $core.bool hasQuery() => $_has(4);
  void clearQuery() => clearField(5);

  $3.Target_DocumentsTarget get documents => $_getN(5);
  set documents($3.Target_DocumentsTarget v) { setField(6, v); }
  $core.bool hasDocuments() => $_has(5);
  void clearDocuments() => clearField(6);
}

class TargetGlobal extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo('TargetGlobal', package: const $pb.PackageName('firestore.client'))
    ..a<$core.int>(1, 'highestTargetId', $pb.PbFieldType.O3)
    ..aInt64(2, 'highestListenSequenceNumber')
    ..a<$0.Timestamp>(3, 'lastRemoteSnapshotVersion', $pb.PbFieldType.OM, $0.Timestamp.getDefault, $0.Timestamp.create)
    ..a<$core.int>(4, 'targetCount', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  TargetGlobal._() : super();
  factory TargetGlobal() => create();
  factory TargetGlobal.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TargetGlobal.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  TargetGlobal clone() => TargetGlobal()..mergeFromMessage(this);
  TargetGlobal copyWith(void Function(TargetGlobal) updates) => super.copyWith((message) => updates(message as TargetGlobal));
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static TargetGlobal create() => TargetGlobal._();
  TargetGlobal createEmptyInstance() => create();
  static $pb.PbList<TargetGlobal> createRepeated() => $pb.PbList<TargetGlobal>();
  static TargetGlobal getDefault() => _defaultInstance ??= create()..freeze();
  static TargetGlobal _defaultInstance;

  $core.int get highestTargetId => $_get(0, 0);
  set highestTargetId($core.int v) { $_setSignedInt32(0, v); }
  $core.bool hasHighestTargetId() => $_has(0);
  void clearHighestTargetId() => clearField(1);

  Int64 get highestListenSequenceNumber => $_getI64(1);
  set highestListenSequenceNumber(Int64 v) { $_setInt64(1, v); }
  $core.bool hasHighestListenSequenceNumber() => $_has(1);
  void clearHighestListenSequenceNumber() => clearField(2);

  $0.Timestamp get lastRemoteSnapshotVersion => $_getN(2);
  set lastRemoteSnapshotVersion($0.Timestamp v) { setField(3, v); }
  $core.bool hasLastRemoteSnapshotVersion() => $_has(2);
  void clearLastRemoteSnapshotVersion() => clearField(3);

  $core.int get targetCount => $_get(3, 0);
  set targetCount($core.int v) { $_setSignedInt32(3, v); }
  $core.bool hasTargetCount() => $_has(3);
  void clearTargetCount() => clearField(4);
}

