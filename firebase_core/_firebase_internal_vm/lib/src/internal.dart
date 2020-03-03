// File created by
// Lung Razvan <long1eu>
// on 23/11/2019

import 'package:firebase_core_vm/firebase_common.dart';
import 'package:meta/meta.dart';

import 'auth.dart';

/// Provides a way for [FirebaseApp] to get an access token if there exists
/// a logged in user.
abstract class InternalTokenProvider {
  /// Fetch a valid STS Token.
  ///
  /// [forceRefresh] force refreshes the token. Should only be set to true if
  /// the token is invalidated out of band.
  Future<GetTokenResult> getAccessToken({@required bool forceRefresh});

  /// A synchronous way to get the current Firebase User's UID.
  /// Returns the String representation of the UID. Returns null if FirebaseAuth
  /// is not linked, or if there is no currently signed-in user.
  String get uid;

  /// Stream that will emit when the user auth state changes, when the user logs
  /// out or the token has been invalidated and it's refreshed.
  Stream<InternalTokenResult> get onTokenChanged;
}

/// Represents an internal token result.
class InternalTokenResult {
  const InternalTokenResult(this.token);

  final String token;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InternalTokenResult && runtimeType == other.runtimeType && token == other.token;

  @override
  int get hashCode => token.hashCode * 31;

  @override
  String toString() {
    return (ToStringHelper(runtimeType)..add('token', token)).toString();
  }
}

/// Internal use only, indicates that no signed-in user and operations like
/// [InternalTokenProvider.getAccessToken] will fail.
class FirebaseNoSignedInUserError extends FirebaseError {
  FirebaseNoSignedInUserError(String message) : super(message);
}
