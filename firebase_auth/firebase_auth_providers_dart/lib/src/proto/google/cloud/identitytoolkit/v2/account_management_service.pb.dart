// This is a generated file - do not edit.
//
// Generated from google/cloud/identitytoolkit/v2/account_management_service.proto.

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

enum FinalizeMfaEnrollmentRequest_VerificationInfo {
  phoneVerificationInfo,
  notSet
}

/// Finishes enrolling a second factor for the user.
class FinalizeMfaEnrollmentRequest extends $pb.GeneratedMessage {
  factory FinalizeMfaEnrollmentRequest({
    $core.String? idToken,
    $core.String? displayName,
    $0.FinalizeMfaPhoneRequestInfo? phoneVerificationInfo,
    $core.String? tenantId,
  }) {
    final result = FinalizeMfaEnrollmentRequest._();
    if (idToken != null) result.idToken = idToken;
    if (displayName != null) result.displayName = displayName;
    if (phoneVerificationInfo != null)
      result.phoneVerificationInfo = phoneVerificationInfo;
    if (tenantId != null) result.tenantId = tenantId;
    return result;
  }

  FinalizeMfaEnrollmentRequest._();

  factory FinalizeMfaEnrollmentRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinalizeMfaEnrollmentRequest()..mergeFromBuffer(data, registry);
  factory FinalizeMfaEnrollmentRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinalizeMfaEnrollmentRequest()..mergeFromJson(json, registry);

  static const $core
      .Map<$core.int, FinalizeMfaEnrollmentRequest_VerificationInfo>
      _FinalizeMfaEnrollmentRequest_VerificationInfoByTag = {
    4: FinalizeMfaEnrollmentRequest_VerificationInfo.phoneVerificationInfo,
    0: FinalizeMfaEnrollmentRequest_VerificationInfo.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FinalizeMfaEnrollmentRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'google.cloud.identitytoolkit.v2'),
      createEmptyInstance: FinalizeMfaEnrollmentRequest.$_createMessage)
    ..oo(0, [4])
    ..aOS(1, _omitFieldNames ? '' : 'idToken')
    ..aOS(3, _omitFieldNames ? '' : 'displayName')
    ..aOM<$0.FinalizeMfaPhoneRequestInfo>(
        4, _omitFieldNames ? '' : 'phoneVerificationInfo',
        subBuilder: $0.FinalizeMfaPhoneRequestInfo.$_createMessage)
    ..aOS(5, _omitFieldNames ? '' : 'tenantId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinalizeMfaEnrollmentRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinalizeMfaEnrollmentRequest copyWith(
          void Function(FinalizeMfaEnrollmentRequest) updates) =>
      super.copyWith(
              (message) => updates(message as FinalizeMfaEnrollmentRequest))
          as FinalizeMfaEnrollmentRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use FinalizeMfaEnrollmentRequest() / FinalizeMfaEnrollmentRequest.new instead')
  static FinalizeMfaEnrollmentRequest create() =>
      FinalizeMfaEnrollmentRequest._();
  static $pb.GeneratedMessage $_createMessage() =>
      FinalizeMfaEnrollmentRequest._();
  @$core.override
  FinalizeMfaEnrollmentRequest createEmptyInstance() =>
      FinalizeMfaEnrollmentRequest._();
  @$core.pragma('dart2js:noInline')
  static FinalizeMfaEnrollmentRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FinalizeMfaEnrollmentRequest>(
          FinalizeMfaEnrollmentRequest.$_createMessage);
  static FinalizeMfaEnrollmentRequest? _defaultInstance;

  @$pb.TagNumber(4)
  FinalizeMfaEnrollmentRequest_VerificationInfo whichVerificationInfo() =>
      _FinalizeMfaEnrollmentRequest_VerificationInfoByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(4)
  void clearVerificationInfo() => $_clearField($_whichOneof(0));

  /// Required. ID token.
  @$pb.TagNumber(1)
  $core.String get idToken => $_getSZ(0);
  @$pb.TagNumber(1)
  set idToken($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIdToken() => $_has(0);
  @$pb.TagNumber(1)
  void clearIdToken() => $_clearField(1);

  /// Display name which is entered  by users to distinguish between different
  /// second factors with same type or different type.
  @$pb.TagNumber(3)
  $core.String get displayName => $_getSZ(1);
  @$pb.TagNumber(3)
  set displayName($core.String value) => $_setString(1, value);
  @$pb.TagNumber(3)
  $core.bool hasDisplayName() => $_has(1);
  @$pb.TagNumber(3)
  void clearDisplayName() => $_clearField(3);

  /// Verification info to authorize sending an SMS for phone verification.
  @$pb.TagNumber(4)
  $0.FinalizeMfaPhoneRequestInfo get phoneVerificationInfo => $_getN(2);
  @$pb.TagNumber(4)
  set phoneVerificationInfo($0.FinalizeMfaPhoneRequestInfo value) =>
      $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasPhoneVerificationInfo() => $_has(2);
  @$pb.TagNumber(4)
  void clearPhoneVerificationInfo() => $_clearField(4);
  @$pb.TagNumber(4)
  $0.FinalizeMfaPhoneRequestInfo ensurePhoneVerificationInfo() => $_ensure(2);

  /// The ID of the Identity Platform tenant that the user enrolling MFA belongs
  /// to. If not set, the user belongs to the default Identity Platform project.
  @$pb.TagNumber(5)
  $core.String get tenantId => $_getSZ(3);
  @$pb.TagNumber(5)
  set tenantId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(5)
  $core.bool hasTenantId() => $_has(3);
  @$pb.TagNumber(5)
  void clearTenantId() => $_clearField(5);
}

enum FinalizeMfaEnrollmentResponse_AuxiliaryAuthInfo { phoneAuthInfo, notSet }

/// FinalizeMfaEnrollment response.
class FinalizeMfaEnrollmentResponse extends $pb.GeneratedMessage {
  factory FinalizeMfaEnrollmentResponse({
    $core.String? idToken,
    $core.String? refreshToken,
    $0.FinalizeMfaPhoneResponseInfo? phoneAuthInfo,
  }) {
    final result = FinalizeMfaEnrollmentResponse._();
    if (idToken != null) result.idToken = idToken;
    if (refreshToken != null) result.refreshToken = refreshToken;
    if (phoneAuthInfo != null) result.phoneAuthInfo = phoneAuthInfo;
    return result;
  }

  FinalizeMfaEnrollmentResponse._();

  factory FinalizeMfaEnrollmentResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinalizeMfaEnrollmentResponse()..mergeFromBuffer(data, registry);
  factory FinalizeMfaEnrollmentResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinalizeMfaEnrollmentResponse()..mergeFromJson(json, registry);

  static const $core
      .Map<$core.int, FinalizeMfaEnrollmentResponse_AuxiliaryAuthInfo>
      _FinalizeMfaEnrollmentResponse_AuxiliaryAuthInfoByTag = {
    3: FinalizeMfaEnrollmentResponse_AuxiliaryAuthInfo.phoneAuthInfo,
    0: FinalizeMfaEnrollmentResponse_AuxiliaryAuthInfo.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FinalizeMfaEnrollmentResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'google.cloud.identitytoolkit.v2'),
      createEmptyInstance: FinalizeMfaEnrollmentResponse.$_createMessage)
    ..oo(0, [3])
    ..aOS(1, _omitFieldNames ? '' : 'idToken')
    ..aOS(2, _omitFieldNames ? '' : 'refreshToken')
    ..aOM<$0.FinalizeMfaPhoneResponseInfo>(
        3, _omitFieldNames ? '' : 'phoneAuthInfo',
        subBuilder: $0.FinalizeMfaPhoneResponseInfo.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinalizeMfaEnrollmentResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinalizeMfaEnrollmentResponse copyWith(
          void Function(FinalizeMfaEnrollmentResponse) updates) =>
      super.copyWith(
              (message) => updates(message as FinalizeMfaEnrollmentResponse))
          as FinalizeMfaEnrollmentResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use FinalizeMfaEnrollmentResponse() / FinalizeMfaEnrollmentResponse.new instead')
  static FinalizeMfaEnrollmentResponse create() =>
      FinalizeMfaEnrollmentResponse._();
  static $pb.GeneratedMessage $_createMessage() =>
      FinalizeMfaEnrollmentResponse._();
  @$core.override
  FinalizeMfaEnrollmentResponse createEmptyInstance() =>
      FinalizeMfaEnrollmentResponse._();
  @$core.pragma('dart2js:noInline')
  static FinalizeMfaEnrollmentResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FinalizeMfaEnrollmentResponse>(
          FinalizeMfaEnrollmentResponse.$_createMessage);
  static FinalizeMfaEnrollmentResponse? _defaultInstance;

  @$pb.TagNumber(3)
  FinalizeMfaEnrollmentResponse_AuxiliaryAuthInfo whichAuxiliaryAuthInfo() =>
      _FinalizeMfaEnrollmentResponse_AuxiliaryAuthInfoByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(3)
  void clearAuxiliaryAuthInfo() => $_clearField($_whichOneof(0));

  /// ID token updated to reflect MFA enrollment.
  @$pb.TagNumber(1)
  $core.String get idToken => $_getSZ(0);
  @$pb.TagNumber(1)
  set idToken($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIdToken() => $_has(0);
  @$pb.TagNumber(1)
  void clearIdToken() => $_clearField(1);

  /// Refresh token updated to reflect MFA enrollment.
  @$pb.TagNumber(2)
  $core.String get refreshToken => $_getSZ(1);
  @$pb.TagNumber(2)
  set refreshToken($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRefreshToken() => $_has(1);
  @$pb.TagNumber(2)
  void clearRefreshToken() => $_clearField(2);

  /// Auxiliary auth info specific to phone auth.
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

enum StartMfaEnrollmentRequest_EnrollmentInfo { phoneEnrollmentInfo, notSet }

/// Sends MFA enrollment verification SMS for a user.
class StartMfaEnrollmentRequest extends $pb.GeneratedMessage {
  factory StartMfaEnrollmentRequest({
    $core.String? idToken,
    $0.StartMfaPhoneRequestInfo? phoneEnrollmentInfo,
    $core.String? tenantId,
  }) {
    final result = StartMfaEnrollmentRequest._();
    if (idToken != null) result.idToken = idToken;
    if (phoneEnrollmentInfo != null)
      result.phoneEnrollmentInfo = phoneEnrollmentInfo;
    if (tenantId != null) result.tenantId = tenantId;
    return result;
  }

  StartMfaEnrollmentRequest._();

  factory StartMfaEnrollmentRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartMfaEnrollmentRequest()..mergeFromBuffer(data, registry);
  factory StartMfaEnrollmentRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartMfaEnrollmentRequest()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, StartMfaEnrollmentRequest_EnrollmentInfo>
      _StartMfaEnrollmentRequest_EnrollmentInfoByTag = {
    3: StartMfaEnrollmentRequest_EnrollmentInfo.phoneEnrollmentInfo,
    0: StartMfaEnrollmentRequest_EnrollmentInfo.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StartMfaEnrollmentRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'google.cloud.identitytoolkit.v2'),
      createEmptyInstance: StartMfaEnrollmentRequest.$_createMessage)
    ..oo(0, [3])
    ..aOS(1, _omitFieldNames ? '' : 'idToken')
    ..aOM<$0.StartMfaPhoneRequestInfo>(
        3, _omitFieldNames ? '' : 'phoneEnrollmentInfo',
        subBuilder: $0.StartMfaPhoneRequestInfo.$_createMessage)
    ..aOS(4, _omitFieldNames ? '' : 'tenantId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartMfaEnrollmentRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartMfaEnrollmentRequest copyWith(
          void Function(StartMfaEnrollmentRequest) updates) =>
      super.copyWith((message) => updates(message as StartMfaEnrollmentRequest))
          as StartMfaEnrollmentRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use StartMfaEnrollmentRequest() / StartMfaEnrollmentRequest.new instead')
  static StartMfaEnrollmentRequest create() => StartMfaEnrollmentRequest._();
  static $pb.GeneratedMessage $_createMessage() =>
      StartMfaEnrollmentRequest._();
  @$core.override
  StartMfaEnrollmentRequest createEmptyInstance() =>
      StartMfaEnrollmentRequest._();
  @$core.pragma('dart2js:noInline')
  static StartMfaEnrollmentRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StartMfaEnrollmentRequest>(
          StartMfaEnrollmentRequest.$_createMessage);
  static StartMfaEnrollmentRequest? _defaultInstance;

  @$pb.TagNumber(3)
  StartMfaEnrollmentRequest_EnrollmentInfo whichEnrollmentInfo() =>
      _StartMfaEnrollmentRequest_EnrollmentInfoByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(3)
  void clearEnrollmentInfo() => $_clearField($_whichOneof(0));

  /// Required. User's ID token.
  @$pb.TagNumber(1)
  $core.String get idToken => $_getSZ(0);
  @$pb.TagNumber(1)
  set idToken($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIdToken() => $_has(0);
  @$pb.TagNumber(1)
  void clearIdToken() => $_clearField(1);

  /// Verification info to authorize sending an SMS for phone verification.
  @$pb.TagNumber(3)
  $0.StartMfaPhoneRequestInfo get phoneEnrollmentInfo => $_getN(1);
  @$pb.TagNumber(3)
  set phoneEnrollmentInfo($0.StartMfaPhoneRequestInfo value) =>
      $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasPhoneEnrollmentInfo() => $_has(1);
  @$pb.TagNumber(3)
  void clearPhoneEnrollmentInfo() => $_clearField(3);
  @$pb.TagNumber(3)
  $0.StartMfaPhoneRequestInfo ensurePhoneEnrollmentInfo() => $_ensure(1);

  /// The ID of the Identity Platform tenant that the user enrolling MFA belongs
  /// to. If not set, the user belongs to the default Identity Platform project.
  @$pb.TagNumber(4)
  $core.String get tenantId => $_getSZ(2);
  @$pb.TagNumber(4)
  set tenantId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(4)
  $core.bool hasTenantId() => $_has(2);
  @$pb.TagNumber(4)
  void clearTenantId() => $_clearField(4);
}

enum StartMfaEnrollmentResponse_EnrollmentResponse { phoneSessionInfo, notSet }

/// StartMfaEnrollment response.
class StartMfaEnrollmentResponse extends $pb.GeneratedMessage {
  factory StartMfaEnrollmentResponse({
    $0.StartMfaPhoneResponseInfo? phoneSessionInfo,
  }) {
    final result = StartMfaEnrollmentResponse._();
    if (phoneSessionInfo != null) result.phoneSessionInfo = phoneSessionInfo;
    return result;
  }

  StartMfaEnrollmentResponse._();

  factory StartMfaEnrollmentResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartMfaEnrollmentResponse()..mergeFromBuffer(data, registry);
  factory StartMfaEnrollmentResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartMfaEnrollmentResponse()..mergeFromJson(json, registry);

  static const $core
      .Map<$core.int, StartMfaEnrollmentResponse_EnrollmentResponse>
      _StartMfaEnrollmentResponse_EnrollmentResponseByTag = {
    1: StartMfaEnrollmentResponse_EnrollmentResponse.phoneSessionInfo,
    0: StartMfaEnrollmentResponse_EnrollmentResponse.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StartMfaEnrollmentResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'google.cloud.identitytoolkit.v2'),
      createEmptyInstance: StartMfaEnrollmentResponse.$_createMessage)
    ..oo(0, [1])
    ..aOM<$0.StartMfaPhoneResponseInfo>(
        1, _omitFieldNames ? '' : 'phoneSessionInfo',
        subBuilder: $0.StartMfaPhoneResponseInfo.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartMfaEnrollmentResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartMfaEnrollmentResponse copyWith(
          void Function(StartMfaEnrollmentResponse) updates) =>
      super.copyWith(
              (message) => updates(message as StartMfaEnrollmentResponse))
          as StartMfaEnrollmentResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use StartMfaEnrollmentResponse() / StartMfaEnrollmentResponse.new instead')
  static StartMfaEnrollmentResponse create() => StartMfaEnrollmentResponse._();
  static $pb.GeneratedMessage $_createMessage() =>
      StartMfaEnrollmentResponse._();
  @$core.override
  StartMfaEnrollmentResponse createEmptyInstance() =>
      StartMfaEnrollmentResponse._();
  @$core.pragma('dart2js:noInline')
  static StartMfaEnrollmentResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StartMfaEnrollmentResponse>(
          StartMfaEnrollmentResponse.$_createMessage);
  static StartMfaEnrollmentResponse? _defaultInstance;

  @$pb.TagNumber(1)
  StartMfaEnrollmentResponse_EnrollmentResponse whichEnrollmentResponse() =>
      _StartMfaEnrollmentResponse_EnrollmentResponseByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  void clearEnrollmentResponse() => $_clearField($_whichOneof(0));

  /// Verification info to authorize sending an SMS for phone verification.
  @$pb.TagNumber(1)
  $0.StartMfaPhoneResponseInfo get phoneSessionInfo => $_getN(0);
  @$pb.TagNumber(1)
  set phoneSessionInfo($0.StartMfaPhoneResponseInfo value) =>
      $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasPhoneSessionInfo() => $_has(0);
  @$pb.TagNumber(1)
  void clearPhoneSessionInfo() => $_clearField(1);
  @$pb.TagNumber(1)
  $0.StartMfaPhoneResponseInfo ensurePhoneSessionInfo() => $_ensure(0);
}

/// Withdraws MFA.
class WithdrawMfaRequest extends $pb.GeneratedMessage {
  factory WithdrawMfaRequest({
    $core.String? idToken,
    $core.String? mfaEnrollmentId,
    $core.String? tenantId,
  }) {
    final result = WithdrawMfaRequest._();
    if (idToken != null) result.idToken = idToken;
    if (mfaEnrollmentId != null) result.mfaEnrollmentId = mfaEnrollmentId;
    if (tenantId != null) result.tenantId = tenantId;
    return result;
  }

  WithdrawMfaRequest._();

  factory WithdrawMfaRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WithdrawMfaRequest()..mergeFromBuffer(data, registry);
  factory WithdrawMfaRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WithdrawMfaRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WithdrawMfaRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'google.cloud.identitytoolkit.v2'),
      createEmptyInstance: WithdrawMfaRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'idToken')
    ..aOS(2, _omitFieldNames ? '' : 'mfaEnrollmentId')
    ..aOS(3, _omitFieldNames ? '' : 'tenantId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WithdrawMfaRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WithdrawMfaRequest copyWith(void Function(WithdrawMfaRequest) updates) =>
      super.copyWith((message) => updates(message as WithdrawMfaRequest))
          as WithdrawMfaRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use WithdrawMfaRequest() / WithdrawMfaRequest.new instead')
  static WithdrawMfaRequest create() => WithdrawMfaRequest._();
  static $pb.GeneratedMessage $_createMessage() => WithdrawMfaRequest._();
  @$core.override
  WithdrawMfaRequest createEmptyInstance() => WithdrawMfaRequest._();
  @$core.pragma('dart2js:noInline')
  static WithdrawMfaRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<WithdrawMfaRequest>(
          WithdrawMfaRequest.$_createMessage);
  static WithdrawMfaRequest? _defaultInstance;

  /// Required. User's ID token.
  @$pb.TagNumber(1)
  $core.String get idToken => $_getSZ(0);
  @$pb.TagNumber(1)
  set idToken($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIdToken() => $_has(0);
  @$pb.TagNumber(1)
  void clearIdToken() => $_clearField(1);

  /// Required. MFA enrollment id from a current MFA enrollment.
  @$pb.TagNumber(2)
  $core.String get mfaEnrollmentId => $_getSZ(1);
  @$pb.TagNumber(2)
  set mfaEnrollmentId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMfaEnrollmentId() => $_has(1);
  @$pb.TagNumber(2)
  void clearMfaEnrollmentId() => $_clearField(2);

  /// The ID of the Identity Platform tenant that the user unenrolling MFA
  /// belongs to. If not set, the user belongs to the default Identity Platform
  /// project.
  @$pb.TagNumber(3)
  $core.String get tenantId => $_getSZ(2);
  @$pb.TagNumber(3)
  set tenantId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTenantId() => $_has(2);
  @$pb.TagNumber(3)
  void clearTenantId() => $_clearField(3);
}

/// Withdraws MultiFactorAuth response.
class WithdrawMfaResponse extends $pb.GeneratedMessage {
  factory WithdrawMfaResponse({
    $core.String? idToken,
    $core.String? refreshToken,
  }) {
    final result = WithdrawMfaResponse._();
    if (idToken != null) result.idToken = idToken;
    if (refreshToken != null) result.refreshToken = refreshToken;
    return result;
  }

  WithdrawMfaResponse._();

  factory WithdrawMfaResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WithdrawMfaResponse()..mergeFromBuffer(data, registry);
  factory WithdrawMfaResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WithdrawMfaResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WithdrawMfaResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'google.cloud.identitytoolkit.v2'),
      createEmptyInstance: WithdrawMfaResponse.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'idToken')
    ..aOS(2, _omitFieldNames ? '' : 'refreshToken')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WithdrawMfaResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WithdrawMfaResponse copyWith(void Function(WithdrawMfaResponse) updates) =>
      super.copyWith((message) => updates(message as WithdrawMfaResponse))
          as WithdrawMfaResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use WithdrawMfaResponse() / WithdrawMfaResponse.new instead')
  static WithdrawMfaResponse create() => WithdrawMfaResponse._();
  static $pb.GeneratedMessage $_createMessage() => WithdrawMfaResponse._();
  @$core.override
  WithdrawMfaResponse createEmptyInstance() => WithdrawMfaResponse._();
  @$core.pragma('dart2js:noInline')
  static WithdrawMfaResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<WithdrawMfaResponse>(
          WithdrawMfaResponse.$_createMessage);
  static WithdrawMfaResponse? _defaultInstance;

  /// ID token updated to reflect removal of the second factor.
  @$pb.TagNumber(1)
  $core.String get idToken => $_getSZ(0);
  @$pb.TagNumber(1)
  set idToken($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIdToken() => $_has(0);
  @$pb.TagNumber(1)
  void clearIdToken() => $_clearField(1);

  /// Refresh token updated to reflect removal of the second factor.
  @$pb.TagNumber(2)
  $core.String get refreshToken => $_getSZ(1);
  @$pb.TagNumber(2)
  set refreshToken($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRefreshToken() => $_has(1);
  @$pb.TagNumber(2)
  void clearRefreshToken() => $_clearField(2);
}

/// Account management for Identity Toolkit
class AccountManagementServiceApi {
  final $pb.RpcClient _client;

  AccountManagementServiceApi(this._client);

  /// Finishes enrolling a second factor for the user.
  $async.Future<FinalizeMfaEnrollmentResponse> finalizeMfaEnrollment(
          $pb.ClientContext? ctx, FinalizeMfaEnrollmentRequest request) =>
      _client.invoke<FinalizeMfaEnrollmentResponse>(
          ctx,
          'AccountManagementService',
          'FinalizeMfaEnrollment',
          request,
          FinalizeMfaEnrollmentResponse());

  /// Step one of the MFA enrollment process. In SMS case, this sends an
  /// SMS verification code to the user.
  $async.Future<StartMfaEnrollmentResponse> startMfaEnrollment(
          $pb.ClientContext? ctx, StartMfaEnrollmentRequest request) =>
      _client.invoke<StartMfaEnrollmentResponse>(
          ctx,
          'AccountManagementService',
          'StartMfaEnrollment',
          request,
          StartMfaEnrollmentResponse());

  /// Revokes one second factor from the enrolled second factors for an account.
  $async.Future<WithdrawMfaResponse> withdrawMfa(
          $pb.ClientContext? ctx, WithdrawMfaRequest request) =>
      _client.invoke<WithdrawMfaResponse>(ctx, 'AccountManagementService',
          'WithdrawMfa', request, WithdrawMfaResponse());
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
