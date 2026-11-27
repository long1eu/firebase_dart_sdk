// The client's ports of Android's persistence test suites, run against the SQLite engine.
import 'package:firebase_database_dart/firebase_database_dart.dart'
    show DatabaseLogLevel;
import 'package:firebase_database_dart/storage_engine.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_storage_engine.dart';
import 'package:test/test.dart';

// The oracles are function files under the client's test/ directory, which no other package can
// import by package URI. KeepSyncedTest is left out: upstream runs it without persistence, and with
// a persistent cache an unsynced query still gets the old cached value offline, as it should.
import '../../firebase_database_dart/test/oracle/persistence_test.dart';
import '../../firebase_database_dart/test/oracle/pruning_test.dart';
import '../../firebase_database_dart/test/oracle/random_persistence_test.dart';
import 'support/store_fixture.dart';

/// How many clean stores are ready when a test starts: the most one test uses.
/// RandomPersistenceTest opens one per seed (`random_persistence_test.dart:134-135`); every
/// PersistenceTest and PruningTest test opens one. This holds only because each oracle runs in a
/// group of its own below.
final int _readyStores = randomPersistenceSeeds.length;

/// One clean store, its engine and what both logged.
final class _PooledStore {
  _PooledStore(this.fixture, this.engine, this.engineLog);

  final StoreFixture fixture;
  final SqliteStorageEngine engine;
  final List<String> engineLog;

  /// Closes the engine and checks that nothing went wrong unnoticed: no stored row was skipped as
  /// unreadable and the store never fell back to memory.
  void closeAndCheck() {
    engine.close();
    expect(
      engineLog.where((String m) => m.contains('could not be read')),
      isEmpty,
    );
    expect(fixture.log.where((String m) => m.contains('memory only')), isEmpty);
  }
}

/// Clean stores opened ahead, because the oracles ask for an engine synchronously and opening a
/// store is asynchronous (the lease). Stores a test did not use stay ready for the next one, so a
/// test opens only as many stores as the test before it used.
final class _StorePool {
  final List<_PooledStore> _ready = <_PooledStore>[];
  final List<_PooledStore> _used = <_PooledStore>[];

  /// Opens stores until [_readyStores] are ready.
  Future<void> fill() async {
    while (_ready.length < _readyStores) {
      final StoreFixture fixture = StoreFixture();
      final List<String> engineLog = <String>[];
      final SqliteStorageEngine engine = SqliteStorageEngine(
        await fixture.open(),
        logger: (DatabaseLogLevel level, String message) =>
            engineLog.add(message),
      );
      _ready.add(_PooledStore(fixture, engine, engineLog));
    }
  }

  /// A clean engine; a [StateError] when a test needs more than [_readyStores].
  PersistenceStorageEngine take() {
    if (_ready.isEmpty) {
      throw StateError(
        'A test opened more than $_readyStores engines; raise _readyStores.',
      );
    }
    final _PooledStore store = _ready.removeLast();
    _used.add(store);
    return store.engine;
  }

  /// Closes, checks and deletes the stores the test used.
  void releaseUsed() {
    try {
      for (final _PooledStore store in _used) {
        store.closeAndCheck();
      }
    } finally {
      for (final _PooledStore store in _used) {
        store.fixture.dispose();
      }
      _used.clear();
    }
  }

  /// Closes and deletes the stores nobody used.
  void disposeReady() {
    for (final _PooledStore store in _ready) {
      store.engine.close();
      store.fixture.dispose();
    }
    _ready.clear();
  }
}

void main() {
  final _StorePool pool = _StorePool();

  setUp(pool.fill);
  tearDown(pool.releaseUsed);
  tearDownAll(pool.disposeReady);

  // One group per oracle: the runners register their setUp and tearDown at the level they are
  // called from (runPruningOracle's setUp opens an engine, pruning_test.dart:91-92), so in a shared
  // group every test would also take the engines of the other oracles' setUp.
  group('Android oracles on SqliteStorageEngine', () {
    group('persistence', () => runPersistenceOracle(pool.take));
    group(
      'pruning',
      () => runPruningOracle(pool.take, keepsOverwrittenRows: true),
    );
    group('random', () => runRandomPersistenceOracle(pool.take));
  });
}
