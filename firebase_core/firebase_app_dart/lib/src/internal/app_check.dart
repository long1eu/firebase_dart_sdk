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
/// Like the Android SDK, a failed request still carries a (placeholder) [token]
/// together with the [error]; the backend rejects the placeholder.
///
/// ```dart
/// import 'package:firebase_app_dart/firebase_app_dart.dart';
///
/// const AppCheckTokenResult ok = AppCheckTokenResult('<app check token>');
/// final AppCheckTokenResult failed = AppCheckTokenResult(
///   '',
///   error: StateError('The attestation service is down.'),
/// );
/// ```
class AppCheckTokenResult {
  /// Creates a result with a [token] and, for a failed request, the [error].
  const AppCheckTokenResult(this.token, {this.error});

  /// The App Check token. May be empty when [error] is set.
  final String token;

  /// Why the token could not be obtained, if it could not.
  final Object? error;
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
/// ```dart
/// import 'dart:async';
///
/// import 'package:firebase_app_dart/firebase_app_dart.dart';
///
/// class BackendAppCheck extends InternalAppCheckTokenProvider {
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
///       return AppCheckTokenResult('', error: e);
///     }
///   }
///
///   @override
///   Stream<AppCheckTokenResult> get onTokenChanged => _changes.stream;
/// }
/// ```
abstract class InternalAppCheckTokenProvider {
  /// Constructor for subclasses.
  InternalAppCheckTokenProvider();

  /// Fetches a token. [forceRefresh] must only be set when the cached token was
  /// invalidated out of band (for example the backend answered UNAUTHENTICATED).
  ///
  /// Report a failure in [AppCheckTokenResult.error] (with a placeholder or
  /// empty token), like the App Check SDKs do. Firestore sends its requests
  /// anyway: with the placeholder, or without the header when the token is
  /// empty or when this method throws, and logs a warning.
  Future<AppCheckTokenResult> getToken({required bool forceRefresh});

  /// Emits whenever the token changes.
  Stream<AppCheckTokenResult> get onTokenChanged;
}
