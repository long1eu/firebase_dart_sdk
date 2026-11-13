// Copyright 2024 Google LLC
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
import 'dart:typed_data';

/// General purpose cache for global values (port of the Android `GlobalsCache` and the JS `globals_cache.ts`).
///
/// Global state that cuts across components is saved here. It contains:
///
/// * `sessionToken`, which tracks server interaction across the listen and write streams. This facilitates cache
///   synchronization and invalidation.
///
/// As upstream, nothing in the client reads or writes the session token yet: the Firestore protocol has no field that
/// carries it.
abstract class GlobalsCache {
  /// Returns the stored session token, or an empty token when none was stored.
  Future<Uint8List> getSessionToken();

  /// Stores [value] as the session token.
  Future<void> setSessionToken(Uint8List value);
}
