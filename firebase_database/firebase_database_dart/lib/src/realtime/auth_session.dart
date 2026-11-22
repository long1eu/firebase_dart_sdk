/// Credentials on a connection (owner K): `auth`/`gauth`/`unauth`, `appcheck`/`unappcheck`, the
/// revoke counters, the force-refresh flag and the stale-reply guard (`rtdb_protocol.md` 4.6 to
/// 4.8, 8.3; threat model T7, T14).
library;

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/src/realtime/connection_timings.dart';

/// Sends a request on the live connection: [action] with [body]; [onResponse] gets the response
/// body `{"s":..,"d":..}`, or is null when the response is ignored (test plan section 5).
typedef RequestSender =
    void Function(
      String action,
      Map<String, Object?> body,
      void Function(Map<String, Object?> body)? onResponse,
    );

/// Which credential a [RealtimeTokenSource] call is about.
enum TokenKind {
  /// The Firebase Auth ID token (or another `gauth` credential).
  auth,

  /// The App Check token.
  appCheck,
}

/// The tokens of one database instance, as the connection half sees them (test plan section 5).
///
/// An empty token from a provider is reported as null. Failures of a provider are errors of the
/// returned future, never with the provider's message in them (threat model T8).
abstract interface class RealtimeTokenSource {
  /// The auth token for the next connection, or null when nobody is signed in (8.1).
  Future<String?> authToken({required bool forceRefresh});

  /// The App Check token for the next connection, or null when there is no App Check.
  Future<String?> appCheckToken({required bool forceRefresh});

  /// Every change of the auth token; null after a sign-out (8.3).
  Stream<String?> get authChanges;

  /// Every change of the App Check token.
  Stream<String?> get appCheckChanges;

  /// The server refused the current token of [kind]; the next fetch of it forces a refresh.
  void notifyInvalid(TokenKind kind);
}

/// A [RealtimeTokenSource] over the providers of `firebase_app_dart`.
///
/// `FirebaseNoSignedInUserException` from the auth provider means null. A forced refresh is
/// requested at most once per `forcedRefreshMinInterval` per provider (threat model T14).
final class ProviderTokenSource implements RealtimeTokenSource {
  /// Creates the adapter over [auth] and [appCheck] (either may be absent).
  ProviderTokenSource({
    AuthTokenProvider? auth,
    AppCheckTokenProvider? appCheck,
    required Duration forcedRefreshMinInterval,
    required DateTime Function() now,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String?> authToken({required bool forceRefresh}) {
    throw UnimplementedError();
  }

  @override
  Future<String?> appCheckToken({required bool forceRefresh}) {
    throw UnimplementedError();
  }

  @override
  Stream<String?> get authChanges => throw UnimplementedError();

  @override
  Stream<String?> get appCheckChanges => throw UnimplementedError();

  @override
  void notifyInvalid(TokenKind kind) {
    throw UnimplementedError();
  }
}

/// The credential state of the current and the next connection (8.3).
///
/// On [onConnected] it sends `auth` (or `gauth`) and then `appcheck` without waiting (JS pipeline,
/// 8.4 steps 1-2). A response is applied only if the token it answers is still the current one
/// (PersistentConnection.ts:397). A non-ok `auth` or an `ac` push asks for the connection to close
/// and sets [forceRefreshNext]; `appcheck` failures only set it (8.3). Requests carrying tokens are
/// logged as `<action> (contents hidden)` (T7).
final class AuthSession {
  /// Creates the session sending through [send] and reading [tokens]. [invalidTokenThreshold] is
  /// `ConnectionTimings.invalidTokenThreshold` (3); [protocol] gives the App Check removal action
  /// of the server ([RealtimeProtocol.unappCheck]).
  ///
  /// [onAuthStatus] gets the result of every current `auth`/`gauth` and every `ac` push (`ok`, or
  /// the revoke status and the server's explanation); [onAppCheckStatus] the same for `appcheck`
  /// and `apc`. The persistent connection forwards both to `ServerActionsDelegate`.
  AuthSession(
    RequestSender send,
    RealtimeTokenSource tokens, {
    required int invalidTokenThreshold,
    required RealtimeProtocol protocol,
    required void Function(String status, String? explanation) onAuthStatus,
    required void Function(String status, String? explanation) onAppCheckStatus,
  }) {
    throw UnimplementedError();
  }

  /// The connection is up (after the hello): sends the stored credentials.
  void onConnected() {
    throw UnimplementedError();
  }

  /// The connection is gone: pending responses are forgotten.
  void onDisconnected() {
    throw UnimplementedError();
  }

  /// The auth [token] changed (or was fetched for the next connection). Non-null while connected:
  /// a new `auth` on the same connection; null while connected: `unauth`; offline: only stored
  /// (4.7, 8.3).
  void authChanged(String? token) {
    throw UnimplementedError();
  }

  /// The App Check [token] changed: `appcheck`, or the removal action when null (4.8).
  void appCheckChanged(String? token) {
    throw UnimplementedError();
  }

  /// Whether the next token fetch must force a refresh (8.1 step 1).
  bool get forceRefreshNext => throw UnimplementedError();

  /// Whether consecutive `invalid_token`/`permission_denied` auth failures reached the threshold:
  /// the owner sets the backoff to its cap (8.3).
  bool get invalidTokenThresholdReached => throw UnimplementedError();

  /// Handles an `ac` push with [status] and [explanation] (5, 8.3).
  void onAuthRevoked(String status, String explanation) {
    throw UnimplementedError();
  }

  /// Handles an `apc` push with [status] and [explanation] (5, 8.3).
  void onAppCheckRevoked(String status, String explanation) {
    throw UnimplementedError();
  }

  /// Emits when the auth credential was revoked and the connection must close (8.3).
  Stream<void> get connectionMustClose => throw UnimplementedError();

  /// Holds tokens: shows nothing of them (threat model T7, T8).
  @override
  String toString() => 'AuthSession';
}

/// The action that carries [token]: `auth` for a three-part JWT whose claims have `iat`, `gauth`
/// otherwise (4.6, util:src/jwt.ts:129-134).
String authActionFor(String token) {
  throw UnimplementedError();
}

/// Whether [token] is an admin credential: 40 characters (legacy secret) or a JWT with
/// `admin: true` (1.3, PersistentConnection.ts:352-353). The cap is already 30 s, so this changes
/// nothing today (test plan B-8.2d).
bool isAdminCredential(String token) {
  throw UnimplementedError();
}
