// File created by
// Lung Razvan <long1eu>
// on 23/11/2019

import 'dart:convert';

import 'package:collection/collection.dart';

import 'util/to_string_helper.dart';

/// A token returned by `InternalTokenProvider.getAccessToken`, with the claims of its payload.
///
/// For a Firebase Auth ID token (a JWT) [claims] holds the payload, unverified. For a token that
/// is not a JWT (an OAuth 2.0 access token, an emulator token) [claims] is empty and the
/// timestamps are the epoch.
///
/// ```dart
/// import 'package:firebase_app_dart/firebase_app_dart.dart';
///
/// void main() {
///   final GetTokenResult result = GetTokenResult('an opaque access token');
///   print(result.claims.isEmpty); // true
///   print(result.signInProvider); // null
/// }
/// ```
class GetTokenResult {
  /// Creates a result for [token], reading the claims from its payload when it is a JWT. Never
  /// throws: a token that cannot be parsed has no claims.
  factory GetTokenResult(String token) {
    final Map<String, dynamic> claims = _parseJwt(token);
    return GetTokenResult._(token, claims);
  }

  const GetTokenResult._(this.token, [this.claims = const <String, dynamic>{}]);

  static const String _expirationTimestamp = 'exp';
  static const String _authTimestamp = 'auth_time';
  static const String _issuedAtTimestamp = 'iat';
  static const String _firebaseKey = 'firebase';
  static const String _signInProvider = 'sign_in_provider';
  static const String _extraClaims = 'extra_claims';

  /// Firebase Auth ID Token. Useful for authenticating calls against your own backend. Verify the integrity and
  /// validity of the token in your server either by using our server SDKs or following the documentation.
  final String token;

  /// Returns the entire payload claims of the ID token including the standard reserved claims as well as the custom
  /// claims (set by developer via Admin SDK). Developers should verify the ID token and parse claims from its payload
  /// on the backend and never trust this value on the client. Returns an empty map if no claims are present.
  final Map<String, dynamic> claims;

  /// The time at which this ID token expires (the `exp` claim), or the epoch when there is none.
  DateTime get expirationTimestamp =>
      _getTimeFromClaimsSafely(_expirationTimestamp);

  /// The time the user signed in (the `auth_time` claim), not the time the token was refreshed;
  /// the epoch when there is none.
  DateTime get authTimestamp => _getTimeFromClaimsSafely(_authTimestamp);

  /// The time the token was issued (the `iat` claim), that is the time it was last refreshed; the
  /// epoch when there is none.
  DateTime get issuedAtTimestamp =>
      _getTimeFromClaimsSafely(_issuedAtTimestamp);

  /// Returns the sign-in provider through which the ID token was obtained (anonymous, custom, phone, password, etc).
  /// Note, this does not map to provider IDs. For example, anonymous and custom authentications are not considered
  /// providers. We chose the name here to map the name used in the ID token.
  String? get signInProvider {
    // Sign in provider might live inside the 'firebase' element of the JSON
    final Object? firebaseElem = claims[_firebaseKey];
    if (firebaseElem is Map) {
      final Object? provider = firebaseElem[_signInProvider];
      return provider is String ? provider : null;
    } else {
      final Object? provider = claims[_signInProvider];
      return provider is String ? provider : null;
    }
  }

  /// The `extra_claims` claim of the token, or an empty map when there is none. Custom claims set
  /// with the Admin SDK are top-level entries of [claims].
  Map<String, dynamic> get extraClaims {
    final Object? extra = claims[_extraClaims];
    return extra is Map
        ? Map<String, dynamic>.from(extra)
        : const <String, dynamic>{};
  }

  DateTime _getTimeFromClaimsSafely(String key) {
    final Object? seconds = claims[key];
    final int milliseconds = seconds is num ? seconds.toInt() : 0;
    return DateTime.fromMillisecondsSinceEpoch(milliseconds * 1000);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GetTokenResult &&
          runtimeType == other.runtimeType &&
          token == other.token &&
          const MapEquality<String, dynamic>().equals(claims, other.claims);

  @override
  int get hashCode =>
      token.hashCode * 31 ^ const MapEquality<String, dynamic>().hash(claims);

  @override
  String toString() {
    // The token is a credential and the claims are personal data (uid,
    // email): neither is part of the string form, which ends up in logs and
    // error messages.
    return (ToStringHelper(GetTokenResult) //
          ..add('token', token.isEmpty ? '<empty>' : '<redacted>')
          ..add('claims', '<${claims.length} claims>')
          ..add('expirationTimestamp', expirationTimestamp))
        .toString();
  }
}

/// Parses the claims of a JWT. Tokens that are not a JWT (opaque or emulator
/// tokens) have no claims.
Map<String, dynamic> _parseJwt(String token) {
  final List<String> parts = token.split('.');
  if (parts.length != 3) {
    return const <String, dynamic>{};
  }

  try {
    final Object? claims = jsonDecode(_decodeBase64(parts[1]));
    return claims is Map
        ? Map<String, dynamic>.from(claims)
        : const <String, dynamic>{};
  } on Object {
    return const <String, dynamic>{};
  }
}

String _decodeBase64(String str) {
  String output = str.replaceAll('-', '+').replaceAll('_', '/');

  switch (output.length % 4) {
    case 0:
      break;
    case 2:
      output += '==';
      break;
    case 3:
      output += '=';
      break;
    default:
      throw Exception('Illegal base64url string!"');
  }

  return utf8.decode(base64Url.decode(output));
}
