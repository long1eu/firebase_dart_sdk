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

/// Builds the document overlays of a persistence that was written before overlays existed (data migration that
/// follows a schema migration).
abstract class OverlayMigrationManager {
  /// Runs the pending overlay migration, if any.
  Future<void> run();
}

/// An [OverlayMigrationManager] for persistences that never need a data migration (memory).
class NoOpOverlayMigrationManager implements OverlayMigrationManager {
  const NoOpOverlayMigrationManager();

  @override
  Future<void> run() async {}
}
