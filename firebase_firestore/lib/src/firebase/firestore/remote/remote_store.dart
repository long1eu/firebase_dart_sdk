// File created by
// Lung Razvan <long1eu>
// on 18/09/2018

import 'package:firebase_database_collection/firebase_database_collection.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/online_state.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/remote_event.dart';
import 'package:grpc/grpc.dart';

/// A callback interface for events from RemoteStore.
abstract class RemoteStoreCallback {
  /// Handle a remote event to the sync engine, notifying any views of the
  /// changes, and releasing any pending mutation batches that would become
  /// visible because of the snapshot version the remote event contains.
  void handleRemoteEvent(RemoteEvent remoteEvent);

  /// Reject the listen for the given [targetId]. This can be triggered by the
  /// backend for any active target.
  ///
  /// The [targetId] corresponding to a listen initiated via listen(). [error]
  /// is a description of the condition that has forced the rejection. Nearly
  /// always this will be an indication that the user is no longer authorized to
  /// see the data matching the target.
  void handleRejectedListen(int targetId, GrpcError error);

  /// Applies the result of a successful write of a mutation batch to the sync
  /// engine, emitting snapshots in any views that the mutation applies to, and
  /// removing the batch from the mutation queue.
  void handleSuccessfulWrite(MutationBatchResult successfulWrite);

  /// Rejects the batch, removing the batch from the mutation queue, recomputing
  /// the local view of any documents affected by the batch and then, emitting
  /// snapshots with the reverted value.
  void handleRejectedWrite(int batchId, GrpcError error);

  /// Called whenever the online state of the client changes. This is based on
  /// the watch stream for now.
  void handleOnlineStateChange(OnlineState onlineState);

  /// Returns the set of remote document keys for the given target ID. This list
  /// includes the documents that were assigned to the target when we received
  /// the last snapshot.
  ///
  /// * Returns an empty set of document keys for unknown targets.
  ImmutableSortedSet<DocumentKey> getRemoteKeysForTarget(int targetId);
}
