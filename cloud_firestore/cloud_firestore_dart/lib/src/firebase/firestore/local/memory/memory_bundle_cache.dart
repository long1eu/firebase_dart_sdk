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
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/bundle_cache.dart';

/// A memory-backed implementation of the bundle cache.
class MemoryBundleCache implements BundleCache {
  final Map<String, BundleMetadata> _bundles = <String, BundleMetadata>{};
  final Map<String, NamedQuery> _namedQueries = <String, NamedQuery>{};

  @override
  Future<BundleMetadata?> getBundleMetadata(String bundleId) async =>
      _bundles[bundleId];

  @override
  Future<void> saveBundleMetadata(BundleMetadata metadata) async {
    _bundles[metadata.bundleId] = metadata;
  }

  @override
  Future<NamedQuery?> getNamedQuery(String queryName) async =>
      _namedQueries[queryName];

  @override
  Future<void> saveNamedQuery(NamedQuery query) async {
    _namedQueries[query.name] = query;
  }
}
