// File created by
// Lung Razvan <long1eu>
// on 04/10/2018

import 'dart:async';

import 'package:firebase_firestore/src/firebase/firestore/auth/empty_credentials_provider.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/database_info.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_data.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/database_id.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/datastore.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/watch_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/watch_stream.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/write_stream.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/async_queue.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/firestore_channel.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/util.dart';
import 'package:grpc/grpc.dart';
import 'package:grpc/src/shared/status.dart';

import '../spec/spec_test_case.dart';

/// A mock version of [Datastore] for SpecTest that allows the test to control
/// the parts that would normally be sent from the backend.
class MockDatastore extends Datastore {
  _MockWatchStream _watchStream;

  _MockWriteStream _writeStream;

  int _writeStreamRequestCount = 0;

  int _watchStreamRequestCount = 0;

  factory MockDatastore(AsyncQueue workerQueue) {
    final RemoteSerializer serializer =
        RemoteSerializer(DatabaseId.forDatabase('project', 'database'));

    final DatabaseInfo databaseInfo = DatabaseInfo(
      DatabaseId.forDatabase('project', 'database'),
      'persistenceKey',
      'host',
      false,
    );

    final ClientChannel clientChannel = ClientChannel(databaseInfo.host,
        options: ChannelOptions(
            credentials: databaseInfo.sslEnabled
                ? const ChannelCredentials.secure()
                : const ChannelCredentials.insecure()));

    final FirestoreChannel channel = FirestoreChannel(
      workerQueue,
      EmptyCredentialsProvider(),
      clientChannel,
      databaseInfo.databaseId,
    );

    return MockDatastore._(databaseInfo, workerQueue, serializer, channel);
  }

  MockDatastore._(DatabaseInfo databaseInfo, AsyncQueue workerQueue,
      RemoteSerializer serializer, FirestoreChannel channel)
      : super.init(databaseInfo, workerQueue, serializer, channel);

  @override
  WatchStream createWatchStream(WatchStreamCallback listener) {
    _watchStream = _MockWatchStream(this, workerQueue, listener);
    return _watchStream;
  }

  @override
  WriteStream createWriteStream(WriteStreamCallback listener) {
    _writeStream = _MockWriteStream(this, workerQueue, listener);
    return _writeStream;
  }

  int get writeStreamRequestCount => _writeStreamRequestCount;

  int get watchStreamRequestCount => _watchStreamRequestCount;

  /// Returns a previous write that had been 'sent to the backend'.
  List<Mutation> waitForWriteSend() => _writeStream.waitForWriteSend();

  /// Returns the number of writes that have been sent to the backend but not
  /// waited on yet.
  int get writesSent => _writeStream.writesSent;

  /// Injects a write ack as though it had come from the backend in response to
  /// a write.
  Future<void> ackWrite(
      SnapshotVersion commitVersion, List<MutationResult> results) async {
    await _writeStream.ackWrite(commitVersion, results);
  }

  /// Injects a failed write response as though it had come from the backend.
  Future<void> failWrite(GrpcError status) async {
    await _writeStream.failStream(status);
  }

  /// Injects a watch change as though it had come from the backend.
  Future<void> writeWatchChange(
      WatchChange change, SnapshotVersion snapshotVersion) async {
    await _watchStream.writeWatchChange(change, snapshotVersion);
  }

  /// Injects a stream failure as though it had come from the backend.
  Future<void> failWatchStream(GrpcError status) async {
    await _watchStream.failStream(status);
  }

  /// Returns the map of active targets on the watch stream, keyed by target ID.
  Map<int, QueryData> get activeTargets {
    // Make a defensive copy as the watch stream continues to modify the Map of
    // active targets.
    return Map<int, QueryData>.from(_watchStream._activeTargets);
  }

  /// Helper method to expose stream state to verify in tests.
  bool get isWatchStreamOpen => _watchStream.isOpen;
}

class _MockWatchStream extends WatchStream {
  final MockDatastore _datastore;

  bool _open = false;

  /// Tracks the currently active watch targets as sent over the watch stream.
  final Map<int, QueryData> _activeTargets = <int, QueryData>{};

  _MockWatchStream(
      this._datastore, AsyncQueue workerQueue, WatchStreamCallback listener)
      : super(/*channel:*/ null, workerQueue, _datastore.serializer, listener);

  @override
  Future<void> start() async {
    Assert.hardAssert(!_open, 'Trying to start already started watch stream');
    _open = true;
    await listener.onOpen();
  }

  @override
  Future<void> stop() async {
    super.stop();
    _activeTargets.clear();
    _open = false;
  }

  @override
  bool get isStarted {
    return _open;
  }

  @override
  bool get isOpen {
    return _open;
  }

  @override
  void watchQuery(QueryData queryData) {
    final String resumeToken = Util.toDebugString(queryData.resumeToken);
    SpecTestCase.log(
        '      watchQuery(${queryData.query}, ${queryData.targetId}, $resumeToken)');
    // Snapshot version is ignored on the wire
    final QueryData sentQueryData = queryData.copyWith(
        snapshotVersion: SnapshotVersion.none,
        resumeToken: queryData.resumeToken,
        sequenceNumber: queryData.sequenceNumber);
    _datastore._watchStreamRequestCount += 1;
    _activeTargets[queryData.targetId] = sentQueryData;
  }

  @override
  void unwatchTarget(int targetId) {
    SpecTestCase.log('      unwatchTarget($targetId)');
    _activeTargets.remove(targetId);
  }

  /// Injects a stream failure as though it had come from the backend.
  Future<void> failStream(GrpcError status) async {
    _open = false;
    await listener.onClose(status);
  }

  /// Injects a watch change as though it had come from the backend.
  Future<void> writeWatchChange(
      WatchChange change, SnapshotVersion snapshotVersion) async {
    if (change is WatchChangeWatchTargetChange) {
      final WatchChangeWatchTargetChange targetChange = change;
      if (targetChange.cause != null &&
          targetChange.cause.code != StatusCode.ok) {
        for (int targetId in targetChange.targetIds) {
          if (!_activeTargets.containsKey(targetId)) {
            // Technically removing an unknown target is valid (e.g. it could
            // race with a server-side removal), but we want to pay extra
            // careful attention in tests that we only remove targets we
            // listened too.
            throw StateError('Removing a non-active target');
          }
          _activeTargets.remove(targetId);
        }
      }
      if (targetChange.targetIds.isNotEmpty) {
        // If the list of target IDs is not empty, we reset the snapshot version
        // to [none] as done in
        // `RemoteSerializer.decodeVersionFromListenResponse()`.
        snapshotVersion = SnapshotVersion.none;
      }
    }
    await listener.onWatchChange(snapshotVersion, change);
  }
}

class _MockWriteStream extends WriteStream {
  final MockDatastore _datastore;

  bool _open = false;

  /*p*/
  final List<List<Mutation>> sentWrites;

  _MockWriteStream(
      this._datastore, AsyncQueue workerQueue, WriteStreamCallback listener)
      : sentWrites = <List<Mutation>>[],
        super(/*channel=*/ null, workerQueue, _datastore.serializer, listener);

  @override
  Future<void> start() async {
    Assert.hardAssert(!_open, 'Trying to start already started write stream');
    handshakeComplete = false;
    _open = true;
    sentWrites.clear();
    await listener.onOpen();
  }

  @override
  Future<void> stop() async {
    super.stop();
    sentWrites.clear();
    _open = false;
    handshakeComplete = false;
  }

  @override
  bool get isStarted {
    return _open;
  }

  @override
  bool get isOpen {
    return _open;
  }

  @override
  Future<void> writeHandshake() async {
    Assert.hardAssert(!handshakeComplete, 'Handshake already completed');
    _datastore._writeStreamRequestCount += 1;
    handshakeComplete = true;

    await listener.onHandshakeComplete();
  }

  @override
  void writeMutations(List<Mutation> mutations) {
    _datastore._writeStreamRequestCount += 1;
    sentWrites.add(mutations);
  }

  /// Injects a write ack as though it had come from the backend in response to
  /// a write.
  Future<void> ackWrite(
      SnapshotVersion commitVersion, List<MutationResult> results) async {
    await listener.onWriteResponse(commitVersion, results);
  }

  /// Injects a stream failure as though it had come from the backend.
  Future<void> failStream(GrpcError status) async {
    _open = false;
    sentWrites.clear();
    await listener.onClose(status);
  }

  /// Returns a previous write that had been 'sent to the backend'.
  List<Mutation> waitForWriteSend() {
    Assert.hardAssert(sentWrites.isNotEmpty,
        'Writes need to happen before you can wait on them.');
    return sentWrites.removeAt(0);
  }

  /// Returns the number of writes that have been sent to the backend but not
  /// waited on yet.
  int get writesSent => sentWrites.length;
}
