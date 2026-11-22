// Runs the persistence manager contract (persistence_manager_contract.dart) against the three
// managers.
import 'package:firebase_database_dart/src/core/persistence/cache_policy.dart';
import 'package:firebase_database_dart/src/core/persistence/default_persistence_manager.dart';
import 'package:firebase_database_dart/src/core/persistence/noop_persistence_manager.dart';
import 'package:firebase_database_dart/src/core/persistence/writes_only_persistence_manager.dart';
import 'package:firebase_database_dart/src/testing/in_memory_persistence_storage_engine.dart';
import 'package:test/test.dart';

import 'persistence_manager_contract.dart';

void main() {
  group('NoopPersistenceManager', () {
    runPersistenceManagerContract(
      NoopPersistenceManager.new,
      persistsWrites: false,
      cachesServerData: false,
    );
  });
  group('DefaultPersistenceManager', () {
    runPersistenceManagerContract(
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
    runPersistenceManagerContract(
      () => WritesOnlyPersistenceManager(InMemoryPersistenceStorageEngine()),
      persistsWrites: true,
      cachesServerData: false,
    );
  });
}
