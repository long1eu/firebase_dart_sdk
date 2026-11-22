// Contract of PersistenceStorageEngine (lib/src/core/persistence/persistence_storage_engine.dart).
//
// Every engine (SQLite, IndexedDB-backed image, ...) must pass persistenceStorageEngineContract;
// main runs it against InMemoryPersistenceStorageEngine. Needs the data layer filled.
import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_storage_engine.dart';
import 'package:firebase_database_dart/src/core/persistence/tracked_query.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/user_write_record.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:firebase_database_dart/src/testing/in_memory_persistence_storage_engine.dart';
import 'package:test/test.dart';

/// The contract.
void persistenceStorageEngineContract(
  PersistenceStorageEngine Function() create,
) {
  late PersistenceStorageEngine engine;

  setUp(() => engine = create());
  tearDown(() => engine.close());

  void inTransaction(void Function() body) {
    engine.beginTransaction();
    try {
      body();
      engine.setTransactionSuccessful();
    } finally {
      engine.endTransaction();
    }
  }

  test('a freshly opened engine is durable', () {
    expect(engine.isDurable, isTrue);
  });

  test('user writes load in write-id order', () {
    inTransaction(() {
      engine.saveUserMerge(
        Path('/b'),
        CompoundWrite.fromValue(<String, Object?>{'x': 1}),
        2,
      );
      engine.saveUserOverwrite(Path('/a'), nodeFromJson('A'), 1);
    });
    final List<UserWriteRecord> writes = engine.loadUserWrites();
    expect(writes.map((UserWriteRecord w) => w.writeId), <int>[1, 2]);
    expect(writes.first.isOverwrite, isTrue);
    expect(writes.first.overwrite, nodeFromJson('A'));
    expect(writes.last.isMerge, isTrue);
  });

  test('removeUserWrite and removeAllUserWrites', () {
    inTransaction(() {
      engine.saveUserOverwrite(Path('/a'), nodeFromJson(1), 1);
      engine.saveUserOverwrite(Path('/b'), nodeFromJson(2), 2);
      engine.removeUserWrite(1);
    });
    expect(engine.loadUserWrites().single.writeId, 2);
    inTransaction(engine.removeAllUserWrites);
    expect(engine.loadUserWrites(), isEmpty);
  });

  test('a transaction without setTransactionSuccessful is rolled back', () {
    engine.beginTransaction();
    engine.saveUserOverwrite(Path('/a'), nodeFromJson(1), 1);
    engine.endTransaction();
    expect(engine.loadUserWrites(), isEmpty);
  });

  test('nested transactions are refused', () {
    engine.beginTransaction();
    expect(engine.beginTransaction, throwsA(anything));
    engine.endTransaction();
  });

  test('server cache overwrite, merge and read below', () {
    inTransaction(() {
      engine.overwriteServerCache(
        Path('/a'),
        nodeFromJson(<String, Object?>{'b': 1, 'c': 2}),
      );
      engine.mergeIntoServerCache(
        Path('/a'),
        nodeFromJson(<String, Object?>{'c': 3, 'd': 4}),
      );
    });
    expect(engine.serverCache(Path('/a')).toJson(), <String, Object?>{
      'b': 1,
      'c': 3,
      'd': 4,
    });
    expect(engine.serverCache(Path('/a/b')).toJson(), 1);
    expect(engine.serverCache(Path('/x')).isEmpty, isTrue);
    expect(engine.serverCacheEstimatedSizeInBytes(), greaterThan(0));
  });

  test('tracked queries and their keys', () {
    final TrackedQuery query = TrackedQuery(
      id: 1,
      querySpec: QuerySpec.defaultAt(Path('/a')),
      lastUse: 100,
      complete: false,
      active: true,
    );
    inTransaction(() {
      engine.saveTrackedQuery(query);
      engine.saveTrackedQueryKeys(1, <ChildKey>{ChildKey('x'), ChildKey('y')});
      engine.updateTrackedQueryKeys(
        1,
        <ChildKey>{ChildKey('z')},
        <ChildKey>{ChildKey('x')},
      );
    });
    expect(engine.loadTrackedQueries(), <TrackedQuery>[query]);
    expect(engine.loadTrackedQueryKeys(<int>{1}), <ChildKey>{
      ChildKey('y'),
      ChildKey('z'),
    });
    engine.resetPreviouslyActiveTrackedQueries(200);
    expect(engine.loadTrackedQueries().single.active, isFalse);
    expect(engine.loadTrackedQueries().single.lastUse, 200);
    inTransaction(() => engine.deleteTrackedQuery(1));
    expect(engine.loadTrackedQueries(), isEmpty);
  });
}

void main() {
  group('InMemoryPersistenceStorageEngine', () {
    persistenceStorageEngineContract(InMemoryPersistenceStorageEngine.new);
  });
}
