// Port of Android DefaultPersistenceManagerTest.java, on InMemoryPersistenceStorageEngine.
import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/persistence/cache_policy.dart';
import 'package:firebase_database_dart/src/core/persistence/default_persistence_manager.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_manager.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/path_index.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/view/cache_node.dart';
import 'package:firebase_database_dart/src/core/view/query_params.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:firebase_database_dart/src/testing/in_memory_persistence_storage_engine.dart';
import 'package:test/test.dart';

DateTime _frozenClock() => DateTime.utc(2026);

QuerySpec defaultQueryAt(String path) => QuerySpec.defaultAt(Path(path));

InMemoryPersistenceStorageEngine newEngine() =>
    InMemoryPersistenceStorageEngine()..disableTransactionCheck = true;

PersistenceManager newTestPersistenceManager() =>
    DefaultPersistenceManager(newEngine(), CachePolicy.none, _frozenClock);

void main() {
  final QuerySpec defaultFooQuery = defaultQueryAt('foo');
  final QuerySpec limit3FooQuery = QuerySpec(
    Path('foo'),
    QueryParams.defaultParams.limitToLast(3),
  );

  test('server cache filters results 1', () {
    final PersistenceManager manager = newTestPersistenceManager();

    manager.updateServerCache(defaultQueryAt('foo/bar'), nodeFromJson(1));
    manager.updateServerCache(defaultQueryAt('foo/baz'), nodeFromJson(2));
    manager.updateServerCache(defaultQueryAt('foo/quu/1'), nodeFromJson(3));
    manager.updateServerCache(defaultQueryAt('foo/quu/2'), nodeFromJson(4));

    final CacheNode cache = manager.serverCache(defaultQueryAt('foo'));
    expect(cache.fullyInitialized, isFalse);
    expect(cache.node, ChildrenNode.empty);
  });

  test('server cache filters results 2', () {
    final PersistenceManager manager = newTestPersistenceManager();

    manager.setQueryActive(limit3FooQuery);
    manager.updateServerCache(
      defaultQueryAt('foo'),
      nodeFromJson(<String, Object?>{'a': 1, 'b': 2, 'c': 3, 'd': 4}),
    );
    manager.setTrackedQueryKeys(limit3FooQuery, <ChildKey>{
      ChildKey('a'),
      ChildKey('b'),
    });
    final CacheNode cache = manager.serverCache(defaultQueryAt('foo'));
    expect(cache.fullyInitialized, isFalse);
    final Node expected = nodeFromJson(<String, Object?>{'a': 1, 'b': 2});
    expect(cache.node, expected);
  });

  test('no-limit non-default query is treated as default query', () {
    final PersistenceManager manager = newTestPersistenceManager();

    manager.setQueryActive(defaultFooQuery);
    final Node data = nodeFromJson(<String, Object?>{'foo': 1, 'bar': 2});
    manager.updateServerCache(defaultFooQuery, data);
    manager.setQueryComplete(defaultFooQuery);

    final QuerySpec orderByQuery = QuerySpec(
      Path('foo'),
      QueryParams.defaultParams.orderBy(PathIndex(Path('index-key'))),
    );
    final CacheNode node = manager.serverCache(orderByQuery);
    expect(node.fullyInitialized, isTrue);
    expect(node.node, data);
    expect(node.filtered, isFalse);
    // Android also checks `getIndexedNode().hasIndex(index)`; Dart has no IndexedNode (nodes
    // build their indexes lazily).
  });

  test('applyUserMerge uses relative path', () {
    final InMemoryPersistenceStorageEngine engine = newEngine();

    final Node initialData = nodeFromJson(<String, Object?>{
      'foo': <String, Object?>{'bar': 'bar-value', 'baz': 'baz-value'},
    });
    engine.overwriteServerCache(Path(''), initialData);

    final DefaultPersistenceManager manager = DefaultPersistenceManager(
      engine,
      CachePolicy.none,
      _frozenClock,
    );

    final CompoundWrite write = CompoundWrite.fromValue(<String, Object?>{
      'baz': 'new-baz',
      'qux': 'qux',
    });
    manager.applyUserMergeToServerCache(Path('foo'), write);

    final Node expected = nodeFromJson(<String, Object?>{
      'foo': <String, Object?>{
        'bar': 'bar-value',
        'baz': 'new-baz',
        'qux': 'qux',
      },
    });
    expect(engine.serverCache(Path('')), expected);
  });
}
