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

/// Configures the source of snapshot listeners on `DocumentReference` and
/// `Query` (see `getSnapshotsWithOptions`). This controls how a listener
/// retrieves data updates.
enum ListenSource {
  /// The default behavior. The listener attempts to return the initial
  /// snapshot from the cache and retrieve up-to-date snapshots from the
  /// Firestore server. Snapshot events are raised on local mutations and
  /// server side updates.
  defaultSource,

  /// The listener retrieves data and listens to updates from the local
  /// Firestore cache only. If the cache is empty, an empty snapshot is
  /// returned. Snapshot events are raised on cache updates, like local
  /// mutations.
  ///
  /// Note that the data might be stale if the cache has not synchronized with
  /// recent server-side changes.
  cache,
}
