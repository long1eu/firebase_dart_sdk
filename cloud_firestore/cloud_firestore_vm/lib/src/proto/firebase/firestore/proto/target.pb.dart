///
//  Generated code. Do not modify.
//  source: firebase/firestore/proto/target.proto
//
// @dart = 2.3
// ignore_for_file: camel_case_types,non_constant_identifier_names,library_prefixes,unused_import,unused_shown_name,return_of_invalid_type

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import '../../../google/protobuf/timestamp.pb.dart' as $4;
import '../../../google/firestore/v1/firestore.pb.dart' as $0;

enum Target_TargetType { query, documents, notSet }

class Target extends $pb.GeneratedMessage {
  static const $core.Map<$core.int, Target_TargetType> _Target_TargetTypeByTag =
      {
    5: Target_TargetType.query,
    6: Target_TargetType.documents,
    0: Target_TargetType.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo('Target',
      package: const $pb.PackageName('firestore.client'),
      createEmptyInstance: create)
    ..oo(0, [5, 6])
    ..a<$core.int>(1, 'targetId', $pb.PbFieldType.O3)
    ..aOM<$4.Timestamp>(2, 'snapshotVersion', subBuilder: $4.Timestamp.create)
    ..a<$core.List<$core.int>>(3, 'resumeToken', $pb.PbFieldType.OY)
    ..aInt64(4, 'lastListenSequenceNumber')
    ..aOM<$0.Target_QueryTarget>(5, 'query',
        subBuilder: $0.Target_QueryTarget.create)
    ..aOM<$0.Target_DocumentsTarget>(6, 'documents',
        subBuilder: $0.Target_DocumentsTarget.create)
    ..hasRequiredFields = false;

  Target._() : super();
  factory Target() => create();
  factory Target.fromBuffer($core.List<$core.int> i,
          [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(i, r);
  factory Target.fromJson($core.String i,
          [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(i, r);
  Target clone() => Target()..mergeFromMessage(this);
  Target copyWith(void Function(Target) updates) =>
      super.copyWith((message) => updates(message as Target));
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static Target create() => Target._();
  Target createEmptyInstance() => create();
  static $pb.PbList<Target> createRepeated() => $pb.PbList<Target>();
  @$core.pragma('dart2js:noInline')
  static Target getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Target>(create);
  static Target _defaultInstance;

  Target_TargetType whichTargetType() =>
      _Target_TargetTypeByTag[$_whichOneof(0)];
  void clearTargetType() => clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.int get targetId => $_getIZ(0);
  @$pb.TagNumber(1)
  set targetId($core.int v) {
    $_setSignedInt32(0, v);
  }

  @$pb.TagNumber(1)
  $core.bool hasTargetId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTargetId() => clearField(1);

  @$pb.TagNumber(2)
  $4.Timestamp get snapshotVersion => $_getN(1);
  @$pb.TagNumber(2)
  set snapshotVersion($4.Timestamp v) {
    setField(2, v);
  }

  @$pb.TagNumber(2)
  $core.bool hasSnapshotVersion() => $_has(1);
  @$pb.TagNumber(2)
  void clearSnapshotVersion() => clearField(2);
  @$pb.TagNumber(2)
  $4.Timestamp ensureSnapshotVersion() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.List<$core.int> get resumeToken => $_getN(2);
  @$pb.TagNumber(3)
  set resumeToken($core.List<$core.int> v) {
    $_setBytes(2, v);
  }

  @$pb.TagNumber(3)
  $core.bool hasResumeToken() => $_has(2);
  @$pb.TagNumber(3)
  void clearResumeToken() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get lastListenSequenceNumber => $_getI64(3);
  @$pb.TagNumber(4)
  set lastListenSequenceNumber($fixnum.Int64 v) {
    $_setInt64(3, v);
  }

  @$pb.TagNumber(4)
  $core.bool hasLastListenSequenceNumber() => $_has(3);
  @$pb.TagNumber(4)
  void clearLastListenSequenceNumber() => clearField(4);

  @$pb.TagNumber(5)
  $0.Target_QueryTarget get query => $_getN(4);
  @$pb.TagNumber(5)
  set query($0.Target_QueryTarget v) {
    setField(5, v);
  }

  @$pb.TagNumber(5)
  $core.bool hasQuery() => $_has(4);
  @$pb.TagNumber(5)
  void clearQuery() => clearField(5);
  @$pb.TagNumber(5)
  $0.Target_QueryTarget ensureQuery() => $_ensure(4);

  @$pb.TagNumber(6)
  $0.Target_DocumentsTarget get documents => $_getN(5);
  @$pb.TagNumber(6)
  set documents($0.Target_DocumentsTarget v) {
    setField(6, v);
  }

  @$pb.TagNumber(6)
  $core.bool hasDocuments() => $_has(5);
  @$pb.TagNumber(6)
  void clearDocuments() => clearField(6);
  @$pb.TagNumber(6)
  $0.Target_DocumentsTarget ensureDocuments() => $_ensure(5);
}

class TargetGlobal extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo('TargetGlobal',
      package: const $pb.PackageName('firestore.client'),
      createEmptyInstance: create)
    ..a<$core.int>(1, 'highestTargetId', $pb.PbFieldType.O3)
    ..aInt64(2, 'highestListenSequenceNumber')
    ..aOM<$4.Timestamp>(3, 'lastRemoteSnapshotVersion',
        subBuilder: $4.Timestamp.create)
    ..a<$core.int>(4, 'targetCount', $pb.PbFieldType.O3)
    ..hasRequiredFields = false;

  TargetGlobal._() : super();
  factory TargetGlobal() => create();
  factory TargetGlobal.fromBuffer($core.List<$core.int> i,
          [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(i, r);
  factory TargetGlobal.fromJson($core.String i,
          [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(i, r);
  TargetGlobal clone() => TargetGlobal()..mergeFromMessage(this);
  TargetGlobal copyWith(void Function(TargetGlobal) updates) =>
      super.copyWith((message) => updates(message as TargetGlobal));
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static TargetGlobal create() => TargetGlobal._();
  TargetGlobal createEmptyInstance() => create();
  static $pb.PbList<TargetGlobal> createRepeated() =>
      $pb.PbList<TargetGlobal>();
  @$core.pragma('dart2js:noInline')
  static TargetGlobal getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TargetGlobal>(create);
  static TargetGlobal _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get highestTargetId => $_getIZ(0);
  @$pb.TagNumber(1)
  set highestTargetId($core.int v) {
    $_setSignedInt32(0, v);
  }

  @$pb.TagNumber(1)
  $core.bool hasHighestTargetId() => $_has(0);
  @$pb.TagNumber(1)
  void clearHighestTargetId() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get highestListenSequenceNumber => $_getI64(1);
  @$pb.TagNumber(2)
  set highestListenSequenceNumber($fixnum.Int64 v) {
    $_setInt64(1, v);
  }

  @$pb.TagNumber(2)
  $core.bool hasHighestListenSequenceNumber() => $_has(1);
  @$pb.TagNumber(2)
  void clearHighestListenSequenceNumber() => clearField(2);

  @$pb.TagNumber(3)
  $4.Timestamp get lastRemoteSnapshotVersion => $_getN(2);
  @$pb.TagNumber(3)
  set lastRemoteSnapshotVersion($4.Timestamp v) {
    setField(3, v);
  }

  @$pb.TagNumber(3)
  $core.bool hasLastRemoteSnapshotVersion() => $_has(2);
  @$pb.TagNumber(3)
  void clearLastRemoteSnapshotVersion() => clearField(3);
  @$pb.TagNumber(3)
  $4.Timestamp ensureLastRemoteSnapshotVersion() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.int get targetCount => $_getIZ(3);
  @$pb.TagNumber(4)
  set targetCount($core.int v) {
    $_setSignedInt32(3, v);
  }

  @$pb.TagNumber(4)
  $core.bool hasTargetCount() => $_has(3);
  @$pb.TagNumber(4)
  void clearTargetCount() => clearField(4);
}
