// Runs the storage engine contract (persistence_storage_engine_contract.dart) against
// InMemoryPersistenceStorageEngine.
import 'package:firebase_database_dart/src/testing/in_memory_persistence_storage_engine.dart';
import 'package:test/test.dart';

import 'persistence_storage_engine_contract.dart';

void main() {
  group('InMemoryPersistenceStorageEngine', () {
    runStorageEngineContract(InMemoryPersistenceStorageEngine.new);
  });
}
