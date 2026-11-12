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
class AppCheckTokenResult {
  const AppCheckTokenResult(this.token, {this.error});

  /// The App Check token. May be empty when [error] is set.
  final String token;

  /// Why the token could not be obtained, if it could not.
  final Object? error;
}

/// Gives Firebase services access to App Check tokens. An implementation (for
/// example one backed by a device attestation service) is registered on the
/// FirebaseApp; services that find none simply send no App Check header.
abstract class InternalAppCheckTokenProvider {
  /// Fetches a token. [forceRefresh] must only be set when the cached token was
  /// invalidated out of band (for example the backend answered UNAUTHENTICATED).
  /// Throws if the request itself fails.
  Future<AppCheckTokenResult> getToken({required bool forceRefresh});

  /// Emits whenever the token changes.
  Stream<AppCheckTokenResult> get onTokenChanged;
}
