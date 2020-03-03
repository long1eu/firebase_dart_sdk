// File created by
// Lung Razvan <long1eu>
// on 04/10/2018

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_common/firebase_common.dart';
import 'package:_firebase_database_collection_vm/_firebase_database_collection_vm.dart';
import 'package:firebase_firestore/src/firebase/firestore/auth/user.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/document_view_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/event_manager.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/online_state.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query_listener.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/sync_engine.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/view_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore_error.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/local_store.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/persistence.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_data.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_purpose.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/sqlite_persistence.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/resource_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/existence_filter.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/remote_event.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/remote_store.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/watch_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart' as asserts;
import 'package:firebase_firestore/src/firebase/firestore/util/async_queue.dart';
import 'package:grpc/grpc.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';
import '../local/mock/database_mock.dart';
import '../remote/mock_datastore.dart';
import 'query_event.dart';

const Duration _delayDuration = Duration(milliseconds: 0);

class SpecTestCase implements RemoteStoreCallback {
  SpecTestCase(this.getPersistence, this.isExcluded);

  /// Set this to true when debugging test failures.
  static const bool _debug = true;
  static const bool _runBenchmarkTests = false;

  // Disables all other tests; useful for debugging. Multiple tests can have this tag and they'll all be run (but all
  // others won't).
  static const String exclusiveTag = 'exclusive';

  // Tags on tests that should be excluded from execution, useful to allow the platforms to temporarily diverge or for
  // features that are designed to be platform specific (such as 'multi-client').
  static final Set<String> _disabledTags =
      _runBenchmarkTests ? <String>{'no-android', 'multi-client'} : <String>{'no-android', 'benchmark', 'multi-client'};

  final Future<Persistence> Function(bool garbageCollectionEnabled, String name) getPersistence;
  final bool Function(Set<String> tags) isExcluded;

  String currentName;

  bool _garbageCollectionEnabled;
  bool _networkEnabled = true;

  // Parts of the Firestore system that the spec tests need to control.

  Persistence _localPersistence;
  AsyncQueue _queue;
  MockDatastore _datastore;
  RemoteStore _remoteStore;
  SyncEngine _syncEngine;
  EventManager _eventManager;

  /// Events to be checked by the expectations.
  List<QueryEvent> _events;

  /// A dictionary for tracking the listens on queries. Note that the identity of the listeners is used to remove them.
  Map<Query, QueryListener> _queryListeners;

  /// Set of documents that are expected to be in limbo. Verified at every step.
  Set<DocumentKey> _expectedLimboDocs;

  /// Set of expected active targets, keyed by target ID.
  Map<int, QueryData> _expectedActiveTargets;

  /// The writes that have been sent to the [SyncEngine] via [SyncEngine.writeMutations] but not yet acknowledged by
  /// calling receiveWriteAck/Error. They are tracked per-user.
  ///
  /// It is mostly an implementation detail used internally to validate that the writes sent to the mock backend by the
  /// [SyncEngine] match the user mutations that initiated them.
  ///
  /// It is exposed specifically for use [_doRestart] to test persistence scenarios where the [SyncEngine] is restarted
  /// while the [Persistence] implementation still has outstanding persisted mutations.
  ///
  /// Note: The size of the list for the current user will generally be the same as [_writesSent], but not necessarily,
  /// since the [RemoteStore] limits the number of outstanding writes to the backend at a given time.
  Map<User, List<Pair<Mutation, Future<void>>>> _outstandingWrites;

  final List<DocumentKey> _acknowledgedDocs = <DocumentKey>[];
  final List<DocumentKey> _rejectedDocs = <DocumentKey>[];

  /// The current user for the [SyncEngine]. Determines which mutation queue is
  /// active.
  User _currentUser;

  static void info(String line) {
    if (_debug) {
      // Print log information out directly to cut down on logger-related cruft like the extra line for the date and
      // class method which are always SpecTestCase+info
      Log.d('SpecTestCase', line);
    } else {
      Log.i('SpecTestCase', line);
    }
  }

  static void log(String line) {
    if (_debug) {
      info(line);
    }
  }

  // Methods for tracking state of writes.

  bool _shouldRun(Set<String> tags) {
    for (String tag in tags) {
      if (_disabledTags.contains(tag)) {
        return false;
      }
    }

    return !isExcluded(tags);
  }

  Future<void> specSetUp(Map<String, dynamic> config) async {
    log('    Clearing all state.');

    _outstandingWrites = <User, List<Pair<Mutation, Future<void>>>>{};

    _garbageCollectionEnabled = config['useGarbageCollection'] ?? false;

    _currentUser = User.unauthenticated;

    if ((config['numClients'] ?? 1) != 1) {
      throw asserts.fail('The Android client does not support multi-client tests');
    }

    if (config.isNotEmpty) {
      await _initClient();
    }

    // Set up internal event tracking for the spec tests.
    _events = <QueryEvent>[];
    _queryListeners = <Query, QueryListener>{};

    _expectedLimboDocs = <DocumentKey>{};
    _expectedActiveTargets = <int, QueryData>{};
  }

  Future<void> specTearDown({bool isError = false}) async {
    if (isError) {
      log('~~~onError~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~');
    }
    await Future<void>.delayed(_delayDuration);
    await _remoteStore.shutdown();
    await _localPersistence.shutdown();
    log('~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~');
  }

  /// Sets up a new client. Is used to initially setup the client initially and after every restart.
  Future<void> _initClient([bool isRestart = false]) async {
    log('    Set up a new client.');

    _localPersistence = await getPersistence(_garbageCollectionEnabled, currentName ?? 'init');

    final LocalStore localStore = LocalStore(_localPersistence, _currentUser);

    _queue = AsyncQueue();

    // Set up the sync engine and various stores.
    _datastore = MockDatastore(_queue);

    _remoteStore = RemoteStore(this, localStore, _datastore, _queue);
    _syncEngine = SyncEngine(localStore, _remoteStore, _currentUser);
    _eventManager = EventManager(_syncEngine);
    await localStore.start();
    await _remoteStore.start();
  }

  @override
  Future<void> handleOnlineStateChange(OnlineState onlineState) async {
    await _syncEngine.handleOnlineStateChange(onlineState);
  }

  List<Pair<Mutation, Future<void>>> _getCurrentOutstandingWrites() {
    List<Pair<Mutation, Future<void>>> writes = _outstandingWrites[_currentUser];
    if (writes == null) {
      writes = <Pair<Mutation, Future<void>>>[];
      _outstandingWrites[_currentUser] = writes;
    }
    return writes;
  }

  // Methods for mocking out the grpc streams.

  /// Validates that a write was sent and matches the expected write.
  void _validateNextWriteSent(Mutation expectedWrite) {
    final List<Mutation> request = _datastore.waitForWriteSend();
    // TODO(long1eu): Batch writes not supported yet
    expect(request.length, 1);
    final Mutation actualWrite = request[0];
    expect(actualWrite, expectedWrite);
    log('      This write was sent: $actualWrite');
  }

  int _writesSent() => _datastore.writesSent;

  // Methods for constructing objects from specs.

  /// The format for a query is string|{path, limit?}.
  /// https://github.com/firebase/firebase-js-sdk/blob/master/packages/firestore/test/unit/specs/spec_test_runner.ts#L1115
  Query _parseQuery(Object querySpec) {
    if (querySpec is String) {
      return Query(ResourcePath.fromString(querySpec));
    } else if (querySpec is Map<String, dynamic>) {
      final Map<String, dynamic> queryDict = querySpec;
      final String path = queryDict['path'];
      Query query = Query(ResourcePath.fromString(path));
      if (queryDict.containsKey('limit')) {
        query = query.limit(queryDict['limit']);
      }
      if (queryDict.containsKey('filters')) {
        final List<dynamic> array = queryDict['filters'];
        for (int i = 0; i < array.length; i++) {
          final List<dynamic> _filter = array[i];
          final String field = _filter[0];
          final String op = _filter[1];
          final Object value = _filter[2];
          query = query.filter(filter(field, op, value));
        }
      }
      if (queryDict.containsKey('orderBys')) {
        final List<dynamic> array = queryDict['orderBys'];
        for (int i = 0; i < array.length; i++) {
          final List<dynamic> _orderBy = array[i];
          final String field = _orderBy[0];
          final String direction = _orderBy[1];
          query = query.orderBy(orderBy(field, direction));
        }
      }
      return query;
    } else {
      throw asserts.fail('Invalid query: $querySpec');
    }
  }

  DocumentViewChange _parseChange(Map<String, dynamic> jsonDoc, DocumentViewChangeType type) {
    final int version = jsonDoc['version'];
    final Map<String, dynamic> options = jsonDoc['options'];
    final DocumentState documentState = options['hasLocalMutations'] ?? false
        ? DocumentState.localMutations
        : (options['hasCommittedMutations'] ?? false ? DocumentState.committedMutations : DocumentState.synced);

    final Map<String, Object> values = _parseMap(jsonDoc['value']);
    final Document document = doc(jsonDoc['key'], version, values, documentState);
    return DocumentViewChange(type, document);
  }

  Object _parseObject(Object obj) {
    if (obj is List<dynamic>) {
      return _parseList(obj);
    } else if (obj is Map<String, dynamic>) {
      return _parseMap(obj);
    } else {
      return obj;
    }
  }

  List<Object> _parseList(List<dynamic> arr) {
    final List<Object> result = List<Object>(arr.length);
    for (int i = 0; i < arr.length; ++i) {
      result[i] = _parseObject(arr[i]);
    }
    return result;
  }

  Map<String, Object> _parseMap(Map<String, dynamic> obj) {
    final Map<String, Object> values = <String, Object>{};
    final Iterable<String> keys = obj.keys;

    for (String key in keys) {
      values[key] = _parseObject(obj[key]);
    }
    return values;
  }

  List<int> _parseIntList(List<dynamic> arr) {
    final List<int> result = <int>[];
    if (arr == null) {
      return result;
    }
    for (int i = 0; i < arr.length; ++i) {
      result.add(arr[i]);
    }
    return result;
  }

  // Methods for doing the steps of the spec test.

  Future<void> _doListen(List<dynamic> listenSpec) async {
    final int expectedId = listenSpec[0];
    final Query query = _parseQuery(listenSpec[1]);

    // TODO(long1eu): Allow customizing listen options in spec tests
    const ListenOptions options = ListenOptions(
      includeDocumentMetadataChanges: true,
      includeQueryMetadataChanges: true,
    );

    final QueryListener listener = QueryListener(query, options)
      ..listen(
        (ViewSnapshot value) {
          _events.add(QueryEvent(query: query, view: value));
        },
        onError: (dynamic error) {
          asserts.hardAssert(error is FirebaseFirestoreError,
              'The recived error is not a FirebaseFirestoreError it is ${error.runtimeType}.');
          _events.add(QueryEvent(query: query, error: error));
        },
      );

    _queryListeners[query] = listener;

    final int actualId = await _eventManager.addQueryListener(listener);
    expect(actualId, expectedId);

    await Future<void>.delayed(_delayDuration);
  }

  Future<void> _doUnlisten(List<dynamic> unlistenSpec) async {
    final Query query = _parseQuery(unlistenSpec[1]);
    final QueryListener listener = _queryListeners.remove(query);
    await _eventManager.removeQueryListener(listener);
  }

  Future<void> _doMutation(Mutation mutation) async {
    final DocumentKey documentKey = mutation.key;
    final Completer<void> callback = Completer<void>();

    final Future<void> writeProcessed = callback.future //
        .then((_) => _acknowledgedDocs.add(documentKey))
        .catchError((dynamic e) => _rejectedDocs.add(documentKey));

    _getCurrentOutstandingWrites().add(Pair<Mutation, Future<void>>(mutation, writeProcessed));
    log('      Sending this write: $mutation');

    await _syncEngine.writeMutations(<Mutation>[mutation], callback);
  }

  Future<void> _doSet(List<dynamic> setSpec) async {
    await _doMutation(setMutation(setSpec[0], _parseMap(setSpec[1])));
  }

  Future<void> _doPatch(List<dynamic> patchSpec) async {
    await _doMutation(patchMutation(patchSpec[0], _parseMap(patchSpec[1])));
  }

  Future<void> _doDelete(String key) async {
    await _doMutation(deleteMutation(key));
  }

  // Helper for calling datastore.writeWatchChange() on the AsyncQueue.

  Future<void> _writeWatchChange(WatchChange change, SnapshotVersion version) async {
    await _datastore.writeWatchChange(change, version);
    await Future<void>.delayed(_delayDuration);
  }

  Future<void> _doWatchAck(List<dynamic> ackedTargets) async {
    final WatchChangeWatchTargetChange change =
        WatchChangeWatchTargetChange(WatchTargetChangeType.added, _parseIntList(ackedTargets));
    await _writeWatchChange(change, SnapshotVersion.none);
  }

  Future<void> _doWatchCurrent(List<dynamic> currentSpec) async {
    final List<int> currentTargets = _parseIntList(currentSpec[0]);
    final Uint8List resumeToken = Uint8List.fromList(utf8.encode(currentSpec[1]));
    final WatchChangeWatchTargetChange change =
        WatchChangeWatchTargetChange(WatchTargetChangeType.current, currentTargets, resumeToken);
    await _writeWatchChange(change, SnapshotVersion.none);
  }

  Future<void> _doWatchRemove(Map<String, dynamic> watchRemoveSpec) async {
    GrpcError error;
    final Map<String, dynamic> cause = watchRemoveSpec['cause'];
    if (cause != null) {
      final int code = cause['code'];
      if (code != 0) {
        error = GrpcError.custom(code, '');
      }
    }

    final List<int> targetIds = _parseIntList(watchRemoveSpec['targetIds'].cast<int>());
    final WatchChangeWatchTargetChange change =
        WatchChangeWatchTargetChange(WatchTargetChangeType.removed, targetIds, Uint8List(0), error);

    await _writeWatchChange(change, SnapshotVersion.none);
    // Unlike web, the MockDatastore detects a watch removal with cause and will remove active targets

    await Future<void>.delayed(_delayDuration);
  }

  Future<void> _doWatchEntity(Map<String, dynamic> watchEntity) async {
    if (watchEntity.containsKey('docs')) {
      asserts.hardAssert(!watchEntity.containsKey('doc'), 'Exactly one of |doc| or |docs| needs to be set.');
      final List<dynamic> docs = watchEntity['docs'];
      for (int i = 0; i < docs.length; ++i) {
        final Map<String, dynamic> doc = docs[i];
        final Map<String, dynamic> watchSpec = <String, dynamic>{};
        watchSpec['doc'] = doc;
        if (watchEntity.containsKey('targets')) {
          watchSpec['targets'] = watchEntity['targets'];
        }
        if (watchEntity.containsKey('removedTargets')) {
          watchSpec['removedTargets'] = watchEntity['removedTargets'];
        }
        await _doWatchEntity(watchSpec);
      }
    } else if (watchEntity.containsKey('doc')) {
      final Map<String, dynamic> docSpec = watchEntity['doc'];
      final String key = docSpec['key'];

      final Map<String, Object> value = docSpec['value'] == null ? null : _parseMap(docSpec['value']);
      final int version = docSpec['version'];

      final MaybeDocument document = value != null ? doc(key, version, value) : deletedDoc(key, version);

      final List<int> updated = _parseIntList(watchEntity['targets'] ?? <int>[].cast<int>());
      final List<int> removed = _parseIntList((watchEntity['removedTargets'] ?? <int>[]).cast<int>());
      final WatchChange change = WatchChangeDocumentChange(updated, removed, document.key, document);

      await _writeWatchChange(change, SnapshotVersion.none);
    } else if (watchEntity.containsKey('key')) {
      final String _key = watchEntity['key'];
      final List<int> removed = _parseIntList(watchEntity['removedTargets'].cast<int>());
      final WatchChange change = WatchChangeDocumentChange(<int>[], removed, key(_key), null);
      await _writeWatchChange(change, SnapshotVersion.none);
    } else {
      throw asserts.fail('Either key, doc or docs must be set.');
    }
  }

  Future<void> _doWatchFilter(List<dynamic> watchFilter) async {
    final List<int> targets = _parseIntList(watchFilter[0].cast<int>());
    asserts.hardAssert(targets.length == 1, 'ExistenceFilters currently support exactly one target only.');

    final int keyCount = watchFilter.isEmpty ? 0 : watchFilter.length - 1;

    // TODO(long1eu): extend this with different existence filters over time.
    final ExistenceFilter filter = ExistenceFilter(keyCount);
    final WatchChangeExistenceFilterWatchChange change = WatchChangeExistenceFilterWatchChange(targets[0], filter);

    await _writeWatchChange(change, SnapshotVersion.none);
  }

  Future<void> _doWatchReset(List<dynamic> targetIds) async {
    final List<int> targets = _parseIntList(targetIds);
    final WatchChange change = WatchChangeWatchTargetChange(WatchTargetChangeType.reset, targets);
    await _writeWatchChange(change, SnapshotVersion.none);
  }

  Future<void> _doWatchSnapshot(Map<String, dynamic> watchSnapshot) async {
    // The client will only respond to watchSnapshots if they are on a target change with an empty set of target IDs.
    final List<int> targets = _parseIntList(watchSnapshot['targetIds']?.cast<int>());
    final String resumeToken = watchSnapshot['resumeToken'] ?? '';

    final WatchChange change = WatchChangeWatchTargetChange(
        WatchTargetChangeType.noChange, targets, Uint8List.fromList(utf8.encode(resumeToken)));

    await _writeWatchChange(change, version(watchSnapshot['version']));
  }

  Future<void> _doWatchStreamClose(Map<String, dynamic> spec) async {
    final Map<String, dynamic> error = spec['error'];

    final bool runBackoffTimer = spec['runBackoffTimer'];
    // TODO(long1eu): Incorporate backoff in Android Spec Tests.
    expect(runBackoffTimer, isTrue);

    final GrpcError status = GrpcError.custom(error['code'], error['message']);
    print('_datastore.isWatchStreamOpen: ${_datastore.isWatchStreamOpen}');
    _datastore.failWatchStream(status);
    // Unlike web, stream should re-open synchronously (if we have active listeners).
    if (_queryListeners.isNotEmpty) {
      assert(_datastore.isWatchStreamOpen, 'Watch stream is open');
    }
  }

  Future<void> _doWriteAck(Map<String, dynamic> writeAckSpec) async {
    final int _version = writeAckSpec['version'];
    final bool keepInQueue = writeAckSpec['keepInQueue'] ?? false;
    assert(!keepInQueue, '"keepInQueue=true" is not supported on Android and should only be set in multi-client tests');
    final Pair<Mutation, Future<void>> write = _getCurrentOutstandingWrites().removeAt(0);
    _validateNextWriteSent(write.first);

    final MutationResult mutationResult = MutationResult(version(_version), /*transformResults:*/ null);
    await _datastore.ackWrite(version(_version), <MutationResult>[mutationResult]);
  }

  Future<void> _doFailWrite(Map<String, dynamic> writeFailureSpec) async {
    final Map<String, dynamic> errorSpec = writeFailureSpec['error'];
    final bool keepInQueue = writeFailureSpec['keepInQueue'] ?? false;

    final int code = errorSpec['code'];
    final GrpcError error = GrpcError.custom(code, '');

    final Pair<Mutation, Future<void>> write = _getCurrentOutstandingWrites()[0];
    _validateNextWriteSent(write.first);

    // If this is a permanent error, the write is not expected to be sent again.
    if (!keepInQueue) {
      _getCurrentOutstandingWrites().removeAt(0);
    }

    log('      Failing a write.');
    await _datastore.failWrite(error);
  }

  Future<void> _doRunTimer(String timer) async {
    TimerId timerId;
    switch (timer) {
      case 'all':
        timerId = TimerId.all;
        break;
      case 'listen_stream_idle':
        timerId = TimerId.listenStreamIdle;
        break;
      case 'listen_stream_connection_backoff':
        timerId = TimerId.listenStreamConnectionBackoff;
        break;
      case 'write_stream_idle':
        timerId = TimerId.writeStreamIdle;
        break;
      case 'write_stream_connection_backoff':
        timerId = TimerId.writeStreamConnectionBackoff;
        break;
      case 'online_state_timeout':
        timerId = TimerId.onlineStateTimeout;
        break;
      default:
        throw asserts.fail('runTimer spec step specified unknown timer: $timer');
    }

    await _queue.runDelayedTasksUntil(timerId);
  }

  Future<void> _doDisableNetwork() async {
    _networkEnabled = false;
    // Make sure to execute all writes that are currently queued. This allows us to assert on the total number of
    // requests sent before shutdown.
    await _remoteStore.fillWritePipeline();
    await _remoteStore.disableNetwork();
    await Future<void>.delayed(_delayDuration);
  }

  Future<void> _doEnableNetwork() async {
    _networkEnabled = true;
    await _remoteStore.enableNetwork();
  }

  Future<void> _doChangeUser(String uid) async {
    _currentUser = User(uid);
    await _syncEngine.handleCredentialChange(_currentUser);
  }

  Future<void> _doRestart() async {
    if (_localPersistence is SQLitePersistence) {
      final SQLitePersistence persistence = _localPersistence;
      final DatabaseMock databaseMock = persistence.database;
      // ignore: cascade_invocations
      databaseMock.renamePath = false;
    }

    await Future.wait(<Future<void>>[
      _remoteStore.shutdown(),
      _localPersistence.shutdown(),
      _initClient(true),
    ]);

    if (_localPersistence is SQLitePersistence) {
      final SQLitePersistence persistence = _localPersistence;
      final DatabaseMock databaseMock = persistence.database;
      // ignore: cascade_invocations
      databaseMock.renamePath = true;
    }
  }

  Future<void> _doStep(Map<String, dynamic> step) async {
    if (step['clientIndex'] != null) {
      throw asserts.fail('The Android client does not support switching clients');
    }

    if (step.containsKey('userListen')) {
      await _doListen(step['userListen']);
    } else if (step.containsKey('userUnlisten')) {
      await _doUnlisten(step['userUnlisten']);
    } else if (step.containsKey('userSet')) {
      await _doSet(step['userSet']);
    } else if (step.containsKey('userPatch')) {
      await _doPatch(step['userPatch']);
    } else if (step.containsKey('userDelete')) {
      await _doDelete(step['userDelete']);
    } else if (step.containsKey('drainQueue')) {
      // TODO(long1eu): add a comment here to explain why are we not using this
    } else if (step.containsKey('watchAck')) {
      await _doWatchAck(step['watchAck']);
    } else if (step.containsKey('watchCurrent')) {
      await _doWatchCurrent(step['watchCurrent']);
    } else if (step.containsKey('watchRemove')) {
      await _doWatchRemove(step['watchRemove']);
    } else if (step.containsKey('watchEntity')) {
      await _doWatchEntity(step['watchEntity']);
    } else if (step.containsKey('watchFilter')) {
      await _doWatchFilter(step['watchFilter']);
    } else if (step.containsKey('watchReset')) {
      await _doWatchReset(step['watchReset']);
    } else if (step.containsKey('watchSnapshot')) {
      await _doWatchSnapshot(step['watchSnapshot']);
    } else if (step.containsKey('watchStreamClose')) {
      await _doWatchStreamClose(step['watchStreamClose']);
    } else if (step.containsKey('watchProto')) {
      // watchProto isn't yet used, and it's unclear how to create arbitrary protos from JSON.
      throw asserts.fail('watchProto is not yet supported.');
    } else if (step.containsKey('writeAck')) {
      await _doWriteAck(step['writeAck']);
    } else if (step.containsKey('failWrite')) {
      await _doFailWrite(step['failWrite']);
    } else if (step.containsKey('runTimer')) {
      await _doRunTimer(step['runTimer']);
    } else if (step.containsKey('enableNetwork')) {
      if (step['enableNetwork']) {
        await _doEnableNetwork();
      } else {
        await _doDisableNetwork();
      }
    } else if (step.containsKey('changeUser')) {
      // NOTE: Map<String, dynamic>.getString('foo') where 'foo' is mapped to null will return 'null'. Explicitly
      // testing for isNull here allows the null value to be preserved. This is important because the unauthenticated
      // user is represented as having a null uid as a value for 'changeUser'.
      final String uid = step['changeUser'];
      await _doChangeUser(uid);
    } else if (step.containsKey('restart')) {
      await _doRestart();
    } else if (step.containsKey('applyClientState')) {
      throw asserts.fail('"applyClientState"is not supported on Android and should only be used in multi-client tests');
    } else {
      throw asserts.fail('Unknown step: $step');
    }
  }

  // Methods for validating expectations.

  void _assertEventMatches(Map<String, dynamic> expected, QueryEvent actual) {
    final Query expectedQuery = _parseQuery(expected['query']);
    expect(actual.query, expectedQuery);
    if (expected.containsKey('errorCode') && expected['errorCode'] != StatusCode.ok) {
      expect(actual.error, isNotNull);
      expect(actual.error.code.value, expected['errorCode']);
    } else {
      final List<DocumentViewChange> expectedChanges = <DocumentViewChange>[];
      final List<dynamic> removed = expected['removed'];
      for (int i = 0; removed != null && i < removed.length; ++i) {
        expectedChanges.add(_parseChange(removed[i], DocumentViewChangeType.removed));
      }

      final List<dynamic> added = expected['added'];
      for (int i = 0; added != null && i < added.length; ++i) {
        expectedChanges.add(_parseChange(added[i], DocumentViewChangeType.added));
      }
      final List<dynamic> modified = expected['modified'];
      for (int i = 0; modified != null && i < modified.length; ++i) {
        expectedChanges.add(_parseChange(modified[i], DocumentViewChangeType.modified));
      }

      final List<dynamic> metadata = expected['metadata'];
      for (int i = 0; metadata != null && i < metadata.length; ++i) {
        expectedChanges.add(_parseChange(metadata[i], DocumentViewChangeType.metadata));
      }
      expect(actual.view.changes, expectedChanges);

      final bool expectedHasPendingWrites = expected['hasPendingWrites'] ?? false;
      final bool expectedFromCache = expected['fromCache'] ?? false;
      expect(actual.view.hasPendingWrites, expectedHasPendingWrites, reason: 'hasPendingWrites');
      expect(actual.view.isFromCache, expectedFromCache, reason: 'fromCache');
    }
  }

  void _validateStepExpectations(List<dynamic> stepExpectations) {
    if (stepExpectations == null) {
      for (QueryEvent event in _events) {
        fail('Unexpected event: $event');
      }
      return;
    }

    // Sort both the expected and actual events by the query's canonical ID.
    _events.sort((QueryEvent q1, QueryEvent q2) => q1.query.canonicalId.compareTo(q2.query.canonicalId));

    final List<Map<String, dynamic>> expectedEvents = <Map<String, dynamic>>[];
    for (int i = 0; i < stepExpectations.length; ++i) {
      expectedEvents.add(stepExpectations[i]);
    }
    expectedEvents.sort((Map<String, dynamic> left, Map<String, dynamic> right) {
      final Query leftQuery = _parseQuery(left['query']);
      final Query rightQuery = _parseQuery(right['query']);
      return leftQuery.canonicalId.compareTo(rightQuery.canonicalId);
    });

    int i = 0;
    for (; i < expectedEvents.length && i < _events.length; ++i) {
      _assertEventMatches(expectedEvents[i], _events[i]);
    }

    for (; i < stepExpectations.length; ++i) {
      fail('Missing event: ${stepExpectations[i]}');
    }

    for (; i < _events.length; ++i) {
      fail('Unexpected event: ${_events[i]}');
    }
  }

  void _validateStateExpectations(Map<String, dynamic> expected) {
    if (expected != null) {
      if (expected.containsKey('numOutstandingWrites')) {
        expect(_writesSent(), expected['numOutstandingWrites']);
      }

      if (expected.containsKey('writeStreamRequestCount')) {
        expect(_datastore.writeStreamRequestCount, expected['writeStreamRequestCount']);
      }

      if (expected.containsKey('watchStreamRequestCount')) {
        expect(_datastore.watchStreamRequestCount, expected['watchStreamRequestCount']);
      }

      if (expected.containsKey('limboDocs')) {
        _expectedLimboDocs = <DocumentKey>{};
        final List<dynamic> limboDocs = expected['limboDocs'];
        for (int i = 0; i < limboDocs.length; i++) {
          _expectedLimboDocs.add(key(limboDocs[i]));
        }
      }

      if (expected.containsKey('activeTargets')) {
        _expectedActiveTargets = <int, QueryData>{};
        final Map<String, dynamic> activeTargets = expected['activeTargets'];
        final Iterable<String> keys = activeTargets.keys;

        for (String targetIdString in keys) {
          final int targetId = int.tryParse(targetIdString);
          final Map<String, dynamic> queryDataJson = activeTargets[targetIdString];
          final Query query = _parseQuery(queryDataJson['query']);
          final String resumeToken = queryDataJson['resumeToken'];

          // TODO(long1eu): populate the purpose of the target once it's possible to encode that in the spec tests. For
          //  now, hard-code that it's a listen despite the fact that it's not always the right value.
          _expectedActiveTargets[targetId] = QueryData(
            query,
            targetId,
            arbitrarySequenceNumber,
            QueryPurpose.listen,
            SnapshotVersion.none,
            Uint8List.fromList(utf8.encode(resumeToken)),
          );
        }
      }
    }

    // Always validate the we received the expected number of events.
    _validateUserCallbacks(expected);
    // Always validate that the expected limbo docs match the actual limbo docs.
    _validateLimboDocs();
    // Always validate that the expected active targets match the actual active targets.
    _validateActiveTargets();
  }

  void _validateUserCallbacks(Map<String, dynamic> expected) {
    if (expected != null && expected.containsKey('userCallbacks')) {
      final Map<String, dynamic> userCallbacks = expected['userCallbacks'];

      final List<dynamic> expectedAcknowledgedDocs = userCallbacks['acknowledgedDocs'];
      for (int i = 0; i < expectedAcknowledgedDocs.length; i++) {
        final String documentKey = expectedAcknowledgedDocs[i];
        expect(_acknowledgedDocs.contains(key(documentKey)), isTrue,
            reason: 'Expected acknowledgment for $documentKey');
      }

      final List<dynamic> expectedRejectedDocs = userCallbacks['rejectedDocs'];
      for (int i = 0; i < expectedRejectedDocs.length; i++) {
        final String documentKey = expectedRejectedDocs[i];
        expect(_rejectedDocs.contains(key(documentKey)), isTrue, reason: 'Expected rejection for $documentKey');
      }
    } else {
      expect(_acknowledgedDocs, isEmpty);
      expect(_rejectedDocs, isEmpty);
    }
  }

  void _validateLimboDocs() {
    // Make a copy so it can modified while checking against the expected limbo docs.
    final Map<DocumentKey, int> actualLimboDocs = Map<DocumentKey, int>.from(_syncEngine.getCurrentLimboDocuments());

    // Validate that each limbo doc has an expected active target
    for (MapEntry<DocumentKey, int> limboDoc in actualLimboDocs.entries) {
      expect(_expectedActiveTargets.containsKey(limboDoc.value), isTrue);
    }

    for (DocumentKey expectedLimboDoc in _expectedLimboDocs) {
      expect(actualLimboDocs.containsKey(expectedLimboDoc), isTrue);
      actualLimboDocs.remove(expectedLimboDoc);
    }
    expect(actualLimboDocs, isEmpty);
  }

  void _validateActiveTargets() {
    if (!_networkEnabled) {
      return;
    }

    final Map<int, QueryData> actualTargets = _datastore.activeTargets;
    for (MapEntry<int, QueryData> expected in _expectedActiveTargets.entries) {
      expect(actualTargets.containsKey(expected.key), isTrue);

      final QueryData expectedTarget = expected.value;
      final QueryData actualTarget = actualTargets[expected.key];

      // TODO(long1eu): validate the purpose of the target once it's possible to encode that in the spec tests. For now,
      //  only validate properties that can be validated.
      // expect(actualTarget, expectedTarget);

      expect(actualTarget.query, expectedTarget.query);
      expect(actualTarget.targetId, expectedTarget.targetId);
      expect(actualTarget.snapshotVersion, expectedTarget.snapshotVersion);
      expect(utf8.decode(actualTarget.resumeToken), utf8.decode(expectedTarget.resumeToken));
      actualTargets.remove(expected.key);
    }

    expect(actualTargets, isEmpty);
  }

  Future<void> runSteps(List<dynamic> steps, Map<String, dynamic> config) async {
    await specSetUp(config);
    for (int i = 0; i < steps.length; ++i) {
      final Map<String, dynamic> step = steps[i];
      final List<dynamic> expect = step.remove('expect');
      final Map<String, dynamic> stateExpect = step.remove('stateExpect');

      log('    Doing step $step');
      await _doStep(step);

      if (expect != null) {
        log('      Validating step expectations $expect');
      }

      _validateStepExpectations(expect);
      if (stateExpect != null) {
        log('      Validating state expectations $stateExpect');
      }
      _validateStateExpectations(stateExpect);

      _events.clear();
      _acknowledgedDocs.clear();
      _rejectedDocs.clear();
    }

    await specTearDown();
  }

  static bool anyTestsAreMarkedExclusive(Map<String, dynamic> fileJSON) {
    for (String key in fileJSON.keys) {
      final Map<String, dynamic> testJSON = fileJSON[key];
      if (getTestTags(testJSON).contains(exclusiveTag)) {
        return true;
      }
    }

    return false;
  }

  /// Called before executing each test to see if it should be run.

  bool shouldRunTest(Set<String> tags) {
    return _shouldRun(tags);
  }

  static Set<String> getTestTags(Map<String, dynamic> testJSON) {
    final List<dynamic> tagsJSON = testJSON['tags'];
    final Set<String> tags = <String>{};
    for (int i = 0; i < tagsJSON.length; i++) {
      tags.add(tagsJSON[i]);
    }
    return tags;
  }

  // RemoteStoreCallback Methods

  @override
  Future<void> handleRemoteEvent(RemoteEvent remoteEvent) async {
    await _syncEngine.handleRemoteEvent(remoteEvent);
  }

  @override
  Future<void> handleRejectedListen(int targetId, GrpcError error) async {
    await _syncEngine.handleRejectedListen(targetId, error);
  }

  @override
  Future<void> handleSuccessfulWrite(MutationBatchResult mutationBatchResult) async {
    await _syncEngine.handleSuccessfulWrite(mutationBatchResult);
  }

  @override
  Future<void> handleRejectedWrite(int batchId, GrpcError error) async {
    await _syncEngine.handleRejectedWrite(batchId, error);
  }

  @override
  ImmutableSortedSet<DocumentKey> Function(int) get getRemoteKeysForTarget =>
      (int targetId) => _syncEngine.getRemoteKeysForTarget(targetId);
}

class Pair<F, S> {
  Pair(this.first, this.second);

  final F first;
  final S second;
}
