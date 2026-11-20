// This is a generated file - do not edit.
//
// Generated from google/cloud/identitytoolkit/v2/authentication_service.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'mfa_info.pb.dart' as $0;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

enum FinalizeMfaSignInRequest_VerificationInfo { phoneVerificationInfo, notSet }

/// Finalizes sign-in by verifying MFA challenge.
class FinalizeMfaSignInRequest extends $pb.GeneratedMessage {
  factory FinalizeMfaSignInRequest({
    $core.String? mfaPendingCredential,
    $0.FinalizeMfaPhoneRequestInfo? phoneVerificationInfo,
    $core.String? tenantId,
  }) {
    final result = FinalizeMfaSignInRequest._();
    if (mfaPendingCredential != null)
      result.mfaPendingCredential = mfaPendingCredential;
    if (phoneVerificationInfo != null)
      result.phoneVerificationInfo = phoneVerificationInfo;
    if (tenantId != null) result.tenantId = tenantId;
    return result;
  }

  FinalizeMfaSignInRequest._();

  factory FinalizeMfaSignInRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinalizeMfaSignInRequest()..mergeFromBuffer(data, registry);
  factory FinalizeMfaSignInRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinalizeMfaSignInRequest()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, FinalizeMfaSignInRequest_VerificationInfo>
      _FinalizeMfaSignInRequest_VerificationInfoByTag = {
    3: FinalizeMfaSignInRequest_VerificationInfo.phoneVerificationInfo,
    0: FinalizeMfaSignInRequest_VerificationInfo.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FinalizeMfaSignInRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'google.cloud.identitytoolkit.v2'),
      createEmptyInstance: FinalizeMfaSignInRequest.$_createMessage)
    ..oo(0, [3])
    ..aOS(2, _omitFieldNames ? '' : 'mfaPendingCredential')
    ..aOM<$0.FinalizeMfaPhoneRequestInfo>(
        3, _omitFieldNames ? '' : 'phoneVerificationInfo',
        subBuilder: $0.FinalizeMfaPhoneRequestInfo.$_createMessage)
    ..aOS(4, _omitFieldNames ? '' : 'tenantId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinalizeMfaSignInRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinalizeMfaSignInRequest copyWith(
          void Function(FinalizeMfaSignInRequest) updates) =>
      super.copyWith((message) => updates(message as FinalizeMfaSignInRequest))
          as FinalizeMfaSignInRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use FinalizeMfaSignInRequest() / FinalizeMfaSignInRequest.new instead')
  static FinalizeMfaSignInRequest create() => FinalizeMfaSignInRequest._();
  static $pb.GeneratedMessage $_createMessage() => FinalizeMfaSignInRequest._();
  @$core.override
  FinalizeMfaSignInRequest createEmptyInstance() =>
      FinalizeMfaSignInRequest._();
  @$core.pragma('dart2js:noInline')
  static FinalizeMfaSignInRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FinalizeMfaSignInRequest>(
          FinalizeMfaSignInRequest.$_createMessage);
  static FinalizeMfaSignInRequest? _defaultInstance;

  @$pb.TagNumber(3)
  FinalizeMfaSignInRequest_VerificationInfo whichVerificationInfo() =>
      _FinalizeMfaSignInRequest_VerificationInfoByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(3)
  void clearVerificationInfo() => $_clearField($_whichOneof(0));

  /// Required. Pending credential from first factor sign-in.
  @$pb.TagNumber(2)
  $core.String get mfaPendingCredential => $_getSZ(0);
  @$pb.TagNumber(2)
  set mfaPendingCredential($core.String value) => $_setString(0, value);
  @$pb.TagNumber(2)
  $core.bool hasMfaPendingCredential() => $_has(0);
  @$pb.TagNumber(2)
  void clearMfaPendingCredential() => $_clearField(2);

  /// Proof of completion of the SMS based MFA challenge.
  @$pb.TagNumber(3)
  $0.FinalizeMfaPhoneRequestInfo get phoneVerificationInfo => $_getN(1);
  @$pb.TagNumber(3)
  set phoneVerificationInfo($0.FinalizeMfaPhoneRequestInfo value) =>
      $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasPhoneVerificationInfo() => $_has(1);
  @$pb.TagNumber(3)
  void clearPhoneVerificationInfo() => $_clearField(3);
  @$pb.TagNumber(3)
  $0.FinalizeMfaPhoneRequestInfo ensurePhoneVerificationInfo() => $_ensure(1);

  /// The ID of the Identity Platform tenant the user is signing in to. If not
  /// set, the user will sign in to the default Identity Platform project.
  @$pb.TagNumber(4)
  $core.String get tenantId => $_getSZ(2);
  @$pb.TagNumber(4)
  set tenantId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(4)
  $core.bool hasTenantId() => $_has(2);
  @$pb.TagNumber(4)
  void clearTenantId() => $_clearField(4);
}

enum FinalizeMfaSignInResponse_AuxiliaryAuthInfo { phoneAuthInfo, notSet }

/// FinalizeMfaSignIn response.
class FinalizeMfaSignInResponse extends $pb.GeneratedMessage {
  factory FinalizeMfaSignInResponse({
    $core.String? idToken,
    $core.String? refreshToken,
    $0.FinalizeMfaPhoneResponseInfo? phoneAuthInfo,
  }) {
    final result = FinalizeMfaSignInResponse._();
    if (idToken != null) result.idToken = idToken;
    if (refreshToken != null) result.refreshToken = refreshToken;
    if (phoneAuthInfo != null) result.phoneAuthInfo = phoneAuthInfo;
    return result;
  }

  FinalizeMfaSignInResponse._();

  factory FinalizeMfaSignInResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinalizeMfaSignInResponse()..mergeFromBuffer(data, registry);
  factory FinalizeMfaSignInResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinalizeMfaSignInResponse()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, FinalizeMfaSignInResponse_AuxiliaryAuthInfo>
      _FinalizeMfaSignInResponse_AuxiliaryAuthInfoByTag = {
    3: FinalizeMfaSignInResponse_AuxiliaryAuthInfo.phoneAuthInfo,
    0: FinalizeMfaSignInResponse_AuxiliaryAuthInfo.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FinalizeMfaSignInResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'google.cloud.identitytoolkit.v2'),
      createEmptyInstance: FinalizeMfaSignInResponse.$_createMessage)
    ..oo(0, [3])
    ..aOS(1, _omitFieldNames ? '' : 'idToken')
    ..aOS(2, _omitFieldNames ? '' : 'refreshToken')
    ..aOM<$0.FinalizeMfaPhoneResponseInfo>(
        3, _omitFieldNames ? '' : 'phoneAuthInfo',
        subBuilder: $0.FinalizeMfaPhoneResponseInfo.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinalizeMfaSignInResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinalizeMfaSignInResponse copyWith(
          void Function(FinalizeMfaSignInResponse) updates) =>
      super.copyWith((message) => updates(message as FinalizeMfaSignInResponse))
          as FinalizeMfaSignInResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use FinalizeMfaSignInResponse() / FinalizeMfaSignInResponse.new instead')
  static FinalizeMfaSignInResponse create() => FinalizeMfaSignInResponse._();
  static $pb.GeneratedMessage $_createMessage() =>
      FinalizeMfaSignInResponse._();
  @$core.override
  FinalizeMfaSignInResponse createEmptyInstance() =>
      FinalizeMfaSignInResponse._();
  @$core.pragma('dart2js:noInline')
  static FinalizeMfaSignInResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FinalizeMfaSignInResponse>(
          FinalizeMfaSignInResponse.$_createMessage);
  static FinalizeMfaSignInResponse? _defaultInstance;

  @$pb.TagNumber(3)
  FinalizeMfaSignInResponse_AuxiliaryAuthInfo whichAuxiliaryAuthInfo() =>
      _FinalizeMfaSignInResponse_AuxiliaryAuthInfoByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(3)
  void clearAuxiliaryAuthInfo() => $_clearField($_whichOneof(0));

  /// ID token for the authenticated user.
  @$pb.TagNumber(1)
  $core.String get idToken => $_getSZ(0);
  @$pb.TagNumber(1)
  set idToken($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIdToken() => $_has(0);
  @$pb.TagNumber(1)
  void clearIdToken() => $_clearField(1);

  /// Refresh token for the authenticated user.
  @$pb.TagNumber(2)
  $core.String get refreshToken => $_getSZ(1);
  @$pb.TagNumber(2)
  set refreshToken($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRefreshToken() => $_has(1);
  @$pb.TagNumber(2)
  void clearRefreshToken() => $_clearField(2);

  /// Extra phone auth info, including android verification proof.
  @$pb.TagNumber(3)
  $0.FinalizeMfaPhoneResponseInfo get phoneAuthInfo => $_getN(2);
  @$pb.TagNumber(3)
  set phoneAuthInfo($0.FinalizeMfaPhoneResponseInfo value) =>
      $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasPhoneAuthInfo() => $_has(2);
  @$pb.TagNumber(3)
  void clearPhoneAuthInfo() => $_clearField(3);
  @$pb.TagNumber(3)
  $0.FinalizeMfaPhoneResponseInfo ensurePhoneAuthInfo() => $_ensure(2);
}

enum StartMfaSignInRequest_SignInInfo { phoneSignInInfo, notSet }

/// Starts multi-factor sign-in by sending the multi-factor auth challenge.
class StartMfaSignInRequest extends $pb.GeneratedMessage {
  factory StartMfaSignInRequest({
    $core.String? mfaPendingCredential,
    $core.String? mfaEnrollmentId,
    $0.StartMfaPhoneRequestInfo? phoneSignInInfo,
    $core.String? tenantId,
  }) {
    final result = StartMfaSignInRequest._();
    if (mfaPendingCredential != null)
      result.mfaPendingCredential = mfaPendingCredential;
    if (mfaEnrollmentId != null) result.mfaEnrollmentId = mfaEnrollmentId;
    if (phoneSignInInfo != null) result.phoneSignInInfo = phoneSignInInfo;
    if (tenantId != null) result.tenantId = tenantId;
    return result;
  }

  StartMfaSignInRequest._();

  factory StartMfaSignInRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartMfaSignInRequest()..mergeFromBuffer(data, registry);
  factory StartMfaSignInRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartMfaSignInRequest()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, StartMfaSignInRequest_SignInInfo>
      _StartMfaSignInRequest_SignInInfoByTag = {
    4: StartMfaSignInRequest_SignInInfo.phoneSignInInfo,
    0: StartMfaSignInRequest_SignInInfo.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StartMfaSignInRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'google.cloud.identitytoolkit.v2'),
      createEmptyInstance: StartMfaSignInRequest.$_createMessage)
    ..oo(0, [4])
    ..aOS(2, _omitFieldNames ? '' : 'mfaPendingCredential')
    ..aOS(3, _omitFieldNames ? '' : 'mfaEnrollmentId')
    ..aOM<$0.StartMfaPhoneRequestInfo>(
        4, _omitFieldNames ? '' : 'phoneSignInInfo',
        subBuilder: $0.StartMfaPhoneRequestInfo.$_createMessage)
    ..aOS(5, _omitFieldNames ? '' : 'tenantId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartMfaSignInRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartMfaSignInRequest copyWith(
          void Function(StartMfaSignInRequest) updates) =>
      super.copyWith((message) => updates(message as StartMfaSignInRequest))
          as StartMfaSignInRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use StartMfaSignInRequest() / StartMfaSignInRequest.new instead')
  static StartMfaSignInRequest create() => StartMfaSignInRequest._();
  static $pb.GeneratedMessage $_createMessage() => StartMfaSignInRequest._();
  @$core.override
  StartMfaSignInRequest createEmptyInstance() => StartMfaSignInRequest._();
  @$core.pragma('dart2js:noInline')
  static StartMfaSignInRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StartMfaSignInRequest>(
          StartMfaSignInRequest.$_createMessage);
  static StartMfaSignInRequest? _defaultInstance;

  @$pb.TagNumber(4)
  StartMfaSignInRequest_SignInInfo whichSignInInfo() =>
      _StartMfaSignInRequest_SignInInfoByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(4)
  void clearSignInInfo() => $_clearField($_whichOneof(0));

  /// Required. Pending credential from first factor sign-in.
  @$pb.TagNumber(2)
  $core.String get mfaPendingCredential => $_getSZ(0);
  @$pb.TagNumber(2)
  set mfaPendingCredential($core.String value) => $_setString(0, value);
  @$pb.TagNumber(2)
  $core.bool hasMfaPendingCredential() => $_has(0);
  @$pb.TagNumber(2)
  void clearMfaPendingCredential() => $_clearField(2);

  /// Required. MFA enrollment id from the user's list of current MFA enrollments.
  @$pb.TagNumber(3)
  $core.String get mfaEnrollmentId => $_getSZ(1);
  @$pb.TagNumber(3)
  set mfaEnrollmentId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(3)
  $core.bool hasMfaEnrollmentId() => $_has(1);
  @$pb.TagNumber(3)
  void clearMfaEnrollmentId() => $_clearField(3);

  /// Verification info to authorize sending an SMS for phone verification.
  @$pb.TagNumber(4)
  $0.StartMfaPhoneRequestInfo get phoneSignInInfo => $_getN(2);
  @$pb.TagNumber(4)
  set phoneSignInInfo($0.StartMfaPhoneRequestInfo value) =>
      $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasPhoneSignInInfo() => $_has(2);
  @$pb.TagNumber(4)
  void clearPhoneSignInInfo() => $_clearField(4);
  @$pb.TagNumber(4)
  $0.StartMfaPhoneRequestInfo ensurePhoneSignInInfo() => $_ensure(2);

  /// The ID of the Identity Platform tenant the user is signing in to. If not
  /// set, the user will sign in to the default Identity Platform project.
  @$pb.TagNumber(5)
  $core.String get tenantId => $_getSZ(3);
  @$pb.TagNumber(5)
  set tenantId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(5)
  $core.bool hasTenantId() => $_has(3);
  @$pb.TagNumber(5)
  void clearTenantId() => $_clearField(5);
}

enum StartMfaSignInResponse_ResponseInfo { phoneResponseInfo, notSet }

/// StartMfaSignIn response.
class StartMfaSignInResponse extends $pb.GeneratedMessage {
  factory StartMfaSignInResponse({
    $0.StartMfaPhoneResponseInfo? phoneResponseInfo,
  }) {
    final result = StartMfaSignInResponse._();
    if (phoneResponseInfo != null) result.phoneResponseInfo = phoneResponseInfo;
    return result;
  }

  StartMfaSignInResponse._();

  factory StartMfaSignInResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartMfaSignInResponse()..mergeFromBuffer(data, registry);
  factory StartMfaSignInResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartMfaSignInResponse()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, StartMfaSignInResponse_ResponseInfo>
      _StartMfaSignInResponse_ResponseInfoByTag = {
    1: StartMfaSignInResponse_ResponseInfo.phoneResponseInfo,
    0: StartMfaSignInResponse_ResponseInfo.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StartMfaSignInResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'google.cloud.identitytoolkit.v2'),
      createEmptyInstance: StartMfaSignInResponse.$_createMessage)
    ..oo(0, [1])
    ..aOM<$0.StartMfaPhoneResponseInfo>(
        1, _omitFieldNames ? '' : 'phoneResponseInfo',
        subBuilder: $0.StartMfaPhoneResponseInfo.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartMfaSignInResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartMfaSignInResponse copyWith(
          void Function(StartMfaSignInResponse) updates) =>
      super.copyWith((message) => updates(message as StartMfaSignInResponse))
          as StartMfaSignInResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use StartMfaSignInResponse() / StartMfaSignInResponse.new instead')
  static StartMfaSignInResponse create() => StartMfaSignInResponse._();
  static $pb.GeneratedMessage $_createMessage() => StartMfaSignInResponse._();
  @$core.override
  StartMfaSignInResponse createEmptyInstance() => StartMfaSignInResponse._();
  @$core.pragma('dart2js:noInline')
  static StartMfaSignInResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StartMfaSignInResponse>(
          StartMfaSignInResponse.$_createMessage);
  static StartMfaSignInResponse? _defaultInstance;

  @$pb.TagNumber(1)
  StartMfaSignInResponse_ResponseInfo whichResponseInfo() =>
      _StartMfaSignInResponse_ResponseInfoByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  void clearResponseInfo() => $_clearField($_whichOneof(0));

  /// MultiFactor sign-in session information specific to SMS-type second
  /// factors. Along with the one-time code retrieved from the sent SMS, the
  /// contents of this session information should be passed to
  /// FinalizeMfaSignIn to complete the sign in.
  @$pb.TagNumber(1)
  $0.StartMfaPhoneResponseInfo get phoneResponseInfo => $_getN(0);
  @$pb.TagNumber(1)
  set phoneResponseInfo($0.StartMfaPhoneResponseInfo value) =>
      $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasPhoneResponseInfo() => $_has(0);
  @$pb.TagNumber(1)
  void clearPhoneResponseInfo() => $_clearField(1);
  @$pb.TagNumber(1)
  $0.StartMfaPhoneResponseInfo ensurePhoneResponseInfo() => $_ensure(0);
}

/// Authentication for Identity Toolkit
class AuthenticationServiceApi {
  final $pb.RpcClient _client;

  AuthenticationServiceApi(this._client);

  /// Verifies the MFA challenge and performs sign-in
  $async.Future<FinalizeMfaSignInResponse> finalizeMfaSignIn(
          $pb.ClientContext? ctx, FinalizeMfaSignInRequest request) =>
      _client.invoke<FinalizeMfaSignInResponse>(ctx, 'AuthenticationService',
          'FinalizeMfaSignIn', request, FinalizeMfaSignInResponse());

  /// Sends the MFA challenge
  $async.Future<StartMfaSignInResponse> startMfaSignIn(
          $pb.ClientContext? ctx, StartMfaSignInRequest request) =>
      _client.invoke<StartMfaSignInResponse>(ctx, 'AuthenticationService',
          'StartMfaSignIn', request, StartMfaSignInResponse());
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
