// This is a generated file - do not edit.
//
// Generated from google/cloud/identitytoolkit/v2/mfa_info.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart'
    as $0;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// The information required to auto-retrieve an SMS.
class AutoRetrievalInfo extends $pb.GeneratedMessage {
  factory AutoRetrievalInfo({
    $core.String? appSignatureHash,
  }) {
    final result = AutoRetrievalInfo._();
    if (appSignatureHash != null) result.appSignatureHash = appSignatureHash;
    return result;
  }

  AutoRetrievalInfo._();

  factory AutoRetrievalInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AutoRetrievalInfo()..mergeFromBuffer(data, registry);
  factory AutoRetrievalInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AutoRetrievalInfo()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AutoRetrievalInfo',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'google.cloud.identitytoolkit.v2'),
      createEmptyInstance: AutoRetrievalInfo.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'appSignatureHash')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AutoRetrievalInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AutoRetrievalInfo copyWith(void Function(AutoRetrievalInfo) updates) =>
      super.copyWith((message) => updates(message as AutoRetrievalInfo))
          as AutoRetrievalInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use AutoRetrievalInfo() / AutoRetrievalInfo.new instead')
  static AutoRetrievalInfo create() => AutoRetrievalInfo._();
  static $pb.GeneratedMessage $_createMessage() => AutoRetrievalInfo._();
  @$core.override
  AutoRetrievalInfo createEmptyInstance() => AutoRetrievalInfo._();
  @$core.pragma('dart2js:noInline')
  static AutoRetrievalInfo getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AutoRetrievalInfo>(
          AutoRetrievalInfo.$_createMessage);
  static AutoRetrievalInfo? _defaultInstance;

  /// The Android app's signature hash for Google Play Service's
  /// SMS Retriever API.
  @$pb.TagNumber(1)
  $core.String get appSignatureHash => $_getSZ(0);
  @$pb.TagNumber(1)
  set appSignatureHash($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAppSignatureHash() => $_has(0);
  @$pb.TagNumber(1)
  void clearAppSignatureHash() => $_clearField(1);
}

/// App Verification info for a StartMfa request.
class StartMfaPhoneRequestInfo extends $pb.GeneratedMessage {
  factory StartMfaPhoneRequestInfo({
    $core.String? phoneNumber,
    $core.String? iosReceipt,
    $core.String? iosSecret,
    $core.String? recaptchaToken,
    AutoRetrievalInfo? autoRetrievalInfo,
    $core.String? safetyNetToken,
  }) {
    final result = StartMfaPhoneRequestInfo._();
    if (phoneNumber != null) result.phoneNumber = phoneNumber;
    if (iosReceipt != null) result.iosReceipt = iosReceipt;
    if (iosSecret != null) result.iosSecret = iosSecret;
    if (recaptchaToken != null) result.recaptchaToken = recaptchaToken;
    if (autoRetrievalInfo != null) result.autoRetrievalInfo = autoRetrievalInfo;
    if (safetyNetToken != null) result.safetyNetToken = safetyNetToken;
    return result;
  }

  StartMfaPhoneRequestInfo._();

  factory StartMfaPhoneRequestInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartMfaPhoneRequestInfo()..mergeFromBuffer(data, registry);
  factory StartMfaPhoneRequestInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartMfaPhoneRequestInfo()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StartMfaPhoneRequestInfo',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'google.cloud.identitytoolkit.v2'),
      createEmptyInstance: StartMfaPhoneRequestInfo.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'phoneNumber')
    ..aOS(2, _omitFieldNames ? '' : 'iosReceipt')
    ..aOS(3, _omitFieldNames ? '' : 'iosSecret')
    ..aOS(4, _omitFieldNames ? '' : 'recaptchaToken')
    ..aOM<AutoRetrievalInfo>(5, _omitFieldNames ? '' : 'autoRetrievalInfo',
        subBuilder: AutoRetrievalInfo.$_createMessage)
    ..aOS(6, _omitFieldNames ? '' : 'safetyNetToken')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartMfaPhoneRequestInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartMfaPhoneRequestInfo copyWith(
          void Function(StartMfaPhoneRequestInfo) updates) =>
      super.copyWith((message) => updates(message as StartMfaPhoneRequestInfo))
          as StartMfaPhoneRequestInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use StartMfaPhoneRequestInfo() / StartMfaPhoneRequestInfo.new instead')
  static StartMfaPhoneRequestInfo create() => StartMfaPhoneRequestInfo._();
  static $pb.GeneratedMessage $_createMessage() => StartMfaPhoneRequestInfo._();
  @$core.override
  StartMfaPhoneRequestInfo createEmptyInstance() =>
      StartMfaPhoneRequestInfo._();
  @$core.pragma('dart2js:noInline')
  static StartMfaPhoneRequestInfo getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StartMfaPhoneRequestInfo>(
          StartMfaPhoneRequestInfo.$_createMessage);
  static StartMfaPhoneRequestInfo? _defaultInstance;

  /// Required for enrollment. Phone number to be enrolled as MFA.
  @$pb.TagNumber(1)
  $core.String get phoneNumber => $_getSZ(0);
  @$pb.TagNumber(1)
  set phoneNumber($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPhoneNumber() => $_has(0);
  @$pb.TagNumber(1)
  void clearPhoneNumber() => $_clearField(1);

  /// iOS only. Receipt of successful app token validation with APNS.
  @$pb.TagNumber(2)
  $core.String get iosReceipt => $_getSZ(1);
  @$pb.TagNumber(2)
  set iosReceipt($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasIosReceipt() => $_has(1);
  @$pb.TagNumber(2)
  void clearIosReceipt() => $_clearField(2);

  /// iOS only. Secret delivered to iOS app via APNS.
  @$pb.TagNumber(3)
  $core.String get iosSecret => $_getSZ(2);
  @$pb.TagNumber(3)
  set iosSecret($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasIosSecret() => $_has(2);
  @$pb.TagNumber(3)
  void clearIosSecret() => $_clearField(3);

  /// Web only. Recaptcha solution.
  @$pb.TagNumber(4)
  $core.String get recaptchaToken => $_getSZ(3);
  @$pb.TagNumber(4)
  set recaptchaToken($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRecaptchaToken() => $_has(3);
  @$pb.TagNumber(4)
  void clearRecaptchaToken() => $_clearField(4);

  /// Android only. Used by Google Play Services to identify the app for
  /// auto-retrieval.
  @$pb.TagNumber(5)
  AutoRetrievalInfo get autoRetrievalInfo => $_getN(4);
  @$pb.TagNumber(5)
  set autoRetrievalInfo(AutoRetrievalInfo value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasAutoRetrievalInfo() => $_has(4);
  @$pb.TagNumber(5)
  void clearAutoRetrievalInfo() => $_clearField(5);
  @$pb.TagNumber(5)
  AutoRetrievalInfo ensureAutoRetrievalInfo() => $_ensure(4);

  /// Android only. Used to assert application identity in place of a
  /// recaptcha token. A SafetyNet Token can be generated via the
  /// [SafetyNet Android Attestation
  /// API](https://developer.android.com/training/safetynet/attestation.html),
  /// with the Base64 encoding of the `phone_number` field as the nonce.
  @$pb.TagNumber(6)
  $core.String get safetyNetToken => $_getSZ(5);
  @$pb.TagNumber(6)
  set safetyNetToken($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasSafetyNetToken() => $_has(5);
  @$pb.TagNumber(6)
  void clearSafetyNetToken() => $_clearField(6);
}

/// Phone Verification info for a StartMfa response.
class StartMfaPhoneResponseInfo extends $pb.GeneratedMessage {
  factory StartMfaPhoneResponseInfo({
    $core.String? sessionInfo,
  }) {
    final result = StartMfaPhoneResponseInfo._();
    if (sessionInfo != null) result.sessionInfo = sessionInfo;
    return result;
  }

  StartMfaPhoneResponseInfo._();

  factory StartMfaPhoneResponseInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartMfaPhoneResponseInfo()..mergeFromBuffer(data, registry);
  factory StartMfaPhoneResponseInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartMfaPhoneResponseInfo()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StartMfaPhoneResponseInfo',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'google.cloud.identitytoolkit.v2'),
      createEmptyInstance: StartMfaPhoneResponseInfo.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'sessionInfo')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartMfaPhoneResponseInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartMfaPhoneResponseInfo copyWith(
          void Function(StartMfaPhoneResponseInfo) updates) =>
      super.copyWith((message) => updates(message as StartMfaPhoneResponseInfo))
          as StartMfaPhoneResponseInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use StartMfaPhoneResponseInfo() / StartMfaPhoneResponseInfo.new instead')
  static StartMfaPhoneResponseInfo create() => StartMfaPhoneResponseInfo._();
  static $pb.GeneratedMessage $_createMessage() =>
      StartMfaPhoneResponseInfo._();
  @$core.override
  StartMfaPhoneResponseInfo createEmptyInstance() =>
      StartMfaPhoneResponseInfo._();
  @$core.pragma('dart2js:noInline')
  static StartMfaPhoneResponseInfo getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StartMfaPhoneResponseInfo>(
          StartMfaPhoneResponseInfo.$_createMessage);
  static StartMfaPhoneResponseInfo? _defaultInstance;

  /// An opaque string that represents the enrollment session.
  @$pb.TagNumber(1)
  $core.String get sessionInfo => $_getSZ(0);
  @$pb.TagNumber(1)
  set sessionInfo($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSessionInfo() => $_has(0);
  @$pb.TagNumber(1)
  void clearSessionInfo() => $_clearField(1);
}

/// Phone Verification info for a FinalizeMfa request.
class FinalizeMfaPhoneRequestInfo extends $pb.GeneratedMessage {
  factory FinalizeMfaPhoneRequestInfo({
    $core.String? sessionInfo,
    $core.String? code,
    $core.String? androidVerificationProof,
    $core.String? phoneNumber,
  }) {
    final result = FinalizeMfaPhoneRequestInfo._();
    if (sessionInfo != null) result.sessionInfo = sessionInfo;
    if (code != null) result.code = code;
    if (androidVerificationProof != null)
      result.androidVerificationProof = androidVerificationProof;
    if (phoneNumber != null) result.phoneNumber = phoneNumber;
    return result;
  }

  FinalizeMfaPhoneRequestInfo._();

  factory FinalizeMfaPhoneRequestInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinalizeMfaPhoneRequestInfo()..mergeFromBuffer(data, registry);
  factory FinalizeMfaPhoneRequestInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinalizeMfaPhoneRequestInfo()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FinalizeMfaPhoneRequestInfo',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'google.cloud.identitytoolkit.v2'),
      createEmptyInstance: FinalizeMfaPhoneRequestInfo.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'sessionInfo')
    ..aOS(2, _omitFieldNames ? '' : 'code')
    ..aOS(3, _omitFieldNames ? '' : 'androidVerificationProof')
    ..aOS(4, _omitFieldNames ? '' : 'phoneNumber')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinalizeMfaPhoneRequestInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinalizeMfaPhoneRequestInfo copyWith(
          void Function(FinalizeMfaPhoneRequestInfo) updates) =>
      super.copyWith(
              (message) => updates(message as FinalizeMfaPhoneRequestInfo))
          as FinalizeMfaPhoneRequestInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use FinalizeMfaPhoneRequestInfo() / FinalizeMfaPhoneRequestInfo.new instead')
  static FinalizeMfaPhoneRequestInfo create() =>
      FinalizeMfaPhoneRequestInfo._();
  static $pb.GeneratedMessage $_createMessage() =>
      FinalizeMfaPhoneRequestInfo._();
  @$core.override
  FinalizeMfaPhoneRequestInfo createEmptyInstance() =>
      FinalizeMfaPhoneRequestInfo._();
  @$core.pragma('dart2js:noInline')
  static FinalizeMfaPhoneRequestInfo getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FinalizeMfaPhoneRequestInfo>(
          FinalizeMfaPhoneRequestInfo.$_createMessage);
  static FinalizeMfaPhoneRequestInfo? _defaultInstance;

  /// An opaque string that represents the enrollment session.
  @$pb.TagNumber(1)
  $core.String get sessionInfo => $_getSZ(0);
  @$pb.TagNumber(1)
  set sessionInfo($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSessionInfo() => $_has(0);
  @$pb.TagNumber(1)
  void clearSessionInfo() => $_clearField(1);

  /// User-entered verification code.
  @$pb.TagNumber(2)
  $core.String get code => $_getSZ(1);
  @$pb.TagNumber(2)
  set code($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCode() => $_has(1);
  @$pb.TagNumber(2)
  void clearCode() => $_clearField(2);

  /// Android only. Uses for "instant" phone number verification though GmsCore.
  @$pb.TagNumber(3)
  $core.String get androidVerificationProof => $_getSZ(2);
  @$pb.TagNumber(3)
  set androidVerificationProof($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAndroidVerificationProof() => $_has(2);
  @$pb.TagNumber(3)
  void clearAndroidVerificationProof() => $_clearField(3);

  /// Required if Android verification proof is presented.
  @$pb.TagNumber(4)
  $core.String get phoneNumber => $_getSZ(3);
  @$pb.TagNumber(4)
  set phoneNumber($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPhoneNumber() => $_has(3);
  @$pb.TagNumber(4)
  void clearPhoneNumber() => $_clearField(4);
}

/// Phone Verification info for a FinalizeMfa response.
class FinalizeMfaPhoneResponseInfo extends $pb.GeneratedMessage {
  factory FinalizeMfaPhoneResponseInfo({
    $core.String? androidVerificationProof,
    $0.Timestamp? androidVerificationProofExpireTime,
    $core.String? phoneNumber,
  }) {
    final result = FinalizeMfaPhoneResponseInfo._();
    if (androidVerificationProof != null)
      result.androidVerificationProof = androidVerificationProof;
    if (androidVerificationProofExpireTime != null)
      result.androidVerificationProofExpireTime =
          androidVerificationProofExpireTime;
    if (phoneNumber != null) result.phoneNumber = phoneNumber;
    return result;
  }

  FinalizeMfaPhoneResponseInfo._();

  factory FinalizeMfaPhoneResponseInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinalizeMfaPhoneResponseInfo()..mergeFromBuffer(data, registry);
  factory FinalizeMfaPhoneResponseInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinalizeMfaPhoneResponseInfo()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FinalizeMfaPhoneResponseInfo',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'google.cloud.identitytoolkit.v2'),
      createEmptyInstance: FinalizeMfaPhoneResponseInfo.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'androidVerificationProof')
    ..aOM<$0.Timestamp>(
        2, _omitFieldNames ? '' : 'androidVerificationProofExpireTime',
        subBuilder: $0.Timestamp.$_createMessage)
    ..aOS(3, _omitFieldNames ? '' : 'phoneNumber')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinalizeMfaPhoneResponseInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinalizeMfaPhoneResponseInfo copyWith(
          void Function(FinalizeMfaPhoneResponseInfo) updates) =>
      super.copyWith(
              (message) => updates(message as FinalizeMfaPhoneResponseInfo))
          as FinalizeMfaPhoneResponseInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use FinalizeMfaPhoneResponseInfo() / FinalizeMfaPhoneResponseInfo.new instead')
  static FinalizeMfaPhoneResponseInfo create() =>
      FinalizeMfaPhoneResponseInfo._();
  static $pb.GeneratedMessage $_createMessage() =>
      FinalizeMfaPhoneResponseInfo._();
  @$core.override
  FinalizeMfaPhoneResponseInfo createEmptyInstance() =>
      FinalizeMfaPhoneResponseInfo._();
  @$core.pragma('dart2js:noInline')
  static FinalizeMfaPhoneResponseInfo getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FinalizeMfaPhoneResponseInfo>(
          FinalizeMfaPhoneResponseInfo.$_createMessage);
  static FinalizeMfaPhoneResponseInfo? _defaultInstance;

  /// Android only. Long-lived replacement for valid code tied to android device.
  @$pb.TagNumber(1)
  $core.String get androidVerificationProof => $_getSZ(0);
  @$pb.TagNumber(1)
  set androidVerificationProof($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAndroidVerificationProof() => $_has(0);
  @$pb.TagNumber(1)
  void clearAndroidVerificationProof() => $_clearField(1);

  /// Android only. Expiration time of verification proof in seconds.
  @$pb.TagNumber(2)
  $0.Timestamp get androidVerificationProofExpireTime => $_getN(1);
  @$pb.TagNumber(2)
  set androidVerificationProofExpireTime($0.Timestamp value) =>
      $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasAndroidVerificationProofExpireTime() => $_has(1);
  @$pb.TagNumber(2)
  void clearAndroidVerificationProofExpireTime() => $_clearField(2);
  @$pb.TagNumber(2)
  $0.Timestamp ensureAndroidVerificationProofExpireTime() => $_ensure(1);

  /// For Android verification proof.
  @$pb.TagNumber(3)
  $core.String get phoneNumber => $_getSZ(2);
  @$pb.TagNumber(3)
  set phoneNumber($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPhoneNumber() => $_has(2);
  @$pb.TagNumber(3)
  void clearPhoneNumber() => $_clearField(3);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
