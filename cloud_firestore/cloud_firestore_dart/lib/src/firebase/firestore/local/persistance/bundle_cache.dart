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

import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_metadata.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/named_query.dart';

/// Provides methods to save and read Firestore bundles.
abstract class BundleCache {
  /// Gets the saved metadata for a given bundle id. Returns null if no bundles are found under the given id.
  Future<BundleMetadata?> getBundleMetadata(String bundleId);

  /// Saves the metadata from a bundle into local storage, using its id as the persistent key.
  Future<void> saveBundleMetadata(BundleMetadata metadata);

  /// Gets a saved [NamedQuery] for the given query name. Returns null if no queries are found under the given name.
  Future<NamedQuery?> getNamedQuery(String queryName);

  /// Saves a [NamedQuery] from a bundle, using its name as the persistent key.
  Future<void> saveNamedQuery(NamedQuery query);
}
