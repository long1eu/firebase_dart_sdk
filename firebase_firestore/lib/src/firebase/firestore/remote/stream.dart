// File created by
// Lung Razvan <long1eu>
// on 24/09/2018

import 'dart:async';

import 'package:grpc/grpc.dart';

/// A Stream is an interface that represents a streaming RPC to the Firestore
/// backend. It's built on top of GRPC's own support for streaming RPCs, and
/// adds several critical features for our clients:
///
/// <ul>
/// <li>Exponential backoff on failure
/// <li>Authentication via CredentialsProvider
/// <li>Dispatching all callbacks into the shared worker queue
/// <li>Closing idle streams after 60 seconds of inactivity
/// </ul>
///
/// * Implementations of Stream should use AbstractStream and provide their own
/// serialization of models to and from the protocol buffers for a specific
/// streaming RPC.
///
/// ## Starting and Stopping
///
/// * Streaming RPCs are stateful and need to be [start]ed before messages can
/// be sent and received. The Stream will call its [onOpen] once the stream is
/// ready to accept requests.
///
/// * Should a [start] fail, Stream will call the [onClose] method of the
/// provided listener.
abstract class Stream<CallbackType extends StreamCallback> {
  /// Returns true if the RPC has been created locally and has started the
  /// process of connecting.
  bool get isStarted;

  /// Returns true if the RPC will accept messages to send.
  bool get isOpen;

  /// Starts the RPC. Only allowed if [isStarted] returns false. The stream is
  /// immediately ready for use.
  ///
  /// * When start returns, [isStarted] will return true.
  Future<void> start();

  /// Stops the RPC. This is guaranteed *not* to call the [onClose] of the
  /// listener in order to ensure that any recovery logic there does not attempt
  /// to reuse the stream.
  ///
  /// * When stop returns [isStarted] will return false.
  Future<void> stop();

  /// After an error the stream will usually back off on the next attempt to
  /// start it. If the error warrants an immediate restart of the stream, the
  /// sender can use this to indicate that the receiver should not back off.
  ///
  /// * Each error will call the [onClose] method of the listener. That listener
  /// can decide to inhibit backoff if required.
  void inhibitBackoff();
}

/// AbstractStream can be in one of 5 states (each described in detail below) based on the
/// following state transition diagram:
///
/// ```
///          start() called             auth & connection succeeded
/// INITIAL ----------------> STARTING -----------------------------> OPEN
///                             ^  |                                   |
///                             |  |                    error occurred |
///                             |  \-----------------------------v-----/
///                             |                                |
///                    backoff  |                                |
///                    elapsed  |              start() called    |
///                             \--- BACKOFF <---------------- ERROR
///
/// [any state] --------------------------> INITIAL
///               stop() called or
///               idle timer expired
/// ```
enum StreamState {
  /// The streaming RPC is not yet running and there is no error condition.
  /// Calling [Stream.start]  will start the stream immediately without backoff.
  /// While in this state [isStarted] will return false.
  Initial,

  /// The stream is starting, either waiting for an auth token or for the stream
  /// to successfully open. While in this state, [Stream.isStarted] will return
  /// true but [Stream.isOpen] will return false.
  ///
  /// * Porting Note: Auth is handled transparently by gRPC in this
  /// implementation, so this state is used as intermediate state until the
  /// [Stream.onOpen] callback is called.
  Starting,

  /// The streaming RPC is up and running. Requests and responses can flow
  /// freely. Both [Stream.isStarted] and [Stream.isOpen] will return true.
  Open,

  /// The stream encountered an error. The next start attempt will back off.
  /// While in this state [Stream.isStarted] will return false.
  Error,

  /// An in-between state after an error where the stream is waiting before
  /// re-starting. After waiting is complete, the stream will try to open. While
  /// in this state [Stream.isStarted] will return true but [Stream.isOpen] will
  /// return false.
  Backoff,
}

/// A (super-interface) for the stream callbacks. Implementations of Stream
/// should provide their own interface that extends this interface.
class StreamCallback {
  /// The stream is now open and is accepting messages
  final Future<void> Function() onOpen;

  /// The stream has closed. If there was an error, the status will be != OK.
  final Future<void> Function(GrpcError) onClose;

  const StreamCallback({this.onOpen, this.onClose});
}
