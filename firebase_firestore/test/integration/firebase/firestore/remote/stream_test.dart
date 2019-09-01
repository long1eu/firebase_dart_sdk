// File created by
// Lung Razvan <long1eu>
// on 10/10/2018

import 'dart:async';

import 'package:firebase_firestore/src/firebase/firestore/auth/empty_credentials_provider.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/datastore.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/stream.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/watch_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/watch_stream.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/write_stream.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/async_queue.dart';
import 'package:grpc/grpc.dart';
import 'package:meta/meta.dart';
import 'package:test/test.dart';

import '../../../../util/integration_test_util.dart';
import '../../../../util/test_util.dart';

class MockCredentialsProvider extends EmptyCredentialsProvider {
  final List<String> states = <String>[];

  @override
  Future<String> get token {
    states.add('getToken');
    return super.token;
  }

  @override
  void invalidateToken() {
    states.add('invalidateToken');
    super.invalidateToken();
  }
}

void main() {
  /// Single mutation to send to the write stream.
  final List<Mutation> mutations = <Mutation>[setMutation('foo/bar', map())];

  /// Waits for a WriteStream to get into a state that accepts mutations.
  Future<void> waitForWriteStreamOpen(AsyncQueue testQueue,
      WriteStream writeStream, _StreamStatusCallback callback,
      [int i]) async {
    testQueue.enqueueAndForget(writeStream.start);
    await callback.openCompleter.future;
    testQueue.enqueueAndForget(writeStream.writeHandshake);
    await callback.handshakeCompleter.future;
  }

  /// Creates a WriteStream and gets it in a state that accepts mutations.
  Future<WriteStream> createAndOpenWriteStream(
      AsyncQueue testQueue, _StreamStatusCallback callback) async {
    final Datastore datastore = Datastore(
        IntegrationTestUtil.testEnvDatabaseInfo(),
        testQueue,
        EmptyCredentialsProvider());
    final WriteStream writeStream = datastore.createWriteStream(callback);
    await waitForWriteStreamOpen(testQueue, writeStream, callback);
    return writeStream;
  }

  test('testWatchStreamStopBeforeHandshake', () async {
    final AsyncQueue testQueue = AsyncQueue();
    final Datastore datastore = Datastore(
        IntegrationTestUtil.testEnvDatabaseInfo(),
        testQueue,
        EmptyCredentialsProvider());
    final _StreamStatusCallback streamCallback = _StreamStatusCallback();
    final WatchStream watchStream = datastore.createWatchStream(streamCallback);

    testQueue.enqueueAndForget(watchStream.start);
    await streamCallback.openCompleter.future;

    // Stop should call watchStreamStreamDidClose.
    await testQueue.enqueue(watchStream.stop);

    expect(streamCallback.closeCompleter.isCompleted, isTrue);
  });

  test('testWriteStreamStopAfterHandshake', () async {
    final AsyncQueue testQueue = AsyncQueue();
    final Datastore datastore = Datastore(
        IntegrationTestUtil.testEnvDatabaseInfo(),
        testQueue,
        EmptyCredentialsProvider());
    WriteStream writeStreamWrapper;

    final _StreamStatusCallback streamCallback = _StreamStatusCallback();

    streamCallback.copyWith(
      onHandshakeComplete: () {
        expect(writeStreamWrapper.lastStreamToken, isNotEmpty);
        return streamCallback.onHandshakeComplete();
      },
      onWriteResponse: (SnapshotVersion commitVersion,
          List<MutationResult> mutationResults) {
        expect(mutationResults.length, 2);
        expect(writeStreamWrapper.lastStreamToken, isNotEmpty);
        return streamCallback.onWriteResponse(commitVersion, mutationResults);
      },
    );

    final WriteStream writeStream =
        writeStreamWrapper = datastore.createWriteStream(streamCallback);
    testQueue.enqueueAndForget(writeStream.start);
    await streamCallback.openCompleter.future;

    // Writing before the handshake should throw
    testQueue.enqueueAndForget(() async =>
        expect(() => writeStream.writeMutations(mutations), throwsStateError));

    // Handshake should always be called
    testQueue.enqueueAndForget(writeStream.writeHandshake);
    await streamCallback.handshakeCompleter.future;

    // Now writes should succeed
    testQueue
        .enqueueAndForget(() async => writeStream.writeMutations(mutations));
    await streamCallback.responseReceivedCompleter.future;

    await testQueue.enqueue(writeStream.stop);
  });

  /// Verifies that the stream issues an [onClose] callback after a call to
  /// [stop].
  test('testWriteStreamStopPartial', () async {
    final AsyncQueue testQueue = AsyncQueue();
    final Datastore datastore = Datastore(
        IntegrationTestUtil.testEnvDatabaseInfo(),
        testQueue,
        EmptyCredentialsProvider());
    final _StreamStatusCallback streamCallback = _StreamStatusCallback();
    final WriteStream writeStream = datastore.createWriteStream(streamCallback);

    testQueue.enqueueAndForget(writeStream.start);
    await streamCallback.openCompleter.future;

    // Don't start the handshake
    await testQueue.enqueue(writeStream.stop);
    expect(streamCallback.closeCompleter.isCompleted, isTrue);
  });

  test('testWriteStreamStop', () async {
    final AsyncQueue testQueue = AsyncQueue();
    final _StreamStatusCallback streamCallback = _StreamStatusCallback();
    final WriteStream writeStream =
        await createAndOpenWriteStream(testQueue, streamCallback);

    // Stop should call watchStreamStreamDidClose.
    await testQueue.enqueue(writeStream.stop);
    expect(streamCallback.closeCompleter.isCompleted, isTrue);
  });

  test('testStreamClosesWhenIdle', () async {
    final AsyncQueue testQueue = AsyncQueue();
    final _StreamStatusCallback callback = _StreamStatusCallback();
    final WriteStream writeStream =
        await createAndOpenWriteStream(testQueue, callback);

    await testQueue.enqueue(() async {
      writeStream.markIdle();
      expect(testQueue.containsDelayedTask(TimerId.writeStreamIdle), isTrue);
    });

    testQueue.runDelayedTasksUntil(TimerId.writeStreamIdle);
    await callback.closeCompleter.future;
    await testQueue.enqueue(() async => expect(writeStream.isOpen, isFalse));
  });

  test('testStreamCancelsIdleOnWrite', () async {
    final AsyncQueue testQueue = AsyncQueue();
    final WriteStream writeStream =
        await createAndOpenWriteStream(testQueue, _StreamStatusCallback());

    await testQueue.enqueue(() async {
      writeStream
        ..markIdle()
        ..writeMutations(mutations);
    });

    expect(testQueue.containsDelayedTask(TimerId.writeStreamIdle), isFalse);
  });

  test('testStreamStaysIdle', () async {
    final AsyncQueue testQueue = AsyncQueue();
    final WriteStream writeStream =
        await createAndOpenWriteStream(testQueue, _StreamStatusCallback());

    await testQueue.enqueue(() async {
      writeStream.markIdle();
      writeStream.markIdle();
    });

    expect(testQueue.containsDelayedTask(TimerId.writeStreamIdle), isTrue);
  });

  //todo
  // This behaviour is hard to replicate right now, I will get back on this.
  test('testStreamRefreshesTokenUponExpiration', () async {
    final AsyncQueue testQueue = AsyncQueue();
    final MockCredentialsProvider mockCredentialsProvider =
        MockCredentialsProvider();
    final Datastore datastore = Datastore(
        IntegrationTestUtil.testEnvDatabaseInfo(),
        testQueue,
        mockCredentialsProvider);
    final _StreamStatusCallback callback = _StreamStatusCallback();
    final WriteStream writeStream = datastore.createWriteStream(callback);
    await waitForWriteStreamOpen(testQueue, writeStream, callback, 1);

    // Simulate callback from GRPC with an unauthenticated error -- this should
    // invalidate the token.
    await testQueue.enqueue(
        () async => writeStream.handleServerClose(GrpcError.unauthenticated()));
    await waitForWriteStreamOpen(testQueue, writeStream, callback, 2);
    await Future<void>.delayed(const Duration(seconds: 1));

    // Simulate a different error -- token should not be invalidated this time.

    await testQueue.enqueue(
        () async => writeStream.handleServerClose(GrpcError.unavailable()));
    await Future<void>.delayed(const Duration(seconds: 1));
    await waitForWriteStreamOpen(testQueue, writeStream, callback, 3);

    expect(
        mockCredentialsProvider.states,
        orderedEquals(
            <String>['getToken', 'invalidateToken', 'getToken', 'getToken']));
  }, skip: true);
}

/// Callback class that invokes a Completer for each callback.
class _StreamStatusCallback
    implements WatchStreamCallback, WriteStreamCallback {
  final Completer<void> openCompleter;

  final Completer<void> closeCompleter;

  final Completer<void> watchChangeCompleter;

  final Completer<void> handshakeCompleter;

  final Completer<void> responseReceivedCompleter;

  /// The stream is now open and is accepting messages
  @override
  final Task<void> onOpen;

  /// The stream has closed. If there was an error, the status will be != OK.
  @override
  final OnClose onClose;

  /// The handshake for this write stream has completed
  @override
  final Task<void> onHandshakeComplete;

  /// Response for the last write.
  @override
  final OnWriteResponse onWriteResponse;

  /// A new change from the watch stream. Snapshot version will ne non-null if
  /// it was set
  @override
  final OnWatchChange onWatchChange;

  factory _StreamStatusCallback() {
    final Completer<void> openCompleter = Completer<void>();
    final Completer<void> closeCompleter = Completer<void>();
    final Completer<void> watchChangeCompleter = Completer<void>();
    final Completer<void> handshakeCompleter = Completer<void>();
    final Completer<void> responseReceivedCompleter = Completer<void>();

    return _StreamStatusCallback._(
      openCompleter: openCompleter,
      closeCompleter: closeCompleter,
      watchChangeCompleter: watchChangeCompleter,
      handshakeCompleter: handshakeCompleter,
      responseReceivedCompleter: responseReceivedCompleter,
      onWatchChange:
          (SnapshotVersion snapshotVersion, WatchChange watchChange) async =>
              watchChangeCompleter.complete(),
      onClose: (GrpcError error) async => closeCompleter.complete(),
      onWriteResponse: (SnapshotVersion commitVersion,
              List<MutationResult> mutationResults) async =>
          responseReceivedCompleter.complete(),
      onHandshakeComplete: () async => handshakeCompleter.complete(),
      onOpen: () async {
        openCompleter.complete();
      },
    );
  }

  _StreamStatusCallback._({
    @required this.openCompleter,
    @required this.closeCompleter,
    @required this.watchChangeCompleter,
    @required this.handshakeCompleter,
    @required this.responseReceivedCompleter,
    @required this.onOpen,
    @required this.onClose,
    @required this.onHandshakeComplete,
    @required this.onWriteResponse,
    @required this.onWatchChange,
  });

  _StreamStatusCallback copyWith({
    Completer<void> openCompleter,
    Completer<void> closeCompleter,
    Completer<void> watchChangeCompleter,
    Completer<void> handshakeCompleter,
    Completer<void> responseReceivedCompleter,
    Task<void> onOpen,
    OnClose onClose,
    Task<void> onHandshakeComplete,
    OnWriteResponse onWriteResponse,
    OnWatchChange onWatchChange,
  }) {
    return _StreamStatusCallback._(
      openCompleter: openCompleter ?? this.openCompleter,
      closeCompleter: closeCompleter ?? this.closeCompleter,
      watchChangeCompleter: watchChangeCompleter ?? this.watchChangeCompleter,
      handshakeCompleter: handshakeCompleter ?? this.handshakeCompleter,
      responseReceivedCompleter:
          responseReceivedCompleter ?? this.responseReceivedCompleter,
      onOpen: onOpen ?? this.onOpen,
      onClose: onClose ?? this.onClose,
      onHandshakeComplete: onHandshakeComplete ?? this.onHandshakeComplete,
      onWriteResponse: onWriteResponse ?? this.onWriteResponse,
      onWatchChange: onWatchChange ?? this.onWatchChange,
    );
  }
}

// ignore: always_specify_types, type_annotate_public_apis
const testCollectionWithDocs = IntegrationTestUtil.testCollectionWithDocs;
// ignore: always_specify_types, type_annotate_public_apis
const querySnapshotToValues = IntegrationTestUtil.querySnapshotToValues;
// ignore: always_specify_types, type_annotate_public_apis
const testFirestore = IntegrationTestUtil.testFirestore;
// ignore: always_specify_types, type_annotate_public_apis
const writeAllDocs = IntegrationTestUtil.writeAllDocs;
// ignore: always_specify_types, type_annotate_public_apis
const querySnapshotToIds = IntegrationTestUtil.querySnapshotToIds;
// ignore: always_specify_types, type_annotate_public_apis
const testCollection = IntegrationTestUtil.testCollection;
