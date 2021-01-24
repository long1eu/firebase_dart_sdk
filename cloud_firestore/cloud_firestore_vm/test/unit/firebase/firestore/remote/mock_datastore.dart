// File created by
// Lung Razvan <long1eu>
// on 04/10/2018

import 'dart:async';

import 'package:cloud_firestore_vm/src/firebase/firestore/auth/empty_credentials_provider.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/target_data.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/datastore/datastore.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/watch_change.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/async_task.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/util.dart';
import 'package:grpc/grpc.dart';
import 'package:grpc/src/shared/status.dart';

import '../spec/spec_test_case.dart';

/// A mock version of [Datastore] for SpecTest that allows the test to control
/// the parts that would normally be sent from the backend.
class MockDatastore extends Datastore {
  factory MockDatastore(AsyncQueue scheduler) {
    final DatabaseId databaseId = DatabaseId.forDatabase('project', 'database');
    final RemoteSerializer serializer = RemoteSerializer(databaseId);
    final DatabaseInfo databaseInfo =
        DatabaseInfo(databaseId, 'persistenceKey', 'host', sslEnabled: false);

    final ClientChannel clientChannel = ClientChannel(databaseInfo.host,
        options:
            const ChannelOptions(credentials: ChannelCredentials.insecure()));

    final ChannelOptionsProvider channelOptionsProvider =
        ChannelOptionsProvider(
            databaseId: databaseId,
            credentialsProvider: EmptyCredentialsProvider());
    return MockDatastore._(
      databaseInfo,
      scheduler,
      serializer,
      FirestoreClient(clientChannel, channelOptionsProvider),
    );
  }

  MockDatastore._(
    DatabaseInfo databaseInfo,
    AsyncQueue scheduler,
    RemoteSerializer serializer,
    FirestoreClient client,
  )   : _serializer = serializer,
        _scheduler = scheduler,
        _client = client,
        super.test(scheduler, databaseInfo, serializer, client);

  final FirestoreClient _client;
  final AsyncQueue _scheduler;
  final RemoteSerializer _serializer;
  _MockWatchStream _watchStream;

  _MockWriteStream _writeStream;

  int _writeStreamRequestCount = 0;

  int _watchStreamRequestCount = 0;

  @override
  WatchStream get watchStream =>
      _watchStream = _MockWatchStream(this, _serializer, _scheduler);

  @override
  WriteStream get writeStream =>
      _writeStream = _MockWriteStream(this, _serializer, _scheduler);

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
  void failWatchStream(GrpcError status) {
    _watchStream.failStream(status);
  }

  /// Returns the map of active targets on the watch stream, keyed by target ID.
  Map<int, TargetData> get activeTargets {
    // Make a defensive copy as the watch stream continues to modify the Map of
    // active targets.
    return Map<int, TargetData>.from(_watchStream._activeTargets);
  }

  /// Helper method to expose stream state to verify in tests.
  bool get isWatchStreamOpen => _watchStream.isOpen;
}

class _MockWatchStream extends WatchStream {
  _MockWatchStream(
    this._datastore,
    RemoteSerializer serializer,
    AsyncQueue scheduler,
  ) : super.test(
          _datastore._client,
          scheduler,
          serializer,
          StreamController<StreamEvent>.broadcast(),
        );

  final MockDatastore _datastore;

  bool _open = false;

  /// Tracks the currently active watch targets as sent over the watch stream.
  final Map<int, TargetData> _activeTargets = <int, TargetData>{};

  @override
  // ignore: must_call_super
  Future<void> start() async {
    hardAssert(!_open, 'Trying to start already started watch stream');
    _open = true;

    addEvent(const OpenEvent());
  }

  @override
  Future<void> stop() async {
    await super.stop();
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
  void watchQuery(TargetData queryData) {
    final String resumeToken = toDebugString(queryData.resumeToken);
    SpecTestCase.log(
        '      watchQuery(${queryData.target}, ${queryData.targetId}, $resumeToken)');
    // Snapshot version is ignored on the wire
    final TargetData sentQueryData = queryData.copyWith(
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
  void failStream(GrpcError status) {
    _open = false;
    addEvent(CloseEvent(status));
  }

  /// Injects a watch change as though it had come from the backend.
  Future<void> writeWatchChange(
      WatchChange change, SnapshotVersion snapshotVersion) async {
    SnapshotVersion _snapshotVersion = snapshotVersion;
    if (change is WatchChangeWatchTargetChange) {
      if (change.cause != null && change.cause.code != StatusCode.ok) {
        for (int targetId in change.targetIds) {
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

      if (change.targetIds.isNotEmpty) {
        // If the list of target IDs is not empty, we reset the snapshot version
        // to [none] as done in
        // `RemoteSerializer.decodeVersionFromListenResponse()`.
        _snapshotVersion = SnapshotVersion.none;
      }
    }

    addEvent(OnWatchChange(_snapshotVersion, change));
  }
}

class _MockWriteStream extends WriteStream {
  _MockWriteStream(
      this._datastore, RemoteSerializer serializer, AsyncQueue scheduler)
      : _sentWrites = <List<Mutation>>[],
        super.test(
          _datastore._client,
          scheduler,
          serializer,
          StreamController<StreamEvent>.broadcast(),
        );

  final MockDatastore _datastore;

  bool _open = false;

  final List<List<Mutation>> _sentWrites;

  @override
  // ignore: must_call_super
  Future<void> start() async {
    hardAssert(!_open, 'Trying to start already started write stream');
    handshakeComplete = false;
    _open = true;
    _sentWrites.clear();

    addEvent(const OpenEvent());
  }

  @override
  Future<void> stop() async {
    await super.stop();
    _sentWrites.clear();
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
    hardAssert(!handshakeComplete, 'Handshake already completed');
    _datastore._writeStreamRequestCount += 1;
    handshakeComplete = true;

    addEvent(const HandshakeCompleteEvent());
  }

  @override
  void writeMutations(List<Mutation> mutations) {
    _datastore._writeStreamRequestCount += 1;
    _sentWrites.add(mutations);
  }

  /// Injects a write ack as though it had come from the backend in response to
  /// a write.
  Future<void> ackWrite(
      SnapshotVersion commitVersion, List<MutationResult> results) async {
    addEvent(OnWriteResponse(commitVersion, results));
  }

  /// Injects a stream failure as though it had come from the backend.
  Future<void> failStream(GrpcError status) async {
    _open = false;
    _sentWrites.clear();

    addEvent(CloseEvent(status));
  }

  /// Returns a previous write that had been 'sent to the backend'.
  List<Mutation> waitForWriteSend() {
    hardAssert(_sentWrites.isNotEmpty,
        'Writes need to happen before you can wait on them.');
    return _sentWrites.removeAt(0);
  }

  /// Returns the number of writes that have been sent to the backend but not
  /// waited on yet.
  int get writesSent => _sentWrites.length;
}
