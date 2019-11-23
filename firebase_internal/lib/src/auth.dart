// File created by
// Lung Razvan <long1eu>
// on 23/11/2019

import 'package:firebase_common/firebase_common.dart';

/// Result object that contains a Firebase Auth ID Token.
class GetTokenResult {
  const GetTokenResult(this.token, [this.claims = const <String, dynamic>{}]);

  factory GetTokenResult.fromJson(Map<String, dynamic> json) {
    final String token = json['token'];
    final Map<String, dynamic> claims = json['claims'] ?? <String, dynamic>{};
    return GetTokenResult(token, claims);
  }

  static const String _expirationTimestamp = 'exp';
  static const String _authTimestamp = 'auth_time';
  static const String _issuedAtTimestamp = 'iat';
  static const String _firebaseKey = 'firebase';
  static const String _signInProvider = 'sign_in_provider';

  /// Firebase Auth ID Token. Useful for authenticating calls against your own
  /// backend. Verify the integrity and validity of the token in your server
  /// either by using our server SDKs or following the documentation.
  final String token;

  /// Returns the entire payload claims of the ID token including the standard
  /// reserved claims as well as the custom claims (set by developer via
  /// Admin SDK). Developers should verify the ID token and parse claims from
  /// its payload on the backend and never trust this value on the client.
  /// Returns an empty map if no claims are present.
  final Map<String, dynamic> claims;

  /// Returns the time at which this ID token will expire
  DateTime get expirationTimestamp =>
      _getTimeFromClaimsSafely(_expirationTimestamp);

  /// Returns the authentication timestamp. This is the time the user
  /// authenticated (signed in) and not the time the token was refreshed.
  DateTime get authTimestamp => _getTimeFromClaimsSafely(_authTimestamp);

  /// Returns the issued at timestamp. This is the time the ID token was last
  /// refreshed and not the authentication timestamp.
  DateTime get issuedAtTimestamp =>
      _getTimeFromClaimsSafely(_issuedAtTimestamp);

  /// Returns the sign-in provider through which the ID token was obtained
  /// (anonymous, custom, phone, password, etc). Note, this does not map to
  /// provider IDs. For example, anonymous and custom authentications are not
  /// considered providers. We chose the name here to map the name used in the
  /// ID token.
  String get signInProvider {
    // Sign in provider lives inside the 'firebase' element of the JSON
    final Map<String, dynamic> firebaseElem = claims[_firebaseKey];
    if (firebaseElem != null) {
      final String provider = firebaseElem[_signInProvider];
      return provider;
    }
    return null;
  }

  DateTime _getTimeFromClaimsSafely(String key) {
    final int milliseconds = claims[key] ?? 0;
    return DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GetTokenResult &&
          runtimeType == other.runtimeType &&
          token == other.token &&
          claims == other.claims;

  @override
  int get hashCode => token.hashCode * 31 ^ claims.hashCode * 31;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'token': token,
      'claims': claims,
    };
  }

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('token', token)
          ..add('claims', claims))
        .toString();
  }
}

class FirebaseAuthError extends FirebaseError {
  FirebaseAuthError(this.errorCode, String message)
      : assert(errorCode.isNotEmpty),
        super(message);

  final String errorCode;
}

