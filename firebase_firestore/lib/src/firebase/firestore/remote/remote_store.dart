// File created by
// Lung Razvan <long1eu>
// on 18/09/2018

import 'dart:async';
import 'dart:collection';

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_database_collection/firebase_database_collection.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/online_state.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/transaction.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/local_store.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_data.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_purpose.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/datastore.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/online_state_tracker.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/remote_event.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/target_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/watch_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/watch_change_aggregator.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/watch_stream.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/write_stream.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/async_queue.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/util.dart';
import 'package:grpc/grpc.dart';

/// [RemoteStore] handles all interaction with the backend through a simple,
/// clean interface. This class is not thread safe and should be only called
/// from the worker [AsyncQueue].
class RemoteStore implements TargetMetadataProvider {
  /// The maximum number of pending writes to allow.
  /// TODO: Negotiate this value with the backend.
  /*private*/
  static final int MAX_PENDING_WRITES = 10;

  /// The log tag to use for this class.
  /*private*/
  static final String _tag = "RemoteStore";

  /*private*/
  final RemoteStoreCallback remoteStoreCallback;

  /*private*/
  final LocalStore localStore;

  /*private*/
  final Datastore datastore;

  /// A mapping of watched targets that the client cares about tracking and the
  /// user has explicitly called a 'listen' for this target.
  ///
  /// * These targets may or may not have been sent to or acknowledged by the
  /// server. On re-establishing the listen stream, these targets should be sent
  /// to the server. The targets removed with unlistens are removed eagerly
  /// without waiting for confirmation from the listen stream.
  /*private*/
  final Map<int, QueryData> listenTargets;

  /*private*/
  final OnlineStateTracker onlineStateTracker;

  /*private*/
  WatchStream watchStream;

  /*private*/
  WriteStream writeStream;

  /*private*/
  bool networkEnabled = false;

  /*private*/
  WatchChangeAggregator watchChangeAggregator;

  /// A list of up to [MAX_PENDING_WRITES] writes that we have fetched from the
  /// [LocalStore] via [fillWritePipeline] and have or will send to the write
  /// stream.
  ///
  /// * Whenever [writePipeline.length] > 0 the [RemoteStore] will attempt to
  /// start or restart the write stream. When the stream is established the
  /// writes in the pipeline will be sent in order.
  ///
  /// * Writes remain in [writePipeline] until they are acknowledged by the
  /// backend and thus will automatically be re-sent if the stream is
  /// interrupted / restarted before they're acknowledged.
  ///
  /// * Write responses from the backend are linked to their originating request
  /// purely based on order, and so we can just poll() writes from the front of
  /// the [writePipeline] as we receive responses.
  /*private*/
  final Queue<MutationBatch> writePipeline;

  RemoteStore(this.remoteStoreCallback, this.localStore, this.datastore,
      AsyncQueue workerQueue)
      : listenTargets = {},
        writePipeline = Queue<MutationBatch>(),
        onlineStateTracker = new OnlineStateTracker(
          workerQueue,
          remoteStoreCallback.handleOnlineStateChange,
        ) {
    // Create new streams (but note they're not started yet).
    watchStream = datastore.createWatchStream(WatchStreamCallback(
      onOpen: handleWatchStreamOpen,
      onClose: handleWatchStreamClose,
      onWatchChange: handleWatchChange,
    ));

    writeStream = datastore.createWriteStream(WriteStreamCallback(
      onOpen: writeStream.writeHandshake,
      onClose: handleWriteStreamClose,
      onHandshakeComplete: handleWriteStreamHandshakeComplete,
      onWriteResponse: handleWriteStreamMutationResults,
    ));
  }

  RemoteStore._(
    this.remoteStoreCallback,
    this.localStore,
    this.datastore,
    this.listenTargets,
    this.onlineStateTracker,
    this.watchStream,
    this.writeStream,
    this.writePipeline,
  );

  /// Re-enables the network. Only to be called as the counterpart to
  /// [disableNetwork].
  Future<void> enableNetwork() async {
    networkEnabled = true;

    if (canUseNetwork()) {
      writeStream.lastStreamToken = localStore.getLastStreamToken();

      if (shouldStartWatchStream()) {
        startWatchStream();
      } else {
        onlineStateTracker.updateState(OnlineState.unknown);
      }

      // This will start the write stream if necessary.
      await fillWritePipeline();
    }
  }

  /// Temporarily disables the network. The network can be re-enabled using
  /// [enableNetwork].
  void disableNetwork() {
    networkEnabled = false;
    disableNetworkInternal();

    // Set the OnlineState to OFFLINE so get()s return from cache, etc.
    onlineStateTracker.updateState(OnlineState.offline);
  }

  /*private*/
  void disableNetworkInternal() {
    watchStream.stop();
    writeStream.stop();

    if (!writePipeline.isEmpty) {
      Log.d(_tag,
          'Stopping write stream with ${writePipeline.length} pending writes');
      writePipeline.clear();
    }

    cleanUpWatchStreamState();
  }

  /// Starts up the remote store, creating streams, restoring state from
  /// [LocalStore], etc. This should called before using any other API endpoints
  /// in this class.
  Future<void> start() async {
    // For now, all setup is handled by enableNetwork(). We might expand on this
    // in the future.
    await enableNetwork();
  }

  /// Shuts down the remote store, tearing down connections and otherwise cleaning up. This is not
  /// reversible and renders the Remote Store unusable.
  void shutdown() {
    Log.d(_tag, 'Shutting down');
    // For now, all shutdown logic is handled by disableNetworkInternal(). We
    // might expand on this in the future.
    networkEnabled = false;
    this.disableNetworkInternal();
    // Set the OnlineState to UNKNOWN (rather than OFFLINE) to avoid potentially
    // triggering spurious listener events with cached data, etc.
    onlineStateTracker.updateState(OnlineState.unknown);
  }

  /// Tells the [RemoteStore] that the currently authenticated user has changed.
  ///
  /// * In response the remote store tears down streams and clears up any
  /// tracked operations that should not persist across users. Restarts the
  /// streams if appropriate.
  Future<void> handleCredentialChange() async {
    // If the network has been explicitly disabled, make sure we don't
    // accidentally re-enable it.
    if (canUseNetwork()) {
      // Tear down and re-create our network streams. This will ensure we get a
      // fresh auth token for the new user and re-fill the write pipeline with
      // new mutations from the [LocalStore] (since mutations are per-user).
      Log.d(_tag, 'Restarting streams for new credential.');
      networkEnabled = false;
      disableNetworkInternal();
      onlineStateTracker.updateState(OnlineState.unknown);
      await enableNetwork();
    }
  }

  // Watch Stream

  /// Listens to the target identified by the given [QueryData]. */
  void listen(QueryData queryData) {
    final int targetId = queryData.targetId;
    Assert.hardAssert(!listenTargets.containsKey(targetId),
        'listen called with duplicate target ID: $targetId');

    listenTargets[targetId] = queryData;

    if (shouldStartWatchStream()) {
      startWatchStream();
    } else if (watchStream.isOpen) {
      sendWatchRequest(queryData);
    }
  }

  /*private*/
  void sendWatchRequest(QueryData queryData) {
    watchChangeAggregator.recordPendingTargetRequest(queryData.targetId);
    watchStream.watchQuery(queryData);
  }

  /// Stops listening to the target with the given target ID.
  ///
  /// * If this is called with the last active targetId, the watch stream enters
  /// idle mode and will be torn down after one minute of inactivity.
  void stopListening(int targetId) {
    QueryData queryData = listenTargets.remove(targetId);
    Assert.hardAssert(queryData != null,
        'stopListening called on target no currently watched: $targetId');

    // The watch stream might not be started if we're in a disconnected state
    if (watchStream.isOpen) {
      sendUnwatchRequest(targetId);
    }

    if (listenTargets.isEmpty) {
      if (watchStream.isOpen) {
        watchStream.markIdle();
      } else if (this.canUseNetwork()) {
        // Revert to [OnlineState.unknown] if the watch stream is not open and
        // we have no listeners, since without any listens to send we cannot
        // confirm if the stream is healthy and upgrade to [OnlineState.online].
        this.onlineStateTracker.updateState(OnlineState.unknown);
      }
    }
  }

  /*private*/
  void sendUnwatchRequest(int targetId) {
    watchChangeAggregator.recordPendingTargetRequest(targetId);
    watchStream.unwatchTarget(targetId);
  }

  /// Returns true if the network is enabled, the write stream has not yet been
  /// started and there are pending writes.
  /*private*/
  bool shouldStartWriteStream() {
    return canUseNetwork() && !writeStream.isStarted && !writePipeline.isEmpty;
  }

  /// Returns true if the network is enabled, the watch stream has not yet been
  /// started and there are active watch targets.
  /*private*/
  bool shouldStartWatchStream() {
    return canUseNetwork() && !watchStream.isStarted && !listenTargets.isEmpty;
  }

  /*private*/
  void cleanUpWatchStreamState() {
    // If the connection is closed then we'll never get a snapshot version for
    // the accumulated changes and so we'll never be able to complete the batch.
    // When we start up again the server is going to resend these changes
    // anyway, so just toss the accumulated state.
    watchChangeAggregator = null;
  }

  /*private*/
  void startWatchStream() {
    Assert.hardAssert(shouldStartWatchStream(),
        'startWatchStream() called when shouldStartWatchStream() is false.');
    watchChangeAggregator = new WatchChangeAggregator(this);
    watchStream.start();

    onlineStateTracker.handleWatchStreamStart();
  }

  /*private*/
  void handleWatchStreamOpen() {
    // Restore any existing watches.
    for (QueryData queryData in listenTargets.values) {
      sendWatchRequest(queryData);
    }
  }

  /*private*/
  Future<void> handleWatchChange(
      SnapshotVersion snapshotVersion, WatchChange watchChange) async {
    // Mark the connection as ONLINE because we got a message from the server.
    onlineStateTracker.updateState(OnlineState.online);

    Assert.hardAssert((watchStream != null) && (watchChangeAggregator != null),
        'WatchStream and WatchStreamAggregator should both be non-null');

    WatchChangeWatchTargetChange watchTargetChange =
        watchChange is WatchChangeWatchTargetChange ? watchChange : null;

    if (watchTargetChange != null &&
        watchTargetChange.changeType == WatchTargetChangeType.Removed &&
        watchTargetChange.cause != null) {
      // There was an error on a target, don't wait for a consistent snapshot to
      // raise events
      await processTargetError(watchTargetChange);
    } else {
      if (watchChange is WatchChangeDocumentChange) {
        watchChangeAggregator.handleDocumentChange(watchChange);
      } else if (watchChange is WatchChangeExistenceFilterWatchChange) {
        watchChangeAggregator.handleExistenceFilter(watchChange);
      } else {
        Assert.hardAssert(watchChange is WatchChangeWatchTargetChange,
            'Expected watchChange to be an instance of WatchTargetChange');
        watchChangeAggregator.handleTargetChange(watchChange);
      }

      if (snapshotVersion != SnapshotVersion.none) {
        SnapshotVersion lastRemoteSnapshotVersion =
            this.localStore.getLastRemoteSnapshotVersion();
        if (snapshotVersion.compareTo(lastRemoteSnapshotVersion) >= 0) {
          // We have received a target change with a global snapshot if the
          // snapshot version is not equal to SnapshotVersion.MIN.
          await raiseWatchSnapshot(snapshotVersion);
        }
      }
    }
  }

  /*private*/
  void handleWatchStreamClose(GrpcError status) {
    if (status.code == StatusCode.ok) {
      // Graceful stop (due to stop() or idle timeout). Make sure that's
      // desirable.
      Assert.hardAssert(!shouldStartWatchStream(),
          'Watch stream was stopped gracefully while still needed.');
    }

    cleanUpWatchStreamState();

    // If we still need the watch stream, retry the connection.
    if (shouldStartWatchStream()) {
      onlineStateTracker.handleWatchStreamFailure(status);

      startWatchStream();
    } else {
      // We don't need to restart the watch stream because there are no active
      // targets. The online state is set to unknown because there is no active
      // attempt at establishing a connection.
      onlineStateTracker.updateState(OnlineState.unknown);
    }
  }

  /*private*/
  bool canUseNetwork() {
    // PORTING NOTE: This method exists mostly because web also has to take into
    // account primary vs. secondary state.
    return networkEnabled;
  }

  /// Takes a batch of changes from the [Datastore], repackages them as a
  /// [RemoteEvent], and passes that on to the listener, which is typically the
  /// [SyncEngine].
  /*private*/
  Future<void> raiseWatchSnapshot(SnapshotVersion snapshotVersion) async {
    Assert.hardAssert(snapshotVersion != SnapshotVersion.none,
        'Can\'t raise event for unknown SnapshotVersion');
    final RemoteEvent remoteEvent =
        watchChangeAggregator.createRemoteEvent(snapshotVersion);

    // Update in-memory resume tokens. [LocalStore] will update the persistent
    // view of these when applying the completed [RemoteEvent].
    for (MapEntry<int, TargetChange> entry
        in remoteEvent.targetChanges.entries) {
      final TargetChange targetChange = entry.value;
      if (targetChange.resumeToken.isNotEmpty) {
        final int targetId = entry.key;
        final QueryData queryData = this.listenTargets[targetId];
        // A watched target might have been removed already.
        if (queryData != null) {
          this.listenTargets[targetId] = queryData.copy(snapshotVersion,
              targetChange.resumeToken, queryData.sequenceNumber);
        }
      }
    }

    // Re-establish listens for the targets that have been invalidated by
    // existence filter mismatches.
    for (int targetId in remoteEvent.targetMismatches) {
      final QueryData queryData = this.listenTargets[targetId];
      // A watched target might have been removed already.
      if (queryData != null) {
        // Clear the resume token for the query, since we're in a known mismatch
        // state.
        this.listenTargets[targetId] = queryData.copy(
            queryData.snapshotVersion, <int>[], queryData.sequenceNumber);

        // Cause a hard reset by unwatching and rewatching immediately, but
        // deliberately don't send a resume token so that we get a full update.
        this.sendUnwatchRequest(targetId);

        // Mark the query we send as being on behalf of an existence filter
        // mismatch, but don't actually retain that in [listenTargets]. This
        // ensures that we flag the first re-listen this way without impacting
        // future listens of this target (that might happen e.g. on reconnect).
        final QueryData requestQueryData = new QueryData.init(
          queryData.query,
          targetId,
          queryData.sequenceNumber,
          QueryPurpose.existenceFilterMismatch,
        );
        this.sendWatchRequest(requestQueryData);
      }
    }

    // Finally raise remote event
    await remoteStoreCallback.handleRemoteEvent(remoteEvent);
  }

  /*private*/
  Future<void> processTargetError(
      WatchChangeWatchTargetChange targetChange) async {
    Assert.hardAssert(
        targetChange.cause != null, 'Processing target error without a cause');
    for (int targetId in targetChange.targetIds) {
      // Ignore targets that have been removed already.
      if (listenTargets.containsKey(targetId)) {
        listenTargets.remove(targetId);
        watchChangeAggregator.removeTarget(targetId);
        await remoteStoreCallback.handleRejectedListen(
            targetId, targetChange.cause);
      }
    }
  }

  // Write Stream

  /// Attempts to fill our write pipeline with writes from the [LocalStore].
  ///
  /// * Called internally to bootstrap or refill the write pipeline by
  /// [SyncEngine] whenever there are new mutations to process.
  ///
  /// * Starts the write stream if necessary.
  Future<void> fillWritePipeline() async {
    int lastBatchIdRetrieved = writePipeline.isEmpty
        ? MutationBatch.unknown
        : writePipeline.last.batchId;
    while (canAddToWritePipeline()) {
      final MutationBatch batch =
          await localStore.getNextMutationBatch(lastBatchIdRetrieved);
      if (batch == null) {
        if (writePipeline.isEmpty) {
          writeStream.markIdle();
        }
        break;
      }
      addToWritePipeline(batch);
      lastBatchIdRetrieved = batch.batchId;
    }

    if (shouldStartWriteStream()) {
      startWriteStream();
    }
  }

  /// Returns true if we can add to the write pipeline (i.e. it is not full and
  /// the network is enabled).
  /*private*/
  bool canAddToWritePipeline() {
    return canUseNetwork() && writePipeline.length < MAX_PENDING_WRITES;
  }

  /// Queues additional writes to be sent to the write stream, sending them
  /// immediately if the write stream is established.
  /*private*/
  void addToWritePipeline(MutationBatch mutationBatch) {
    Assert.hardAssert(canAddToWritePipeline(),
        'addToWritePipeline called when pipeline is full');

    writePipeline.add(mutationBatch);

    if (writeStream.isOpen && writeStream.isHandshakeComplete) {
      writeStream.writeMutations(mutationBatch.mutations);
    }
  }

  /*private*/
  void startWriteStream() {
    Assert.hardAssert(shouldStartWriteStream(),
        'startWriteStream() called when shouldStartWriteStream() is false.');
    writeStream.start();
  }

  /// Handles a successful handshake response from the server, which is our cue
  /// to send any pending writes.
  /*private*/
  void handleWriteStreamHandshakeComplete() {
    // Record the stream token.
    localStore.setLastStreamToken(writeStream.lastStreamToken);

    // Send the write pipeline now that stream is established.
    for (MutationBatch batch in writePipeline) {
      writeStream.writeMutations(batch.mutations);
    }
  }

  /// Handles a successful [StreamingWriteResponse] from the server that
  /// contains a mutation result.
  /*private*/
  Future<void> handleWriteStreamMutationResults(
      SnapshotVersion commitVersion, List<MutationResult> results) async {
    // This is a response to a write containing mutations and should be
    // correlated to the first write in our write pipeline.
    final MutationBatch batch = writePipeline.removeFirst();

    final MutationBatchResult mutationBatchResult = MutationBatchResult.create(
        batch, commitVersion, results, writeStream.lastStreamToken);
    await remoteStoreCallback.handleSuccessfulWrite(mutationBatchResult);

    // It's possible that with the completion of this mutation another slot has
    // freed up.
    await fillWritePipeline();
  }

  /*private*/
  Future<void> handleWriteStreamClose(GrpcError status) async {
    if (status.code == StatusCode.ok) {
      // Graceful stop (due to stop() or idle timeout). Make sure that's
      // desirable.
      Assert.hardAssert(!shouldStartWatchStream(),
          'Write stream was stopped gracefully while still needed.');
    }

    // If the write stream closed due to an error, invoke the error callbacks
    // if there are pending writes.
    if (status.code != StatusCode.ok && writePipeline.isNotEmpty) {
      // TODO: handle UNAUTHENTICATED status, see go/firestore-client-errors
      if (writeStream.isHandshakeComplete) {
        // This error affects the actual writes
        await handleWriteError(status);
      } else {
        // If there was an error before the handshake has finished, it's
        // possible that the server is unable to process the stream token we're
        // sending. (Perhaps it's too old?)
        await handleWriteHandshakeError(status);
      }
    }

    // The write stream may have already been restarted by refilling the write
    // pipeline for failed writes. In that case, we don't want to start the
    // write stream again.
    if (shouldStartWriteStream()) {
      startWriteStream();
    }
  }

  /*private*/
  Future<void> handleWriteHandshakeError(GrpcError status) async {
    Assert.hardAssert(
        status.code != StatusCode.ok, 'Handling write error with status OK.');
    // Reset the token if it's a permanent error or the error code is ABORTED,
    // signaling the write stream is no longer valid.
    if (Datastore.isPermanentWriteError(status) ||
        status.code == StatusCode.aborted) {
      final String token = Util.toDebugString(writeStream.lastStreamToken);
      Log.d(_tag,
          'RemoteStore error before completed handshake; resetting stream token $token: $status');
      writeStream.lastStreamToken = WriteStream.EMPTY_STREAM_TOKEN;
      await localStore.setLastStreamToken(WriteStream.EMPTY_STREAM_TOKEN);
    }
  }

  /*private*/
  Future<void> handleWriteError(GrpcError status) async {
    Assert.hardAssert(
        status.code != StatusCode.ok, 'Handling write error with status OK.');
    // Only handle permanent error, if it's transient just let the retry logic
    // kick in.
    if (Datastore.isPermanentWriteError(status)) {
      // If this was a permanent error, the request itself was the problem so
      // it's not going to succeed if we resend it.
      final MutationBatch batch = writePipeline.removeFirst();

      // In this case it's also unlikely that the server itself is melting down
      // -- this was just a bad request, so inhibit backoff on the next restart
      writeStream.inhibitBackoff();

      await remoteStoreCallback.handleRejectedWrite(batch.batchId, status);

      // It's possible that with the completion of this mutation another slot
      // has freed up.
      await fillWritePipeline();
    }
  }

  Transaction createTransaction() => Transaction(datastore);

  @override
  ImmutableSortedSet<DocumentKey> getRemoteKeysForTarget(int targetId) {
    return this.remoteStoreCallback.getRemoteKeysForTarget(targetId);
  }

  @override
  QueryData getQueryDataForTarget(int targetId) => listenTargets[targetId];
}

/// A callback interface for events from RemoteStore.
abstract class RemoteStoreCallback {
  /// Handle a remote event to the sync engine, notifying any views of the
  /// changes, and releasing any pending mutation batches that would become
  /// visible because of the snapshot version the remote event contains.
  Future<void> handleRemoteEvent(RemoteEvent remoteEvent);

  /// Reject the listen for the given [targetId]. This can be triggered by the
  /// backend for any active target.
  ///
  /// The [targetId] corresponding to a listen initiated via listen(). [error]
  /// is a description of the condition that has forced the rejection. Nearly
  /// always this will be an indication that the user is no longer authorized to
  /// see the data matching the target.
  Future<void> handleRejectedListen(int targetId, GrpcError error);

  /// Applies the result of a successful write of a mutation batch to the sync
  /// engine, emitting snapshots in any views that the mutation applies to, and
  /// removing the batch from the mutation queue.
  Future<void> handleSuccessfulWrite(MutationBatchResult successfulWrite);

  /// Rejects the batch, removing the batch from the mutation queue, recomputing
  /// the local view of any documents affected by the batch and then, emitting
  /// snapshots with the reverted value.
  Future<void> handleRejectedWrite(int batchId, GrpcError error);

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
