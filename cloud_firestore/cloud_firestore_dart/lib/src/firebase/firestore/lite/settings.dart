// Copyright 2026 Google LLC
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

import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_settings.dart'
    as full;

/// The settings of a Firestore Lite instance: where the backend is.
///
/// There is nothing about a cache: Firestore Lite has none.
class FirestoreSettings {
  /// Settings for the backend at [host]:[port]. The defaults are those of
  /// the production service.
  FirestoreSettings({
    String host = defaultHost,
    int port = defaultPort,
    bool sslEnabled = true,
    int grpcFlowControlWindow = defaultGrpcFlowControlWindow,
  }) : this._(
         full.FirestoreSettings(
           host: host,
           port: port,
           sslEnabled: sslEnabled,
           persistenceEnabled: false,
           grpcFlowControlWindow: grpcFlowControlWindow,
         ),
       );

  FirestoreSettings._(this._checked);

  /// The host of the production service.
  static const String defaultHost = full.FirestoreSettings.defaultHost;

  /// The port of the production service.
  static const int defaultPort = full.FirestoreSettings.defaultPort;

  /// The default of [grpcFlowControlWindow], 256 KiB.
  static const int defaultGrpcFlowControlWindow =
      full.FirestoreSettings.defaultGrpcFlowControlWindow;

  // The settings of the main library check the host, the SSL flag and the
  // mock user token: the rules are the same.
  final full.FirestoreSettings _checked;

  /// The host of the Firestore backend.
  String get host => _checked.host;

  /// The port of the Firestore backend.
  int get port => _checked.port;

  /// Whether the connection uses TLS.
  bool get sslEnabled => _checked.sslEnabled;

  /// The HTTP/2 flow-control window of the gRPC transport, in bytes. An
  /// advanced setting, see the `grpcFlowControlWindow` of the settings of the
  /// main library. Ignored by the web transport.
  int get grpcFlowControlWindow => _checked.grpcFlowControlWindow;

  /// The token sent as the credentials of every request to the emulator: a
  /// token string, or the claims of a Firebase ID token as a map. Null unless
  /// set with [withEmulator].
  Object? get mockUserToken => _checked.mockUserToken;

  /// Returns settings for the Firestore emulator at [host]:[port] (without
  /// TLS).
  ///
  /// With a [mockUserToken] the requests are authenticated as that user
  /// instead of the user of Firebase Auth, so that security rules can be
  /// exercised: either a token string, or the claims of a Firebase ID token as
  /// a map with at least a `sub` (or `user_id`) entry.
  FirestoreSettings withEmulator(
    String host,
    int port, {
    Object? mockUserToken,
  }) {
    return FirestoreSettings._(
      _checked.withEmulator(host, port, mockUserToken: mockUserToken),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FirestoreSettings && _checked == other._checked;

  @override
  int get hashCode => _checked.hashCode;

  @override
  String toString() =>
      'FirestoreSettings{host: $host, port: $port, sslEnabled: $sslEnabled, '
      'grpcFlowControlWindow: $grpcFlowControlWindow}';
}
