// Oracle: Android androidTest/.../core/persistence/PersistenceTest.java, one test per upstream test,
// in upstream order. The sync tree tests run on SyncTree + DefaultPersistenceManager over the engine
// [runPersistenceOracle] is given; the Repo tests run on the public API with that engine as forced
// persistence (Android setForcedPersistentCache) and a FakeDatabaseServer answering what the real
// server would.
//
// Android's newTestPersistenceManager sets disableTransactionCheck on its mock engine and calls the
// manager outside transactions; the interface has no such switch, so those direct manager calls run
// inside manager.runInTransaction instead.
import 'dart:async';

import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:firebase_database_dart/src/api/fake_database_server.dart';
import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/connection/listen_hash_provider.dart';
import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/core/event_registration.dart';
import 'package:firebase_database_dart/src/core/listen_provider.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/persistence/cache_policy.dart';
import 'package:firebase_database_dart/src/core/persistence/default_persistence_manager.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_manager.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_storage_engine.dart';
import 'package:firebase_database_dart/src/core/persistence/tracked_query.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/sync_tree.dart';
import 'package:firebase_database_dart/src/core/tag.dart';
import 'package:firebase_database_dart/src/core/user_write_record.dart';
import 'package:firebase_database_dart/src/core/util/server_values.dart';
import 'package:firebase_database_dart/src/core/view/cache_node.dart';
import 'package:firebase_database_dart/src/core/view/change.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';
import 'package:firebase_database_dart/src/core/view/query_params.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:test/test.dart';

import '../api/support/fake_time.dart';
import 'oracle_support.dart';

void main() => runPersistenceOracle(openInMemoryEngine);

/// Android `PersistenceTest.TestEventRegistration`: every event is a value-typed DataEvent whose
/// snapshot sits at the query path (value) or at the child's path (child events).
final class _TestEventRegistration extends EventRegistration {
  _TestEventRegistration(this.querySpec, this._types);

  @override
  final QuerySpec querySpec;

  final List<EventType> _types;

  @override
  bool respondsTo(EventType type) => _types.contains(type);

  @override
  DataEvent createEvent(Change change, QuerySpec query) => DataEvent(
    EventType.value,
    this,
    change.eventType == EventType.value
        ? query.path
        : query.path.child(change.childKey!),
    change.node,
  );

  @override
  void fireEvent(DataEvent event) {}

  @override
  void fireCancelEvent(DatabaseError error) {}

  @override
  EventRegistration clone(QuerySpec newQuery) =>
      _TestEventRegistration(newQuery, _types);

  @override
  bool isSameListener(EventRegistration other) => identical(other, this);
}

EventRegistration _testEventRegistration(
  QuerySpec query, [
  List<EventType> types = const <EventType>[],
]) => _TestEventRegistration(query, types);

/// Android `MockListenProvider`.
final class _MockListenProvider implements ListenProvider {
  final Set<QuerySpec> _listens = <QuerySpec>{};

  bool hasListen(QuerySpec query) => _listens.contains(query);

  @override
  List<Event> startListening(
    QuerySpec query,
    Tag? tag,
    ListenHashProvider hash,
    ListenCompletion onComplete,
  ) {
    _listens.add(query);
    return const <Event>[];
  }

  @override
  void stopListening(QuerySpec query, Tag? tag) => _listens.remove(query);
}

Map<String, Object?> _serverValuesNow() =>
    generateServerValues(timestamp: DateTime.now().millisecondsSinceEpoch);

/// The PersistenceTest suite against the engines [openEngine] opens (clean ones).
void runPersistenceOracle(OpenEngine openEngine) {
  final QuerySpec defaultFooQuery = defaultQueryAt('foo');
  final QuerySpec limit3FooQuery = QuerySpec(
    p('foo'),
    QueryParams.defaultParams.limitToLast(3),
  );
  final QuerySpec limit2FooQuery = QuerySpec(
    p('foo'),
    QueryParams.defaultParams.limitToLast(2),
  );

  final List<PersistenceStorageEngine> opened = <PersistenceStorageEngine>[];

  PersistenceStorageEngine newEngine() {
    final PersistenceStorageEngine engine = openEngine();
    opened.add(engine);
    return engine;
  }

  tearDown(() {
    for (final PersistenceStorageEngine engine in opened) {
      engine.close();
    }
    opened.clear();
  });

  ({PersistenceManager manager, PersistenceStorageEngine engine})
  newTestPersistence() {
    final PersistenceStorageEngine engine = newEngine();
    return (
      manager: DefaultPersistenceManager(
        engine,
        CachePolicy.none,
        DateTime.now,
      ),
      engine: engine,
    );
  }

  PersistenceManager newTestPersistenceManager() =>
      newTestPersistence().manager;

  /// Android `newTestSyncTree`.
  SyncTree newTestSyncTree(
    PersistenceManager persistenceManager, {
    List<UserWriteRecord> records = const <UserWriteRecord>[],
    ListenProvider? listenProvider,
  }) {
    final SyncTree tree = SyncTree(
      listenProvider: listenProvider ?? _MockListenProvider(),
      persistenceManager: persistenceManager,
    );
    for (final UserWriteRecord record in records) {
      if (record.isOverwrite) {
        tree.applyUserOverwrite(
          record.path,
          record.overwrite!,
          record.overwrite!,
          record.writeId,
          visible: true,
          persist: true,
        );
      } else {
        tree.applyUserMerge(
          record.path,
          record.merge!,
          record.merge!,
          record.writeId,
          persist: true,
        );
      }
    }
    return tree;
  }

  void applyUserOverwrite(SyncTree tree, Path path, Node node, int id) => tree
      .applyUserOverwrite(path, node, node, id, visible: true, persist: true);

  void assertTrackedQueriesMatch(
    List<QuerySpec> expected,
    List<TrackedQuery> actual,
  ) {
    expect(actual.length, expected.length, reason: '$actual vs $expected');
    final Set<QuerySpec> expectedSet = expected.toSet();
    for (final TrackedQuery trackedQuery in actual) {
      expect(expectedSet.contains(trackedQuery.querySpec), isTrue);
    }
  }

  /// Runs [body] in a fake clock (the public API's timers) and lets it settle at the end.
  void withTime(void Function(FakeTime time) body) =>
      fakeTime<void>((FakeTime time) {
        body(time);
        time.elapse(Duration.zero);
      });

  /// Android `goOnline(cfg)` followed by the reconnect.
  void reconnect(FakeTime time, FirebaseDatabase db) {
    db.goOnline();
    time.elapse(const Duration(seconds: 2));
  }

  group('PersistenceTest', () {
    test('listenRaisesValueEventWithCachedData', () {
      final PersistenceManager manager = newTestPersistenceManager();
      manager.runInTransaction(() {
        manager.setQueryActive(defaultFooQuery);
        manager.updateServerCache(defaultFooQuery, n('leaf-value'));
      });

      final SyncTree tree = newTestSyncTree(manager);

      final List<Event> events = tree.addEventRegistration(
        _testEventRegistration(defaultFooQuery, <EventType>[EventType.value]),
      );
      expect(events.length, 1);
      final DataEvent event = events[0] as DataEvent;
      expect(event.path, p('foo'));
      expect(event.snapshot.value, 'leaf-value');
    });

    test('listenRaisesValueEventWithCachedDataForQuery', () {
      final PersistenceManager manager = newTestPersistenceManager();
      final Map<String, Object?> data = <String, Object?>{
        'a': '1',
        'b': '2',
        'c': '3',
        'd': '4',
      };
      manager.runInTransaction(() {
        manager.setQueryActive(limit3FooQuery);
        manager.setTrackedQueryKeys(
          limit3FooQuery,
          childKeySet(<String>['b', 'c', 'd']),
        );
        manager.updateServerCache(limit3FooQuery, n(data));
      });

      final SyncTree tree = newTestSyncTree(manager);

      final List<Event> events = tree.addEventRegistration(
        _testEventRegistration(limit3FooQuery, <EventType>[EventType.value]),
      );
      expect(events.length, 1);
      final DataEvent event = events[0] as DataEvent;
      expect(event.path, p('foo'));
      expect(event.snapshot.value, <String, Object?>{
        'b': '2',
        'c': '3',
        'd': '4',
      });
    });

    test('listenRaisesNoValueButCachedChildEventsForIncompleteQueries', () {
      final PersistenceManager manager = newTestPersistenceManager();
      manager.runInTransaction(() {
        manager.setQueryActive(defaultQueryAt('foo/a'));
        manager.setQueryActive(defaultQueryAt('foo/b'));
        manager.setQueryActive(defaultQueryAt('foo/c'));
        manager.setQueryActive(defaultQueryAt('foo/d'));

        manager.updateServerCache(defaultQueryAt('foo/a'), n('1'));
        manager.updateServerCache(defaultQueryAt('foo/b'), n('2'));
        manager.updateServerCache(defaultQueryAt('foo/c'), n('3'));
        manager.updateServerCache(defaultQueryAt('foo/d'), n('4'));
      });

      final SyncTree tree = newTestSyncTree(manager);

      final List<Event> events = tree.addEventRegistration(
        _testEventRegistration(defaultFooQuery, <EventType>[
          EventType.value,
          EventType.childAdded,
        ]),
      );
      expect(events.length, 4);
      final DataEvent event1 = events[0] as DataEvent;
      expect(event1.path, p('foo/a'));
      expect(event1.snapshot.value, '1');

      final DataEvent event2 = events[1] as DataEvent;
      expect(event2.path, p('foo/b'));
      expect(event2.snapshot.value, '2');

      final DataEvent event3 = events[2] as DataEvent;
      expect(event3.path, p('foo/c'));
      expect(event3.snapshot.value, '3');

      final DataEvent event4 = events[3] as DataEvent;
      expect(event4.path, p('foo/d'));
      expect(event4.snapshot.value, '4');
    });

    test(
      'listenRaisesNoValueButCachedChildEventsForIncompleteNonDefaultQueries',
      () {
        final PersistenceManager manager = newTestPersistenceManager();
        manager.runInTransaction(() {
          manager.setQueryActive(defaultQueryAt('foo/a'));
          manager.setQueryActive(defaultQueryAt('foo/b'));
          manager.setQueryActive(defaultQueryAt('foo/c'));
          manager.setQueryActive(defaultQueryAt('foo/d'));

          manager.updateServerCache(defaultQueryAt('foo/a'), n('1'));
          manager.updateServerCache(defaultQueryAt('foo/b'), n('2'));
          manager.updateServerCache(defaultQueryAt('foo/c'), n('3'));
          manager.updateServerCache(defaultQueryAt('foo/d'), n('4'));
        });

        final SyncTree tree = newTestSyncTree(manager);

        final List<Event> events = tree.addEventRegistration(
          _testEventRegistration(limit3FooQuery, <EventType>[
            EventType.value,
            EventType.childAdded,
          ]),
        );
        expect(events.length, 3);

        final DataEvent event1 = events[0] as DataEvent;
        expect(event1.path, p('foo/b'));
        expect(event1.snapshot.value, '2');

        final DataEvent event2 = events[1] as DataEvent;
        expect(event2.path, p('foo/c'));
        expect(event2.snapshot.value, '3');

        final DataEvent event3 = events[2] as DataEvent;
        expect(event3.path, p('foo/d'));
        expect(event3.snapshot.value, '4');
      },
    );

    test('listenRaisesValueEventIfQueryWasMarkedComplete', () {
      final PersistenceManager manager = newTestPersistenceManager();
      manager.runInTransaction(() {
        manager.setQueryActive(limit3FooQuery);
        manager.updateServerCache(defaultQueryAt('foo/a'), n('1'));
        manager.updateServerCache(defaultQueryAt('foo/b'), n('2'));
        manager.updateServerCache(defaultQueryAt('foo/c'), n('3'));
        manager.updateServerCache(defaultQueryAt('foo/d'), n('4'));
        manager.setTrackedQueryKeys(
          limit3FooQuery,
          childKeySet(<String>['b', 'c', 'd']),
        );
        manager.setQueryComplete(limit3FooQuery);
      });

      final SyncTree tree = newTestSyncTree(manager);

      final List<Event> events = tree.addEventRegistration(
        _testEventRegistration(limit3FooQuery, <EventType>[EventType.value]),
      );
      expect(events.length, 1);
      final DataEvent event = events[0] as DataEvent;
      expect(event.path, p('foo'));
      expect(event.snapshot.value, <String, Object?>{
        'b': '2',
        'c': '3',
        'd': '4',
      });

      final List<Event> events2 = tree.addEventRegistration(
        _testEventRegistration(limit2FooQuery, <EventType>[EventType.value]),
      );
      expect(events2.length, 0);
    });

    test('persistedWritesAreUsed', () {
      final PersistenceManager manager = newTestPersistenceManager();
      manager.runInTransaction(() {
        manager.setQueryActive(limit3FooQuery);
        manager.updateServerCache(defaultQueryAt('foo/a'), n('1'));
        manager.updateServerCache(defaultQueryAt('foo/b'), n('2'));
        manager.updateServerCache(defaultQueryAt('foo/c'), n('3'));
        manager.updateServerCache(defaultQueryAt('foo/d'), n('4'));
        manager.setQueryComplete(limit3FooQuery);
      });

      final UserWriteRecord write1 = UserWriteRecord.overwrite(
        1,
        p('foo/b'),
        n('new-b-value'),
        visible: true,
      );
      final UserWriteRecord write2 = UserWriteRecord.merge(
        2,
        p('foo'),
        CompoundWrite.fromPathMerge(<Path, Node>{
          p('d'): n('prev-d-value'),
          p('f'): n('f-value'),
        }),
      );
      final UserWriteRecord write3 = UserWriteRecord.overwrite(
        3,
        p('foo/d'),
        n('new-d-value'),
        visible: true,
      );
      final UserWriteRecord write4 = UserWriteRecord.overwrite(
        4,
        p('foo/e'),
        n('e-value'),
        visible: true,
      );

      final SyncTree tree = newTestSyncTree(
        manager,
        records: <UserWriteRecord>[write1, write2, write3, write4],
      );

      final List<Event> events = tree.addEventRegistration(
        _testEventRegistration(limit3FooQuery, <EventType>[EventType.value]),
      );
      expect(events.length, 1);
      final DataEvent event = events[0] as DataEvent;
      expect(event.path, p('foo'));
      expect(event.snapshot.value, <String, Object?>{
        'd': 'new-d-value',
        'e': 'e-value',
        'f': 'f-value',
      });
    });

    test('persistedWritesAreUsedInRepo', () {
      final (:PersistenceManager manager, :PersistenceStorageEngine engine) =
          newTestPersistence();
      manager.runInTransaction(() {
        manager.setQueryActive(limit3FooQuery);
        manager.updateServerCache(defaultQueryAt('foo/a'), n('1'));
        manager.updateServerCache(defaultQueryAt('foo/b'), n('2'));
        manager.updateServerCache(defaultQueryAt('foo/c'), n('3'));
        manager.updateServerCache(defaultQueryAt('foo/d'), n('4'));
        manager.setQueryComplete(limit3FooQuery);

        manager.saveUserOverwrite(p('foo/b'), n('new-b-value'), 1);
        manager.saveUserMerge(
          p('foo'),
          CompoundWrite.fromPathMerge(<Path, Node>{
            p('d'): n('prev-d-value'),
            p('f'): n('f-value'),
          }),
          2,
        );
        manager.saveUserOverwrite(p('foo/d'), n('new-d-value'), 3);
        manager.saveUserOverwrite(p('foo/e'), n('e-value'), 4);
      });

      withTime((FakeTime time) {
        final FirebaseDatabase db = oracleDatabase(
          FakeDatabaseServer(),
          engine: engine,
        );
        final DatabaseReference ref = db.ref().root.child('foo');

        db.goOffline();

        final List<DatabaseEvent> records = <DatabaseEvent>[];
        final StreamSubscription<DatabaseEvent> sub = ref
            .limitToLast(3)
            .onValue
            .listen(records.add);
        time.elapse(Duration.zero);
        unawaited(sub.cancel());

        expect(records, isNotEmpty, reason: 'no event');
        final DatabaseEvent record = records[0];
        expect(record.type, DatabaseEventType.value);
        expect(record.snapshot.value, <String, Object?>{
          'd': 'new-d-value',
          'e': 'e-value',
          'f': 'f-value',
        });
      });
    });

    test('persistedWritesCanLeadToValueEvents', () {
      final PersistenceManager manager = newTestPersistenceManager();
      manager.runInTransaction(() {
        manager.updateServerCache(defaultQueryAt('foo/a'), n('1'));
        manager.updateServerCache(defaultQueryAt('foo/b'), n('2'));
        manager.updateServerCache(defaultQueryAt('foo/c'), n('3'));
      });

      final Node writeNode = n(<String, Object?>{'foo': 'bar'});

      final SyncTree tree = newTestSyncTree(
        manager,
        records: <UserWriteRecord>[
          UserWriteRecord.overwrite(1, p('foo'), writeNode, visible: true),
        ],
      );

      final List<Event> events = tree.addEventRegistration(
        _testEventRegistration(defaultFooQuery, <EventType>[EventType.value]),
      );
      expect(events.length, 1);
      final DataEvent event = events[0] as DataEvent;
      expect(event.path, p('foo'));
      expect(event.snapshot.value, <String, Object?>{'foo': 'bar'});
    });

    test('serverOperationUpdatesCacheAndMarksComplete', () {
      final (:PersistenceManager manager, :PersistenceStorageEngine engine) =
          newTestPersistence();

      final SyncTree tree = newTestSyncTree(manager);

      tree.addEventRegistration(
        _testEventRegistration(defaultFooQuery, <EventType>[EventType.value]),
      );
      tree.applyServerOverwrite(p('foo'), n('bar'));
      final Node node = engine.serverCache(p('foo'));
      expectNode(node, n('bar'));
      expect(manager.serverCache(defaultFooQuery).fullyInitialized, isTrue);
    });

    test('serverOperationMergeUpdatesCache', () {
      final (:PersistenceManager manager, :PersistenceStorageEngine engine) =
          newTestPersistence();

      final SyncTree tree = newTestSyncTree(manager);

      tree.applyServerOverwrite(
        p('foo'),
        n(<String, Object?>{'foo': 'foo-value'}),
      );
      tree.applyServerMerge(p('foo'), <Path, Node>{
        p('bar'): n('bar-value'),
        p('baz'): n('baz-value'),
      });
      final Node node = engine.serverCache(p('foo'));
      final Node expected = n(<String, Object?>{
        'foo': 'foo-value',
        'bar': 'bar-value',
        'baz': 'baz-value',
      });
      expectNode(node, expected);
    });

    test('listenCompleteMarksPersistenceComplete', () {
      final PersistenceManager manager = newTestPersistenceManager();

      final SyncTree tree = newTestSyncTree(manager);
      tree.addEventRegistration(
        _testEventRegistration(defaultFooQuery, <EventType>[EventType.value]),
      );
      tree.applyListenComplete(p('foo'));
      expect(
        manager.serverCache(defaultQueryAt('foo')).fullyInitialized,
        isTrue,
      );
    });

    // this could probably happen if pruning happens at the wrong time.
    test('listenCompleteForUntrackedListenIsAllowed', () {
      final PersistenceManager manager = newTestPersistenceManager();

      final SyncTree tree = newTestSyncTree(manager);
      tree.applyListenComplete(p('foo'));
    });

    test('keepSyncedQueriesAreListenedTo', () {
      final PersistenceManager manager = newTestPersistenceManager();
      final _MockListenProvider listenProvider = _MockListenProvider();
      final SyncTree tree = newTestSyncTree(
        manager,
        listenProvider: listenProvider,
      );
      tree.keepSynced(defaultFooQuery, keep: true);
      expect(listenProvider.hasListen(defaultFooQuery), isTrue);

      // stop keeping-synced and make sure listen goes away.
      tree.keepSynced(defaultFooQuery, keep: false);
      expect(listenProvider.hasListen(defaultFooQuery), isFalse);
    });

    test('keepSyncedQueriesCacheData', () {
      final PersistenceManager manager = newTestPersistenceManager();
      final SyncTree tree = newTestSyncTree(manager);
      tree.keepSynced(defaultFooQuery, keep: true);
      tree.applyServerOverwrite(p('foo'), n('leaf-value'));

      final List<Event> events = tree.addEventRegistration(
        _testEventRegistration(defaultFooQuery, <EventType>[EventType.value]),
      );
      expect(events.length, 1);
      final DataEvent event = events[0] as DataEvent;
      expect(event.path, p('foo'));
      expect(event.snapshot.value, 'leaf-value');
    });

    test('pruningSanityCheck', () {
      final PersistenceStorageEngine storage = newEngine();
      final TestCachePolicy cachePolicy = TestCachePolicy(
        1.0,
        // Java Long.MAX_VALUE; 2^53 - 1 is the largest int every platform holds.
        9007199254740991,
      );
      final PersistenceManager manager = DefaultPersistenceManager(
        storage,
        cachePolicy,
        DateTime.now,
      );
      final SyncTree tree = newTestSyncTree(manager);

      final QuerySpec fooQuery = defaultQueryAt('foo');
      final EventRegistration fooReg = _testEventRegistration(
        fooQuery,
        <EventType>[EventType.value],
      );
      tree.addEventRegistration(fooReg);

      final QuerySpec fooDeepQuery = defaultQueryAt('foo/deep');
      final EventRegistration fooDeepReg = _testEventRegistration(
        fooDeepQuery,
        <EventType>[EventType.value],
      );
      tree.addEventRegistration(fooDeepReg);

      Map<String, Object?> data = <String, Object?>{
        'deep': 'foo-deep',
        'deep2': 'foo-deep2',
      };
      tree.applyServerOverwrite(p('foo'), n(data));

      final QuerySpec barQuery = defaultQueryAt('bar');
      final EventRegistration barReg = _testEventRegistration(
        barQuery,
        <EventType>[EventType.value],
      );
      tree.addEventRegistration(barReg);

      final QuerySpec barLimitQuery = QuerySpec(
        p('bar'),
        QueryParams.defaultParams.limitToLast(3),
      );
      final EventRegistration barLimitReg = _testEventRegistration(
        barLimitQuery,
        <EventType>[EventType.value],
      );
      tree.addEventRegistration(barLimitReg);

      data = <String, Object?>{'a': 1, 'b': 2, 'c': 3, 'd': 4};
      tree.applyServerOverwrite(p('bar'), n(data));

      final QuerySpec bazQuery = defaultQueryAt('baz');
      tree.keepSynced(bazQuery, keep: true);
      tree.applyServerOverwrite(p('baz'), n('baz-val'));

      final List<QuerySpec> expectedQueries = <QuerySpec>[
        fooQuery,
        fooDeepQuery,
        barQuery,
        barLimitQuery,
        bazQuery,
      ];
      assertTrackedQueriesMatch(expectedQueries, storage.loadTrackedQueries());

      data = <String, Object?>{
        'foo': <String, Object?>{'deep': 'foo-deep', 'deep2': 'foo-deep2'},
        'bar': <String, Object?>{'a': 1, 'b': 2, 'c': 3, 'd': 4},
        'baz': 'baz-val',
      };
      Node expectedData = n(data);
      expectNode(storage.serverCache(Path.empty), expectedData);

      // Trigger pruning (nothing should happen).
      cachePolicy.pruneOnNextServerUpdate();
      tree.applyServerMerge(Path.empty, <Path, Node>{});
      assertTrackedQueriesMatch(expectedQueries, storage.loadTrackedQueries());
      expectNode(storage.serverCache(Path.empty), expectedData);

      // Remove /foo listener.  Query should be pruned, and foo/deep2 removed.
      tree.removeEventRegistration(fooReg);
      cachePolicy.pruneOnNextServerUpdate();
      tree.applyServerMerge(Path.empty, <Path, Node>{});
      expectedQueries.remove(fooQuery);
      expectedData = expectedData.updateChild(
        p('foo/deep2'),
        ChildrenNode.empty,
      );
      assertTrackedQueriesMatch(expectedQueries, storage.loadTrackedQueries());
      expectNode(storage.serverCache(Path.empty), expectedData);

      // Remove /bar listener.  Query should be pruned, but no data removed.
      tree.removeEventRegistration(barReg);
      cachePolicy.pruneOnNextServerUpdate();
      tree.applyServerMerge(Path.empty, <Path, Node>{});
      expectedQueries.remove(barQuery);
      assertTrackedQueriesMatch(expectedQueries, storage.loadTrackedQueries());
      expectNode(storage.serverCache(Path.empty), expectedData);

      // Remove keep-synced baz query.  Query and data should be pruned.
      tree.keepSynced(bazQuery, keep: false);
      expectedQueries.remove(bazQuery);
      cachePolicy.pruneOnNextServerUpdate();
      tree.applyServerMerge(Path.empty, <Path, Node>{});
      expectedData = expectedData.updateChild(p('baz'), ChildrenNode.empty);
      assertTrackedQueriesMatch(expectedQueries, storage.loadTrackedQueries());
      expectNode(storage.serverCache(Path.empty), expectedData);

      // Remove foo/deep and bar limit 3 listens.  Everything should be pruned.
      tree.removeEventRegistration(fooDeepReg);
      tree.removeEventRegistration(barLimitReg);
      cachePolicy.pruneOnNextServerUpdate();
      tree.applyServerMerge(Path.empty, <Path, Node>{});

      expectedData = ChildrenNode.empty;
      expectedQueries.clear();
      assertTrackedQueriesMatch(expectedQueries, storage.loadTrackedQueries());
      expectNode(storage.serverCache(Path.empty), expectedData);
      expectNode(storage.serverCache(Path.empty), expectedData);
    });

    test('pruningDoesOldestFirst', () {
      final PersistenceStorageEngine storage = newEngine();
      final TestCachePolicy cachePolicy = TestCachePolicy(
        0.5,
        // Java Long.MAX_VALUE; 2^53 - 1 is the largest int every platform holds.
        9007199254740991,
      );
      final TestClock clock = TestClock();
      final PersistenceManager manager = DefaultPersistenceManager(
        storage,
        cachePolicy,
        clock.call,
      );
      final QuerySpec fooQuery = defaultQueryAt('foo');
      final QuerySpec barQuery = defaultQueryAt('bar');
      final QuerySpec bazQuery = defaultQueryAt('baz');
      final QuerySpec quxQuery = defaultQueryAt('qux');

      final EventRegistration dummyRegFoo = _testEventRegistration(
        fooQuery,
        <EventType>[EventType.value],
      );
      final EventRegistration dummyRegBar = _testEventRegistration(
        barQuery,
        <EventType>[EventType.value],
      );
      final EventRegistration dummyRegBaz = _testEventRegistration(
        bazQuery,
        <EventType>[EventType.value],
      );
      final EventRegistration dummyRegQux = _testEventRegistration(
        quxQuery,
        <EventType>[EventType.value],
      );
      final SyncTree tree = newTestSyncTree(manager);

      tree.addEventRegistration(dummyRegFoo);
      tree.addEventRegistration(dummyRegBar);
      tree.addEventRegistration(dummyRegBaz);
      tree.addEventRegistration(dummyRegQux);

      final Node node = n(<String, Object?>{
        'foo': 'foo-val',
        'bar': 'bar-val',
        'baz': 'baz-val',
        'qux': 'qux-val',
      });
      tree.applyServerOverwrite(p('foo'), node.getChild(p('foo')));
      tree.applyServerOverwrite(p('bar'), node.getChild(p('bar')));
      tree.applyServerOverwrite(p('baz'), node.getChild(p('baz')));
      tree.applyServerOverwrite(p('qux'), node.getChild(p('qux')));

      // Now remove everything so it's prunable.
      tree.removeEventRegistration(dummyRegFoo);
      clock.tick();
      tree.removeEventRegistration(dummyRegBar);
      clock.tick();
      tree.removeEventRegistration(dummyRegBaz);
      clock.tick();
      tree.removeEventRegistration(dummyRegQux);

      final List<QuerySpec> expectedQueries = <QuerySpec>[
        fooQuery,
        barQuery,
        bazQuery,
        quxQuery,
      ];
      Node expectedData = node;
      assertTrackedQueriesMatch(expectedQueries, storage.loadTrackedQueries());
      expectNode(storage.serverCache(Path.empty), expectedData);

      cachePolicy.pruneOnNextServerUpdate();
      tree.applyServerMerge(Path.empty, <Path, Node>{});

      // We should have pruned the oldest 50%.
      expectedQueries
        ..remove(fooQuery)
        ..remove(barQuery);
      expectedData = expectedData.updateChild(p('foo'), ChildrenNode.empty);
      expectedData = expectedData.updateChild(p('bar'), ChildrenNode.empty);
      assertTrackedQueriesMatch(expectedQueries, storage.loadTrackedQueries());
      expectNode(storage.serverCache(Path.empty), expectedData);

      // Prune the oldest 50% again (1).
      cachePolicy.pruneOnNextServerUpdate();
      tree.applyServerMerge(Path.empty, <Path, Node>{});
      expectedQueries.remove(bazQuery);
      expectedData = expectedData.updateChild(p('baz'), ChildrenNode.empty);
      assertTrackedQueriesMatch(expectedQueries, storage.loadTrackedQueries());
      expectNode(storage.serverCache(Path.empty), expectedData);

      // Prune the last one.
      cachePolicy.pruneOnNextServerUpdate();
      tree.applyServerMerge(Path.empty, <Path, Node>{});
      expectedQueries.remove(quxQuery);
      expectedData = expectedData.updateChild(p('qux'), ChildrenNode.empty);
      assertTrackedQueriesMatch(expectedQueries, storage.loadTrackedQueries());
      expectNode(storage.serverCache(Path.empty), expectedData);
    });

    test('taggedListenCompleteMarksPersistenceCompleteForThatQuery', () {
      final PersistenceManager manager = newTestPersistenceManager();
      final SyncTree tree = newTestSyncTree(manager);
      tree.addEventRegistration(_testEventRegistration(limit3FooQuery));
      tree.applyTaggedListenComplete(const Tag(1));
      expect(manager.serverCache(limit3FooQuery).fullyInitialized, isTrue);
      expect(manager.serverCache(defaultFooQuery).fullyInitialized, isFalse);
      expect(manager.serverCache(limit2FooQuery).fullyInitialized, isFalse);
    });

    test('taggedServerMergeIsApplied', () {
      final PersistenceManager manager = newTestPersistenceManager();
      final SyncTree tree = newTestSyncTree(manager);
      tree.addEventRegistration(_testEventRegistration(limit3FooQuery));
      tree.applyServerOverwrite(
        p('foo'),
        n(<String, Object?>{'foo': 'foo-value'}),
      );
      tree.applyTaggedQueryMerge(p('foo'), <Path, Node>{
        p('bar'): n('bar-value'),
        p('baz'): n('baz-value'),
      }, const Tag(1));
      final CacheNode cacheNode = manager.serverCache(limit3FooQuery);
      expect(cacheNode.fullyInitialized, isTrue);
      final Node expected = n(<String, Object?>{
        'foo': 'foo-value',
        'bar': 'bar-value',
        'baz': 'baz-value',
      });
      expectNode(cacheNode.node, expected);
    });

    test('deltaSyncTrackedKeysAreSaved', () {
      final PersistenceManager manager = newTestPersistenceManager();
      final SyncTree tree = newTestSyncTree(manager);

      // Seed some data in the cache.
      tree.addEventRegistration(
        _testEventRegistration(defaultQueryAt('foo/baz')),
      );
      tree.applyServerOverwrite(p('foo/baz'), n('two'));

      // Do a query and mark it complete for existing data.
      tree.addEventRegistration(_testEventRegistration(limit3FooQuery));
      tree.applyTaggedListenComplete(const Tag(1));

      // We should have a fully initialized cache for that query now.
      final CacheNode cacheNode = manager.serverCache(limit3FooQuery);
      expect(cacheNode.fullyInitialized, isTrue);
      final Node expected = n(<String, Object?>{'baz': 'two'});
      expectNode(cacheNode.node, expected);
    });

    test('ackIsAppliedToCacheIfNoListenExists', () {
      final PersistenceManager manager = newTestPersistenceManager();
      final SyncTree tree = newTestSyncTree(manager);
      applyUserOverwrite(tree, p('foo'), n('foo-value'), 1);
      CacheNode serverCache = manager.serverCache(defaultQueryAt('foo'));
      expect(serverCache.fullyInitialized, isFalse);
      expect(serverCache.node.isEmpty, isTrue);

      tree.ackUserWrite(
        1,
        revert: false,
        persist: true,
        serverValues: _serverValuesNow(),
      );

      serverCache = manager.serverCache(defaultQueryAt('foo'));
      expect(serverCache.fullyInitialized, isTrue);
      expectNode(serverCache.node, n('foo-value'));
    });

    test('ackIsAppliedToCacheIfNoDefaultListenExists', () {
      final PersistenceManager manager = newTestPersistenceManager();
      final SyncTree tree = newTestSyncTree(manager);
      tree.addEventRegistration(_testEventRegistration(limit3FooQuery));
      applyUserOverwrite(tree, p('foo'), n('foo-value'), 1);
      CacheNode serverCache = manager.serverCache(defaultFooQuery);
      expect(serverCache.fullyInitialized, isFalse);
      expect(serverCache.node.isEmpty, isTrue);

      tree.ackUserWrite(
        1,
        revert: false,
        persist: true,
        serverValues: _serverValuesNow(),
      );

      serverCache = manager.serverCache(defaultFooQuery);
      expect(serverCache.fullyInitialized, isTrue);
      expectNode(serverCache.node, n('foo-value'));
    });

    test('ackIsNotAppliedIfDefaultListenExists', () {
      final PersistenceManager manager = newTestPersistenceManager();
      final SyncTree tree = newTestSyncTree(manager);
      tree.addEventRegistration(_testEventRegistration(defaultFooQuery));
      applyUserOverwrite(tree, p('foo'), n('foo-value'), 1);
      CacheNode serverCache = manager.serverCache(defaultFooQuery);
      expect(serverCache.fullyInitialized, isFalse);
      expect(serverCache.node.isEmpty, isTrue);

      tree.ackUserWrite(
        1,
        revert: false,
        persist: true,
        serverValues: _serverValuesNow(),
      );

      serverCache = manager.serverCache(defaultFooQuery);
      expect(serverCache.fullyInitialized, isFalse);
      expect(serverCache.node.isEmpty, isTrue);
    });

    test('userOverwriteIsSaved', () {
      final PersistenceStorageEngine engine = newEngine();
      withTime((FakeTime time) {
        final FirebaseDatabase db = oracleDatabase(
          FakeDatabaseServer(),
          engine: engine,
        );
        final DatabaseReference ref = db.ref();
        db.goOffline();
        unawaited(ref.set('foo-value'));
        time.elapse(Duration.zero);
        final List<UserWriteRecord> records = engine.loadUserWrites();
        expect(records.length, 1);
        final UserWriteRecord record = records[0];
        expect(record.path, Path.empty);
        expect(record.writeId, 1);
        expectNode(record.overwrite!, n('foo-value'));
      });
    });

    test('userMergeIsSaved', () {
      final PersistenceStorageEngine engine = newEngine();
      withTime((FakeTime time) {
        final FirebaseDatabase db = oracleDatabase(
          FakeDatabaseServer(),
          engine: engine,
        );
        final DatabaseReference ref = db.ref();
        db.goOffline();
        unawaited(ref.update(<String, Object?>{'foo': 'foo-value'}));
        time.elapse(Duration.zero);
        final List<UserWriteRecord> records = engine.loadUserWrites();
        expect(records.length, 1);
        final UserWriteRecord record = records[0];
        expect(record.path, Path.empty);
        expect(record.writeId, 1);
        // Android compares getMerge().getValue(true) with {foo: foo-value}; CompoundWrite.toJson
        // keys paths as '/foo', so the merge is compared as a CompoundWrite.
        expect(
          record.merge,
          CompoundWrite.fromPathMerge(<Path, Node>{p('foo'): n('foo-value')}),
        );
      });
    });

    test('ackRemovesWriteFromPersistence', () {
      final PersistenceStorageEngine engine = newEngine();
      withTime((FakeTime time) {
        final FakeDatabaseServer server = FakeDatabaseServer();
        final FirebaseDatabase db = oracleDatabase(server, engine: engine);
        final DatabaseReference ref = db.ref();
        db.goOffline();
        bool done = false;
        unawaited(ref.set('foo-value').then((_) => done = true));
        time.elapse(Duration.zero);
        final List<UserWriteRecord> records = engine.loadUserWrites();
        expect(records.length, 1);
        reconnect(time, db);
        // The real server acknowledges the write.
        server.ackLastWrite();
        time.elapse(Duration.zero);
        expect(done, isTrue);
        expect(engine.loadUserWrites(), isEmpty);
      });
    });

    test('revertIsNotAppliedToCache', () {
      final PersistenceManager manager = newTestPersistenceManager();
      final SyncTree tree = newTestSyncTree(manager);
      applyUserOverwrite(tree, p('foo'), n('foo-value'), 1);

      CacheNode serverCache = manager.serverCache(defaultFooQuery);
      expect(serverCache.fullyInitialized, isFalse);
      expect(serverCache.node.isEmpty, isTrue);

      tree.ackUserWrite(
        1,
        revert: true,
        persist: true,
        serverValues: _serverValuesNow(),
      );

      serverCache = manager.serverCache(defaultFooQuery);
      expect(serverCache.fullyInitialized, isFalse);
      expect(serverCache.node.isEmpty, isTrue);
    });

    test('serverValuesArePreservedInWrite', () {
      final PersistenceStorageEngine engine = newEngine();
      withTime((FakeTime time) {
        final FirebaseDatabase db = oracleDatabase(
          FakeDatabaseServer(),
          engine: engine,
        );
        final DatabaseReference ref = db.ref();
        db.goOffline();
        unawaited(ref.set(ServerValue.timestamp));
        time.elapse(Duration.zero);
        final List<UserWriteRecord> records = engine.loadUserWrites();
        expect(records.length, 1);
        final UserWriteRecord record = records[0];
        // Compared as JSON: two leaves holding a server value map are equal only by identity
        // (JS `equals`), where Android compares the maps.
        expect(
          record.overwrite!.toJson(exportFormat: true),
          n(ServerValue.timestamp).toJson(exportFormat: true),
        );
      });
    });

    test('ackForServerValueYieldsResolvedValueInCache', () {
      final PersistenceStorageEngine engine = newEngine();
      withTime((FakeTime time) {
        final FakeDatabaseServer server = FakeDatabaseServer();
        final FirebaseDatabase db = oracleDatabase(server, engine: engine);
        final DatabaseReference ref = db.ref();
        final QuerySpec query = QuerySpec.defaultAt(Path.empty);

        bool written = false;
        unawaited(ref.set(ServerValue.timestamp).then((_) => written = true));
        time.elapse(Duration.zero);
        server.ackLastWrite();
        time.elapse(Duration.zero);
        expect(written, isTrue);

        // Android reads manager.serverCache(query); the engine holds the same node at the path.
        final Node node = engine.serverCache(query.path);
        final int drift =
            DateTime.now().millisecondsSinceEpoch - (node.value! as int);
        expect(drift.abs(), lessThan(2000));
      });
    });

    test('persistedServerValuesAreResolved', () {
      final (:PersistenceManager manager, :PersistenceStorageEngine engine) =
          newTestPersistence();
      manager.runInTransaction(
        () => manager.saveUserOverwrite(p('foo'), n(ServerValue.timestamp), 1),
      );
      withTime((FakeTime time) {
        // The server resolves the timestamp a little later than the client, so the two events
        // differ (as they do against the real server).
        final FakeDatabaseServer server = FakeDatabaseServer()
          ..serverTime = DateTime.now().add(const Duration(milliseconds: 500));
        final FirebaseDatabase db = oracleDatabase(server, engine: engine);
        final DatabaseReference ref = db.ref().root.child('foo');
        final List<DatabaseEvent> records = <DatabaseEvent>[];
        final StreamSubscription<DatabaseEvent> sub = ref.onValue.listen(
          records.add,
        );
        time.elapse(Duration.zero);
        // The real server answers the listen with what it has (nothing yet), then applies and
        // acknowledges the restored write.
        server.answerListen('foo', null);
        time.elapse(Duration.zero);
        server.ackLastWrite();
        time.elapse(Duration.zero);
        unawaited(sub.cancel());

        // There will be two events, one local and one when the server responds
        expect(records.length, greaterThanOrEqualTo(2));
        final int now = DateTime.now().millisecondsSinceEpoch;
        final int drift1 = (records[0].snapshot.value! as int) - now;
        final int drift2 = (records[1].snapshot.value! as int) - now;
        expect(drift1.abs(), lessThan(2000));
        expect(drift2.abs(), lessThan(2000));
      });
    });

    test('writeIdsAreRestored', () {
      final PersistenceStorageEngine engine = newEngine();
      withTime((FakeTime time) {
        final FirebaseDatabase db1 = oracleDatabase(
          FakeDatabaseServer(),
          engine: engine,
        );
        final DatabaseReference ref1 = db1.ref();
        db1.goOffline();
        unawaited(ref1.push().set('value-1'));
        time.elapse(Duration.zero);
        final FirebaseDatabase db2 = oracleDatabase(
          FakeDatabaseServer(),
          engine: engine,
        );
        final DatabaseReference ref2 = db2.ref();
        db2.goOffline();
        unawaited(ref2.push().set('value-2'));
        time.elapse(Duration.zero);
        final List<UserWriteRecord> writes = engine.loadUserWrites();
        int? lastWriteId;
        expect(writes.length, 2);
        for (final UserWriteRecord record in writes) {
          expect(lastWriteId == null || lastWriteId < record.writeId, isTrue);
          lastWriteId = record.writeId;
        }
      });
    });

    // There was a case where the merge was sent to the server with a slash at the beginning, which
    // was rejected by the server. This tests that a persisted merge will successfully by applied by
    // the server
    test('simpleMergeTest', () {
      final PersistenceStorageEngine engine = newEngine();
      withTime((FakeTime time) {
        final FirebaseDatabase db1 = oracleDatabase(
          FakeDatabaseServer(),
          engine: engine,
        );
        final DatabaseReference ref1 = db1.ref().push();
        db1.goOffline();
        final Map<String, Object?> updates = <String, Object?>{'foo': 'bar'};
        unawaited(ref1.update(updates));
        time.elapse(Duration.zero);

        final FakeDatabaseServer server2 = FakeDatabaseServer();
        final FirebaseDatabase db2 = oracleDatabase(server2, engine: engine);
        final DatabaseReference ref2 = db2.ref().child(ref1.key!);

        final List<DatabaseEvent> events = <DatabaseEvent>[];
        final StreamSubscription<DatabaseEvent> sub = ref2.onValue.listen(
          events.add,
        );
        time.elapse(Duration.zero);
        // The real server: the listen sees no data yet, then the restored merge is applied and
        // acknowledged.
        server2.answerListen(ref1.key!, null);
        time.elapse(Duration.zero);
        server2.ackLastWrite();
        time.elapse(Duration.zero);
        unawaited(sub.cancel());

        expect(events, isNotEmpty);
        expect(events.last.snapshot.value, updates);
      });
    });

    // This tests that a persisted deep update will be properly applied by the server.
    test('deepUpdateTest', () {
      final PersistenceStorageEngine engine = newEngine();
      withTime((FakeTime time) {
        final FirebaseDatabase db1 = oracleDatabase(
          FakeDatabaseServer(),
          engine: engine,
        );
        final DatabaseReference ref1 = db1.ref().push();
        db1.goOffline();
        final Map<String, Object?> updates = <String, Object?>{
          'foo/deep/update': 'bar',
        };
        unawaited(ref1.update(updates));
        time.elapse(Duration.zero);

        final FakeDatabaseServer server2 = FakeDatabaseServer();
        final FirebaseDatabase db2 = oracleDatabase(server2, engine: engine);
        final DatabaseReference ref2 = db2.ref().child(ref1.key!);

        final List<DatabaseEvent> events = <DatabaseEvent>[];
        final StreamSubscription<DatabaseEvent> sub = ref2.onValue.listen(
          events.add,
        );
        time.elapse(Duration.zero);
        server2.answerListen(ref1.key!, null);
        time.elapse(Duration.zero);
        server2.ackLastWrite();
        time.elapse(Duration.zero);
        unawaited(sub.cancel());

        expect(events, isNotEmpty);
        expect(events.last.snapshot.value, <String, Object?>{
          'foo': <String, Object?>{
            'deep': <String, Object?>{'update': 'bar'},
          },
        });
      });
    });
  });
}
