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

import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/load_bundle_task_progress.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';

/// Represents the task of loading a Firestore bundle. It provides progress of bundle loading, as well as task
/// completion and error events.
///
/// [FirebaseFirestore.loadBundle] and [FirebaseFirestore.loadBundleStream] start the task and return it at once. Wait for [future],
/// or follow [stream] to show progress:
///
/// ```dart
/// final LoadBundleTask task = firestore.loadBundle(bundleBytes);
/// task.stream.listen((LoadBundleTaskSnapshot progress) {
///   print('${progress.documentsLoaded} of ${progress.totalDocuments} documents');
/// });
/// final LoadBundleTaskSnapshot result = await task.future;
/// print('loaded ${result.documentsLoaded} documents');
/// ```
///
/// Loading writes only to the local cache and needs no connection. A bundle that cannot be read fails the task with a
/// [FirestoreException] (code `invalidArgument`). After a successful load the named queries of the bundle are available
/// through [FirebaseFirestore.namedQuery]. Loading a bundle again whose id was already loaded with the same or a later
/// creation time completes at once without changing the cache.
///
/// PORTING NOTE: the Android class extends `Task<LoadBundleTaskSnapshot>`. Here the task completion is exposed as
/// [future] and the progress updates as [stream].
class LoadBundleTask {
  /// Implementation detail of the SDK; not part of the supported API. Use [FirebaseFirestore.loadBundle].
  LoadBundleTask._() {
    // Failures are reported to every consumer of [future]. Do not turn a failure nobody asked about into an
    // unhandled error.
    _completion.future.ignore();
  }

  final Completer<LoadBundleTaskSnapshot> _completion =
      Completer<LoadBundleTaskSnapshot>();

  final StreamController<LoadBundleTaskSnapshot> _progress =
      StreamController<LoadBundleTaskSnapshot>.broadcast();

  /// The last progress update.
  LoadBundleTaskSnapshot _snapshot = LoadBundleTaskSnapshotInternal.initial;

  /// The last progress update; all counts are zero before the first one.
  LoadBundleTaskSnapshot get snapshot => _snapshot;

  /// Completes with the final progress (state [LoadBundleTaskState.success]) once the bundle is loaded, or with the
  /// error if loading failed.
  ///
  /// The error is reported only to those who listen to this future; a failed task that nobody waits for does not
  /// cause an unhandled error.
  Future<LoadBundleTaskSnapshot> get future => _completion.future;

  /// The progress updates reported from now on. A final update with state [LoadBundleTaskState.success] or
  /// [LoadBundleTaskState.error] is the last event, after which the stream is closed. This is a broadcast stream: it
  /// does not replay updates that were reported before the listener subscribed (see [snapshot]).
  Stream<LoadBundleTaskSnapshot> get stream => _progress.stream;

  // Called by the library.

  /// Completes the task successfully with the given final [result].
  void _setResult(LoadBundleTaskSnapshot result) {
    hardAssert(
      result.taskState == LoadBundleTaskState.success,
      'Expected success, but was ${result.taskState}',
    );
    _snapshot = result;
    _completion.complete(result);
    _progress
      ..add(result)
      ..close();
  }

  /// Completes the task with the given [exception].
  void _setException(Object exception) {
    final LoadBundleTaskSnapshot snapshot =
        LoadBundleTaskSnapshotInternal.create(
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
  void _updateProgress(LoadBundleTaskSnapshot progressUpdate) {
    _snapshot = progressUpdate;
    _progress.add(progressUpdate);
  }
}

/// Members of [LoadBundleTask] for the SDK itself. Not exported by the public libraries.
extension LoadBundleTaskInternal on LoadBundleTask {
  /// Whether the task completed, successfully or not.
  bool get isComplete => _completion.isCompleted;

  /// Creates a task that has not started.
  static LoadBundleTask create() => LoadBundleTask._();

  /// Completes the task successfully with the given final [result].
  void setResult(LoadBundleTaskSnapshot result) => _setResult(result);

  /// Completes the task with the given [exception].
  void setException(Object exception) => _setException(exception);

  /// Reports a progress update.
  void updateProgress(LoadBundleTaskSnapshot progressUpdate) =>
      _updateProgress(progressUpdate);
}
