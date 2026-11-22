// Shared support of the Android persistence oracles in test/oracle (PruningTest, KeepSyncedTest,
// RandomPersistenceTest, PersistenceTest). No main here: other packages (storage engines) import the
// oracle files and call their run*Oracle functions with their own engine factory.
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/src/api/database_logger.dart';
import 'package:firebase_database_dart/src/api/fake_database.dart';
import 'package:firebase_database_dart/src/api/fake_database_server.dart';
import 'package:firebase_database_dart/src/api/firebase_database.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/persistence/cache_policy.dart';
import 'package:firebase_database_dart/src/core/persistence/database_persistence.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_storage_engine.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_storage_engine_opener.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:firebase_database_dart/src/testing/in_memory_persistence_storage_engine.dart';
import 'package:test/test.dart';

/// Opens a clean storage engine; each oracle takes one.
typedef OpenEngine = PersistenceStorageEngine Function();

/// The default engine of the oracles.
PersistenceStorageEngine openInMemoryEngine() =>
    InMemoryPersistenceStorageEngine();

/// Android `NodeFromJSON`.
Node n(Object? json) => nodeFromJson(json);

/// Android `new Path(s)` / `path(s)`.
Path p(String path) => Path(path);

/// Android `defaultQueryAt(path)`.
QuerySpec defaultQueryAt(String path) => QuerySpec.defaultAt(Path(path));

/// Android `childKeySet(...)`.
Set<ChildKey> childKeySet(List<String> keys) => <ChildKey>{
  for (final String key in keys) ChildKey(key),
};

/// Android `assertEquals(Node, Node)`, with both sides shown as JSON on failure.
void expectNode(Node actual, Node expected) => expect(
  actual,
  expected,
  reason:
      'expected ${expected.toJson(exportFormat: true)}, '
      'got ${actual.toJson(exportFormat: true)}',
);

/// Runs [body] in one storage transaction of [engine], committed when it returns.
void inEngineTransaction(
  PersistenceStorageEngine engine,
  void Function() body,
) {
  engine.beginTransaction();
  try {
    body();
    engine.setTransactionSuccessful();
  } finally {
    engine.endTransaction();
  }
}

/// Android `testUtil/.../core/persistence/TestCachePolicy.java`.
final class TestCachePolicy implements CachePolicy {
  /// Android `TestCachePolicy(float, long)`.
  TestCachePolicy(this._percentToPruneAtOnce, this._maxNumberToKeep);

  final double _percentToPruneAtOnce;
  final int _maxNumberToKeep;
  bool _timeToPrune = false;

  /// Makes the next prune check prune.
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

  @override
  double get percentOfQueriesToPruneAtOnce => _percentToPruneAtOnce;

  @override
  int get maxNumberOfQueriesToKeep => _maxNumberToKeep;
}

/// Android `testUtil/.../core/utilities/TestClock.java`: starts at 1 ms, [tick] adds 1 ms.
final class TestClock {
  int _now = 1;

  /// The current time (pass the tear-off as a `Clock`).
  DateTime call() => DateTime.fromMillisecondsSinceEpoch(_now, isUtc: true);

  /// Moves time forward by 1 ms.
  void tick() => _now++;
}

int _appCount = 0;

/// A new app with a unique name.
FirebaseApp newOracleApp() => FirebaseApp.withOptions(
  const FirebaseOptions(
    apiKey: 'test-key',
    appId: '1:1234567890:dart:test',
    projectId: 'test-project',
  ),
  name: 'rtdb-oracle-${_appCount++}',
);

/// A database connected to [server]; persisted in [engine] when given (Android
/// `setForcedPersistentCache`), memory only otherwise. Several databases may share one engine.
FirebaseDatabase oracleDatabase(
  FakeDatabaseServer server, {
  PersistenceStorageEngine? engine,
}) => databaseWithFakeServer(
  newOracleApp(),
  server,
  persistence: engine == null
      ? null
      : databasePersistence(
          opener: (PersistenceKey key, {DatabaseLogger? logger}) async =>
              engine,
        ),
);
