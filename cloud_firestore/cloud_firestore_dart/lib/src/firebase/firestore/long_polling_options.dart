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
/// Port of `WebExperimentalLongPollingOptions` of the JS SDK.
///
/// Note: this class is experimental and may change in any release.
///
/// See [Settings.webExperimentalAutoDetectLongPolling],
/// [Settings.webExperimentalForceLongPolling] and
/// [Settings.webExperimentalLongPollingOptions].
///
/// ```dart
/// final Settings settings = Settings(
///   webExperimentalForceLongPolling: true,
///   webExperimentalLongPollingOptions: const WebExperimentalLongPollingOptions(
///     timeoutDuration: Duration(seconds: 25),
///   ),
/// );
/// ```
///
/// Only the web transport uses these options; the gRPC transport ignores
/// them.
class WebExperimentalLongPollingOptions {
  /// Creates long-polling options. Without [timeoutDuration] the default
  /// timeout of 30 seconds applies.
  const WebExperimentalLongPollingOptions({this.timeoutDuration});

  /// The longest time that the backend should hold a long-polling request
  /// open before it answers. Valid values are between 5 and 30 seconds,
  /// inclusive (checked by [Settings]); it is rounded to the nearest
  /// millisecond.
  ///
  /// By default the hanging request of long polling times out after 30
  /// seconds. A buffering proxy that made long polling necessary may close
  /// such requests sooner; a shorter timeout (for example 25 seconds) then
  /// keeps them from being cut off. See
  /// https://github.com/firebase/firebase-js-sdk/issues/6987.
  ///
  /// Only the web transport uses this, and only while it long-polls
  /// ([Settings.webExperimentalForceLongPolling], or a buffering proxy
  /// that [Settings.webExperimentalAutoDetectLongPolling] detected).
  final Duration? timeoutDuration;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WebExperimentalLongPollingOptions &&
          timeoutDuration == other.timeoutDuration;

  @override
  int get hashCode => timeoutDuration.hashCode;

  @override
  String toString() =>
      'WebExperimentalLongPollingOptions{timeoutDuration=$timeoutDuration}';
}

/// Members of [WebExperimentalLongPollingOptions] for the SDK itself. Not exported by the public libraries.
extension WebExperimentalLongPollingOptionsInternal
    on WebExperimentalLongPollingOptions {
  /// [timeoutDuration] in seconds, with fractions, or null.
  num? get timeoutSeconds {
    final Duration? duration = timeoutDuration;
    return duration == null
        ? null
        : duration.inMicroseconds / Duration.microsecondsPerSecond;
  }
}
