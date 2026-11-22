/// Credentials on a connection (owner K): `auth`/`gauth`/`unauth`, `appcheck`/`unappcheck`, the
/// revoke counters, the force-refresh flag and the stale-reply guard (`rtdb_protocol.md` 4.6 to
/// 4.8, 8.3; threat model T7, T14).
library;

import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/realtime/connection_timings.dart';
import 'package:firebase_database_dart/src/realtime/realtime_error.dart';

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

  /// Every change of the auth token: null after a sign-out (8.3), non-null after a sign-in or a
  /// refresh. A non-null value is only a signal: the connection fetches the token with
  /// [authToken] and never sends the value of the event (an `AuthTokenChange` may carry a marker
  /// in place of the token, shim review H1).
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
///
/// `FirebaseApiNotAvailableException` from either provider also means null (the convention of
/// `AuthTokenProvider`); any other failure is a [StateError] that names the provider and keeps the
/// original stack trace, never the provider's message (T8). An App Check result with an error
/// still carries its placeholder token, which is used as Android does; an empty token is null. A
/// forced refresh that the interval refuses is remembered and done by the first fetch after it.
final class ProviderTokenSource implements RealtimeTokenSource {
  /// Creates the adapter over [auth] and [appCheck] (either may be absent).
  ProviderTokenSource({
    AuthTokenProvider? auth,
    AppCheckTokenProvider? appCheck,
    required Duration forcedRefreshMinInterval,
    required DateTime Function() now,
  }) : _auth = auth,
       _appCheck = appCheck,
       _authLimit = _ForcedRefreshLimit(forcedRefreshMinInterval, now),
       _appCheckLimit = _ForcedRefreshLimit(forcedRefreshMinInterval, now);

  final AuthTokenProvider? _auth;
  final AppCheckTokenProvider? _appCheck;
  final _ForcedRefreshLimit _authLimit;
  final _ForcedRefreshLimit _appCheckLimit;

  @override
  Future<String?> authToken({required bool forceRefresh}) async {
    final AuthTokenProvider? auth = _auth;
    if (auth == null) {
      return null;
    }
    final bool force = _authLimit.take(requested: forceRefresh);
    try {
      final GetTokenResult result = await auth.getAccessToken(
        forceRefresh: force,
      );
      return _nonEmpty(result.token);
    } on FirebaseNoSignedInUserException {
      return null;
    } on FirebaseApiNotAvailableException {
      return null;
    } on Object catch (_, stackTrace) {
      Error.throwWithStackTrace(
        StateError('The auth token provider failed.'),
        stackTrace,
      );
    }
  }

  @override
  Future<String?> appCheckToken({required bool forceRefresh}) async {
    final AppCheckTokenProvider? appCheck = _appCheck;
    if (appCheck == null) {
      return null;
    }
    final bool force = _appCheckLimit.take(requested: forceRefresh);
    try {
      final AppCheckTokenResult result = await appCheck.getToken(
        forceRefresh: force,
      );
      return _nonEmpty(result.token);
    } on FirebaseApiNotAvailableException {
      return null;
    } on Object catch (_, stackTrace) {
      Error.throwWithStackTrace(
        StateError('The App Check token provider failed.'),
        stackTrace,
      );
    }
  }

  @override
  Stream<String?> get authChanges {
    final AuthTokenProvider? auth = _auth;
    if (auth == null) {
      return const Stream<String?>.empty();
    }
    return auth.onTokenChanged.map(
      (AuthTokenChange change) => _nonEmpty(change.token),
    );
  }

  @override
  Stream<String?> get appCheckChanges {
    final AppCheckTokenProvider? appCheck = _appCheck;
    if (appCheck == null) {
      return const Stream<String?>.empty();
    }
    return appCheck.onTokenChanged.map(
      (AppCheckTokenResult result) => _nonEmpty(result.token),
    );
  }

  @override
  void notifyInvalid(TokenKind kind) {
    switch (kind) {
      case TokenKind.auth:
        _authLimit.pending = true;
      case TokenKind.appCheck:
        _appCheckLimit.pending = true;
    }
  }

  /// Holds providers only: shows nothing of their tokens (threat model T8).
  @override
  String toString() => 'ProviderTokenSource';
}

/// At most one forced refresh per [interval] for one provider (threat model T14).
final class _ForcedRefreshLimit {
  _ForcedRefreshLimit(this.interval, this.now);

  final Duration interval;
  final DateTime Function() now;

  /// A forced refresh is owed: the server refused the token ([RealtimeTokenSource.notifyInvalid]),
  /// or a request was refused by the interval.
  bool pending = false;

  DateTime? _lastForced;

  /// Whether this fetch forces a refresh, given that the caller [requested] one; records it.
  bool take({required bool requested}) {
    if (!requested && !pending) {
      return false;
    }
    final DateTime at = now();
    final DateTime? last = _lastForced;
    if (last != null && at.difference(last) < interval) {
      pending = true;
      return false;
    }
    _lastForced = at;
    pending = false;
    return true;
  }
}

/// The credential state of the current and the next connection (8.3).
///
/// On [onConnected] it sends `auth` (or `gauth`) and then `appcheck` without waiting (JS pipeline,
/// 8.4 steps 1-2). A response is applied only if the token it answers is still the current one
/// (PersistentConnection.ts:397). A non-ok `auth` or an `ac` push asks for the connection to close
/// and sets [forceRefreshNext]; `appcheck` failures only set it (8.3). Requests carrying tokens are
/// logged as `<action> (contents hidden)` (T7).
///
/// The logging of token-carrying requests is the sender's job (the persistent connection logs every
/// `auth`, `gauth`, `appcheck`, `unauth` and removal request as `<action> (contents hidden)`); this
/// class logs nothing. The stale-reply guard also drops a response that arrives on a later
/// connection than the request, and applies to `appcheck` too (JS does not guard it, :415-431).
/// Every refusal also tells the token source ([RealtimeTokenSource.notifyInvalid]), so the next
/// fetch of that token forces a refresh within the source's limit. Response and push texts are
/// expected cleaned by `decodeServerMessage` and are passed on as they are.
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
  }) : _send = send,
       _tokens = tokens,
       _threshold = invalidTokenThreshold,
       _protocol = protocol,
       _onAuthStatus = onAuthStatus,
       _onAppCheckStatus = onAppCheckStatus;

  final RequestSender _send;
  final RealtimeTokenSource _tokens;
  final int _threshold;
  final RealtimeProtocol _protocol;
  final void Function(String status, String? explanation) _onAuthStatus;
  final void Function(String status, String? explanation) _onAppCheckStatus;
  final StreamController<void> _mustClose = StreamController<void>.broadcast();

  String? _authToken;
  String? _appCheckToken;
  bool _connected = false;

  /// Bumped on every connect and disconnect: a response of an earlier connection is stale.
  int _generation = 0;
  bool _forceRefreshNext = false;
  int _invalidAuthCount = 0;
  int _invalidAppCheckCount = 0;

  /// The connection is up (after the hello): sends the stored credentials.
  ///
  /// Also clears [forceRefreshNext]: the tokens of this connection were fetched before it opened.
  void onConnected() {
    _connected = true;
    _generation++;
    _forceRefreshNext = false;
    final String? auth = _authToken;
    if (auth != null) {
      _sendAuth(auth);
    }
    final String? appCheck = _appCheckToken;
    if (appCheck != null) {
      _sendAppCheck(appCheck);
    }
  }

  /// The connection is gone: pending responses are forgotten.
  void onDisconnected() {
    _connected = false;
    _generation++;
  }

  /// The auth [token] changed (or was fetched for the next connection). Non-null while connected:
  /// a new `auth` on the same connection; null while connected: `unauth`; offline: only stored
  /// (4.7, 8.3). An empty token counts as null.
  void authChanged(String? token) {
    final String? current = _nonEmpty(token);
    _authToken = current;
    if (!_connected) {
      return;
    }
    if (current != null) {
      _sendAuth(current);
    } else {
      _send(RealtimeProtocol.unauth, <String, Object?>{}, null);
    }
  }

  /// The App Check [token] changed: `appcheck`, or the removal action when null (4.8). An empty
  /// token counts as null; offline it is only stored.
  void appCheckChanged(String? token) {
    final String? current = _nonEmpty(token);
    _appCheckToken = current;
    if (!_connected) {
      return;
    }
    if (current != null) {
      _sendAppCheck(current);
    } else {
      _send(_protocol.unappCheck, <String, Object?>{}, null);
    }
  }

  /// Whether the next token fetch must force a refresh (8.1 step 1).
  bool get forceRefreshNext => _forceRefreshNext;

  /// Whether consecutive `invalid_token`/`permission_denied` auth failures reached the threshold:
  /// the owner sets the backoff to its cap (8.3).
  bool get invalidTokenThresholdReached => _invalidAuthCount >= _threshold;

  /// Whether consecutive `invalid_token`/`permission_denied` App Check failures reached the
  /// threshold: the owner logs a warning; the connection stays open (8.3,
  /// PersistentConnection.ts:1006-1021).
  bool get invalidAppCheckThresholdReached =>
      _invalidAppCheckCount >= _threshold;

  /// Handles an `ac` push with [status] and [explanation] (5, 8.3).
  void onAuthRevoked(String status, String explanation) {
    _authRevoked(status, explanation);
  }

  /// Handles an `apc` push with [status] and [explanation] (5, 8.3).
  void onAppCheckRevoked(String status, String explanation) {
    _appCheckRevoked(status, explanation);
  }

  /// Emits when the auth credential was revoked and the connection must close (8.3).
  Stream<void> get connectionMustClose => _mustClose.stream;

  /// Holds tokens: shows nothing of them (threat model T7, T8).
  @override
  String toString() => 'AuthSession';

  void _sendAuth(String token) {
    final int generation = _generation;
    _send(authActionFor(token), <String, Object?>{_credKey: token}, (
      Map<String, Object?> body,
    ) {
      if (generation != _generation || _authToken != token) {
        return;
      }
      final (String status, String? explanation) = _result(body);
      if (status == _ok) {
        _invalidAuthCount = 0;
        _onAuthStatus(status, null);
      } else {
        _authRevoked(status, explanation);
      }
    });
  }

  void _sendAppCheck(String token) {
    final int generation = _generation;
    _send(RealtimeProtocol.appCheck, <String, Object?>{_tokenKey: token}, (
      Map<String, Object?> body,
    ) {
      if (generation != _generation || _appCheckToken != token) {
        return;
      }
      final (String status, String? explanation) = _result(body);
      if (status == _ok) {
        _invalidAppCheckCount = 0;
        _onAppCheckStatus(status, null);
      } else {
        _appCheckRevoked(status, explanation);
      }
    });
  }

  /// PersistentConnection.ts:985-1004: forget the token, force the next fetch, count the failure,
  /// close the connection.
  void _authRevoked(String status, String? explanation) {
    _authToken = null;
    _forceRefreshNext = true;
    _tokens.notifyInvalid(TokenKind.auth);
    if (countsAsInvalidToken(status)) {
      _invalidAuthCount++;
    }
    _onAuthStatus(status, explanation);
    _mustClose.add(null);
  }

  /// PersistentConnection.ts:1006-1021: as for auth, but the connection stays open.
  void _appCheckRevoked(String status, String? explanation) {
    _appCheckToken = null;
    _forceRefreshNext = true;
    _tokens.notifyInvalid(TokenKind.appCheck);
    if (countsAsInvalidToken(status)) {
      _invalidAppCheckCount++;
    }
    _onAppCheckStatus(status, explanation);
  }
}

/// The action that carries [token]: `auth` for a three-part JWT whose claims have `iat`, `gauth`
/// otherwise (4.6, util:src/jwt.ts:129-134).
String authActionFor(String token) {
  final Map<String, Object?>? claims = _jwtClaims(token);
  if (claims != null && claims.containsKey(_issuedAtClaim)) {
    return RealtimeProtocol.auth;
  }
  return RealtimeProtocol.gauth;
}

/// Whether [token] is an admin credential: 40 characters (legacy secret) or a JWT with
/// `admin: true` (1.3, PersistentConnection.ts:352-353). The cap is already 30 s, so this changes
/// nothing today (test plan B-8.2d).
bool isAdminCredential(String token) {
  if (token.length == _legacySecretLength) {
    return true;
  }
  return _jwtClaims(token)?[_adminClaim] == true;
}

const String _ok = 'ok';
const String _credKey = 'cred';
const String _tokenKey = 'token';
const String _issuedAtClaim = 'iat';
const String _adminClaim = 'admin';
const int _legacySecretLength = 40;

String? _nonEmpty(String? token) =>
    token == null || token.isEmpty ? null : token;

/// The status and explanation of a response body `{"s":..,"d":..}`; a status that is not a string
/// is `DatabaseErrorCode.operationFailed`'s.
(String, String?) _result(Map<String, Object?> body) {
  final Object? status = body[RealtimeProtocol.statusKey];
  final Object? data = body['d'];
  return (
    status is String ? status : DatabaseErrorCode.operationFailed.wireStatus,
    data is String ? data : null,
  );
}

/// The claims of [token] when it is three dot-separated parts whose first two are base64 JSON
/// objects (util:src/jwt.ts:34-60, `decode`), else null. Never throws; the signature is not
/// checked.
Map<String, Object?>? _jwtClaims(String token) {
  final List<String> parts = token.split('.');
  if (parts.length != 3) {
    return null;
  }
  final Object? header = _base64Json(parts[0]);
  final Object? claims = _base64Json(parts[1]);
  if (header is! Map<String, Object?> || claims is! Map<String, Object?>) {
    return null;
  }
  return claims;
}

Object? _base64Json(String part) {
  try {
    final String normalized = base64Url.normalize(
      part.replaceAll('+', '-').replaceAll('/', '_'),
    );
    return jsonDecode(utf8.decode(base64Url.decode(normalized)));
  } on FormatException {
    return null;
  }
}
