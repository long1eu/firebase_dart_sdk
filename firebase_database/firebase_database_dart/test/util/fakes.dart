// Owner K. Token providers and a recording request sender for the unit tests (test plan 2.4,
// 2.4a); FakeAuth and FakeAppCheck follow firebase_storage_dart's test/fakes.dart.

import 'dart:async';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/src/realtime/auth_session.dart';

/// An auth provider that hands out [tokens] in turn (the last one repeats) and records the
/// `forceRefresh` of each call. A null token means nobody is signed in.
final class FakeAuth extends AuthTokenProvider {
  /// Creates the provider; with [error] every call fails with it.
  FakeAuth(this.tokens, {this.error});

  /// The tokens, in the order they are handed out.
  final List<String?> tokens;

  /// The error of every call, when set.
  final Object? error;

  final List<bool> _calls = <bool>[];
  final StreamController<AuthTokenChange> _changes =
      StreamController<AuthTokenChange>.broadcast(sync: true);

  /// The `forceRefresh` of each call.
  List<bool> get calls => _calls;

  /// While set and not completed, [getAccessToken] waits for it: a fetch in flight.
  Completer<void>? gate;

  /// Emits [token] on [onTokenChanged] (empty for a sign-out).
  void emit(String token) {
    _changes.add(AuthTokenChange(token));
  }

  @override
  Future<GetTokenResult> getAccessToken({required bool forceRefresh}) async {
    _calls.add(forceRefresh);
    final int index = _calls.length - 1;
    final Completer<void>? wait = gate;
    if (wait != null) {
      await wait.future;
    }
    final Object? failure = error;
    if (failure != null) {
      return Future<Never>.error(failure);
    }
    final String? token = tokens[index.clamp(0, tokens.length - 1)];
    if (token == null) {
      throw const FirebaseNoSignedInUserException('No user.');
    }
    return GetTokenResult(token);
  }

  @override
  String? get uid => null;

  @override
  Stream<AuthTokenChange> get onTokenChanged => _changes.stream;
}

/// An App Check provider with a fixed [token], or one that fails with [error].
final class FakeAppCheck extends AppCheckTokenProvider {
  /// Creates the provider.
  FakeAppCheck(this.token, {this.error});

  /// The token handed out.
  final String token;

  /// The error of every call, when set.
  final Object? error;

  final List<bool> _calls = <bool>[];
  final StreamController<AppCheckTokenResult> _changes =
      StreamController<AppCheckTokenResult>.broadcast(sync: true);

  /// The `forceRefresh` of each call.
  List<bool> get calls => _calls;

  /// While set and not completed, [getToken] waits for it.
  Completer<void>? gate;

  /// Emits [result] on [onTokenChanged].
  void emit(AppCheckTokenResult result) {
    _changes.add(result);
  }

  @override
  Future<AppCheckTokenResult> getToken({required bool forceRefresh}) async {
    _calls.add(forceRefresh);
    final Completer<void>? wait = gate;
    if (wait != null) {
      await wait.future;
    }
    final Object? failure = error;
    if (failure != null) {
      return Future<Never>.error(failure);
    }
    return AppCheckTokenResult(token);
  }

  @override
  Stream<AppCheckTokenResult> get onTokenChanged => _changes.stream;
}

/// A [RealtimeTokenSource] with settable tokens that records every call, for the units that take a
/// token source (`AuthSession`, the persistent connection, the REST client).
final class FakeTokenSource implements RealtimeTokenSource {
  /// Creates the source handing out [auth] and [appCheck].
  FakeTokenSource({this.auth, this.appCheck});

  /// The auth token handed out.
  String? auth;

  /// The App Check token handed out.
  String? appCheck;

  /// The `forceRefresh` of each [authToken] call.
  final List<bool> authCalls = <bool>[];

  /// The `forceRefresh` of each [appCheckToken] call.
  final List<bool> appCheckCalls = <bool>[];

  /// Every [notifyInvalid], in order.
  final List<TokenKind> invalid = <TokenKind>[];

  final StreamController<String?> _authChanges =
      StreamController<String?>.broadcast(sync: true);
  final StreamController<String?> _appCheckChanges =
      StreamController<String?>.broadcast(sync: true);

  /// Emits [token] on [authChanges].
  void emitAuth(String? token) {
    _authChanges.add(token);
  }

  /// Emits [token] on [appCheckChanges].
  void emitAppCheck(String? token) {
    _appCheckChanges.add(token);
  }

  @override
  Future<String?> authToken({required bool forceRefresh}) async {
    authCalls.add(forceRefresh);
    return auth;
  }

  @override
  Future<String?> appCheckToken({required bool forceRefresh}) async {
    appCheckCalls.add(forceRefresh);
    return appCheck;
  }

  @override
  Stream<String?> get authChanges => _authChanges.stream;

  @override
  Stream<String?> get appCheckChanges => _appCheckChanges.stream;

  @override
  void notifyInvalid(TokenKind kind) {
    invalid.add(kind);
  }
}

/// A request recorded by [RecordingSender].
final class SentRequest {
  /// Creates the record of [action] with [body]; [onResponse] is the callback given, if any.
  const SentRequest(this.action, this.body, this.onResponse);

  /// The action.
  final String action;

  /// The body.
  final Map<String, Object?> body;

  /// The response callback, or null.
  final void Function(Map<String, Object?> body)? onResponse;

  /// Shows the action only: the body may hold a token.
  @override
  String toString() => 'SentRequest($action)';
}

/// A [RequestSender] that records every request; no WebSocket involved (test plan 2.4a).
final class RecordingSender {
  /// Creates an empty recorder.
  RecordingSender();

  final List<SentRequest> _sent = <SentRequest>[];

  /// The closure to inject.
  RequestSender get send =>
      (
        String action,
        Map<String, Object?> body,
        void Function(Map<String, Object?> body)? onResponse,
      ) {
        _sent.add(SentRequest(action, body, onResponse));
      };

  /// Every request so far, in order.
  List<SentRequest> get sent => _sent;

  /// The actions of [sent], in order.
  List<String> get actions => <String>[
    for (final SentRequest request in _sent) request.action,
  ];

  /// Answers request number [index] of [sent] with [status] and [data].
  ///
  /// Throws a [StateError] when that request was sent without a callback: a test that answers it
  /// is wrong.
  void respond(int index, String status, [Object? data]) {
    final void Function(Map<String, Object?> body)? callback =
        _sent[index].onResponse;
    if (callback == null) {
      throw StateError(
        'Request $index (${_sent[index].action}) has no callback.',
      );
    }
    callback(<String, Object?>{'s': status, 'd': data});
  }
}
