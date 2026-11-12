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

import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_metadata.dart';

/// Represents the state of bundle loading tasks.
///
/// Both [success] and [error] are final states: the task will abort or complete and there will be no more updates after
/// they are reported.
///
/// PORTING NOTE: nested in `LoadBundleTaskProgress` as `TaskState` in the Android SDK.
enum LoadBundleTaskState {
  error,
  running,
  success,
}

/// Represents a progress update or a final state from loading bundles.
class LoadBundleTaskProgress {
  const LoadBundleTaskProgress(
    this.documentsLoaded,
    this.totalDocuments,
    this.bytesLoaded,
    this.totalBytes,
    this.exception,
    this.taskState,
  );

  /// Creates an 'initial' status update from a bundle's metadata. The initial status sets all loading indicators to 0.
  factory LoadBundleTaskProgress.forInitial(BundleMetadata bundleMetadata) {
    return LoadBundleTaskProgress(
      0,
      bundleMetadata.totalDocuments,
      0,
      bundleMetadata.totalBytes,
      null,
      LoadBundleTaskState.running,
    );
  }

  /// Creates a 'success' status update from a bundle's metadata. The success status sets all loading indicators to
  /// their maximum values.
  factory LoadBundleTaskProgress.forSuccess(BundleMetadata bundleMetadata) {
    return LoadBundleTaskProgress(
      bundleMetadata.totalDocuments,
      bundleMetadata.totalDocuments,
      bundleMetadata.totalBytes,
      bundleMetadata.totalBytes,
      null,
      LoadBundleTaskState.success,
    );
  }

  /// The progress a [LoadBundleTask] reports before the bundle metadata is known.
  static const LoadBundleTaskProgress initial =
      LoadBundleTaskProgress(0, 0, 0, 0, null, LoadBundleTaskState.success);

  /// How many documents have been loaded.
  final int documentsLoaded;

  /// The total number of documents in the bundle. 0 if the bundle failed to parse.
  final int totalDocuments;

  /// How many bytes have been loaded.
  final int bytesLoaded;

  /// The total number of bytes in the bundle. 0 if the bundle failed to parse.
  final int totalBytes;

  /// If the [LoadBundleTask] failed, the exception. Otherwise null.
  final Object? exception;

  /// The current state of the [LoadBundleTask].
  final LoadBundleTaskState taskState;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoadBundleTaskProgress &&
          runtimeType == other.runtimeType &&
          documentsLoaded == other.documentsLoaded &&
          totalDocuments == other.totalDocuments &&
          bytesLoaded == other.bytesLoaded &&
          totalBytes == other.totalBytes &&
          taskState == other.taskState &&
          exception == other.exception;

  @override
  int get hashCode =>
      documentsLoaded.hashCode ^
      totalDocuments.hashCode ^
      bytesLoaded.hashCode ^
      totalBytes.hashCode ^
      taskState.hashCode ^
      exception.hashCode;

  @override
  String toString() =>
      'LoadBundleTaskProgress{documentsLoaded: $documentsLoaded, totalDocuments: $totalDocuments, '
      'bytesLoaded: $bytesLoaded, totalBytes: $totalBytes, taskState: $taskState, exception: $exception}';
}
