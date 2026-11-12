// This is a generated file - do not edit.
//
// Generated from firebase/firestore/proto/target.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart'
    as $0;

import '../../../google/firestore/v1/firestore.pb.dart' as $1;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

enum Target_TargetType { query, documents, notSet }

/// A Target is a long-lived data structure representing a resumable listen on a
/// particular user query. While the query describes what to listen to, the
/// Target records data about when the results were last updated and enough
/// information to be able to resume listening later.
class Target extends $pb.GeneratedMessage {
  factory Target({
    $core.int? targetId,
    $0.Timestamp? snapshotVersion,
    $core.List<$core.int>? resumeToken,
    $fixnum.Int64? lastListenSequenceNumber,
    $1.Target_QueryTarget? query,
    $1.Target_DocumentsTarget? documents,
    $0.Timestamp? lastLimboFreeSnapshotVersion,
  }) {
    final result = Target._();
    if (targetId != null) result.targetId = targetId;
    if (snapshotVersion != null) result.snapshotVersion = snapshotVersion;
    if (resumeToken != null) result.resumeToken = resumeToken;
    if (lastListenSequenceNumber != null)
      result.lastListenSequenceNumber = lastListenSequenceNumber;
    if (query != null) result.query = query;
    if (documents != null) result.documents = documents;
    if (lastLimboFreeSnapshotVersion != null)
      result.lastLimboFreeSnapshotVersion = lastLimboFreeSnapshotVersion;
    return result;
  }

  Target._();

  factory Target.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Target()..mergeFromBuffer(data, registry);
  factory Target.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Target()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, Target_TargetType> _Target_TargetTypeByTag =
      {
    5: Target_TargetType.query,
    6: Target_TargetType.documents,
    0: Target_TargetType.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Target',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'firestore.client'),
      createEmptyInstance: Target.$_createMessage)
    ..oo(0, [5, 6])
    ..aI(1, _omitFieldNames ? '' : 'targetId')
    ..aOM<$0.Timestamp>(2, _omitFieldNames ? '' : 'snapshotVersion',
        subBuilder: $0.Timestamp.$_createMessage)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'resumeToken', $pb.PbFieldType.OY)
    ..aInt64(4, _omitFieldNames ? '' : 'lastListenSequenceNumber')
    ..aOM<$1.Target_QueryTarget>(5, _omitFieldNames ? '' : 'query',
        subBuilder: $1.Target_QueryTarget.$_createMessage)
    ..aOM<$1.Target_DocumentsTarget>(6, _omitFieldNames ? '' : 'documents',
        subBuilder: $1.Target_DocumentsTarget.$_createMessage)
    ..aOM<$0.Timestamp>(
        7, _omitFieldNames ? '' : 'lastLimboFreeSnapshotVersion',
        subBuilder: $0.Timestamp.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Target clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Target copyWith(void Function(Target) updates) =>
      super.copyWith((message) => updates(message as Target)) as Target;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Target() / Target.new instead')
  static Target create() => Target._();
  static $pb.GeneratedMessage $_createMessage() => Target._();
  @$core.override
  Target createEmptyInstance() => Target._();
  @$core.pragma('dart2js:noInline')
  static Target getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Target>(Target.$_createMessage);
  static Target? _defaultInstance;

  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  Target_TargetType whichTargetType() =>
      _Target_TargetTypeByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  void clearTargetType() => $_clearField($_whichOneof(0));

  /// An auto-generated sequential numeric identifier for the target. This
  /// serves as the identity of the target, and once assigned never changes.
  @$pb.TagNumber(1)
  $core.int get targetId => $_getIZ(0);
  @$pb.TagNumber(1)
  set targetId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTargetId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTargetId() => $_clearField(1);

  /// The last snapshot version received from the Watch Service for this target.
  ///
  /// This is the same value as TargetChange.read_time
  /// https://github.com/googleapis/googleapis/blob/master/google/firestore/v1/firestore.proto#L735
  @$pb.TagNumber(2)
  $0.Timestamp get snapshotVersion => $_getN(1);
  @$pb.TagNumber(2)
  set snapshotVersion($0.Timestamp value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasSnapshotVersion() => $_has(1);
  @$pb.TagNumber(2)
  void clearSnapshotVersion() => $_clearField(2);
  @$pb.TagNumber(2)
  $0.Timestamp ensureSnapshotVersion() => $_ensure(1);

  /// An opaque, server-assigned token that allows watching a query to be
  /// resumed after disconnecting without retransmitting all the data that
  /// matches the query. The resume token essentially identifies a point in
  /// time from which the server should resume sending results.
  ///
  /// This is related to the snapshot_version in that the resume_token
  /// effectively also encodes that value, but the resume_token is opaque and
  /// sometimes encodes additional information.
  ///
  /// A consequence of this is that the resume_token should be used when asking
  /// the server to reason about where this client is in the watch stream, but
  /// the client should use the snapshot_version for its own purposes.
  ///
  /// This is the same value as TargetChange.resume_token
  /// https://github.com/googleapis/googleapis/blob/master/google/firestore/v1/firestore.proto#L723
  @$pb.TagNumber(3)
  $core.List<$core.int> get resumeToken => $_getN(2);
  @$pb.TagNumber(3)
  set resumeToken($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasResumeToken() => $_has(2);
  @$pb.TagNumber(3)
  void clearResumeToken() => $_clearField(3);

  /// A sequence number representing the last time this query was listened to,
  /// used for garbage collection purposes.
  ///
  /// Conventionally this would be a timestamp value, but device-local clocks
  /// are unreliable and they must be able to create new listens even while
  /// disconnected. Instead this should be a monotonically increasing number
  /// that's incremented on each listen call.
  ///
  /// This is different from the target_id since the target_id is an immutable
  /// identifier assigned to the Target on first use while
  /// last_listen_sequence_number is updated every time the query is listened
  /// to.
  @$pb.TagNumber(4)
  $fixnum.Int64 get lastListenSequenceNumber => $_getI64(3);
  @$pb.TagNumber(4)
  set lastListenSequenceNumber($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasLastListenSequenceNumber() => $_has(3);
  @$pb.TagNumber(4)
  void clearLastListenSequenceNumber() => $_clearField(4);

  /// A target specified by a query.
  @$pb.TagNumber(5)
  $1.Target_QueryTarget get query => $_getN(4);
  @$pb.TagNumber(5)
  set query($1.Target_QueryTarget value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasQuery() => $_has(4);
  @$pb.TagNumber(5)
  void clearQuery() => $_clearField(5);
  @$pb.TagNumber(5)
  $1.Target_QueryTarget ensureQuery() => $_ensure(4);

  /// A target specified by a set of document names.
  @$pb.TagNumber(6)
  $1.Target_DocumentsTarget get documents => $_getN(5);
  @$pb.TagNumber(6)
  set documents($1.Target_DocumentsTarget value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasDocuments() => $_has(5);
  @$pb.TagNumber(6)
  void clearDocuments() => $_clearField(6);
  @$pb.TagNumber(6)
  $1.Target_DocumentsTarget ensureDocuments() => $_ensure(5);

  /// Denotes the maximum snapshot version at which the associated query view
  /// contained no limbo documents.
  @$pb.TagNumber(7)
  $0.Timestamp get lastLimboFreeSnapshotVersion => $_getN(6);
  @$pb.TagNumber(7)
  set lastLimboFreeSnapshotVersion($0.Timestamp value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasLastLimboFreeSnapshotVersion() => $_has(6);
  @$pb.TagNumber(7)
  void clearLastLimboFreeSnapshotVersion() => $_clearField(7);
  @$pb.TagNumber(7)
  $0.Timestamp ensureLastLimboFreeSnapshotVersion() => $_ensure(6);
}

/// Global state tracked across all Targets, tracked separately to avoid the
/// need for extra indexes.
class TargetGlobal extends $pb.GeneratedMessage {
  factory TargetGlobal({
    $core.int? highestTargetId,
    $fixnum.Int64? highestListenSequenceNumber,
    $0.Timestamp? lastRemoteSnapshotVersion,
    $core.int? targetCount,
  }) {
    final result = TargetGlobal._();
    if (highestTargetId != null) result.highestTargetId = highestTargetId;
    if (highestListenSequenceNumber != null)
      result.highestListenSequenceNumber = highestListenSequenceNumber;
    if (lastRemoteSnapshotVersion != null)
      result.lastRemoteSnapshotVersion = lastRemoteSnapshotVersion;
    if (targetCount != null) result.targetCount = targetCount;
    return result;
  }

  TargetGlobal._();

  factory TargetGlobal.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TargetGlobal()..mergeFromBuffer(data, registry);
  factory TargetGlobal.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TargetGlobal()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TargetGlobal',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'firestore.client'),
      createEmptyInstance: TargetGlobal.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'highestTargetId')
    ..aInt64(2, _omitFieldNames ? '' : 'highestListenSequenceNumber')
    ..aOM<$0.Timestamp>(3, _omitFieldNames ? '' : 'lastRemoteSnapshotVersion',
        subBuilder: $0.Timestamp.$_createMessage)
    ..aI(4, _omitFieldNames ? '' : 'targetCount')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TargetGlobal clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TargetGlobal copyWith(void Function(TargetGlobal) updates) =>
      super.copyWith((message) => updates(message as TargetGlobal))
          as TargetGlobal;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use TargetGlobal() / TargetGlobal.new instead')
  static TargetGlobal create() => TargetGlobal._();
  static $pb.GeneratedMessage $_createMessage() => TargetGlobal._();
  @$core.override
  TargetGlobal createEmptyInstance() => TargetGlobal._();
  @$core.pragma('dart2js:noInline')
  static TargetGlobal getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TargetGlobal>(
          TargetGlobal.$_createMessage);
  static TargetGlobal? _defaultInstance;

  /// The highest numbered target id across all Targets.
  ///
  /// See Target.target_id.
  @$pb.TagNumber(1)
  $core.int get highestTargetId => $_getIZ(0);
  @$pb.TagNumber(1)
  set highestTargetId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasHighestTargetId() => $_has(0);
  @$pb.TagNumber(1)
  void clearHighestTargetId() => $_clearField(1);

  /// The highest numbered last_listen_sequence_number across all Targets.
  ///
  /// See Target.last_listen_sequence_number.
  @$pb.TagNumber(2)
  $fixnum.Int64 get highestListenSequenceNumber => $_getI64(1);
  @$pb.TagNumber(2)
  set highestListenSequenceNumber($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasHighestListenSequenceNumber() => $_has(1);
  @$pb.TagNumber(2)
  void clearHighestListenSequenceNumber() => $_clearField(2);

  /// A global snapshot version representing the last consistent snapshot we
  /// received from the backend. This is monotonically increasing and any
  /// snapshots received from the backend prior to this version (e.g. for
  /// targets resumed with a resume_token) should be suppressed (buffered) until
  /// the backend has caught up to this snapshot_version again. This prevents
  /// our cache from ever going backwards in time.
  ///
  /// This is updated whenever our we get a TargetChange with a read_time and
  /// empty target_ids.
  @$pb.TagNumber(3)
  $0.Timestamp get lastRemoteSnapshotVersion => $_getN(2);
  @$pb.TagNumber(3)
  set lastRemoteSnapshotVersion($0.Timestamp value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasLastRemoteSnapshotVersion() => $_has(2);
  @$pb.TagNumber(3)
  void clearLastRemoteSnapshotVersion() => $_clearField(3);
  @$pb.TagNumber(3)
  $0.Timestamp ensureLastRemoteSnapshotVersion() => $_ensure(2);

  /// On platforms that need it, holds the number of targets persisted.
  @$pb.TagNumber(4)
  $core.int get targetCount => $_getIZ(3);
  @$pb.TagNumber(4)
  set targetCount($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTargetCount() => $_has(3);
  @$pb.TagNumber(4)
  void clearTargetCount() => $_clearField(4);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
