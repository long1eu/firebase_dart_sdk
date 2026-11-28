// This is a generated file - do not edit.
//
// Generated from graphql_error.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;
import 'package:protobuf/well_known_types/google/protobuf/struct.pb.dart' as $0;

import 'google/rpc/code.pbenum.dart' as $1;
import 'graphql_error.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'graphql_error.pbenum.dart';

/// GraphqlError conforms to the GraphQL error spec.
/// https://spec.graphql.org/draft/#sec-Errors
///
/// Firebase Data Connect API surfaces `GraphqlError` in various APIs:
/// - Upon compile error, `UpdateSchema` and `UpdateConnector` return
/// Code.Invalid_Argument with a list of `GraphqlError` in error details.
/// - Upon query compile error, `ExecuteGraphql`, `ExecuteGraphqlRead` and
/// `IntrospectGraphql` return Code.OK with a list of `GraphqlError` in response
/// body.
/// - Upon query execution error, `ExecuteGraphql`, `ExecuteGraphqlRead`,
/// `ExecuteMutation`, `ExecuteQuery`, `IntrospectGraphql`, `ImpersonateQuery`
/// and `ImpersonateMutation` all return Code.OK with a list of `GraphqlError` in
/// response body.
class GraphqlError extends $pb.GeneratedMessage {
  factory GraphqlError({
    $core.String? message,
    $core.Iterable<SourceLocation>? locations,
    $0.ListValue? path,
    GraphqlErrorExtensions? extensions,
  }) {
    final result = GraphqlError._();
    if (message != null) result.message = message;
    if (locations != null) result.locations.addAll(locations);
    if (path != null) result.path = path;
    if (extensions != null) result.extensions = extensions;
    return result;
  }

  GraphqlError._();

  factory GraphqlError.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GraphqlError()..mergeFromBuffer(data, registry);
  factory GraphqlError.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GraphqlError()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GraphqlError',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'google.firebase.dataconnect.v1'),
      createEmptyInstance: GraphqlError.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'message')
    ..pPM<SourceLocation>(2, _omitFieldNames ? '' : 'locations',
        subBuilder: SourceLocation.$_createMessage)
    ..aOM<$0.ListValue>(3, _omitFieldNames ? '' : 'path',
        subBuilder: $0.ListValue.$_createMessage)
    ..aOM<GraphqlErrorExtensions>(4, _omitFieldNames ? '' : 'extensions',
        subBuilder: GraphqlErrorExtensions.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GraphqlError clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GraphqlError copyWith(void Function(GraphqlError) updates) =>
      super.copyWith((message) => updates(message as GraphqlError))
          as GraphqlError;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use GraphqlError() / GraphqlError.new instead')
  static GraphqlError create() => GraphqlError._();
  static $pb.GeneratedMessage $_createMessage() => GraphqlError._();
  @$core.override
  GraphqlError createEmptyInstance() => GraphqlError._();
  @$core.pragma('dart2js:noInline')
  static GraphqlError getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GraphqlError>(
          GraphqlError.$_createMessage);
  static GraphqlError? _defaultInstance;

  /// The detailed error message.
  /// The message should help developer understand the underlying problem without
  /// leaking internal data.
  @$pb.TagNumber(1)
  $core.String get message => $_getSZ(0);
  @$pb.TagNumber(1)
  set message($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMessage() => $_has(0);
  @$pb.TagNumber(1)
  void clearMessage() => $_clearField(1);

  /// The source locations where the error occurred.
  /// Locations should help developers and toolings identify the source of error
  /// quickly.
  ///
  /// Included in admin endpoints (`ExecuteGraphql`, `ExecuteGraphqlRead`,
  /// `IntrospectGraphql`, `ImpersonateQuery`, `ImpersonateMutation`,
  /// `UpdateSchema` and `UpdateConnector`) to reference the provided GraphQL
  /// GQL document.
  ///
  /// Omitted in `ExecuteMutation` and `ExecuteQuery` since the caller shouldn't
  /// have access access the underlying GQL source.
  @$pb.TagNumber(2)
  $pb.PbList<SourceLocation> get locations => $_getList(1);

  /// The result field which could not be populated due to error.
  ///
  /// Clients can use path to identify whether a null result is intentional or
  /// caused by a runtime error.
  /// It should be a list of string or index from the root of GraphQL query
  /// document.
  @$pb.TagNumber(3)
  $0.ListValue get path => $_getN(2);
  @$pb.TagNumber(3)
  set path($0.ListValue value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasPath() => $_has(2);
  @$pb.TagNumber(3)
  void clearPath() => $_clearField(3);
  @$pb.TagNumber(3)
  $0.ListValue ensurePath() => $_ensure(2);

  /// Additional error information.
  @$pb.TagNumber(4)
  GraphqlErrorExtensions get extensions => $_getN(3);
  @$pb.TagNumber(4)
  set extensions(GraphqlErrorExtensions value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasExtensions() => $_has(3);
  @$pb.TagNumber(4)
  void clearExtensions() => $_clearField(4);
  @$pb.TagNumber(4)
  GraphqlErrorExtensions ensureExtensions() => $_ensure(3);
}

/// GraphqlErrorExtensions contains additional information of `GraphqlError`.
class GraphqlErrorExtensions extends $pb.GeneratedMessage {
  factory GraphqlErrorExtensions({
    $core.String? file,
    $1.Code? code,
    $core.String? debugDetails,
    $core.String? resource,
    WarningLevel? warningLevel,
    $core.Iterable<Workaround>? workarounds,
  }) {
    final result = GraphqlErrorExtensions._();
    if (file != null) result.file = file;
    if (code != null) result.code = code;
    if (debugDetails != null) result.debugDetails = debugDetails;
    if (resource != null) result.resource = resource;
    if (warningLevel != null) result.warningLevel = warningLevel;
    if (workarounds != null) result.workarounds.addAll(workarounds);
    return result;
  }

  GraphqlErrorExtensions._();

  factory GraphqlErrorExtensions.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GraphqlErrorExtensions()..mergeFromBuffer(data, registry);
  factory GraphqlErrorExtensions.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GraphqlErrorExtensions()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GraphqlErrorExtensions',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'google.firebase.dataconnect.v1'),
      createEmptyInstance: GraphqlErrorExtensions.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'file')
    ..aE<$1.Code>(2, _omitFieldNames ? '' : 'code', enumValues: $1.Code.values)
    ..aOS(3, _omitFieldNames ? '' : 'debugDetails')
    ..aOS(4, _omitFieldNames ? '' : 'resource')
    ..aE<WarningLevel>(5, _omitFieldNames ? '' : 'warningLevel',
        enumValues: WarningLevel.values)
    ..pPM<Workaround>(6, _omitFieldNames ? '' : 'workarounds',
        subBuilder: Workaround.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GraphqlErrorExtensions clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GraphqlErrorExtensions copyWith(
          void Function(GraphqlErrorExtensions) updates) =>
      super.copyWith((message) => updates(message as GraphqlErrorExtensions))
          as GraphqlErrorExtensions;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use GraphqlErrorExtensions() / GraphqlErrorExtensions.new instead')
  static GraphqlErrorExtensions create() => GraphqlErrorExtensions._();
  static $pb.GeneratedMessage $_createMessage() => GraphqlErrorExtensions._();
  @$core.override
  GraphqlErrorExtensions createEmptyInstance() => GraphqlErrorExtensions._();
  @$core.pragma('dart2js:noInline')
  static GraphqlErrorExtensions getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GraphqlErrorExtensions>(
          GraphqlErrorExtensions.$_createMessage);
  static GraphqlErrorExtensions? _defaultInstance;

  /// The source file name where the error occurred.
  /// Included only for `UpdateSchema` and `UpdateConnector`, it corresponds
  /// to `File.path` of the provided `Source`.
  @$pb.TagNumber(1)
  $core.String get file => $_getSZ(0);
  @$pb.TagNumber(1)
  set file($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFile() => $_has(0);
  @$pb.TagNumber(1)
  void clearFile() => $_clearField(1);

  /// Maps to canonical gRPC codes.
  /// If not specified, it represents `Code.INTERNAL`.
  @$pb.TagNumber(2)
  $1.Code get code => $_getN(1);
  @$pb.TagNumber(2)
  set code($1.Code value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasCode() => $_has(1);
  @$pb.TagNumber(2)
  void clearCode() => $_clearField(2);

  /// More detailed error message to assist debugging.
  /// It contains application business logic that are inappropriate to leak
  /// publicly.
  ///
  /// In the emulator, Data Connect API always includes it to assist local
  /// development and debugging.
  /// In the backend, ConnectorService always hides it.
  /// GraphqlService without impersonation always include it.
  /// GraphqlService with impersonation includes it only if explicitly opted-in
  /// with `include_debug_details` in `GraphqlRequestExtensions`.
  @$pb.TagNumber(3)
  $core.String get debugDetails => $_getSZ(2);
  @$pb.TagNumber(3)
  set debugDetails($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDebugDetails() => $_has(2);
  @$pb.TagNumber(3)
  void clearDebugDetails() => $_clearField(3);

  /// Distinguish which schema or connector the error originates from.
  /// It should be set on errors from control plane APIs (e.g. `UpdateSchema`,
  /// `UpdateConnector`).
  @$pb.TagNumber(4)
  $core.String get resource => $_getSZ(3);
  @$pb.TagNumber(4)
  set resource($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasResource() => $_has(3);
  @$pb.TagNumber(4)
  void clearResource() => $_clearField(4);

  /// Warning level describes the severity and required action to suppress this
  /// warning when Firebase CLI run into it.
  @$pb.TagNumber(5)
  WarningLevel get warningLevel => $_getN(4);
  @$pb.TagNumber(5)
  set warningLevel(WarningLevel value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasWarningLevel() => $_has(4);
  @$pb.TagNumber(5)
  void clearWarningLevel() => $_clearField(5);

  /// Workarounds provide suggestions to address warnings.
  @$pb.TagNumber(6)
  $pb.PbList<Workaround> get workarounds => $_getList(5);
}

/// Workaround provides suggestions to address errors and warnings.
class Workaround extends $pb.GeneratedMessage {
  factory Workaround({
    $core.String? description,
    $core.String? reason,
    $core.String? replace,
  }) {
    final result = Workaround._();
    if (description != null) result.description = description;
    if (reason != null) result.reason = reason;
    if (replace != null) result.replace = replace;
    return result;
  }

  Workaround._();

  factory Workaround.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Workaround()..mergeFromBuffer(data, registry);
  factory Workaround.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Workaround()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Workaround',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'google.firebase.dataconnect.v1'),
      createEmptyInstance: Workaround.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'description')
    ..aOS(2, _omitFieldNames ? '' : 'reason')
    ..aOS(3, _omitFieldNames ? '' : 'replace')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Workaround clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Workaround copyWith(void Function(Workaround) updates) =>
      super.copyWith((message) => updates(message as Workaround)) as Workaround;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Workaround() / Workaround.new instead')
  static Workaround create() => Workaround._();
  static $pb.GeneratedMessage $_createMessage() => Workaround._();
  @$core.override
  Workaround createEmptyInstance() => Workaround._();
  @$core.pragma('dart2js:noInline')
  static Workaround getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Workaround>(Workaround.$_createMessage);
  static Workaround? _defaultInstance;

  /// Description of this workaround.
  @$pb.TagNumber(1)
  $core.String get description => $_getSZ(0);
  @$pb.TagNumber(1)
  set description($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDescription() => $_has(0);
  @$pb.TagNumber(1)
  void clearDescription() => $_clearField(1);

  /// Why would this workaround address the error and warning.
  @$pb.TagNumber(2)
  $core.String get reason => $_getSZ(1);
  @$pb.TagNumber(2)
  set reason($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasReason() => $_has(1);
  @$pb.TagNumber(2)
  void clearReason() => $_clearField(2);

  /// A suggested code snippet to fix the error and warning.
  @$pb.TagNumber(3)
  $core.String get replace => $_getSZ(2);
  @$pb.TagNumber(3)
  set replace($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasReplace() => $_has(2);
  @$pb.TagNumber(3)
  void clearReplace() => $_clearField(3);
}

/// SourceLocation references a location in a GraphQL source.
class SourceLocation extends $pb.GeneratedMessage {
  factory SourceLocation({
    $core.int? line,
    $core.int? column,
  }) {
    final result = SourceLocation._();
    if (line != null) result.line = line;
    if (column != null) result.column = column;
    return result;
  }

  SourceLocation._();

  factory SourceLocation.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SourceLocation()..mergeFromBuffer(data, registry);
  factory SourceLocation.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SourceLocation()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SourceLocation',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'google.firebase.dataconnect.v1'),
      createEmptyInstance: SourceLocation.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'line')
    ..aI(2, _omitFieldNames ? '' : 'column')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SourceLocation clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SourceLocation copyWith(void Function(SourceLocation) updates) =>
      super.copyWith((message) => updates(message as SourceLocation))
          as SourceLocation;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SourceLocation() / SourceLocation.new instead')
  static SourceLocation create() => SourceLocation._();
  static $pb.GeneratedMessage $_createMessage() => SourceLocation._();
  @$core.override
  SourceLocation createEmptyInstance() => SourceLocation._();
  @$core.pragma('dart2js:noInline')
  static SourceLocation getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SourceLocation>(
          SourceLocation.$_createMessage);
  static SourceLocation? _defaultInstance;

  /// Line number starting at 1.
  @$pb.TagNumber(1)
  $core.int get line => $_getIZ(0);
  @$pb.TagNumber(1)
  set line($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLine() => $_has(0);
  @$pb.TagNumber(1)
  void clearLine() => $_clearField(1);

  /// Column number starting at 1.
  @$pb.TagNumber(2)
  $core.int get column => $_getIZ(1);
  @$pb.TagNumber(2)
  set column($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasColumn() => $_has(1);
  @$pb.TagNumber(2)
  void clearColumn() => $_clearField(2);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
