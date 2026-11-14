// File created by
// Lung Razvan <long1eu>
// on 04/10/2018

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/empty_credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/datastore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/grpc_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/watch_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart';
import 'package:grpc/grpc.dart';

import '../spec/spec_test_case.dart';

/// A mock version of [Datastore] for SpecTest that allows the test to control
/// the parts that would normally be sent from the backend.
class MockDatastore extends Datastore {
  factory MockDatastore(TaskScheduler scheduler) {
    // The bloom filters in the spec tests are built from document paths of this database.
    final DatabaseId databaseId = DatabaseId.forProject('test-project');
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
      FirestoreClient(GrpcTransport(clientChannel, channelOptionsProvider),
          channelOptionsProvider),
    );
  }

  MockDatastore._(
    DatabaseInfo databaseInfo,
    TaskScheduler scheduler,
    RemoteSerializer serializer,
    FirestoreClient client,
  )   : _serializer = serializer,
        _scheduler = scheduler,
        _client = client,
        super.test(scheduler, databaseInfo, serializer, client);

  /// When true, a watch removal with a cause may name a target that is not active (the spec config
  /// `allowUnlistedTargetRemoval`, used by specs where the server removes a target the client already unlistened).
  bool allowUnlistedTargetRemoval = false;

  /// Called for every target the remote store listens to, after it was recorded: a test can answer like a backend.
  void Function(QueryData queryData)? onWatchQuery;

  final FirestoreClient _client;
  final TaskScheduler _scheduler;
  final RemoteSerializer _serializer;
  late _MockWatchStream _watchStream;

  late _MockWriteStream _writeStream;

  int _writeStreamRequestCount = 0;

  int _watchStreamRequestCount = 0;

  @override
  WatchStream get watchStream =>
      _watchStream = _MockWatchStream(this, _serializer, _scheduler);

  @override
  WriteStream get writeStream =>
      _writeStream = _MockWriteStream(this, _serializer, _scheduler);

  /// How often the backoff of the streams was reset with `inhibitBackoff()`.
  int watchStreamInhibitBackoffCount = 0;
  int writeStreamInhibitBackoffCount = 0;

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

  /// Reports a connection of the open watch stream, as the transport does
  /// when the WebChannel handshake succeeds.
  void connectWatchStream() => _watchStream.addEvent(const ConnectedEvent());

  /// Injects a stream failure as though it had come from the backend.
  void failWatchStream(GrpcError status) {
    _watchStream.failStream(status);
  }

  /// Returns the map of active targets on the watch stream, keyed by target ID.
  Map<int, QueryData> get activeTargets {
    // Make a defensive copy as the watch stream continues to modify the Map of
    // active targets.
    return Map<int, QueryData>.from(_watchStream._activeTargets);
  }

  /// Helper method to expose stream state to verify in tests.
  bool get isWatchStreamOpen => _watchStream.isOpen;

  /// Whether the watch stream waits for its backoff timer
  /// ([TaskId.listenStreamConnectionBackoff]) before it opens again.
  bool get isWatchStreamInBackoff => _watchStream._backoffTask != null;

  /// Runs the pending backoff timer of the watch stream, and only that one
  /// (other timers, such as the online state timeout, stay pending).
  void runWatchStreamBackoff() => _watchStream._runBackoff();
}

class _MockWatchStream extends WatchStream {
  _MockWatchStream(
    this._datastore,
    RemoteSerializer serializer,
    TaskScheduler scheduler,
  ) : super.test(
          _datastore._client,
          scheduler,
          serializer,
          StreamController<StreamEvent>.broadcast(),
        );

  final MockDatastore _datastore;

  bool _open = false;

  /// Set by [failStream]: like a real stream in its error state, the next
  /// [start] goes through the backoff instead of opening at once.
  bool _failed = false;

  /// The pending backoff timer of a [start] after a failure. It is scheduled
  /// on the [TaskScheduler] under [TaskId.listenStreamConnectionBackoff] and
  /// only runs when the test runs it ([MockDatastore.runWatchStreamBackoff], or
  /// `runUntil`), as the JS spec runner does with
  /// `runAllDelayedOperationsUntil`; so a spec can leave the stream
  /// closed in backoff (`watchStreamClose` with `runBackoffTimer: false`).
  TimerTask? _backoffTask;

  /// Long enough never to elapse during a test: only the runner fires it.
  static const Duration _backoffDelay = Duration(days: 1);

  /// Tracks the currently active watch targets as sent over the watch stream.
  final Map<int, QueryData> _activeTargets = <int, QueryData>{};

  @override
  // ignore: must_call_super
  Future<void> start() async {
    hardAssert(!_open, 'Trying to start already started watch stream');
    hardAssert(_backoffTask == null, 'Watch stream is already in backoff');
    if (_failed) {
      _failed = false;
      _backoffTask = _datastore._scheduler.add(
        TaskId.listenStreamConnectionBackoff,
        _backoffDelay,
        _openAfterBackoff,
      );
      return;
    }
    _open = true;

    addEvent(const OpenEvent());
  }

  void _openAfterBackoff() {
    _backoffTask = null;
    _open = true;
    addEvent(const OpenEvent());
  }

  void _runBackoff() {
    final TimerTask? task = _backoffTask;
    hardAssert(task != null, 'The watch stream is not in backoff');
    task!.cancel();
    _openAfterBackoff();
  }

  @override
  Future<void> stop() async {
    await super.stop();
    _backoffTask?.cancel();
    _backoffTask = null;
    _activeTargets.clear();
    _open = false;
  }

  @override
  void inhibitBackoff() {
    _datastore.watchStreamInhibitBackoffCount++;
    _failed = false;
    super.inhibitBackoff();
  }

  @override
  bool get isStarted {
    // A stream waiting for its backoff counts as started, as in [BaseStream].
    return _open || _backoffTask != null;
  }

  @override
  bool get isOpen {
    return _open;
  }

  @override
  void watchQuery(QueryData queryData) {
    final String resumeToken = toDebugString(queryData.resumeToken);
    SpecTestCase.log(
        '      watchQuery(${queryData.target}, ${queryData.targetId}, $resumeToken)');
    // Snapshot version is ignored on the wire
    final QueryData sentQueryData = queryData
        .copyWith(
            snapshotVersion: SnapshotVersion.none,
            resumeToken: queryData.resumeToken,
            sequenceNumber: queryData.sequenceNumber)
        .withExpectedCount(queryData.expectedCount);
    _datastore._watchStreamRequestCount += 1;
    _activeTargets[queryData.targetId] = sentQueryData;
    _datastore.onWatchQuery?.call(sentQueryData);
  }

  @override
  void unwatchTarget(int targetId) {
    SpecTestCase.log('      unwatchTarget($targetId)');
    _activeTargets.remove(targetId);
  }

  /// Injects a stream failure as though it had come from the backend. As the
  /// JS mock connection, the targets of the closed stream are forgotten: the
  /// remote store sends them again when the stream opens again.
  void failStream(GrpcError status) {
    _open = false;
    _failed = true;
    _activeTargets.clear();
    addEvent(CloseEvent(status));
  }

  /// Injects a watch change as though it had come from the backend.
  Future<void> writeWatchChange(
      WatchChange change, SnapshotVersion snapshotVersion) async {
    SnapshotVersion _snapshotVersion = snapshotVersion;
    if (change is WatchChangeWatchTargetChange) {
      final GrpcError? cause = change.cause;
      if (cause != null && cause.code != StatusCode.ok) {
        for (int targetId in change.targetIds) {
          if (!_activeTargets.containsKey(targetId) &&
              !_datastore.allowUnlistedTargetRemoval) {
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
      this._datastore, RemoteSerializer serializer, TaskScheduler scheduler)
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
  void inhibitBackoff() {
    _datastore.writeStreamInhibitBackoffCount++;
    super.inhibitBackoff();
  }

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
