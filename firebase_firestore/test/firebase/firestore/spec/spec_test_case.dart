// File created by
// Lung Razvan <long1eu>
// on 04/10/2018

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_database_collection/firebase_database_collection.dart';
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
import 'package:firebase_firestore/src/firebase/firestore/remote/watch_stream.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/async_queue.dart';
import 'package:grpc/grpc.dart';
import 'package:test/test.dart';

import '../../../util/test_util.dart';
import '../remote/mock_datastore.dart';
import 'query_event.dart';

class SpecTestCase implements RemoteStoreCallback {
  /// Set this to true when debugging test failures.
  /*p*/
  static const bool debug = true;

  // TODO: Make this configurable with JUnit options.
  /*p*/
  static const bool runBenchmarkTests = false;

  // Disables all other tests; useful for debugging. Multiple tests can have
  // this tag and they'll all be run (but all others won't).
  /*p*/
  static const String exclusiveTag = 'exclusive';

  // Tags on tests that should be excluded from execution, useful to allow the
  // platforms to temporarily diverge or for features that are designed to be
  // platform specific (such as 'multi-client').
  /*p*/
  static final Set<String> disabledTags = runBenchmarkTests
      ? Set<String>.from(<String>['no-android', 'multi-client'])
      : Set<String>.from(<String>['no-android', 'benchmark', 'multi-client']);

  final Future<Persistence> Function(bool garbageCollectionEnabled, String name)
      getPersistence;
  final bool Function(Set<String> tags) isExcluded;

  String currentName;

  SpecTestCase(this.getPersistence, this.isExcluded);

  /*p*/
  bool garbageCollectionEnabled;

  /*p*/
  bool networkEnabled = true;

  //
  // Parts of the Firestore system that the spec tests need to control.
  //
  /*p*/
  Persistence localPersistence;

  /*p*/
  AsyncQueue queue;

  /*p*/
  MockDatastore datastore;

  /*p*/
  RemoteStore remoteStore;

  /*p*/
  SyncEngine syncEngine;

  /*p*/
  EventManager eventManager;

  /*p*/

  /// Events to be checked by the expectations.
  List<QueryEvent> events;

  /*p*/

  /// A dictionary for tracking the listens on queries. Note that the identity
  /// of the listeners is used to remove them.
  Map<Query, QueryListener> queryListeners;

  /*p*/

  /// Set of documents that are expected to be in limbo. Verified at every step.
  Set<DocumentKey> expectedLimboDocs;

  /*p*/

  /// Set of expected active targets, keyed by target ID.
  Map<int, QueryData> expectedActiveTargets;

  /// The writes that have been sent to the [SyncEngine] via
  /// [SyncEngine.writeMutations] but not yet acknowledged by calling
  /// receiveWriteAck/Error. They are tracked per-user.
  ///
  /// * It is mostly an implementation detail used internally to validate that
  /// the writes sent to the mock backend by the [SyncEngine] match the user
  /// mutations that initiated them.
  ///
  /// * It is exposed specifically for use [doRestart] to test persistence
  /// scenarios where the [SyncEngine] is restarted while the [Persistence]
  /// implementation still has outstanding persisted mutations.
  ///
  /// * Note: The size of the list for the current user will generally be the
  /// same as [writesSent], but not necessarily, since the [RemoteStore] limits
  /// the number of outstanding writes to the backend at a given time.
  /*p*/
  Map<User, List<Pair<Mutation, Future<void>>>> outstandingWrites;

  /*p*/
  final List<DocumentKey> acknowledgedDocs = <DocumentKey>[];

  /*p*/
  final List<DocumentKey> rejectedDocs = <DocumentKey>[];

  /*p*/

  /// The current user for the [SyncEngine]. Determines which mutation queue is
  /// active.
  User currentUser;

  static void info(String line) {
    if (debug) {
      // Print log information out directly to cut down on logger-related cruft
      // like the extra line for the date and class method which are always
      // SpecTestCase+info
      Log.d('SpecTestCase', line);
    } else {
      Log.i('SpecTestCase', line);
    }
  }

  static void log(String line) {
    if (debug) {
      info(line);
    }
  }

  //
  // Methods for tracking state of writes.
  //

  /*p*/
  bool shouldRun(Set<String> tags) {
    for (String tag in tags) {
      if (disabledTags.contains(tag)) {
        return false;
      }
    }

    return !isExcluded(tags);
  }

  Future<void> specSetUp(Map<String, dynamic> config) async {
    log('    Clearing all state.');

    outstandingWrites = <User, List<Pair<Mutation, Future<void>>>>{};

    garbageCollectionEnabled = config['useGarbageCollection'] as bool ?? false;

    currentUser = User.unauthenticated;

    if ((config['numClients'] ?? 1) != 1) {
      throw Assert.fail(
          'The Android client does not support multi-client tests');
    }

    await initClient();

    // Set up internal event tracking for the spec tests.
    events = <QueryEvent>[];
    queryListeners = <Query, QueryListener>{};

    expectedLimboDocs = Set<DocumentKey>();
    expectedActiveTargets = <int, QueryData>{};
  }

  Future<void> specTearDown() /*throws Exception*/ async {
    remoteStore.shutdown();
    await localPersistence.shutdown();
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  /// Sets up a new client. Is used to initially setup the client initially and
  /// after every restart.
  /*p*/
  Future<void> initClient() async {
    log('    Set up a new client.');
    localPersistence =
        await getPersistence(garbageCollectionEnabled, currentName ?? 'init');
    final LocalStore localStore = LocalStore(localPersistence, currentUser);

    queue = await AsyncQueue.createQueue();

    // Set up the sync engine and various stores.
    datastore = MockDatastore(queue);

    remoteStore = RemoteStore(this, localStore, datastore, queue);
    syncEngine = SyncEngine(localStore, remoteStore, currentUser);
    eventManager = EventManager(syncEngine);
    await localStore.start();
    await remoteStore.start();
  }

  @override
  void handleOnlineStateChange(OnlineState onlineState) {
    syncEngine.handleOnlineStateChange(onlineState);
    eventManager.handleOnlineStateChange(onlineState);
  }

  /*p*/
  List<Pair<Mutation, Future<void>>> getCurrentOutstandingWrites() {
    List<Pair<Mutation, Future<void>>> writes = outstandingWrites[currentUser];
    if (writes == null) {
      writes = <Pair<Mutation, Future<void>>>[];
      outstandingWrites[currentUser] = writes;
    }
    return writes;
  }

  //
  // Methods for mocking out the grpc streams.
  //

  /// Validates that a write was sent and matches the expected write.
  /*p*/
  void validateNextWriteSent(Mutation expectedWrite) {
    final List<Mutation> request = datastore.waitForWriteSend();
    // TODO: Batch writes not supported yet
    expect(request.length, 1);
    final Mutation actualWrite = request[0];
    expect(actualWrite, expectedWrite);
    log('      This write was sent: $actualWrite');
  }

  /*p*/
  int writesSent() => datastore.writesSent;

  //
  // Methods for constructing objects from specs.
  //

  /// The format for a query is string|{path, limit?}.
  /// https://github.com/firebase/firebase-js-sdk/blob/master/packages/firestore/test/unit/specs/spec_test_runner.ts#L1115
  /*p*/
  Query parseQuery(Object querySpec) /*throws JSONException*/ {
    if (querySpec is String) {
      return Query.atPath(ResourcePath.fromString(querySpec));
    } else if (querySpec is Map<String, dynamic>) {
      final Map<String, dynamic> queryDict = querySpec;
      final String path = queryDict['path'];
      Query query = Query.atPath(ResourcePath.fromString(path));
      if (queryDict.containsKey('limit')) {
        query = query.limit(queryDict['limit'] as int);
      }
      if (queryDict.containsKey('filters')) {
        final List<dynamic> array = queryDict['filters'];
        for (int i = 0; i < array.length; i++) {
          final List<dynamic> filter = array[i];
          final String field = filter[0];
          final String op = filter[1];
          final Object value = filter[2];
          query = query.filter(TestUtil.filter(field, op, value));
        }
      }
      if (queryDict.containsKey('orderBys')) {
        final List<dynamic> array = queryDict['orderBys'];
        for (int i = 0; i < array.length; i++) {
          final List<dynamic> orderBy = array[i];
          final String field = orderBy[0];
          final String direction = orderBy[1];
          query = query.orderBy(TestUtil.orderBy(field, direction));
        }
      }
      return query;
    } else {
      throw Assert.fail('Invalid query: $querySpec');
    }
  }

  /*
   * The format for change is [path, version, values, options...] for a doc.
   * https://github.com/firebase/firebase-js-sdk/blob/master/packages/firestore/test/unit/specs/spec_test_runner.ts#L1137
   */
  /*p*/
  DocumentViewChange parseChange(
      List<dynamic> change, DocumentViewChangeType type)
  /*throws JSONException*/ {
    bool hasMutations = false;
    for (int i = 3; i < change.length; ++i) {
      if (change[i] == 'local') {
        hasMutations = true;
      }
    }
    final int version = change[1];
    final Map<String, Object> values =
        parseMap(change[2] as Map<String, dynamic>);
    final Document doc =
        TestUtil.doc(change[0] as String, version, values, hasMutations);
    return DocumentViewChange(type, doc);
  }

  /*p*/
  Object parseObject(Object obj) /*throws JSONException*/ {
    if (obj is List<dynamic>) {
      return parseList(obj);
    } else if (obj is Map<String, dynamic>) {
      return parseMap(obj);
    } else {
      return obj;
    }
  }

  /*p*/
  List<Object> parseList(List<dynamic> arr) /*throws JSONException*/ {
    final List<Object> result = List<Object>(arr.length);
    for (int i = 0; i < arr.length; ++i) {
      result[i] = parseObject(arr[i]);
    }
    return result;
  }

  /*p*/
  Map<String, Object> parseMap(
      Map<String, dynamic> obj) /*throws JSONException*/ {
    final Map<String, Object> values = <String, Object>{};
    final Iterable<String> keys = obj.keys;

    for (String key in keys) {
      values[key] = parseObject(obj[key]);
    }
    return values;
  }

  /*p*/
  List<int> parseIntList(List<dynamic> arr) /*throws JSONException*/ {
    final List<int> result = <int>[];
    if (arr == null) {
      return result;
    }
    for (int i = 0; i < arr.length; ++i) {
      result.add(arr[i] as int);
    }
    return result;
  }

  //
  // Methods for doing the steps of the spec test.
  //

  /*p*/
  Future<void> doListen(List<dynamic> listenSpec) /*throws Exception*/ async {
    final int expectedId = listenSpec[0];
    final Query query = parseQuery(listenSpec[1]);
    // TODO: Allow customizing listen options in spec tests
    final ListenOptions options = ListenOptions();
    options.includeDocumentMetadataChanges = true;
    options.includeQueryMetadataChanges = true;
    final QueryListener listener = QueryListener(
      query,
      options,
      StreamController<ViewSnapshot>()
        ..stream.listen((ViewSnapshot value) {
          events.add(QueryEvent(query: query, view: value));
        }, onError: (dynamic error) {
          Assert.hardAssert(error is FirebaseFirestoreError,
              'The recived error is not a FirebaseFirestoreError it is ${error.runtimeType}.');
          events.add(
              QueryEvent(query: query, error: error as FirebaseFirestoreError));
        }),
    );

    queryListeners[query] = listener;

    final int actualId = await eventManager.addQueryListener(listener);
    expect(actualId, expectedId);
  }

  /*p*/
  void doUnlisten(List<dynamic> unlistenSpec) /*throws Exception*/ {
    final Query query = parseQuery(unlistenSpec[1]);
    final QueryListener listener = queryListeners.remove(query);
    eventManager.removeQueryListener(listener);
  }

  /*p*/
  Future<void> doMutation(Mutation mutation) /*throws Exception*/ async {
    final DocumentKey documentKey = mutation.key;
    final Completer<void> callback = Completer<void>();

    final Future<void> writeProcessed = callback.future
        .then((_) => acknowledgedDocs.add(documentKey))
        .catchError((dynamic e) => rejectedDocs.add(documentKey));

    getCurrentOutstandingWrites()
        .add(Pair<Mutation, Future<void>>(mutation, writeProcessed));
    log('      Sending this write: $mutation');

    await syncEngine.writeMutations(<Mutation>[mutation], callback);
  }

  /*p*/
  Future<void> doSet(List<dynamic> setSpec) /*throws Exception*/ async {
    await doMutation(setMutation(
        setSpec[0] as String, parseMap(setSpec[1] as Map<String, dynamic>)));
  }

  /*p*/
  Future<void> doPatch(List<dynamic> patchSpec) /*throws Exception*/ async {
    await doMutation(patchMutation(patchSpec[0] as String,
        parseMap(patchSpec[1] as Map<String, dynamic>)));
  }

  /*p*/
  Future<void> doDelete(String key) /*throws Exception*/ async {
    await doMutation(deleteMutation(key));
  }

  // Helper for calling datastore.writeWatchChange() on the AsyncQueue.
  /*p*/
  void writeWatchChange(
      WatchChange change, SnapshotVersion version) /*throws Exception*/ {
    datastore.writeWatchChange(change, version);
  }

  /*p*/
  void doWatchAck(List<dynamic> ackedTargets) /*throws Exception*/ {
    final WatchChangeWatchTargetChange change = WatchChangeWatchTargetChange(
        WatchTargetChangeType.Added, parseIntList(ackedTargets));
    writeWatchChange(change, SnapshotVersion.none);
  }

  /*p*/
  void doWatchCurrent(List<dynamic> currentSpec) /*throws Exception*/ {
    final List<int> currentTargets =
        parseIntList(currentSpec[0] as List<dynamic>);
    final Uint8List resumeToken =
        Uint8List.fromList(utf8.encode(currentSpec[1] as String));
    final WatchChangeWatchTargetChange change = WatchChangeWatchTargetChange(
        WatchTargetChangeType.Current, currentTargets, resumeToken);
    writeWatchChange(change, SnapshotVersion.none);
  }

  /*p*/
  void doWatchRemove(
      Map<String, dynamic> watchRemoveSpec) /*throws Exception*/ {
    GrpcError error;
    final Map<String, dynamic> cause = watchRemoveSpec['cause'];
    if (cause != null) {
      final int code = cause['code'];
      if (code != 0) {
        error = GrpcError.custom(code);
      }
    }

    final List<int> targetIds =
        parseIntList(watchRemoveSpec['targetIds'] as List<int>);
    final WatchChangeWatchTargetChange change = WatchChangeWatchTargetChange(
        WatchTargetChangeType.Removed,
        targetIds,
        WatchStream.emptyResumeToken,
        error);
    writeWatchChange(change, SnapshotVersion.none);
    // Unlike web, the MockDatastore detects a watch removal with cause and will
    // remove active targets
  }

  /*p*/
  void doWatchEntity(Map<String, dynamic> watchEntity) /*throws Exception*/ {
    if (watchEntity.containsKey('docs')) {
      Assert.hardAssert(!watchEntity.containsKey('doc'),
          'Exactly one of |doc| or |docs| needs to be set.');
      final List<dynamic> docs = watchEntity['docs'];
      for (int i = 0; i < docs.length; ++i) {
        final List<dynamic> doc = docs[i];
        final Map<String, dynamic> watchSpec = <String, dynamic>{};
        watchSpec['doc'] = doc;
        if (watchEntity.containsKey('targets')) {
          watchSpec['targets'] = watchEntity['targets'];
        }
        if (watchEntity.containsKey('removedTargets')) {
          watchSpec['removedTargets'] = watchEntity['removedTargets'];
        }
        doWatchEntity(watchSpec);
      }
    } else if (watchEntity.containsKey('doc')) {
      final List<dynamic> docSpec = watchEntity['doc'];
      final String key = docSpec[0];

      final Map<String, Object> value = docSpec[2] != null
          ? parseMap(docSpec[2] as Map<String, dynamic>)
          : null;
      final int version = docSpec[1];
      final MaybeDocument doc = value != null
          ? TestUtil.doc(key, version, value)
          : TestUtil.deletedDoc(key, version);
      final List<int> updated =
          parseIntList(watchEntity['targets'].cast<int>() as List<int>);
      final List<int> removed =
          parseIntList(watchEntity['removedTargets'] as List<int>);
      final WatchChange change =
          WatchChangeDocumentChange(updated, removed, doc.key, doc);
      writeWatchChange(change, SnapshotVersion.none);
    } else if (watchEntity.containsKey('key')) {
      final String key = watchEntity['key'];
      final List<int> removed =
          parseIntList(watchEntity['removedTargets'] as List<int>);
      final WatchChange change =
          WatchChangeDocumentChange(<int>[], removed, TestUtil.key(key), null);
      writeWatchChange(change, SnapshotVersion.none);
    } else {
      throw Assert.fail('Either key, doc or docs must be set.');
    }
  }

  /*p*/
  void doWatchFilter(List<dynamic> watchFilter) /*throws Exception*/ {
    final List<int> targets = parseIntList(watchFilter[0] as List<int>);
    Assert.hardAssert(targets.length == 1,
        'ExistenceFilters currently support exactly one target only.');

    final int keyCount = watchFilter.isEmpty ? 0 : watchFilter.length - 1;

    // TODO: extend this with different existence filters over time.
    final ExistenceFilter filter = ExistenceFilter(keyCount);
    final WatchChangeExistenceFilterWatchChange change =
        WatchChangeExistenceFilterWatchChange(targets[0], filter);

    writeWatchChange(change, SnapshotVersion.none);
  }

  /*p*/
  void doWatchReset(List<dynamic> targetIds) /*throws Exception*/ {
    final List<int> targets = parseIntList(targetIds);
    final WatchChange change =
        WatchChangeWatchTargetChange(WatchTargetChangeType.Reset, targets);
    writeWatchChange(change, SnapshotVersion.none);
  }

  /*p*/
  void doWatchSnapshot(
      Map<String, dynamic> watchSnapshot) /*throws Exception*/ {
    // The client will only respond to watchSnapshots if they are on a target
    // change with an empty set of target IDs.
    final List<int> targets = watchSnapshot.containsKey('targetIds')
        ? parseIntList(watchSnapshot['targetIds'] as List<int>)
        : <int>[];
    final String resumeToken = watchSnapshot['resumeToken'] ?? '';

    final WatchChange change = WatchChangeWatchTargetChange(
        WatchTargetChangeType.NoChange,
        targets,
        Uint8List.fromList(utf8.encode(resumeToken)));
    writeWatchChange(change, version(watchSnapshot['version'] as int));
  }

  /*p*/
  void doWatchStreamClose(Map<String, dynamic> spec) /*throws Exception*/ {
    final Map<String, dynamic> error = spec['error'];

    final bool runBackoffTimer = spec['runBackoffTimer'];
    // TODO: Incorporate backoff in Android Spec Tests.
    expect(runBackoffTimer, isTrue);

    final GrpcError status =
        GrpcError.custom(error['code'] as int, error['message'] as String);
    datastore.failWatchStream(status);
    // Unlike web, stream should re-open synchronously (if we have active
    // listeners).
    if (queryListeners.isNotEmpty) {
      assert(datastore.isWatchStreamOpen, 'Watch stream is open');
    }
  }

  /*p*/
  void doWriteAck(Map<String, dynamic> writeAckSpec) /*throws Exception*/ {
    final int version = writeAckSpec['version'];
    final bool keepInQueue = writeAckSpec['keepInQueue'] ?? false;
    assert(keepInQueue,
        '"keepInQueue=true" is not supported on Android and should only be set in multi-client tests');
    final Pair<Mutation, Future<void>> write =
        getCurrentOutstandingWrites().removeAt(0);
    validateNextWriteSent(write.first);

    final MutationResult mutationResult =
        MutationResult(TestUtil.version(version), /*transformResults:*/ null);
    datastore
        .ackWrite(TestUtil.version(version), <MutationResult>[mutationResult]);
  }

  /*p*/
  void doFailWrite(Map<String, dynamic> writeFailureSpec) /*throws Exception*/ {
    final Map<String, dynamic> errorSpec = writeFailureSpec['error'];
    final bool keepInQueue = writeFailureSpec['keepInQueue'] ?? false;

    final int code = errorSpec['code'];
    final GrpcError error = GrpcError.custom(code);

    final Pair<Mutation, Future<void>> write = getCurrentOutstandingWrites()[0];
    validateNextWriteSent(write.first);

    // If this is a permanent error, the write is not expected to be sent again.
    if (!keepInQueue) {
      getCurrentOutstandingWrites().removeAt(0);
    }

    log('      Failing a write.');
    datastore.failWrite(error);
  }

  /*p*/
  void doRunTimer(String timer) /*throws Exception*/ {
    TimerId timerId;
    switch (timer) {
      case 'all':
        timerId = TimerId.ALL;
        break;
      case 'listen_stream_idle':
        timerId = TimerId.LISTEN_STREAM_IDLE;
        break;
      case 'listen_stream_connection_backoff':
        timerId = TimerId.LISTEN_STREAM_CONNECTION_BACKOFF;
        break;
      case 'write_stream_idle':
        timerId = TimerId.WRITE_STREAM_IDLE;
        break;
      case 'write_stream_connection_backoff':
        timerId = TimerId.WRITE_STREAM_CONNECTION_BACKOFF;
        break;
      case 'online_state_timeout':
        timerId = TimerId.ONLINE_STATE_TIMEOUT;
        break;
      default:
        throw Assert.fail('runTimer spec step specified unknown timer: $timer');
    }

    queue.runDelayedTasksUntil(timerId);
  }

  /*p*/
  Future<void> doDisableNetwork() /*throws Exception*/ async {
    networkEnabled = false;
    // Make sure to execute all writes that are currently queued. This allows us
    // to assert on the total number of requests sent before shutdown.
    await remoteStore.fillWritePipeline();
    remoteStore.disableNetwork();
  }

  /*p*/
  Future<void> doEnableNetwork() /*throws Exception*/ async {
    networkEnabled = true;
    await remoteStore.enableNetwork();
  }

  /*p*/
  Future<void> doChangeUser(String uid) /*throws Exception*/ async {
    currentUser = User(uid);
    await syncEngine.handleCredentialChange(currentUser);
  }

  /*p*/
  Future<void> doRestart() /*throws Exception*/ async {
    remoteStore.shutdown();
    await localPersistence.shutdown();
    await initClient();
  }

  /*p*/
  Future<void> doStep(Map<String, dynamic> step) /*throws Exception*/ async {
    if (step['clientIndex'] != null) {
      throw Assert.fail(
          'The Android client does not support switching clients');
    }

    if (step.containsKey('userListen')) {
      await doListen(step['userListen'] as List<dynamic>);
    } else if (step.containsKey('userUnlisten')) {
      doUnlisten(step['userUnlisten'] as List<dynamic>);
    } else if (step.containsKey('userSet')) {
      await doSet(step['userSet'] as List<dynamic>);
    } else if (step.containsKey('userPatch')) {
      await doPatch(step['userPatch'] as List<dynamic>);
    } else if (step.containsKey('userDelete')) {
      await doDelete(step['userDelete'] as String);
    } else if (step.containsKey('drainQueue')) {
      // TODO:{05/10/2018 12:05}-long1eu: add a comment here to explain why are we not using this
      print('drainQueue??');
    } else if (step.containsKey('watchAck')) {
      doWatchAck(step['watchAck'] as List<dynamic>);
    } else if (step.containsKey('watchCurrent')) {
      doWatchCurrent(step['watchCurrent'] as List<dynamic>);
    } else if (step.containsKey('watchRemove')) {
      doWatchRemove(step['watchRemove'] as Map<String, dynamic>);
    } else if (step.containsKey('watchEntity')) {
      doWatchEntity(step['watchEntity'] as Map<String, dynamic>);
    } else if (step.containsKey('watchFilter')) {
      doWatchFilter(step['watchFilter'] as List<dynamic>);
    } else if (step.containsKey('watchReset')) {
      doWatchReset(step['watchReset'] as List<dynamic>);
    } else if (step.containsKey('watchSnapshot')) {
      doWatchSnapshot(step['watchSnapshot'] as Map<String, dynamic>);
    } else if (step.containsKey('watchStreamClose')) {
      doWatchStreamClose(step['watchStreamClose'] as Map<String, dynamic>);
    } else if (step.containsKey('watchProto')) {
      // watchProto isn't yet used, and it's unclear how to create arbitrary
      // protos from JSON.
      throw Assert.fail('watchProto is not yet supported.');
    } else if (step.containsKey('writeAck')) {
      doWriteAck(step['writeAck'] as Map<String, dynamic>);
    } else if (step.containsKey('failWrite')) {
      doFailWrite(step['failWrite'] as Map<String, dynamic>);
    } else if (step.containsKey('runTimer')) {
      doRunTimer(step['runTimer'] as String);
    } else if (step.containsKey('enableNetwork')) {
      if (step['enableNetwork'] as bool) {
        await doEnableNetwork();
      } else {
        await doDisableNetwork();
      }
    } else if (step.containsKey('changeUser')) {
      // NOTE: Map<String, dynamic>.getString('foo') where 'foo' is mapped to
      // null will return 'null'. Explicitly testing for isNull here allows the
      // null value to be preserved. This is important because the
      // unauthenticated user is represented as having a null uid as a value for
      // 'changeUser'.
      final String uid = step['changeUser'];
      await doChangeUser(uid);
    } else if (step.containsKey('restart')) {
      await doRestart();
    } else if (step.containsKey('applyClientState')) {
      throw Assert.fail(
          '"applyClientState"is not supported on Android and should only be used in multi-client tests');
    } else {
      throw Assert.fail('Unknown step: $step');
    }
  }

  //
  // Methods for validating expectations.
  //

  /*p*/
  void assertEventMatches(Map<String, dynamic> expected,
      QueryEvent actual) /*throws JSONException*/ {
    final Query expectedQuery = parseQuery(expected['query']);
    expect(actual.query, expectedQuery);
    if (expected.containsKey('errorCode') &&
        expected['errorCode'] != StatusCode.ok) {
      expect(actual.error, isNotNull);
      expect(actual.error.code, expected['errorCode']);
    } else {
      final List<DocumentViewChange> expectedChanges = <DocumentViewChange>[];
      final List<dynamic> removed = expected['removed'];
      for (int i = 0; removed != null && i < removed.length; ++i) {
        expectedChanges.add(parseChange(
            removed[i] as List<dynamic>, DocumentViewChangeType.removed));
      }

      final List<dynamic> added = expected['added'];
      for (int i = 0; added != null && i < added.length; ++i) {
        expectedChanges.add(parseChange(
            added[i] as List<dynamic>, DocumentViewChangeType.added));
      }
      final List<dynamic> modified = expected['modified'];
      for (int i = 0; modified != null && i < modified.length; ++i) {
        expectedChanges.add(parseChange(
            modified[i] as List<dynamic>, DocumentViewChangeType.modified));
      }

      final List<dynamic> metadata = expected['metadata'];
      for (int i = 0; metadata != null && i < metadata.length; ++i) {
        expectedChanges.add(parseChange(
            metadata[i] as List<dynamic>, DocumentViewChangeType.metadata));
      }
      expect(actual.view.changes, expectedChanges);

      final bool expectedHasPendingWrites =
          expected['hasPendingWrites'] ?? false;
      final bool expectedFromCache = expected['fromCache'] ?? false;
      expect(actual.view.hasPendingWrites, expectedHasPendingWrites,
          reason: 'hasPendingWrites');
      expect(actual.view.isFromCache, expectedFromCache, reason: 'fromCache');
    }
  }

  /*p*/
  void validateStepExpectations(
      List<dynamic> stepExpectations) /*throws JSONException*/ {
    if (stepExpectations == null) {
      for (QueryEvent event in events) {
        fail('Unexpected event: $event');
      }
      return;
    }

    // Sort both the expected and actual events by the query's canonical ID.
    events.sort((QueryEvent q1, QueryEvent q2) =>
        q1.query.canonicalId.compareTo(q2.query.canonicalId));

    final List<Map<String, dynamic>> expectedEvents = <Map<String, dynamic>>[];
    for (int i = 0; i < stepExpectations.length; ++i) {
      expectedEvents.add(stepExpectations[i] as Map<String, dynamic>);
    }
    expectedEvents
        .sort((Map<String, dynamic> left, Map<String, dynamic> right) {
      final Query leftQuery = parseQuery(left['query']);
      final Query rightQuery = parseQuery(right['query']);
      return leftQuery.canonicalId.compareTo(rightQuery.canonicalId);
    });

    int i = 0;
    for (; i < expectedEvents.length && i < events.length; ++i) {
      assertEventMatches(expectedEvents[i], events[i]);
    }

    for (; i < stepExpectations.length; ++i) {
      fail('Missing event: ${stepExpectations[i]}');
    }

    for (; i < events.length; ++i) {
      fail('Unexpected event: ${events[i]}');
    }
  }

  /*p*/
  void validateStateExpectations(
      Map<String, dynamic> expected) /*throws JSONException*/ {
    if (expected != null) {
      if (expected.containsKey('numOutstandingWrites')) {
        expect(writesSent(), expected['numOutstandingWrites']);
      }

      if (expected.containsKey('writeStreamRequestCount')) {
        expect(datastore.writeStreamRequestCount,
            expected['writeStreamRequestCount']);
      }

      if (expected.containsKey('watchStreamRequestCount')) {
        expect(datastore.watchStreamRequestCount,
            expected['watchStreamRequestCount']);
      }

      if (expected.containsKey('limboDocs')) {
        expectedLimboDocs = Set<DocumentKey>();
        final List<dynamic> limboDocs = expected['limboDocs'];
        for (int i = 0; i < limboDocs.length; i++) {
          expectedLimboDocs.add(TestUtil.key(limboDocs[i] as String));
        }
      }

      if (expected.containsKey('activeTargets')) {
        expectedActiveTargets = <int, QueryData>{};
        final Map<String, dynamic> activeTargets = expected['activeTargets'];
        final Iterable<String> keys = activeTargets.keys;

        for (String targetIdString in keys) {
          final int targetId = int.tryParse(targetIdString);
          final Map<String, dynamic> queryDataJson =
              activeTargets[targetIdString];
          final Query query = parseQuery(queryDataJson['query']);
          final String resumeToken = queryDataJson['resumeToken'];

          // TODO: populate the purpose of the target once it's possible to
          // encode that in the spec tests. For now, hard-code that it's a
          // listen despite the fact that it's not always the right value.
          expectedActiveTargets[targetId] = QueryData(
            query,
            targetId,
            TestUtil.arbitrarySequenceNumber,
            QueryPurpose.listen,
            SnapshotVersion.none,
            Uint8List.fromList(utf8.encode(resumeToken)),
          );
        }
      }
    }

    // Always validate the we received the expected number of events.
    validateUserCallbacks(expected);
    // Always validate that the expected limbo docs match the actual limbo docs.
    validateLimboDocs();
    // Always validate that the expected active targets match the actual active
    // targets.
    validateActiveTargets();
  }

  /*p*/
  void validateUserCallbacks(
      Map<String, dynamic> expected) /*throws JSONException*/ {
    if (expected != null && expected.containsKey('userCallbacks')) {
      final Map<String, dynamic> userCallbacks = expected['userCallbacks'];

      final List<dynamic> expectedAcknowledgedDocs =
          userCallbacks['acknowledgedDocs'];
      for (int i = 0; i < expectedAcknowledgedDocs.length; i++) {
        final String documentKey = expectedAcknowledgedDocs[i];
        expect(acknowledgedDocs.contains(key(documentKey)), isTrue,
            reason: 'Expected acknowledgment for $documentKey');
      }

      final List<dynamic> expectedRejectedDocs = userCallbacks['rejectedDocs'];
      for (int i = 0; i < expectedRejectedDocs.length; i++) {
        final String documentKey = expectedRejectedDocs[i];
        expect(rejectedDocs.contains(key(documentKey)), isTrue,
            reason: 'Expected rejection for $documentKey');
      }
    } else {
      expect(acknowledgedDocs, isEmpty);
      expect(rejectedDocs, isEmpty);
    }
  }

  /*p*/
  void validateLimboDocs() {
    // Make a copy so it can modified while checking against the expected limbo
    // docs.
    final Map<DocumentKey, int> actualLimboDocs =
        Map<DocumentKey, int>.from(syncEngine.getCurrentLimboDocuments());

    // Validate that each limbo doc has an expected active target
    for (MapEntry<DocumentKey, int> limboDoc in actualLimboDocs.entries) {
      expect(expectedActiveTargets.containsKey(limboDoc.value), isTrue);
    }

    for (DocumentKey expectedLimboDoc in expectedLimboDocs) {
      expect(actualLimboDocs.containsKey(expectedLimboDoc), isTrue);
      actualLimboDocs.remove(expectedLimboDoc);
    }
    expect(actualLimboDocs, isEmpty);
  }

  /*p*/
  void validateActiveTargets() {
    if (!networkEnabled) {
      return;
    }

    // Create a copy so we can modify it in tests
    final Map<int, QueryData> actualTargets =
        Map<int, QueryData>.from(datastore.activeTargets());

    for (MapEntry<int, QueryData> expected in expectedActiveTargets.entries) {
      expect(actualTargets.containsKey(expected.key), isTrue);

      final QueryData expectedTarget = expected.value;
      final QueryData actualTarget = actualTargets[expected.key];

      // TODO: validate the purpose of the target once it's possible to encode
      // that in the spec tests. For now, only validate properties that can be
      // validated.
      // expect(actualTarget, expectedTarget);

      expect(actualTarget.query, expectedTarget.query);
      expect(actualTarget.targetId, expectedTarget.targetId);
      expect(actualTarget.snapshotVersion, expectedTarget.snapshotVersion);
      expect(utf8.decode(actualTarget.resumeToken),
          utf8.decode(expectedTarget.resumeToken));
      actualTargets.remove(expected.key);
    }

    expect(actualTargets, isEmpty);
  }

  /*p*/
  Future<void> runSteps(List<dynamic> steps,
      Map<String, dynamic> config) /*throws Exception*/ async {
    await specSetUp(config);
    for (int i = 0; i < steps.length; ++i) {
      final Map<String, dynamic> step = steps[i];
      final List<dynamic> expect = step.remove('expect');
      final Map<String, dynamic> stateExpect = step.remove('stateExpect');

      log('    Doing step $step');
      await doStep(step);

      if (expect != null) {
        log('      Validating step expectations $expect');
      }

      validateStepExpectations(expect);
      if (stateExpect != null) {
        log('      Validating state expectations $stateExpect');
      }
      validateStateExpectations(stateExpect);
      events.clear();
      acknowledgedDocs.clear();
      rejectedDocs.clear();
    }
    /*
    try {} finally {
      // Ensure that Persistence is torn down even if the test is failing due to
      // a thrown exception so that any open databases are closed. This is
      // important when the LocalStore is backed by SQLite because SQLite opens
      // databases in exclusive mode. If tearDownForSpec were not called after
      // an exception then subsequent attempts to open the SQLite database will
      // fail, making it harder to zero in on the spec tests as a culprit.
      print('finaly');
      await specTearDown();
    }
    */
  }

  /*p*/
  static bool anyTestsAreMarkedExclusive(
      Map<String, dynamic> fileJSON) /*throws JSONException*/ {
    for (String key in fileJSON.keys) {
      final Map<String, dynamic> testJSON = fileJSON[key];
      if (getTestTags(testJSON).contains(exclusiveTag)) {
        return true;
      }
    }

    return false;
  }

  /// Called before executing each test to see if it should be run.
  /*p*/
  bool shouldRunTest(Set<String> tags) {
    return shouldRun(tags);
  }

  /*p*/
  static Set<String> getTestTags(
      Map<String, dynamic> testJSON) /*throws JSONException*/ {
    final List<dynamic> tagsJSON = testJSON['tags'];
    final Set<String> tags = Set<String>();
    for (int i = 0; i < tagsJSON.length; i++) {
      tags.add(tagsJSON[i] as String);
    }
    return tags;
  }

  //
  // RemoteStoreCallback Methods
  //

  @override
  Future<void> handleRemoteEvent(RemoteEvent remoteEvent) async {
    await syncEngine.handleRemoteEvent(remoteEvent);
  }

  @override
  Future<void> handleRejectedListen(int targetId, GrpcError error) async {
    await syncEngine.handleRejectedListen(targetId, error);
  }

  @override
  Future<void> handleSuccessfulWrite(
      MutationBatchResult mutationBatchResult) async {
    await syncEngine.handleSuccessfulWrite(mutationBatchResult);
  }

  @override
  Future<void> handleRejectedWrite(int batchId, GrpcError error) async {
    await syncEngine.handleRejectedWrite(batchId, error);
  }

  @override
  ImmutableSortedSet<DocumentKey> Function(int) get getRemoteKeysForTarget =>
      (int targetId) => syncEngine.getRemoteKeysForTarget(targetId);
}

// ignore: always_specify_types
const filter = TestUtil.filter;
// ignore: always_specify_types
const doc = TestUtil.doc;
// ignore: always_specify_types
const setMutation = TestUtil.setMutation;
// ignore: always_specify_types
const patchMutation = TestUtil.patchMutation;
// ignore: always_specify_types
const deleteMutation = TestUtil.deleteMutation;
// ignore: always_specify_types
const version = TestUtil.version;
// ignore: always_specify_types
const key = TestUtil.key;

class Pair<F, S> {
  final F first;
  final S second;

  Pair(this.first, this.second);
}
