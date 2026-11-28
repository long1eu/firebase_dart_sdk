// This is a generated file - do not edit.
//
// Generated from graphql_response_extensions.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;
import 'package:protobuf/well_known_types/google/protobuf/duration.pb.dart'
    as $1;
import 'package:protobuf/well_known_types/google/protobuf/struct.pb.dart' as $0;

import 'graphql_response_extensions.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'graphql_response_extensions.pbenum.dart';

/// GraphqlResponseExtensions contains additional information of
/// `GraphqlResponse` or `ExecuteQueryResponse`.
class GraphqlResponseExtensions extends $pb.GeneratedMessage {
  factory GraphqlResponseExtensions({
    $core.Iterable<DataConnectProperties>? dataConnect,
  }) {
    final result = GraphqlResponseExtensions._();
    if (dataConnect != null) result.dataConnect.addAll(dataConnect);
    return result;
  }

  GraphqlResponseExtensions._();

  factory GraphqlResponseExtensions.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GraphqlResponseExtensions()..mergeFromBuffer(data, registry);
  factory GraphqlResponseExtensions.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GraphqlResponseExtensions()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GraphqlResponseExtensions',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'google.firebase.dataconnect.v1'),
      createEmptyInstance: GraphqlResponseExtensions.$_createMessage)
    ..pPM<DataConnectProperties>(1, _omitFieldNames ? '' : 'dataConnect',
        subBuilder: DataConnectProperties.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GraphqlResponseExtensions clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GraphqlResponseExtensions copyWith(
          void Function(GraphqlResponseExtensions) updates) =>
      super.copyWith((message) => updates(message as GraphqlResponseExtensions))
          as GraphqlResponseExtensions;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use GraphqlResponseExtensions() / GraphqlResponseExtensions.new instead')
  static GraphqlResponseExtensions create() => GraphqlResponseExtensions._();
  static $pb.GeneratedMessage $_createMessage() =>
      GraphqlResponseExtensions._();
  @$core.override
  GraphqlResponseExtensions createEmptyInstance() =>
      GraphqlResponseExtensions._();
  @$core.pragma('dart2js:noInline')
  static GraphqlResponseExtensions getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GraphqlResponseExtensions>(
          GraphqlResponseExtensions.$_createMessage);
  static GraphqlResponseExtensions? _defaultInstance;

  /// Data Connect specific GraphQL extension, a list of paths and properties.
  /// (-- Future fields should go inside to avoid name conflicts with other GQL
  /// extensions in the wild unless we're implementing a common 3P pattern in
  /// extensions such as versioning and telemetry. --)
  @$pb.TagNumber(1)
  $pb.PbList<DataConnectProperties> get dataConnect => $_getList(0);
}

/// Data Connect specific properties for a path under response.data.
/// (-- Design doc: http://go/fdc-caching-wire-protocol --)
class DataConnectProperties extends $pb.GeneratedMessage {
  factory DataConnectProperties({
    $0.ListValue? path,
    $core.String? entityId,
    $core.Iterable<$core.String>? entityIds,
    $1.Duration? maxAge,
    Action? action,
  }) {
    final result = DataConnectProperties._();
    if (path != null) result.path = path;
    if (entityId != null) result.entityId = entityId;
    if (entityIds != null) result.entityIds.addAll(entityIds);
    if (maxAge != null) result.maxAge = maxAge;
    if (action != null) result.action = action;
    return result;
  }

  DataConnectProperties._();

  factory DataConnectProperties.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DataConnectProperties()..mergeFromBuffer(data, registry);
  factory DataConnectProperties.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DataConnectProperties()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DataConnectProperties',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'google.firebase.dataconnect.v1'),
      createEmptyInstance: DataConnectProperties.$_createMessage)
    ..aOM<$0.ListValue>(1, _omitFieldNames ? '' : 'path',
        subBuilder: $0.ListValue.$_createMessage)
    ..aOS(2, _omitFieldNames ? '' : 'entityId')
    ..pPS(3, _omitFieldNames ? '' : 'entityIds')
    ..aOM<$1.Duration>(4, _omitFieldNames ? '' : 'maxAge',
        subBuilder: $1.Duration.$_createMessage)
    ..aE<Action>(5, _omitFieldNames ? '' : 'action', enumValues: Action.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataConnectProperties clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataConnectProperties copyWith(
          void Function(DataConnectProperties) updates) =>
      super.copyWith((message) => updates(message as DataConnectProperties))
          as DataConnectProperties;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use DataConnectProperties() / DataConnectProperties.new instead')
  static DataConnectProperties create() => DataConnectProperties._();
  static $pb.GeneratedMessage $_createMessage() => DataConnectProperties._();
  @$core.override
  DataConnectProperties createEmptyInstance() => DataConnectProperties._();
  @$core.pragma('dart2js:noInline')
  static DataConnectProperties getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DataConnectProperties>(
          DataConnectProperties.$_createMessage);
  static DataConnectProperties? _defaultInstance;

  /// The path under response.data where the rest of the fields apply.
  /// Each element may be a string (field name) or number (array index).
  /// The root of response.data is denoted by the empty list `[]`.
  /// (-- To simplify client logic, the server should never set this to null.
  /// i.e. Use `[]` if the properties below apply to everything in data. --)
  @$pb.TagNumber(1)
  $0.ListValue get path => $_getN(0);
  @$pb.TagNumber(1)
  set path($0.ListValue value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearPath() => $_clearField(1);
  @$pb.TagNumber(1)
  $0.ListValue ensurePath() => $_ensure(0);

  /// A single Entity ID. Set if the path points to a single entity.
  @$pb.TagNumber(2)
  $core.String get entityId => $_getSZ(1);
  @$pb.TagNumber(2)
  set entityId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEntityId() => $_has(1);
  @$pb.TagNumber(2)
  void clearEntityId() => $_clearField(2);

  /// A list of Entity IDs. Set if the path points to an array of entities. An
  /// ID is present for each element of the array at the corresponding index.
  @$pb.TagNumber(3)
  $pb.PbList<$core.String> get entityIds => $_getList(2);

  /// The server-suggested duration before data under path is considered stale.
  /// (-- Right now, this field is never set. For future plans, see
  /// http://go/fdc-sdk-caching-config#heading=h.rmvncy2rao3g --)
  @$pb.TagNumber(4)
  $1.Duration get maxAge => $_getN(3);
  @$pb.TagNumber(4)
  set maxAge($1.Duration value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasMaxAge() => $_has(3);
  @$pb.TagNumber(4)
  void clearMaxAge() => $_clearField(4);
  @$pb.TagNumber(4)
  $1.Duration ensureMaxAge() => $_ensure(3);

  /// Indicates the action performed on the entity in this path.
  @$pb.TagNumber(5)
  Action get action => $_getN(4);
  @$pb.TagNumber(5)
  set action(Action value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasAction() => $_has(4);
  @$pb.TagNumber(5)
  void clearAction() => $_clearField(5);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
