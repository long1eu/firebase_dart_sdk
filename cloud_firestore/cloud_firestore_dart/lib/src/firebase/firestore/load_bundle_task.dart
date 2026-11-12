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

import 'package:cloud_firestore_dart/src/firebase/firestore/load_bundle_task_progress.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';

/// A listener that is called periodically during execution of a [LoadBundleTask].
typedef OnProgressListener = void Function(LoadBundleTaskProgress snapshot);

/// Represents the task of loading a Firestore bundle. It provides progress of bundle loading, as well as task
/// completion and error events.
///
/// PORTING NOTE: the Android class extends `Task<LoadBundleTaskProgress>`. Here the task completion is exposed as
/// [future] and the progress updates as [stream] / [addOnProgressListener].
class LoadBundleTask {
  LoadBundleTask() {
    // Failures are reported to every consumer of [future]. Do not turn a failure nobody asked about into an
    // unhandled error.
    _completion.future.ignore();
  }

  final Completer<LoadBundleTaskProgress> _completion =
      Completer<LoadBundleTaskProgress>();

  final StreamController<LoadBundleTaskProgress> _progress =
      StreamController<LoadBundleTaskProgress>.broadcast();

  /// The last progress update.
  LoadBundleTaskProgress _snapshot = LoadBundleTaskProgress.initial;

  /// The last progress update, or [LoadBundleTaskProgress.initial] if none was reported yet.
  LoadBundleTaskProgress get snapshot => _snapshot;

  /// Completes with the final progress (state [LoadBundleTaskState.success]) once the bundle is loaded, or with the
  /// error if loading failed.
  Future<LoadBundleTaskProgress> get future => _completion.future;

  /// The progress updates reported from now on. A final update with state [LoadBundleTaskState.success] or
  /// [LoadBundleTaskState.error] is the last event, after which the stream is closed. This is a broadcast stream: it
  /// does not replay updates that were reported before the listener subscribed (see [snapshot]).
  Stream<LoadBundleTaskProgress> get stream => _progress.stream;

  /// Returns true if the task is complete (successfully or not).
  bool get isComplete => _completion.isCompleted;

  /// Returns true if the task has completed successfully.
  bool get isSuccessful =>
      _completion.isCompleted &&
      _snapshot.taskState == LoadBundleTaskState.success &&
      _snapshot.exception == null;

  /// The exception that caused the task to fail. Null if the task is not yet complete, or completed successfully.
  Object? get exception => _snapshot.exception;

  /// Adds a listener that is called with every progress update, including the final one. Returns this task.
  LoadBundleTask addOnProgressListener(OnProgressListener listener) {
    _progress.stream.listen(listener);
    return this;
  }

  // Called by the library.

  /// Completes the task successfully with the given final [result].
  void setResult(LoadBundleTaskProgress result) {
    hardAssert(result.taskState == LoadBundleTaskState.success,
        'Expected success, but was ${result.taskState}');
    _snapshot = result;
    _completion.complete(result);
    _progress
      ..add(result)
      ..close();
  }

  /// Completes the task with the given [exception].
  void setException(Object exception) {
    final LoadBundleTaskProgress snapshot = LoadBundleTaskProgress(
      _snapshot.documentsLoaded,
      _snapshot.totalDocuments,
      _snapshot.bytesLoaded,
      _snapshot.totalBytes,
      exception,
      LoadBundleTaskState.error,
    );
    _snapshot = snapshot;
    _completion.completeError(exception);
    _progress
      ..add(snapshot)
      ..close();
  }

  /// Reports a progress update.
  void updateProgress(LoadBundleTaskProgress progressUpdate) {
    _snapshot = progressUpdate;
    _progress.add(progressUpdate);
  }
}
