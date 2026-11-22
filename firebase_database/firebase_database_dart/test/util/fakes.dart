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

  /// The `forceRefresh` of each call.
  List<bool> get calls => throw UnimplementedError();

  /// While set and not completed, [getAccessToken] waits for it: a fetch in flight.
  Completer<void>? gate;

  /// Emits [token] on [onTokenChanged] (empty for a sign-out).
  void emit(String token) {
    throw UnimplementedError();
  }

  @override
  Future<GetTokenResult> getAccessToken({required bool forceRefresh}) {
    throw UnimplementedError();
  }

  @override
  String? get uid => throw UnimplementedError();

  @override
  Stream<AuthTokenChange> get onTokenChanged => throw UnimplementedError();
}

/// An App Check provider with a fixed [token], or one that fails with [error].
final class FakeAppCheck extends AppCheckTokenProvider {
  /// Creates the provider.
  FakeAppCheck(this.token, {this.error});

  /// The token handed out.
  final String token;

  /// The error of every call, when set.
  final Object? error;

  /// The `forceRefresh` of each call.
  List<bool> get calls => throw UnimplementedError();

  /// While set and not completed, [getToken] waits for it.
  Completer<void>? gate;

  /// Emits [result] on [onTokenChanged].
  void emit(AppCheckTokenResult result) {
    throw UnimplementedError();
  }

  @override
  Future<AppCheckTokenResult> getToken({required bool forceRefresh}) {
    throw UnimplementedError();
  }

  @override
  Stream<AppCheckTokenResult> get onTokenChanged => throw UnimplementedError();
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
  RecordingSender() {
    throw UnimplementedError();
  }

  /// The closure to inject.
  RequestSender get send => throw UnimplementedError();

  /// Every request so far, in order.
  List<SentRequest> get sent => throw UnimplementedError();

  /// Answers request number [index] of [sent] with [status] and [data].
  void respond(int index, String status, [Object? data]) {
    throw UnimplementedError();
  }
}
