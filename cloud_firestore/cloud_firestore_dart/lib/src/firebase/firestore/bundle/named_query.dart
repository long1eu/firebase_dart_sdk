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

// Ported from the Firestore Android SDK (com.google.firebase.firestore.bundle).

import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_element.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundled_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';

/// Represents a named query saved by the SDK in its local storage.
class NamedQuery implements BundleElement {
  const NamedQuery(this.name, this.bundledQuery, this.readTime);

  /// The name of the query.
  final String name;

  /// The underlying bundled query for this named query.
  final BundledQuery bundledQuery;

  /// The time at which the results for this query were read.
  final SnapshotVersion readTime;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NamedQuery &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          bundledQuery == other.bundledQuery &&
          readTime == other.readTime;

  @override
  int get hashCode => name.hashCode ^ bundledQuery.hashCode ^ readTime.hashCode;

  @override
  String toString() =>
      'NamedQuery{name: $name, bundledQuery: $bundledQuery, readTime: $readTime}';
}
