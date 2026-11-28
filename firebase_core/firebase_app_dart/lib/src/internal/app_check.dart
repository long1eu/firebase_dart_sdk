// Copyright 2021 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:async';

/// Result of an App Check token request.
///
/// A result without an [error] carries a token the provider vouches for. A
/// failed request ([AppCheckTokenResult.failure]) carries the
/// [placeholderToken] together with the [error], like the JS, Android and iOS
/// SDKs; services send the placeholder, so that the backend can tell a failed
/// attestation from an app without App Check, and the backend rejects it when
/// App Check is enforced.
///
/// ```dart
/// import 'package:firebase_app_dart/firebase_app_dart.dart';
///
/// const AppCheckTokenResult ok = AppCheckTokenResult('<app check token>');
/// final AppCheckTokenResult failed = AppCheckTokenResult.failure(
///   StateError('The attestation service is down.'),
/// );
/// ```
class AppCheckTokenResult {
  /// Creates a result with a [token] and, for a failed request, the [error].
  ///
  /// For a failed request use [AppCheckTokenResult.failure]. An empty [token]
  /// with an [error] means that no header is sent; it is what a provider
  /// answers after its owner closed it.
  const AppCheckTokenResult(this.token, {this.error});

  /// A failed request: the [token] is the [placeholderToken] and [error] says
  /// why. Keep tokens and secrets out of the text of [error].
  const AppCheckTokenResult.failure(Object this.error)
    : token = placeholderToken;

  /// The token of a failed request: the base64 form of
  /// `{"error":"UNKNOWN_ERROR"}`, the value the JS and iOS SDKs use.
  static const String placeholderToken = 'eyJlcnJvciI6IlVOS05PV05fRVJST1IifQ==';

  /// The App Check token: the [placeholderToken] for a failed request. A
  /// provider written before [AppCheckTokenResult.failure] may give an empty
  /// token when [error] is set.
  final String token;

  /// Why the token could not be obtained, if it could not.
  final Object? error;

  /// A description without the token and without the text of the [error],
  /// which is written by code outside this package and may quote a token:
  /// `AppCheckTokenResult(token: <redacted>)`, or
  /// `AppCheckTokenResult(token: <redacted>, error: StateError)` with the
  /// runtime type of the [error].
  @override
  String toString() {
    final Object? error = this.error;
    if (error == null) {
      return 'AppCheckTokenResult(token: <redacted>)';
    }
    return 'AppCheckTokenResult(token: <redacted>, '
        'error: ${error.runtimeType})';
  }
}

/// Gives Firebase services access to App Check tokens. An implementation (for
/// example one backed by a device attestation service) is registered on the
/// FirebaseApp; services that find none simply send no App Check header.
///
/// Set it with `FirebaseApp.appCheckProvider` or
/// `PlatformDependencies.appCheckProvider`. Firestore, `FirebaseUserAuth` and
/// the Realtime Database read it once, when they are created: set it before.
/// The other services read it at each request. These packages do not attest a
/// device: you supply the tokens, for example from your own backend.
///
/// A provider that can also mint a token for one request implements
/// [LimitedUseAppCheckTokenProvider] in addition.
///
/// The contract of every provider, so that a service sees the same thing
/// whichever provider is installed. "Both methods" are [getToken] and
/// [LimitedUseAppCheckTokenProvider.getLimitedUseToken].
///
/// * S1, validity. A result without an error carries a token the provider
///   vouches for: not expired and, when the provider knows the expiry, with at
///   least 5 minutes of life left, or half of the token's lifetime when the
///   lifetime is under 10 minutes. A provider that cannot know the expiry (a
///   bridge to another SDK) returns what its source gives. A service never
///   judges validity and never keeps a token beyond the attempt it was
///   fetched for.
/// * S2, failure token. A failed call of either method completes with
///   [AppCheckTokenResult.failure]: the token is the placeholder. A provider
///   written before this contract may return an empty token with an error;
///   services handle both.
/// * S3, no throw. Both methods report a failure in the result. Services treat
///   a throw like an empty token.
/// * S4, an answer within 8 s. Both methods complete no later than
///   [responseDeadline] after the call, with a token or with a failure. The
///   time covers everything the call waits for: loading a stored token,
///   joining an exchange already in flight, the exchange, a custom callback. A
///   provider may let that work continue after it answered and use the result
///   for the next call; only the answer is bounded.
/// * S5, [onTokenChanged]. A broadcast stream. It emits a result each time the
///   session token is replaced by a new one, and only results without an
///   error. No replay to a new listener. Never a limited-use token.
/// * S6, error object. Services never print [AppCheckTokenResult.error]; keep
///   tokens and secrets out of its text all the same.
/// * S7, closed. After its owner closed it, a provider still answers and never
///   throws: both methods complete with an empty token and a [StateError],
///   `AppCheckTokenResult('', error: StateError(...))`, not with the
///   placeholder. No header is sent then: a closed App Check is "no App
///   Check", not "attestation failed".
///
/// What a service sends, for session and limited-use tokens alike: a token
/// without an error is sent; the placeholder of a failure is sent; an empty
/// token, a throw or no answer in time sends the request without the App Check
/// header. A token failure never fails the request on the client: enforcement
/// is the backend's setting. A log line about a failure names the runtime type
/// of the error, never its text.
///
/// ```dart
/// import 'dart:async';
///
/// import 'package:firebase_app_dart/firebase_app_dart.dart';
///
/// class BackendAppCheck extends AppCheckTokenProvider {
///   BackendAppCheck(this.fetchToken);
///
///   /// Asks your backend for a token.
///   final Future<String> Function() fetchToken;
///
///   final StreamController<AppCheckTokenResult> _changes =
///       StreamController<AppCheckTokenResult>.broadcast();
///
///   String? _lastToken;
///
///   @override
///   Future<AppCheckTokenResult> getToken({required bool forceRefresh}) async {
///     try {
///       final String token = await fetchToken().timeout(
///         AppCheckTokenProvider.responseDeadline,
///       );
///       final AppCheckTokenResult result = AppCheckTokenResult(token);
///       if (token != _lastToken) {
///         _lastToken = token;
///         _changes.add(result);
///       }
///       return result;
///     } on Object catch (e) {
///       return AppCheckTokenResult.failure(e);
///     }
///   }
///
///   @override
///   Stream<AppCheckTokenResult> get onTokenChanged => _changes.stream;
/// }
/// ```
abstract class AppCheckTokenProvider {
  /// Constructor for subclasses.
  AppCheckTokenProvider();

  /// How long [getToken] and
  /// [LimitedUseAppCheckTokenProvider.getLimitedUseToken] may take to answer,
  /// with a token or with a failure (S4 of the class comment).
  static const Duration responseDeadline = Duration(seconds: 8);

  /// Fetches a token. [forceRefresh] must only be set when the cached token was
  /// invalidated out of band (for example the backend answered UNAUTHENTICATED).
  ///
  /// Report a failure with [AppCheckTokenResult.failure], like the App Check
  /// SDKs do; do not throw, and answer within [responseDeadline]. Firestore
  /// sends its requests anyway: with the placeholder, or without the header
  /// when the token is empty or when this method throws, and logs a warning.
  Future<AppCheckTokenResult> getToken({required bool forceRefresh});

  /// Emits a result each time the session token of [getToken] is replaced by
  /// a new one.
  ///
  /// A broadcast stream. It emits only results without an error, does not
  /// replay the current token to a new listener, and never emits a limited-use
  /// token. A listener must still tolerate a result with an error: a provider
  /// written before this contract may emit one.
  Stream<AppCheckTokenResult> get onTokenChanged;
}

/// Implemented, in addition to extending [AppCheckTokenProvider], by a provider
/// that can mint limited-use tokens: a token for one request to a backend that
/// consumes App Check tokens (replay protection).
///
/// A provider that cannot mint them does not implement this interface, and a
/// limited-use request then carries no App Check header. Nothing falls back to
/// [AppCheckTokenProvider.getToken]: a backend that consumes tokens would
/// consume the cached session token, and later requests with that token would
/// be refused with nothing on the client saying why.
///
/// For implementers, in addition to S2, S3, S4 and S7 of
/// [AppCheckTokenProvider]:
///
/// * L1. Each call returns a token minted for that call. Never return the
///   cached session token, never store the token you return, and never emit it
///   on [AppCheckTokenProvider.onTokenChanged].
/// * L2. There is no `forceRefresh`: nothing is cached, so nothing can be
///   refreshed.
/// * L3. Calls may overlap; each call gets its own token. "Cannot mint
///   limited-use tokens" is not a result: such a provider does not implement
///   this interface.
///
/// For callers:
///
/// * C1. Call once for each attempt that carries the token. A retry, and each
///   reconnect of a stream, asks again. Do not keep the token after the
///   attempt, and never read its content.
/// * C2. Send a token that is not empty, the placeholder of a failed mint
///   included. When the token is empty, or the call throws or does not answer
///   in time, send the request without the App Check header and let the
///   backend decide. A log line names the runtime type of the error, never its
///   text.
/// * C3. Never send a session token of [AppCheckTokenProvider.getToken] in
///   place of a missing limited-use token. For a provider that does not
///   implement this interface, send no App Check header on a limited-use
///   request.
///
/// ```dart
/// import 'dart:async';
///
/// import 'package:firebase_app_dart/firebase_app_dart.dart';
///
/// class BackendAppCheck extends AppCheckTokenProvider
///     implements LimitedUseAppCheckTokenProvider {
///   BackendAppCheck(this.fetchToken, this.fetchLimitedUseToken);
///
///   /// Asks your backend for a session token.
///   final Future<String> Function() fetchToken;
///
///   /// Asks your backend for a new token for one request.
///   final Future<String> Function() fetchLimitedUseToken;
///
///   @override
///   Future<AppCheckTokenResult> getToken({required bool forceRefresh}) async {
///     try {
///       return AppCheckTokenResult(
///         await fetchToken().timeout(AppCheckTokenProvider.responseDeadline),
///       );
///     } on Object catch (e) {
///       return AppCheckTokenResult.failure(e);
///     }
///   }
///
///   @override
///   Future<AppCheckTokenResult> getLimitedUseToken() async {
///     try {
///       return AppCheckTokenResult(
///         await fetchLimitedUseToken().timeout(
///           AppCheckTokenProvider.responseDeadline,
///         ),
///       );
///     } on Object catch (e) {
///       return AppCheckTokenResult.failure(e);
///     }
///   }
///
///   @override
///   Stream<AppCheckTokenResult> get onTokenChanged =>
///       const Stream<AppCheckTokenResult>.empty();
/// }
/// ```
abstract interface class LimitedUseAppCheckTokenProvider {
  /// Fetches a limited-use token, minted for this call (L1 to L3 of the class
  /// comment).
  ///
  /// Report a failure with [AppCheckTokenResult.failure]; do not throw, and
  /// answer within [AppCheckTokenProvider.responseDeadline].
  Future<AppCheckTokenResult> getLimitedUseToken();
}
