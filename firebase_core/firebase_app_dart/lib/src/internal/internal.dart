// File created by
// Lung Razvan <long1eu>
// on 23/11/2019

import 'dart:async';

import 'auth.dart';
import 'util/to_string_helper.dart';

/// The source of the token that Firestore sends with each request (`Authorization: Bearer`).
///
/// Assign an implementation to `FirebaseApp.authProvider` (or return it from
/// `PlatformDependencies.authProvider`) before the Firestore instance of the app is created.
/// `package:firebase_auth_providers_dart` has ready-made ones: `FirebaseUserAuth` for signed-in
/// users and `OAuthTokenProvider` for service accounts.
///
/// How Firestore uses it:
///
/// * it calls [getAccessToken] before each request and stream; `forceRefresh` is `true` after the
///   backend answered `unauthenticated`;
/// * when [getAccessToken] throws `FirebaseNoSignedInUserException` or `FirebaseApiNotAvailableException`,
///   the request goes out without a token; any other error fails it with `unauthenticated`;
/// * it reads [uid] to keep the cache and the pending writes of each user apart, and restarts its
///   streams when [onTokenChanged] emits a token of another user.
///
/// ```dart
/// import 'dart:async';
///
/// import 'package:firebase_app_dart/firebase_app_dart.dart';
///
/// /// A provider for tokens that your program gets elsewhere.
/// class StaticTokenProvider extends AuthTokenProvider {
///   StaticTokenProvider(this.token, this.uid);
///
///   final String? token;
///
///   @override
///   final String? uid;
///
///   @override
///   Future<GetTokenResult> getAccessToken({required bool forceRefresh}) async {
///     final String? value = token;
///     if (value == null) {
///       throw FirebaseNoSignedInUserException('No user is signed in.');
///     }
///     return GetTokenResult(value);
///   }
///
///   @override
///   Stream<AuthTokenChange> get onTokenChanged =>
///       const Stream<AuthTokenChange>.empty();
/// }
/// ```
abstract class AuthTokenProvider {
  /// Constructor for subclasses.
  AuthTokenProvider();

  /// Returns a valid token.
  ///
  /// [forceRefresh] asks for a new token even when the current one has not expired; callers set it
  /// only when the token was invalidated out of band. Throw `FirebaseNoSignedInUserException` when
  /// there is no user.
  Future<GetTokenResult> getAccessToken({required bool forceRefresh});

  /// The id of the signed-in user, or null when nobody is signed in or the token does not belong to
  /// a Firebase user (a service account).
  String? get uid;

  /// Emits after a sign-in, a sign-out (an empty token) and a refresh of the token. A provider
  /// without users can return an empty stream.
  ///
  /// An event is a signal, not the token to send: see [AuthTokenChange]. By the time a listener
  /// runs, [uid] and [getAccessToken] already answer for the new state.
  Stream<AuthTokenChange> get onTokenChanged;
}

/// An event of `AuthTokenProvider.onTokenChanged`: a signal that the token changed.
///
/// Read only one thing from [token]: an empty one means that nobody is signed in. A token that is
/// not empty may be the new token or a placeholder (a provider that learns of a change without the
/// token emits one), so never send it: call `AuthTokenProvider.getAccessToken` for the token and
/// read `AuthTokenProvider.uid` for the user.
///
/// [toString] does not show the token.
///
/// ```dart
/// import 'package:firebase_app_dart/firebase_app_dart.dart';
///
/// const AuthTokenChange signedOut = AuthTokenChange('');
/// ```
class AuthTokenChange {
  /// Creates an event holding [token].
  const AuthTokenChange(this.token);

  /// Empty after a sign-out; otherwise the new token or a placeholder for it. Not for sending.
  final String token;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthTokenChange &&
          runtimeType == other.runtimeType &&
          token == other.token;

  @override
  int get hashCode => token.hashCode * 31;

  @override
  String toString() {
    // The token is a credential: never part of the string form, which ends up
    // in logs and error messages.
    return (ToStringHelper(runtimeType) //
          ..add('token', token.isEmpty ? '<empty>' : '<redacted>'))
        .toString();
  }
}
