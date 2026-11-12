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
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';

/// Represents a Firestore bundle saved by the SDK in its local storage.
class BundleMetadata implements BundleElement {
  const BundleMetadata(
    this.bundleId,
    this.schemaVersion,
    this.createTime,
    this.totalDocuments,
    this.totalBytes,
  );

  /// The ID of the bundle. It is used together with [createTime] to determine if a bundle has been loaded by the SDK.
  final String bundleId;

  /// The schema version of the bundle.
  final int schemaVersion;

  /// The snapshot version of the bundle if created by the Server SDKs, or else [SnapshotVersion.none].
  final SnapshotVersion createTime;

  /// The number of documents in the bundle.
  final int totalDocuments;

  /// The size of the bundle in bytes, excluding this [BundleMetadata].
  final int totalBytes;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BundleMetadata &&
          runtimeType == other.runtimeType &&
          bundleId == other.bundleId &&
          schemaVersion == other.schemaVersion &&
          createTime == other.createTime &&
          totalDocuments == other.totalDocuments &&
          totalBytes == other.totalBytes;

  @override
  int get hashCode =>
      bundleId.hashCode ^
      schemaVersion.hashCode ^
      createTime.hashCode ^
      totalDocuments.hashCode ^
      totalBytes.hashCode;

  @override
  String toString() =>
      'BundleMetadata{bundleId: $bundleId, schemaVersion: $schemaVersion, createTime: $createTime, '
      'totalDocuments: $totalDocuments, totalBytes: $totalBytes}';
}
