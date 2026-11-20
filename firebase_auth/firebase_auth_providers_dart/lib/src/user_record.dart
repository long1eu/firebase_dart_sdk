// The user record of FirebaseUserAuth: reading it from the answers of the Identity Toolkit API, and the format it is
// stored in. Not exported.

import 'dart:convert';

import 'package:firebase_app_dart/firebase_app_dart.dart';

import 'auth_credential.dart';
import 'auth_user.dart';
import 'multi_factor.dart';

String? _text(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

/// A time in milliseconds since the epoch, as a number or a string (the REST API sends strings), in UTC.
DateTime? _millis(Object? value) {
  final int? millis = switch (value) {
    final num n => n.toInt(),
    final String s => int.tryParse(s),
    _ => null,
  };
  return millis == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
}

/// [user] with the given fields replaced (null keeps a value).
AuthUser copyUser(
  AuthUser user, {
  String? email,
  bool? isAnonymous,
  bool? emailVerified,
  String? displayName,
  String? photoUrl,
  String? phoneNumber,
  String? tenantId,
  UserMetadata? metadata,
  List<UserInfo>? providerData,
  List<MultiFactorInfo>? enrolledFactors,
  bool clearDisplayName = false,
  bool clearPhotoUrl = false,
  bool clearPhoneNumber = false,
}) => AuthUser(
  uid: user.uid,
  email: email ?? user.email,
  isAnonymous: isAnonymous ?? user.isAnonymous,
  emailVerified: emailVerified ?? user.emailVerified,
  displayName: clearDisplayName ? null : displayName ?? user.displayName,
  photoUrl: clearPhotoUrl ? null : photoUrl ?? user.photoUrl,
  phoneNumber: clearPhoneNumber ? null : phoneNumber ?? user.phoneNumber,
  tenantId: tenantId ?? user.tenantId,
  metadata: metadata ?? user.metadata,
  providerData: providerData ?? user.providerData,
  enrolledFactors: enrolledFactors ?? user.enrolledFactors,
);

/// The entries of `providerUserInfo` (`extractProviderData` of the JS SDK).
List<UserInfo> providerDataOf(Object? providers) =>
    List<UserInfo>.unmodifiable(<UserInfo>[
      if (providers is List)
        for (final Object? provider in providers)
          if (provider is Map<String, Object?> &&
              _text(provider['providerId']) != null)
            UserInfo(
              providerId: provider['providerId']! as String,
              uid: _text(provider['rawId']) ?? '',
              email: _text(provider['email']),
              displayName: _text(provider['displayName']),
              photoUrl: _text(provider['photoUrl']),
              phoneNumber: _text(provider['phoneNumber']),
            ),
    ]);

/// The entries of `mfaInfo` (`MultiFactorUserImpl` of the JS SDK reads them on every reload).
List<MultiFactorInfo> enrolledFactorsOf(Object? mfaInfo) =>
    List<MultiFactorInfo>.unmodifiable(<MultiFactorInfo>[
      if (mfaInfo is List)
        for (final Object? enrollment in mfaInfo)
          ?MultiFactorInfo.fromResponse(enrollment),
    ]);

/// The user of an account of `accounts:lookup`, like `_reloadWithoutSaving` of the JS SDK: [previous] is the user
/// before (its provider data is merged with the new one, and a user that was not anonymous never becomes
/// anonymous).
AuthUser userFromAccount(Map<String, Object?> account, AuthUser previous) {
  final List<UserInfo> fresh = providerDataOf(account['providerUserInfo']);
  // mergeProviderData: the old entries of providers that the answer does not list stay.
  final List<UserInfo> providerData = List<UserInfo>.unmodifiable(<UserInfo>[
    for (final UserInfo old in previous.providerData)
      if (!fresh.any((UserInfo n) => n.providerId == old.providerId)) old,
    ...fresh,
  ]);
  final String? email = _text(account['email']);
  // A user stays anonymous until the account has an email address and a password, or a provider.
  final bool newIsAnonymous =
      !(email != null && account['passwordHash'] != null) &&
      providerData.isEmpty;
  return AuthUser(
    uid: previous.uid,
    email: email,
    isAnonymous: previous.isAnonymous && newIsAnonymous,
    emailVerified: account['emailVerified'] == true,
    displayName: _text(account['displayName']),
    photoUrl: _text(account['photoUrl']),
    phoneNumber: _text(account['phoneNumber']),
    tenantId: _text(account['tenantId']),
    metadata: UserMetadata(
      creationTime: _millis(account['createdAt']),
      lastSignInTime: _millis(account['lastLoginAt']),
    ),
    providerData: providerData,
    // The answer is the account as it is: without `mfaInfo` it has no second factor (left).
    enrolledFactors: enrolledFactorsOf(account['mfaInfo']),
  );
}

/// The additional information of a sign-in answer (`_fromIdTokenResponse` of the JS SDK's
/// `additional_user_info.ts`).
AdditionalUserInfo? additionalUserInfoOf(Map<String, Object?> response) {
  final String? providerId = _text(response['providerId']);
  Map<String, Object?>? profile;
  final String? raw = _text(response['rawUserInfo']);
  if (raw != null) {
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) {
        profile = decoded;
      }
    } on FormatException {
      // A profile that is not JSON is left out.
    }
  }
  final bool isNewUser =
      response['isNewUser'] == true ||
      response['kind'] == 'identitytoolkit#SignupNewUserResponse';
  if (providerId == null) {
    final String? idToken = _text(response['idToken']);
    final String? signInProvider = idToken == null
        ? null
        : GetTokenResult(idToken).signInProvider;
    if (signInProvider == null) {
      return null;
    }
    return AdditionalUserInfo(
      isNewUser: isNewUser,
      providerId: signInProvider == 'anonymous' || signInProvider == 'custom'
          ? null
          : signInProvider,
    );
  }
  switch (providerId) {
    case 'custom' || 'anonymous':
      return AdditionalUserInfo(isNewUser: isNewUser);
    case 'github.com':
      final Object? login = profile?['login'];
      return AdditionalUserInfo(
        isNewUser: isNewUser,
        providerId: providerId,
        profile: profile ?? const <String, Object?>{},
        username: login is String ? login : null,
      );
    case 'twitter.com':
      return AdditionalUserInfo(
        isNewUser: isNewUser,
        providerId: providerId,
        profile: profile ?? const <String, Object?>{},
        username: _text(response['screenName']),
      );
    default:
      return AdditionalUserInfo(
        isNewUser: isNewUser,
        providerId: providerId,
        profile: profile ?? const <String, Object?>{},
      );
  }
}

/// The version of the stored session that this package writes. Version 1 (0.1 and 0.2) had no `version` field and
/// only the user's uid, email, isAnonymous, emailVerified, displayName and photoUrl.
const int storageVersion = 2;

/// The stored form of a session: the user and the refresh token.
String encodeSession(
  AuthUser user,
  String refreshToken,
) => jsonEncode(<String, Object?>{
  'version': storageVersion,
  'uid': user.uid,
  'email': user.email,
  'isAnonymous': user.isAnonymous,
  'emailVerified': user.emailVerified,
  'displayName': user.displayName,
  'photoUrl': user.photoUrl,
  'phoneNumber': user.phoneNumber,
  'tenantId': user.tenantId,
  'createdAt': user.metadata.creationTime?.millisecondsSinceEpoch,
  'lastLoginAt': user.metadata.lastSignInTime?.millisecondsSinceEpoch,
  'providerData': <Object?>[
    for (final UserInfo info in user.providerData)
      <String, Object?>{
        'providerId': info.providerId,
        'rawId': info.uid,
        'email': info.email,
        'displayName': info.displayName,
        'photoUrl': info.photoUrl,
        'phoneNumber': info.phoneNumber,
      },
  ],
  // In the shape of `mfaInfo`, so that it is read back like an answer of the backend.
  'mfaInfo': <Object?>[
    for (final MultiFactorInfo factor in user.enrolledFactors)
      <String, Object?>{
        'mfaEnrollmentId': factor.uid,
        'displayName': factor.displayName,
        if (factor.factorId == MultiFactorInfo.phoneFactorId)
          'phoneInfo': factor.phoneNumber ?? '',
        if (factor.factorId == MultiFactorInfo.totpFactorId)
          'totpInfo': const <String, Object?>{},
        'enrolledAt': factor.enrollmentTime?.toIso8601String(),
      },
  ],
  'refreshToken': refreshToken,
});

/// Reads a stored session of any version: the fields a version does not have are left empty. Returns null for a
/// value this package did not write (not JSON, no uid or refresh token).
({AuthUser user, String refreshToken})? decodeSession(String stored) {
  final Object? json;
  try {
    json = jsonDecode(stored);
  } on FormatException {
    return null;
  }
  if (json is! Map<String, Object?> ||
      json['refreshToken'] is! String ||
      json['uid'] is! String) {
    return null;
  }
  return (
    user: AuthUser(
      uid: json['uid']! as String,
      email: _text(json['email']),
      isAnonymous: json['isAnonymous'] == true,
      emailVerified: json['emailVerified'] == true,
      displayName: _text(json['displayName']),
      photoUrl: _text(json['photoUrl']),
      phoneNumber: _text(json['phoneNumber']),
      tenantId: _text(json['tenantId']),
      metadata: UserMetadata(
        creationTime: _millis(json['createdAt']),
        lastSignInTime: _millis(json['lastLoginAt']),
      ),
      providerData: providerDataOf(json['providerData']),
      enrolledFactors: enrolledFactorsOf(json['mfaInfo']),
    ),
    refreshToken: json['refreshToken']! as String,
  );
}

/// The credential the backend returned in a sign-in answer or a tagged error (`credentialFromResult` and
/// `credentialFromError` of the JS SDK's providers), or null when it returned none.
OAuthCredential? credentialFromResponse(Map<String, Object?>? response) {
  if (response == null) {
    return null;
  }
  final String? providerId = _text(response['providerId']);
  final String? idToken = _text(response['oauthIdToken']);
  final String? accessToken = _text(response['oauthAccessToken']);
  final String? secret = _text(response['oauthTokenSecret']);
  final String? pendingToken = _text(response['pendingToken']);
  if (providerId == null) {
    return null;
  }
  switch (providerId) {
    case TwitterAuthProvider.PROVIDER_ID:
      return accessToken == null || secret == null
          ? null
          : TwitterAuthProvider.credential(
              accessToken: accessToken,
              secret: secret,
            );
    case FacebookAuthProvider.PROVIDER_ID || GithubAuthProvider.PROVIDER_ID:
      return accessToken == null
          ? null
          : OAuthCredential(
              providerId: providerId,
              signInMethod: providerId,
              accessToken: accessToken,
            );
    case GoogleAuthProvider.PROVIDER_ID:
      return idToken == null && accessToken == null
          ? null
          : GoogleAuthProvider.credential(
              idToken: idToken,
              accessToken: accessToken,
            );
    case 'password' || 'phone' || 'anonymous' || 'custom':
      return null;
    default:
      if (idToken == null &&
          accessToken == null &&
          secret == null &&
          pendingToken == null) {
        return null;
      }
      return OAuthCredential(
        providerId: providerId,
        signInMethod: providerId,
        idToken: idToken,
        accessToken: accessToken,
        secret: secret,
        rawNonce: pendingToken == null ? _text(response['nonce']) : null,
        pendingToken: pendingToken,
      );
  }
}
