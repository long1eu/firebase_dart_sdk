// File created by
// Lung Razvan <long1eu>
// on 18/09/2018

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/event_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/firestore_client.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view.dart';

/// Describes the online state of the Firestore client. Note that this does not
/// indicate whether or not the remote store is trying to connect or not. This
/// is primarily used by the View/EventManager code to change their behavior
/// while offline (e.g. get() calls shouldn't wait for data from the server and
/// snapshot events should set [SnapshotMetadata.isFromCache] is true).
enum OnlineState {
  /// The Firestore client is in an unknown online state. This means the client
  /// is either not actively trying to establish a connection or it is currently
  /// trying to establish a connection, but it has not succeeded or failed yet.
  ///
  /// Higher-level components (e.g. [View]'s and the [EventManager]) should
  /// likely operate in online mode, waiting until they receive a definitive
  /// [OnlineState.offline] notification before reverting to cache data, etc.
  unknown,

  /// The client is connected and the connections are healthy. This state is
  /// reached after a successful connection and there has been at least one
  /// successful message received from the backends.
  online,

  /// The client is either trying to establish a connection but failing, or it
  /// has been explicitly marked offline via a call to
  /// [FirestoreClient.disableNetwork].
  ///
  /// Higher-level components (e.g. [View]'s and the [EventManager]) should
  /// operate in offline mode.
  offline,
}

/// Where an [OnlineState] change comes from. The primary client of a shared persistence takes it from its remote store
/// and shares it, the other clients take it from the shared client state (their own network is not used).
enum OnlineStateSource {
  /// The online state of the remote store of the client.
  remoteStore,

  /// The online state the primary client shared.
  sharedClientState,
}
