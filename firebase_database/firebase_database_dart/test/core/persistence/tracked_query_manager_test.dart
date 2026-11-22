// Port of Android TrackedQueryManagerTest.java, on InMemoryPersistenceStorageEngine with a test
// clock (Android TestClock) and a test cache policy (Android TestCachePolicy).
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/persistence/cache_policy.dart';
import 'package:firebase_database_dart/src/core/persistence/prune_forest.dart';
import 'package:firebase_database_dart/src/core/persistence/tracked_query.dart';
import 'package:firebase_database_dart/src/core/persistence/tracked_query_manager.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/path_index.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/view/query_params.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:firebase_database_dart/src/testing/in_memory_persistence_storage_engine.dart';
import 'package:test/test.dart';

/// Android testUtil TestClock: starts at 1, moves on [tick].
final class TestClock {
  int now = 1;

  DateTime call() => DateTime.fromMillisecondsSinceEpoch(now, isUtc: true);

  int millis() => now;

  int tick() => ++now;
}

/// Android testUtil TestCachePolicy.
final class TestCachePolicy implements CachePolicy {
  TestCachePolicy(
    this.percentOfQueriesToPruneAtOnce,
    this.maxNumberOfQueriesToKeep,
  );

  bool _timeToPrune = false;

  @override
  final double percentOfQueriesToPruneAtOnce;

  @override
  final int maxNumberOfQueriesToKeep;

  void pruneOnNextServerUpdate() => _timeToPrune = true;

  @override
  bool shouldPrune(int currentSizeBytes, int countOfPrunableQueries) {
    if (_timeToPrune) {
      _timeToPrune = false;
      return true;
    }
    return false;
  }

  @override
  bool shouldCheckCacheSize(int serverUpdatesSinceLastCheck) => true;
}

// "No limit" (Android uses Long.MAX_VALUE); 2^53 - 1 also compiles for the web.
const int maxInt = 9007199254740991;

QuerySpec defaultQueryAt(String path) => QuerySpec.defaultAt(Path(path));

ChildKey ck(String name) => ChildKey(name);

final QueryParams sampleQueryParams = QueryParams.defaultParams
    .orderBy(PathIndex(Path('child')))
    .startAt(nodeFromJson('startVal'), ChildKey('startKey'))
    .endAt(nodeFromJson('endVal'), ChildKey('endKey'))
    .limitToLast(5);

final QuerySpec sampleFooQuery = QuerySpec(Path('foo'), sampleQueryParams);
final QuerySpec defaultFooQuery = defaultQueryAt('foo');
final QuerySpec defaultBarQuery = defaultQueryAt('bar');

InMemoryPersistenceStorageEngine newEngine() =>
    InMemoryPersistenceStorageEngine()..disableTransactionCheck = true;

/// Android `TrackedQueryManager.verifyCache` (package-private there): the stored tracked queries
/// are exactly what the manager holds for [queries] (every query the test touched).
void verifyCache(
  TrackedQueryManager manager,
  InMemoryPersistenceStorageEngine engine,
  Iterable<QuerySpec> queries,
) {
  final List<TrackedQuery> held = <TrackedQuery>{
    for (final QuerySpec query in queries)
      if (manager.findTrackedQuery(query) case final TrackedQuery q) q,
  }.toList()..sort((TrackedQuery a, TrackedQuery b) => a.id.compareTo(b.id));
  expect(engine.loadTrackedQueries(), held);
}

void main() {
  late InMemoryPersistenceStorageEngine engine;
  late TestClock clock;

  TrackedQueryManager newManager() => TrackedQueryManager(engine, clock.call);

  setUp(() {
    engine = newEngine();
    clock = TestClock();
  });

  test('findTrackedQuery', () {
    final TrackedQueryManager manager = newManager();
    expect(manager.findTrackedQuery(sampleFooQuery), isNull);
    manager.setQueryActive(sampleFooQuery);
    expect(manager.findTrackedQuery(sampleFooQuery), isNotNull);
  });

  test('removeTrackedQuery', () {
    final TrackedQueryManager manager = newManager();
    manager.setQueryActive(sampleFooQuery);
    expect(manager.findTrackedQuery(sampleFooQuery), isNotNull);
    manager.removeTrackedQuery(sampleFooQuery);
    expect(manager.findTrackedQuery(sampleFooQuery), isNull);
    verifyCache(manager, engine, <QuerySpec>[sampleFooQuery]);
  });

  test('setQueryActive and setQueryInactive', () {
    final TrackedQueryManager manager = newManager();

    manager.setQueryActive(sampleFooQuery);
    TrackedQuery q = manager.findTrackedQuery(sampleFooQuery)!;
    expect(q.active, isTrue);
    expect(q.lastUse, clock.millis());
    verifyCache(manager, engine, <QuerySpec>[sampleFooQuery]);

    clock.tick();
    manager.setQueryInactive(sampleFooQuery);
    q = manager.findTrackedQuery(sampleFooQuery)!;
    expect(q.active, isFalse);
    expect(q.lastUse, clock.millis());
    verifyCache(manager, engine, <QuerySpec>[sampleFooQuery]);
  });

  test('setQueryComplete', () {
    final TrackedQueryManager manager = newManager();
    manager.setQueryActive(sampleFooQuery);
    manager.setQueryCompleteIfExists(sampleFooQuery);
    expect(manager.findTrackedQuery(sampleFooQuery)!.complete, isTrue);
    verifyCache(manager, engine, <QuerySpec>[sampleFooQuery]);
  });

  test('setQueriesComplete', () {
    final TrackedQueryManager manager = newManager();
    final List<QuerySpec> queries = <QuerySpec>[
      defaultQueryAt('foo'),
      defaultQueryAt('foo/bar'),
      defaultQueryAt('elsewhere'),
      QuerySpec(Path('foo'), sampleQueryParams),
      QuerySpec(Path('foo/baz'), sampleQueryParams),
      QuerySpec(Path('elsewhere'), sampleQueryParams),
    ];
    queries.forEach(manager.setQueryActive);

    manager.setQueriesComplete(Path('foo'));

    expect(manager.findTrackedQuery(defaultQueryAt('foo'))!.complete, isTrue);
    expect(
      manager.findTrackedQuery(defaultQueryAt('foo/bar'))!.complete,
      isTrue,
    );
    expect(
      manager
          .findTrackedQuery(QuerySpec(Path('foo'), sampleQueryParams))!
          .complete,
      isTrue,
    );
    expect(
      manager
          .findTrackedQuery(QuerySpec(Path('foo/baz'), sampleQueryParams))!
          .complete,
      isTrue,
    );
    expect(
      manager.findTrackedQuery(defaultQueryAt('elsewhere'))!.complete,
      isFalse,
    );
    expect(
      manager
          .findTrackedQuery(QuerySpec(Path('elsewhere'), sampleQueryParams))!
          .complete,
      isFalse,
    );
    verifyCache(manager, engine, queries);
  });

  test('isQueryComplete', () {
    final TrackedQueryManager manager = newManager();

    manager.setQueryActive(sampleFooQuery);
    manager.setQueryCompleteIfExists(sampleFooQuery);

    manager.setQueryActive(defaultBarQuery);

    manager.setQueryActive(defaultQueryAt('baz'));
    manager.setQueryCompleteIfExists(defaultQueryAt('baz'));

    expect(manager.isQueryComplete(sampleFooQuery), isTrue);
    expect(manager.isQueryComplete(defaultBarQuery), isFalse);

    expect(manager.isQueryComplete(defaultQueryAt('')), isFalse);
    expect(manager.isQueryComplete(defaultQueryAt('baz')), isTrue);
    expect(manager.isQueryComplete(defaultQueryAt('baz/quu')), isTrue);
  });

  test('pruneOldQueries', () {
    final TrackedQueryManager manager = newManager();

    manager.setQueryActive(defaultQueryAt('active1'));
    manager.setQueryActive(defaultQueryAt('active2'));
    manager.setQueryActive(defaultQueryAt('inactive1'));
    manager.setQueryInactive(defaultQueryAt('inactive1'));
    clock.tick();
    manager.setQueryActive(defaultQueryAt('inactive2'));
    manager.setQueryInactive(defaultQueryAt('inactive2'));
    clock.tick();
    manager.setQueryActive(defaultQueryAt('inactive3'));
    manager.setQueryInactive(defaultQueryAt('inactive3'));
    clock.tick();
    manager.setQueryActive(defaultQueryAt('inactive4'));
    manager.setQueryInactive(defaultQueryAt('inactive4'));

    // Should prune the first two inactive queries.
    PruneForest forest = manager.pruneOldQueries(TestCachePolicy(0.5, maxInt));
    PruneForest expected = PruneForest()
        .prune(Path('inactive1'))
        .prune(Path('inactive2'))
        .keep(Path('active1'))
        .keep(Path('active2'))
        .keep(Path('inactive3'))
        .keep(Path('inactive4'));
    expect(forest, expected);

    // Should prune the other two inactive queries.
    forest = manager.pruneOldQueries(TestCachePolicy(1, maxInt));
    expected = PruneForest()
        .prune(Path('inactive3'))
        .prune(Path('inactive4'))
        .keep(Path('active1'))
        .keep(Path('active2'));
    expect(forest, expected);

    forest = manager.pruneOldQueries(TestCachePolicy(1, maxInt));
    expect(forest.prunesAnything(), isFalse);

    verifyCache(manager, engine, <QuerySpec>[
      for (final String p in <String>[
        'active1',
        'active2',
        'inactive1',
        'inactive2',
        'inactive3',
        'inactive4',
      ])
        defaultQueryAt(p),
    ]);
  });

  test('prune queries over max size', () {
    final TrackedQueryManager manager = newManager();

    // Create a bunch of inactive queries.
    for (int i = 0; i < 15; i++) {
      manager.setQueryActive(defaultQueryAt('$i'));
      manager.setQueryInactive(defaultQueryAt('$i'));
      clock.tick();
    }

    final PruneForest forest = manager.pruneOldQueries(
      TestCachePolicy(0.2, 10),
    );

    // Should prune down to the max of 10, so 5 pruned.
    PruneForest expected = PruneForest();
    for (int i = 0; i < 15; i++) {
      expected = i < 5 ? expected.prune(Path('$i')) : expected.keep(Path('$i'));
    }
    expect(forest, expected);

    verifyCache(manager, engine, <QuerySpec>[
      for (int i = 0; i < 15; i++) defaultQueryAt('$i'),
    ]);
  });

  test('prune default with deeper queries', () {
    final TrackedQueryManager manager = newManager();

    manager.setQueryActive(defaultQueryAt('foo'));
    manager.setQueryActive(QuerySpec(Path('foo/a'), sampleQueryParams));
    manager.setQueryActive(QuerySpec(Path('foo/b'), sampleQueryParams));
    manager.setQueryInactive(defaultQueryAt('foo'));

    // Prune foo, but keep foo/a and foo/b.
    final PruneForest forest = manager.pruneOldQueries(
      TestCachePolicy(1, maxInt),
    );
    final PruneForest expected = PruneForest()
        .prune(Path('foo'))
        .keep(Path('foo/a'))
        .keep(Path('foo/b'));
    expect(forest, expected);
    verifyCache(manager, engine, <QuerySpec>[
      defaultQueryAt('foo'),
      QuerySpec(Path('foo/a'), sampleQueryParams),
      QuerySpec(Path('foo/b'), sampleQueryParams),
    ]);
  });

  test('prune queries with default query on parent', () {
    final TrackedQueryManager manager = newManager();

    manager.setQueryActive(defaultQueryAt('foo'));
    manager.setQueryActive(QuerySpec(Path('foo/a'), sampleQueryParams));
    manager.setQueryActive(QuerySpec(Path('foo/b'), sampleQueryParams));
    manager.setQueryInactive(QuerySpec(Path('foo/a'), sampleQueryParams));
    manager.setQueryInactive(QuerySpec(Path('foo/b'), sampleQueryParams));

    // Prune foo/a and foo/b, but keep foo.
    final PruneForest forest = manager.pruneOldQueries(
      TestCachePolicy(1, maxInt),
    );
    final PruneForest expected = PruneForest()
        .prune(Path('foo/a'))
        .prune(Path('foo/b'))
        .keep(Path('foo'));
    expect(forest, expected);
    verifyCache(manager, engine, <QuerySpec>[
      defaultQueryAt('foo'),
      QuerySpec(Path('foo/a'), sampleQueryParams),
      QuerySpec(Path('foo/b'), sampleQueryParams),
    ]);
  });

  test('getKnownCompleteChildren', () {
    final TrackedQueryManager manager = newManager();

    expect(manager.getKnownCompleteChildren(Path('foo')), <ChildKey>{});

    manager.setQueryActive(defaultQueryAt('foo/a'));
    manager.setQueryCompleteIfExists(defaultQueryAt('foo/a'));
    manager.setQueryActive(defaultQueryAt('foo/not-included'));
    manager.setQueryActive(defaultQueryAt('foo/deep/not-included'));
    manager.setQueryCompleteIfExists(defaultQueryAt('foo/deep/not-included'));

    manager.setQueryActive(sampleFooQuery);
    final TrackedQuery trackedQuery = manager.findTrackedQuery(sampleFooQuery)!;
    engine.saveTrackedQueryKeys(trackedQuery.id, <ChildKey>{ck('d'), ck('e')});

    expect(manager.getKnownCompleteChildren(Path('foo')), <ChildKey>{
      ck('a'),
      ck('d'),
      ck('e'),
    });
    expect(manager.getKnownCompleteChildren(Path('')), <ChildKey>{});
    expect(manager.getKnownCompleteChildren(Path('foo/baz')), <ChildKey>{});
  });

  test('getKnownCompleteChildren is null under a complete default query', () {
    // Dart only: Android asserts instead (the signature returns null).
    final TrackedQueryManager manager = newManager();
    manager.ensureCompleteTrackedQuery(Path('foo'));
    expect(manager.getKnownCompleteChildren(Path('foo/bar')), isNull);
  });

  test('ensure tracked query for new query', () {
    final TrackedQueryManager manager = newManager();

    manager.ensureCompleteTrackedQuery(Path('foo'));
    final TrackedQuery query = manager.findTrackedQuery(defaultFooQuery)!;
    expect(query.complete, isTrue);
    expect(query.lastUse, clock.millis());
  });

  test('ensure tracked query for already tracked query', () {
    final TrackedQueryManager manager = newManager();

    manager.setQueryActive(defaultFooQuery);

    final int lastTick = clock.millis();
    clock.tick();
    manager.ensureCompleteTrackedQuery(Path('foo'));
    expect(manager.findTrackedQuery(defaultFooQuery)!.lastUse, lastTick);
  });

  test('hasActiveDefaultQuery', () {
    final TrackedQueryManager manager = newManager();

    manager.setQueryActive(sampleFooQuery);
    manager.setQueryActive(defaultBarQuery);

    expect(manager.hasActiveDefaultQuery(Path('foo')), isFalse);
    expect(manager.hasActiveDefaultQuery(Path('')), isFalse);
    expect(manager.hasActiveDefaultQuery(Path('bar')), isTrue);
    expect(manager.hasActiveDefaultQuery(Path('bar/baz')), isTrue);
  });

  test('cache sanity check', () {
    final TrackedQueryManager manager = newManager();
    final List<QuerySpec> queries = <QuerySpec>[
      sampleFooQuery,
      defaultFooQuery,
    ];

    manager.setQueryActive(sampleFooQuery);
    manager.setQueryActive(defaultFooQuery);
    verifyCache(manager, engine, queries);

    manager.setQueryCompleteIfExists(sampleFooQuery);
    verifyCache(manager, engine, queries);

    manager.setQueryInactive(defaultFooQuery);
    verifyCache(manager, engine, queries);

    final TrackedQueryManager manager2 = newManager();
    verifyCache(manager2, engine, queries);
  });
}
