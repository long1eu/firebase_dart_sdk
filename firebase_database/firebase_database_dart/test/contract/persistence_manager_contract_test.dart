// Contract of PersistenceManager (lib/src/core/persistence/persistence_manager.dart).
//
// persistenceManagerContract holds for every manager; main runs it against
// NoopPersistenceManager and a DefaultPersistenceManager over InMemoryPersistenceStorageEngine.
// Needs the data layer and the managers filled.
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/persistence/cache_policy.dart';
import 'package:firebase_database_dart/src/core/persistence/default_persistence_manager.dart';
import 'package:firebase_database_dart/src/core/persistence/noop_persistence_manager.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_manager.dart';
import 'package:firebase_database_dart/src/core/persistence/writes_only_persistence_manager.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/view/cache_node.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:firebase_database_dart/src/testing/in_memory_persistence_storage_engine.dart';
import 'package:test/test.dart';

/// The contract; [persistsWrites] and [cachesServerData] say what the manager keeps.
void persistenceManagerContract(
  PersistenceManager Function() create, {
  required bool persistsWrites,
  required bool cachesServerData,
}) {
  late PersistenceManager manager;

  setUp(() => manager = create());

  test('isDurable matches what is persisted', () {
    expect(manager.isDurable, persistsWrites);
  });

  test('runInTransaction returns the body result synchronously', () {
    expect(manager.runInTransaction(() => 42), 42);
  });

  test('nested transactions are refused', () {
    expect(
      () => manager.runInTransaction(() => manager.runInTransaction(() => 1)),
      throwsA(anything),
    );
  });

  test('an exception in the body is rethrown', () {
    expect(
      () => manager.runInTransaction<void>(() => throw StateError('x')),
      throwsStateError,
    );
  });

  test('a saved write is loaded back only when persisting', () {
    manager.runInTransaction(
      () => manager.saveUserOverwrite(Path('/a'), nodeFromJson(1), 1),
    );
    expect(manager.loadUserWrites().length, persistsWrites ? 1 : 0);
  });

  test('server cache of an unknown query is empty and incomplete', () {
    final CacheNode cache = manager.runInTransaction(
      () => manager.serverCache(QuerySpec.defaultAt(Path('/nothing'))),
    );
    expect(cache.node.isEmpty, isTrue);
    expect(cache.fullyInitialized, isFalse);
  });

  test('server data of a complete default query is served complete', () {
    final QuerySpec query = QuerySpec.defaultAt(Path('/a'));
    manager.runInTransaction(() {
      manager.setQueryActive(query);
      manager.updateServerCache(query, nodeFromJson(<String, Object?>{'b': 1}));
      manager.setQueryComplete(query);
    });
    final CacheNode cache = manager.runInTransaction(
      () => manager.serverCache(query),
    );
    expect(cache.fullyInitialized, cachesServerData);
    if (cachesServerData) {
      expect(cache.node.toJson(), <String, Object?>{'b': 1});
    }
  });
}

void main() {
  group('NoopPersistenceManager', () {
    persistenceManagerContract(
      NoopPersistenceManager.new,
      persistsWrites: false,
      cachesServerData: false,
    );
  });
  group('DefaultPersistenceManager', () {
    persistenceManagerContract(
      () => DefaultPersistenceManager(
        InMemoryPersistenceStorageEngine(),
        CachePolicy.none,
        () => DateTime.utc(2026),
      ),
      persistsWrites: true,
      cachesServerData: true,
    );
  });
  group('WritesOnlyPersistenceManager', () {
    persistenceManagerContract(
      () => WritesOnlyPersistenceManager(InMemoryPersistenceStorageEngine()),
      persistsWrites: true,
      cachesServerData: false,
    );
  });
}
