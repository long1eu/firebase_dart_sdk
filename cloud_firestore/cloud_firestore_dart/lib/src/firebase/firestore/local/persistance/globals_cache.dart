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

import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';

/// General purpose cache for global values (port of the Android `GlobalsCache` and the JS `globals_cache.ts`).
///
/// Global state that cuts across components is saved here. It contains:
///
/// * `sessionToken`, which tracks server interaction across the listen and write streams. This facilitates cache
///   synchronization and invalidation.
///
/// * NOT IN THE OFFICIAL SDKS: the [QueuedWritesMergeMark] of each user's mutation queue, see
///   `LocalStore.startMergingQueuedWrites`.
///
/// As upstream, nothing in the client reads or writes the session token yet: the Firestore protocol has no field that
/// carries it.
abstract class GlobalsCache {
  /// Returns the stored session token, or an empty token when none was stored.
  Future<Uint8List> getSessionToken();

  /// Stores [value] as the session token.
  Future<void> setSessionToken(Uint8List value);

  /// Returns the value stored under [name], or null when there is none.
  ///
  /// PORTING NOTE: not upstream, which reads and writes the session token only. The import of the JS SDK's cache
  /// keeps its record here, in the transaction that adds the imported writes.
  Future<Uint8List?> getValue(String name);

  /// Stores [value] under [name], or removes the entry when [value] is null.
  Future<void> setValue(String name, Uint8List? value);

  /// NOT IN THE OFFICIAL SDKS: the mark of the mutation queue of the user [uid] (the normalized uid, '' for no user),
  /// or null when none was stored.
  Future<QueuedWritesMergeMark?> getQueuedWritesMergeMark(String uid);

  /// NOT IN THE OFFICIAL SDKS: stores [mark] as the mark of the mutation queue of the user [uid].
  Future<void> setQueuedWritesMergeMark(String uid, QueuedWritesMergeMark mark);
}

/// NOT IN THE OFFICIAL SDKS (`mergeUnsentWrites`): the batches of a user's mutation queue up to [batchId] are what the
/// merge of unsent writes at write time would have left of the same writes, so the merge of the queue at start
/// (`LocalStore.startMergingQueuedWrites`) does not look at them again, and resumes after them when it was stopped.
///
/// [localWriteTime] is the local write time of the batch [batchId]. Batch ids start again from 1 once the mutation
/// queues of all users are empty: a queue whose oldest batch has an id up to [batchId] but was written after
/// [localWriteTime] holds new batches with reused ids, and the mark does not apply to it.
class QueuedWritesMergeMark {
  const QueuedWritesMergeMark(this.batchId, this.localWriteTime);

  final int batchId;

  final Timestamp localWriteTime;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QueuedWritesMergeMark &&
          batchId == other.batchId &&
          localWriteTime == other.localWriteTime;

  @override
  int get hashCode => Object.hash(batchId, localWriteTime);

  @override
  String toString() =>
      'QueuedWritesMergeMark{batchId: $batchId, localWriteTime: $localWriteTime}';
}
