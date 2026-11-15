// Copyright 2024 Google LLC (behaviour ported from the Android SDK)
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

import 'package:cloud_firestore_dart/src/firebase/firestore/listen_source.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/metadata_change.dart';

/// Options that configure the behavior of snapshot listeners, such as whether
/// metadata-only changes trigger events and the source (server or cache) the
/// listener retrieves data from.
///
/// Pass them to `getSnapshotsWithOptions` of a `DocumentReference` or a `Query`. They are the
/// options object of `onSnapshot` in the JS SDK (`includeMetadataChanges` and `source`).
///
/// PORTING NOTE: the Android `executor` and `activity` options have no
/// equivalent here, a listener is a Dart [Stream].
///
/// ```dart
/// firestore
///     .doc('cities/SF')
///     .getSnapshotsWithOptions(
///       const SnapshotListenOptions(
///         metadataChanges: MetadataChanges.include,
///         source: ListenSource.cache,
///       ),
///     )
///     .listen((DocumentSnapshot<Map<String, Object?>> snapshot) {
///       print(snapshot.metadata);
///     });
/// ```
class SnapshotListenOptions {
  /// Creates the options. By default metadata-only changes are excluded and the listener uses both
  /// the cache and the server.
  const SnapshotListenOptions({
    this.metadataChanges = MetadataChanges.exclude,
    this.source = ListenSource.defaultSource,
  });

  /// Whether metadata-only changes should trigger snapshot events, [MetadataChanges.exclude] by
  /// default.
  final MetadataChanges metadataChanges;

  /// The source the listener retrieves data from, [ListenSource.defaultSource] (the cache and the
  /// server) by default.
  final ListenSource source;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SnapshotListenOptions &&
          metadataChanges == other.metadataChanges &&
          source == other.source;

  @override
  int get hashCode => Object.hash(metadataChanges, source);

  @override
  String toString() =>
      'SnapshotListenOptions{metadataChanges=$metadataChanges, source=$source}';
}
