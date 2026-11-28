// This is a generated file - do not edit.
//
// Generated from connector_service.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;
import 'package:protobuf/well_known_types/google/protobuf/struct.pb.dart' as $0;

import 'graphql_error.pb.dart' as $1;
import 'graphql_response_extensions.pb.dart' as $2;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// The ExecuteQuery request to Firebase Data Connect.
class ExecuteQueryRequest extends $pb.GeneratedMessage {
  factory ExecuteQueryRequest({
    $core.String? name,
    $core.String? operationName,
    $0.Struct? variables,
  }) {
    final result = ExecuteQueryRequest._();
    if (name != null) result.name = name;
    if (operationName != null) result.operationName = operationName;
    if (variables != null) result.variables = variables;
    return result;
  }

  ExecuteQueryRequest._();

  factory ExecuteQueryRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ExecuteQueryRequest()..mergeFromBuffer(data, registry);
  factory ExecuteQueryRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ExecuteQueryRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ExecuteQueryRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'google.firebase.dataconnect.v1'),
      createEmptyInstance: ExecuteQueryRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOS(2, _omitFieldNames ? '' : 'operationName')
    ..aOM<$0.Struct>(3, _omitFieldNames ? '' : 'variables',
        subBuilder: $0.Struct.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ExecuteQueryRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ExecuteQueryRequest copyWith(void Function(ExecuteQueryRequest) updates) =>
      super.copyWith((message) => updates(message as ExecuteQueryRequest))
          as ExecuteQueryRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use ExecuteQueryRequest() / ExecuteQueryRequest.new instead')
  static ExecuteQueryRequest create() => ExecuteQueryRequest._();
  static $pb.GeneratedMessage $_createMessage() => ExecuteQueryRequest._();
  @$core.override
  ExecuteQueryRequest createEmptyInstance() => ExecuteQueryRequest._();
  @$core.pragma('dart2js:noInline')
  static ExecuteQueryRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ExecuteQueryRequest>(
          ExecuteQueryRequest.$_createMessage);
  static ExecuteQueryRequest? _defaultInstance;

  /// The resource name of the connector to find the predefined query, in
  /// the format:
  /// ```
  /// projects/{project}/locations/{location}/services/{service}/connectors/{connector}
  /// ```
  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  /// The name of the GraphQL operation name.
  /// Required because all Connector operations must be named.
  /// See https://graphql.org/learn/queries/#operation-name.
  /// (-- api-linter: core::0122::name-suffix=disabled
  ///     aip.dev/not-precedent: Must conform to GraphQL HTTP spec standard. --)
  @$pb.TagNumber(2)
  $core.String get operationName => $_getSZ(1);
  @$pb.TagNumber(2)
  set operationName($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasOperationName() => $_has(1);
  @$pb.TagNumber(2)
  void clearOperationName() => $_clearField(2);

  /// Values for GraphQL variables provided in this request.
  @$pb.TagNumber(3)
  $0.Struct get variables => $_getN(2);
  @$pb.TagNumber(3)
  set variables($0.Struct value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasVariables() => $_has(2);
  @$pb.TagNumber(3)
  void clearVariables() => $_clearField(3);
  @$pb.TagNumber(3)
  $0.Struct ensureVariables() => $_ensure(2);
}

/// The ExecuteMutation request to Firebase Data Connect.
class ExecuteMutationRequest extends $pb.GeneratedMessage {
  factory ExecuteMutationRequest({
    $core.String? name,
    $core.String? operationName,
    $0.Struct? variables,
  }) {
    final result = ExecuteMutationRequest._();
    if (name != null) result.name = name;
    if (operationName != null) result.operationName = operationName;
    if (variables != null) result.variables = variables;
    return result;
  }

  ExecuteMutationRequest._();

  factory ExecuteMutationRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ExecuteMutationRequest()..mergeFromBuffer(data, registry);
  factory ExecuteMutationRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ExecuteMutationRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ExecuteMutationRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'google.firebase.dataconnect.v1'),
      createEmptyInstance: ExecuteMutationRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOS(2, _omitFieldNames ? '' : 'operationName')
    ..aOM<$0.Struct>(3, _omitFieldNames ? '' : 'variables',
        subBuilder: $0.Struct.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ExecuteMutationRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ExecuteMutationRequest copyWith(
          void Function(ExecuteMutationRequest) updates) =>
      super.copyWith((message) => updates(message as ExecuteMutationRequest))
          as ExecuteMutationRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ExecuteMutationRequest() / ExecuteMutationRequest.new instead')
  static ExecuteMutationRequest create() => ExecuteMutationRequest._();
  static $pb.GeneratedMessage $_createMessage() => ExecuteMutationRequest._();
  @$core.override
  ExecuteMutationRequest createEmptyInstance() => ExecuteMutationRequest._();
  @$core.pragma('dart2js:noInline')
  static ExecuteMutationRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ExecuteMutationRequest>(
          ExecuteMutationRequest.$_createMessage);
  static ExecuteMutationRequest? _defaultInstance;

  /// The resource name of the connector to find the predefined mutation, in
  /// the format:
  /// ```
  /// projects/{project}/locations/{location}/services/{service}/connectors/{connector}
  /// ```
  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  /// The name of the GraphQL operation name.
  /// Required because all Connector operations must be named.
  /// See https://graphql.org/learn/queries/#operation-name.
  /// (-- api-linter: core::0122::name-suffix=disabled
  ///     aip.dev/not-precedent: Must conform to GraphQL HTTP spec standard. --)
  @$pb.TagNumber(2)
  $core.String get operationName => $_getSZ(1);
  @$pb.TagNumber(2)
  set operationName($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasOperationName() => $_has(1);
  @$pb.TagNumber(2)
  void clearOperationName() => $_clearField(2);

  /// Values for GraphQL variables provided in this request.
  @$pb.TagNumber(3)
  $0.Struct get variables => $_getN(2);
  @$pb.TagNumber(3)
  set variables($0.Struct value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasVariables() => $_has(2);
  @$pb.TagNumber(3)
  void clearVariables() => $_clearField(3);
  @$pb.TagNumber(3)
  $0.Struct ensureVariables() => $_ensure(2);
}

/// The ExecuteQuery response from Firebase Data Connect.
class ExecuteQueryResponse extends $pb.GeneratedMessage {
  factory ExecuteQueryResponse({
    $0.Struct? data,
    $core.Iterable<$1.GraphqlError>? errors,
    $2.GraphqlResponseExtensions? extensions,
  }) {
    final result = ExecuteQueryResponse._();
    if (data != null) result.data = data;
    if (errors != null) result.errors.addAll(errors);
    if (extensions != null) result.extensions = extensions;
    return result;
  }

  ExecuteQueryResponse._();

  factory ExecuteQueryResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ExecuteQueryResponse()..mergeFromBuffer(data, registry);
  factory ExecuteQueryResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ExecuteQueryResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ExecuteQueryResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'google.firebase.dataconnect.v1'),
      createEmptyInstance: ExecuteQueryResponse.$_createMessage)
    ..aOM<$0.Struct>(1, _omitFieldNames ? '' : 'data',
        subBuilder: $0.Struct.$_createMessage)
    ..pPM<$1.GraphqlError>(2, _omitFieldNames ? '' : 'errors',
        subBuilder: $1.GraphqlError.$_createMessage)
    ..aOM<$2.GraphqlResponseExtensions>(3, _omitFieldNames ? '' : 'extensions',
        subBuilder: $2.GraphqlResponseExtensions.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ExecuteQueryResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ExecuteQueryResponse copyWith(void Function(ExecuteQueryResponse) updates) =>
      super.copyWith((message) => updates(message as ExecuteQueryResponse))
          as ExecuteQueryResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ExecuteQueryResponse() / ExecuteQueryResponse.new instead')
  static ExecuteQueryResponse create() => ExecuteQueryResponse._();
  static $pb.GeneratedMessage $_createMessage() => ExecuteQueryResponse._();
  @$core.override
  ExecuteQueryResponse createEmptyInstance() => ExecuteQueryResponse._();
  @$core.pragma('dart2js:noInline')
  static ExecuteQueryResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ExecuteQueryResponse>(
          ExecuteQueryResponse.$_createMessage);
  static ExecuteQueryResponse? _defaultInstance;

  /// The result of executing the requested operation.
  @$pb.TagNumber(1)
  $0.Struct get data => $_getN(0);
  @$pb.TagNumber(1)
  set data($0.Struct value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasData() => $_has(0);
  @$pb.TagNumber(1)
  void clearData() => $_clearField(1);
  @$pb.TagNumber(1)
  $0.Struct ensureData() => $_ensure(0);

  /// Errors of this response.
  @$pb.TagNumber(2)
  $pb.PbList<$1.GraphqlError> get errors => $_getList(1);

  /// Additional response information.
  @$pb.TagNumber(3)
  $2.GraphqlResponseExtensions get extensions => $_getN(2);
  @$pb.TagNumber(3)
  set extensions($2.GraphqlResponseExtensions value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasExtensions() => $_has(2);
  @$pb.TagNumber(3)
  void clearExtensions() => $_clearField(3);
  @$pb.TagNumber(3)
  $2.GraphqlResponseExtensions ensureExtensions() => $_ensure(2);
}

/// The ExecuteMutation response from Firebase Data Connect.
class ExecuteMutationResponse extends $pb.GeneratedMessage {
  factory ExecuteMutationResponse({
    $0.Struct? data,
    $core.Iterable<$1.GraphqlError>? errors,
    $2.GraphqlResponseExtensions? extensions,
  }) {
    final result = ExecuteMutationResponse._();
    if (data != null) result.data = data;
    if (errors != null) result.errors.addAll(errors);
    if (extensions != null) result.extensions = extensions;
    return result;
  }

  ExecuteMutationResponse._();

  factory ExecuteMutationResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ExecuteMutationResponse()..mergeFromBuffer(data, registry);
  factory ExecuteMutationResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ExecuteMutationResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ExecuteMutationResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'google.firebase.dataconnect.v1'),
      createEmptyInstance: ExecuteMutationResponse.$_createMessage)
    ..aOM<$0.Struct>(1, _omitFieldNames ? '' : 'data',
        subBuilder: $0.Struct.$_createMessage)
    ..pPM<$1.GraphqlError>(2, _omitFieldNames ? '' : 'errors',
        subBuilder: $1.GraphqlError.$_createMessage)
    ..aOM<$2.GraphqlResponseExtensions>(3, _omitFieldNames ? '' : 'extensions',
        subBuilder: $2.GraphqlResponseExtensions.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ExecuteMutationResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ExecuteMutationResponse copyWith(
          void Function(ExecuteMutationResponse) updates) =>
      super.copyWith((message) => updates(message as ExecuteMutationResponse))
          as ExecuteMutationResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ExecuteMutationResponse() / ExecuteMutationResponse.new instead')
  static ExecuteMutationResponse create() => ExecuteMutationResponse._();
  static $pb.GeneratedMessage $_createMessage() => ExecuteMutationResponse._();
  @$core.override
  ExecuteMutationResponse createEmptyInstance() => ExecuteMutationResponse._();
  @$core.pragma('dart2js:noInline')
  static ExecuteMutationResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ExecuteMutationResponse>(
          ExecuteMutationResponse.$_createMessage);
  static ExecuteMutationResponse? _defaultInstance;

  /// The result of executing the requested operation.
  @$pb.TagNumber(1)
  $0.Struct get data => $_getN(0);
  @$pb.TagNumber(1)
  set data($0.Struct value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasData() => $_has(0);
  @$pb.TagNumber(1)
  void clearData() => $_clearField(1);
  @$pb.TagNumber(1)
  $0.Struct ensureData() => $_ensure(0);

  /// Errors of this response.
  @$pb.TagNumber(2)
  $pb.PbList<$1.GraphqlError> get errors => $_getList(1);

  /// Additional response information.
  @$pb.TagNumber(3)
  $2.GraphqlResponseExtensions get extensions => $_getN(2);
  @$pb.TagNumber(3)
  set extensions($2.GraphqlResponseExtensions value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasExtensions() => $_has(2);
  @$pb.TagNumber(3)
  void clearExtensions() => $_clearField(3);
  @$pb.TagNumber(3)
  $2.GraphqlResponseExtensions ensureExtensions() => $_ensure(2);
}

/// Firebase Data Connect provides means to deploy a set of predefined GraphQL
/// operations (queries and mutations) as a Connector.
///
/// Firebase developers can build mobile and web apps that uses Connectors
/// to access Data Sources directly. Connectors allow operations without
/// admin credentials and help Firebase customers control the API exposure.
///
/// Note: `ConnectorService` doesn't check IAM permissions and instead developers
/// must define auth policies on each pre-defined operation to secure this
/// connector. The auth policies typically define rules on the Firebase Auth
/// token.
class ConnectorServiceApi {
  final $pb.RpcClient _client;

  ConnectorServiceApi(this._client);

  /// Execute a predefined query in a Connector.
  $async.Future<ExecuteQueryResponse> executeQuery(
          $pb.ClientContext? ctx, ExecuteQueryRequest request) =>
      _client.invoke<ExecuteQueryResponse>(ctx, 'ConnectorService',
          'ExecuteQuery', request, ExecuteQueryResponse());

  /// Execute a predefined mutation in a Connector.
  $async.Future<ExecuteMutationResponse> executeMutation(
          $pb.ClientContext? ctx, ExecuteMutationRequest request) =>
      _client.invoke<ExecuteMutationResponse>(ctx, 'ConnectorService',
          'ExecuteMutation', request, ExecuteMutationResponse());
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
