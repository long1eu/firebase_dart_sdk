import 'dart:convert';

import 'package:meta/meta.dart';

/// A user account as an administrator sees it: what `FirebaseAuthAdmin.getUser` returns.
///
/// It holds no password hash and no token. [toString] shows the uid only.
@immutable
final class AdminUser {
  /// Creates a record. The package creates them; you need this only for tests.
  const AdminUser({
    required this.uid,
    this.email,
    this.emailVerified = false,
    this.displayName,
    this.photoUrl,
    this.phoneNumber,
    this.disabled = false,
    this.customClaims = const <String, Object?>{},
    this.tokensValidAfter,
    this.createdAt,
    this.lastSignInAt,
    this.providerIds = const <String>[],
    this.tenantId,
  });

  /// Reads a user of an `accounts:lookup` answer of the Identity Toolkit API.
  factory AdminUser.fromJson(Map<String, Object?> json) {
    String? string(String key) {
      final Object? value = json[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    DateTime? time(String key, {required bool seconds}) {
      final Object? value = json[key];
      final int? number = value is num ? value.toInt() : int.tryParse('$value');
      if (value == null || number == null) {
        return null;
      }
      return DateTime.fromMillisecondsSinceEpoch(
        seconds ? number * 1000 : number,
        isUtc: true,
      );
    }

    Map<String, Object?> claims = const <String, Object?>{};
    final String? attributes = string('customAttributes');
    if (attributes != null) {
      try {
        final Object? decoded = jsonDecode(attributes);
        if (decoded is Map<String, Object?>) {
          claims = Map<String, Object?>.unmodifiable(decoded);
        }
      } on FormatException {
        // Left empty: the backend only stores JSON objects.
      }
    }
    final Object? providers = json['providerUserInfo'];
    return AdminUser(
      uid: string('localId') ?? '',
      email: string('email'),
      emailVerified: json['emailVerified'] == true,
      displayName: string('displayName'),
      photoUrl: string('photoUrl'),
      phoneNumber: string('phoneNumber'),
      disabled: json['disabled'] == true,
      customClaims: claims,
      tokensValidAfter: time('validSince', seconds: true),
      createdAt: time('createdAt', seconds: false),
      lastSignInAt: time('lastLoginAt', seconds: false),
      providerIds: List<String>.unmodifiable(<String>[
        if (providers is List)
          for (final Object? provider in providers)
            if (provider is Map && provider['providerId'] is String)
              provider['providerId'] as String,
      ]),
      tenantId: string('tenantId'),
    );
  }

  /// The user's id.
  final String uid;

  /// The email address, or null.
  final String? email;

  /// Whether the email address is verified.
  final bool emailVerified;

  /// The display name, or null.
  final String? displayName;

  /// The photo URL, or null.
  final String? photoUrl;

  /// The phone number in E.164 format, or null.
  final String? phoneNumber;

  /// Whether the account is disabled.
  final bool disabled;

  /// The custom claims set with `setCustomUserClaims`; empty when there are none.
  final Map<String, Object?> customClaims;

  /// ID tokens issued (signed in) before this time are revoked: set by `revokeRefreshTokens`. Second precision.
  final DateTime? tokensValidAfter;

  /// When the account was created.
  final DateTime? createdAt;

  /// When the user last signed in.
  final DateTime? lastSignInAt;

  /// The sign-in providers linked to the account (`password`, `phone`, `google.com`, ...). A user created with a
  /// custom token only has none.
  final List<String> providerIds;

  /// The tenant of the user, or null.
  final String? tenantId;

  @override
  String toString() => 'AdminUser($uid)';
}

/// One uid that `FirebaseAuthAdmin.deleteUsers` could not delete.
@immutable
final class DeleteUserError {
  /// Creates an error. The package creates them; you need this only for tests.
  const DeleteUserError({
    required this.index,
    required this.uid,
    required this.message,
  });

  /// The position of [uid] in the list that was passed to `deleteUsers`.
  final int index;

  /// The uid that was not deleted.
  final String uid;

  /// Why, as the backend said it.
  final String message;

  @override
  String toString() => 'DeleteUserError($index, $uid: $message)';
}

/// What `FirebaseAuthAdmin.deleteUsers` did.
@immutable
final class DeleteUsersResult {
  /// Creates a result. The package creates them; you need this only for tests.
  const DeleteUsersResult({required this.successCount, required this.errors});

  /// How many uids were deleted. A uid that has no user counts as deleted, as in the Admin SDKs.
  final int successCount;

  /// The uids that were not deleted, in the order they were passed.
  final List<DeleteUserError> errors;

  /// How many uids were not deleted.
  int get failureCount => errors.length;

  @override
  String toString() =>
      'DeleteUsersResult(successCount: $successCount, failureCount: $failureCount)';
}

/// An ID token that `FirebaseAuthAdmin.verifyIdToken` checked: signed by Google (or by the emulator in emulator
/// mode), for this project, not expired.
@immutable
final class VerifiedIdToken {
  /// Creates a token from its decoded [claims]. The package creates them; you need this only for tests.
  VerifiedIdToken(Map<String, Object?> claims)
    : claims = Map<String, Object?>.unmodifiable(claims);

  /// Every claim of the token: the standard ones (`sub`, `aud`, `iat`, ...), `firebase`, and the custom claims
  /// of the user and of the custom token it signed in with.
  final Map<String, Object?> claims;

  /// The uid of the user (`sub`).
  String get uid => claims['sub']! as String;

  /// When the user signed in (`auth_time`).
  DateTime get authTime => _time('auth_time');

  /// When the token was issued (`iat`).
  DateTime get issuedAt => _time('iat');

  /// When the token expires (`exp`).
  DateTime get expiresAt => _time('exp');

  /// The email address of the user, or null.
  String? get email =>
      claims['email'] is String ? claims['email']! as String : null;

  /// How the user signed in (`firebase.sign_in_provider`): `custom`, `password`, `anonymous`, ...
  String? get signInProvider => _firebase['sign_in_provider'] is String
      ? _firebase['sign_in_provider']! as String
      : null;

  /// The tenant of the user (`firebase.tenant`), or null.
  String? get tenantId =>
      _firebase['tenant'] is String ? _firebase['tenant']! as String : null;

  Map<Object?, Object?> get _firebase {
    final Object? firebase = claims['firebase'];
    return firebase is Map ? firebase : const <Object?, Object?>{};
  }

  DateTime _time(String key) => DateTime.fromMillisecondsSinceEpoch(
    (claims[key]! as num).toInt() * 1000,
    isUtc: true,
  );

  @override
  String toString() => 'VerifiedIdToken($uid)';
}
