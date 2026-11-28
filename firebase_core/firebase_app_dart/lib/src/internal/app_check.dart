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
  /// without limited-use tokens returns from
  /// [AppCheckTokenProvider.getLimitedUseToken].
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
/// `PlatformDependencies.appCheckProvider`, before the Firestore instance (and a
/// `FirebaseUserAuth`) of the app is created. These packages do not attest a
/// device: you supply the tokens, for example from your own backend.
///
/// The contract of every provider, so that a service sees the same thing
/// whichever provider is installed:
///
/// 1. Validity. A result without an error carries a token the provider vouches
///    for: not expired and, when the provider knows the expiry, with at least 5
///    minutes of life left, or half of the token's lifetime when the lifetime
///    is under 10 minutes. A provider that cannot know the expiry (a bridge to
///    another SDK) returns what its source gives. Services never judge
///    validity, never read the token and never keep it.
/// 2. Failure token. A failed [getToken], and a failed [getLimitedUseToken] of
///    a provider that can mint limited-use tokens, completes with
///    [AppCheckTokenResult.failure].
/// 3. No throw. Both methods report a failure in the result. Services treat a
///    throw like an empty token.
/// 4. Bounded. Both methods complete within a deadline the provider sets for
///    its own work. Services add their own deadline.
/// 5. [onTokenChanged] is a broadcast stream of successes, without replay.
/// 6. Error object. Services never print [AppCheckTokenResult.error]; keep
///    tokens and secrets out of its text all the same.
///
/// What a service sends, for session and limited-use tokens alike: a token
/// without an error is sent; the placeholder of a failure is sent, and the
/// failure is logged once; an empty token, a throw or a timeout sends the
/// request without the App Check header, logged once. A token failure never
/// fails the request on the client: enforcement is the backend's setting. A
/// log line names the runtime type of the error, never its text.
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
///   @override
///   Future<AppCheckTokenResult> getToken({required bool forceRefresh}) async {
///     try {
///       final AppCheckTokenResult result = AppCheckTokenResult(
///         await fetchToken(),
///       );
///       _changes.add(result);
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

  /// Fetches a token. [forceRefresh] must only be set when the cached token was
  /// invalidated out of band (for example the backend answered UNAUTHENTICATED).
  ///
  /// Report a failure with [AppCheckTokenResult.failure], like the App Check
  /// SDKs do; do not throw. Firestore sends its requests anyway: with the
  /// placeholder, or without the header when the token is empty or when this
  /// method throws, and logs a warning.
  Future<AppCheckTokenResult> getToken({required bool forceRefresh});

  /// Fetches a limited-use token: a token for one request to a backend that
  /// consumes App Check tokens (replay protection).
  ///
  /// The default gives no token: it completes with an empty token and an
  /// [UnsupportedError] in [AppCheckTokenResult.error]. It does not fall back
  /// to [getToken], because a backend that consumes tokens would consume the
  /// cached session token, and later requests with that token would be
  /// refused with nothing on the client saying why. A provider that can mint
  /// limited-use tokens overrides this method. A provider declared with
  /// `implements` instead of `extends` must define it.
  ///
  /// For implementers:
  ///
  /// 1. Each call returns a token minted for that call. Never return the
  ///    cached session token of [getToken], never store the token you return,
  ///    and never emit it on [onTokenChanged].
  /// 2. There is no `forceRefresh`: nothing is cached, so nothing can be
  ///    refreshed.
  /// 3. Calls may overlap; each call gets its own token.
  /// 4. "Cannot mint limited-use tokens" is an empty token with an
  ///    [UnsupportedError], as the default gives. "Minting failed" is
  ///    [AppCheckTokenResult.failure]. A caller tells them apart by the type
  ///    of the error. Do not throw.
  ///
  /// For callers:
  ///
  /// 1. Call once for each attempt that carries the token. A retry, and each
  ///    reconnect of a stream, asks again. Do not keep the token after the
  ///    attempt.
  /// 2. Send a token that is not empty, the placeholder of a failure
  ///    included. When the token is empty, or the call throws or times out,
  ///    send the request without the App Check header and let the backend
  ///    decide. Log the failure once per provider type, naming only the
  ///    runtime type of the error, never its text.
  /// 3. Never send a session token of [getToken] in place of a missing
  ///    limited-use token.
  Future<AppCheckTokenResult> getLimitedUseToken() =>
      Future<AppCheckTokenResult>.value(
        AppCheckTokenResult(
          '',
          error: UnsupportedError(
            'This App Check provider does not give limited-use tokens. '
            'Override getLimitedUseToken().',
          ),
        ),
      );

  /// Emits a result each time the session token of [getToken] is replaced by
  /// a new one.
  ///
  /// A broadcast stream. It emits only results without an error, does not
  /// replay the current token to a new listener, and never emits a limited-use
  /// token. A listener must still tolerate a result with an error: a provider
  /// written before this contract may emit one.
  Stream<AppCheckTokenResult> get onTokenChanged;
}
