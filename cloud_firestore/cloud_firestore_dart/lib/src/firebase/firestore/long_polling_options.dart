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

import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_settings.dart';

/// Options of the web transport (WebChannel) for when it uses long polling.
/// Port of `ExperimentalLongPollingOptions` of the JS SDK.
///
/// Note: this class is experimental and may change in any release.
///
/// See [FirestoreSettings.experimentalAutoDetectLongPolling],
/// [FirestoreSettings.experimentalForceLongPolling] and
/// [FirestoreSettings.experimentalLongPollingOptions].
class ExperimentalLongPollingOptions {
  /// Creates long-polling options.
  const ExperimentalLongPollingOptions({this.timeoutSeconds});

  /// The longest time, in seconds, that the backend should hold a
  /// long-polling request open before it answers. Valid values are between 5
  /// and 30, inclusive (checked by [FirestoreSettings]); fractions are rounded
  /// to the nearest millisecond.
  ///
  /// By default the hanging request of long polling times out after 30
  /// seconds. A buffering proxy that made long polling necessary may close
  /// such requests sooner; a shorter timeout (for example 25 seconds) then
  /// keeps them from being cut off. See
  /// https://github.com/firebase/firebase-js-sdk/issues/6987.
  ///
  /// Only the web transport uses this, and only while it long-polls
  /// ([FirestoreSettings.experimentalForceLongPolling], or a buffering proxy
  /// that [FirestoreSettings.experimentalAutoDetectLongPolling] detected).
  final num? timeoutSeconds;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExperimentalLongPollingOptions &&
          timeoutSeconds == other.timeoutSeconds;

  @override
  int get hashCode => timeoutSeconds.hashCode;

  @override
  String toString() =>
      'ExperimentalLongPollingOptions{timeoutSeconds=$timeoutSeconds}';
}
