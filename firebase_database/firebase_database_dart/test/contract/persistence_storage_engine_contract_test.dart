// Runs the storage engine contract (persistence_storage_engine_contract.dart) against
// InMemoryPersistenceStorageEngine, then the reference engine's own checks: what only stored data
// can get wrong is a StateError there while it is durable (a reference-engine check, not a
// requirement on engines), and pruneCache warns and skips instead.
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/persistence/prune_forest.dart';
import 'package:firebase_database_dart/src/core/persistence/tracked_query.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/util/logger.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:firebase_database_dart/src/testing/in_memory_persistence_storage_engine.dart';
import 'package:test/test.dart';

import 'persistence_storage_engine_contract.dart';

void main() {
  group('InMemoryPersistenceStorageEngine', () {
    runStorageEngineContract(InMemoryPersistenceStorageEngine.new);
  });

  group('InMemoryPersistenceStorageEngine reference checks', () {
    late InMemoryPersistenceStorageEngine engine;
    late List<String> warnings;

    setUp(() {
      warnings = <String>[];
      engine = InMemoryPersistenceStorageEngine()
        ..logger = (DatabaseLogLevel level, String message) {
          if (level == DatabaseLogLevel.warning) {
            warnings.add(message);
          }
        };
    });

    TrackedQuery tracked(int id, String path) => TrackedQuery(
      id: id,
      querySpec: QuerySpec.defaultAt(Path(path)),
      lastUse: 100,
      complete: false,
      active: true,
    );

    void inTransaction(void Function() body) {
      engine.beginTransaction();
      try {
        body();
        engine.setTransactionSuccessful();
      } finally {
        engine.endTransaction();
      }
    }

    void expectStateError(void Function() body) {
      engine.beginTransaction();
      try {
        expect(body, throwsStateError);
      } finally {
        engine.endTransaction();
      }
    }

    test('unknown ids and keys are a StateError while durable', () {
      inTransaction(() => engine.saveTrackedQuery(tracked(1, '/a')));
      expectStateError(() => engine.removeUserWrite(7));
      expectStateError(
        () => engine.saveTrackedQueryKeys(2, <ChildKey>{ChildKey('x')}),
      );
      expectStateError(
        () => engine.updateTrackedQueryKeys(2, <ChildKey>{}, <ChildKey>{}),
      );
      expectStateError(
        () => engine.updateTrackedQueryKeys(1, <ChildKey>{}, <ChildKey>{
          ChildKey('missing'),
        }),
      );
      expect(() => engine.loadTrackedQueryKeys(<int>{2}), throwsStateError);
      expectStateError(() => engine.saveTrackedQuery(tracked(1, '/b')));
      expectStateError(() => engine.saveTrackedQuery(tracked(2, '/a')));
    });

    test('the same calls pass once degraded', () {
      inTransaction(() => engine.saveTrackedQuery(tracked(1, '/a')));
      engine.degrade();
      inTransaction(() {
        engine.removeUserWrite(7);
        engine.saveTrackedQueryKeys(2, <ChildKey>{ChildKey('x')});
        engine.updateTrackedQueryKeys(1, <ChildKey>{}, <ChildKey>{
          ChildKey('missing'),
        });
        engine.saveTrackedQuery(tracked(2, '/a'));
      });
      expect(engine.loadTrackedQueryKeys(<int>{3}), isEmpty);
    });

    test('pruneCache skips data stored above its root with a warning', () {
      inTransaction(
        () => engine.overwriteServerCache(
          Path('/a'),
          nodeFromJson(<String, Object?>{
            'b': <String, Object?>{'c': 1},
          }),
        ),
      );
      inTransaction(
        () => engine.pruneCache(Path('/a/b'), PruneForest().prune(Path.empty)),
      );
      expect(warnings, hasLength(1));
      expect(engine.serverCache(Path('/a/b/c')).toJson(), 1);
    });

    test('pruneCache skips data neither pruned nor kept with a warning', () {
      inTransaction(
        () => engine.overwriteServerCache(Path('/x/y'), nodeFromJson(1)),
      );
      inTransaction(
        () => engine.pruneCache(Path.empty, PruneForest().prune(Path('/a'))),
      );
      expect(warnings, hasLength(1));
      expect(engine.serverCache(Path('/x/y')).toJson(), 1);
    });
  });
}
