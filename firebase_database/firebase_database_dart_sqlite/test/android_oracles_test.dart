// The client's ports of Android's persistence test suites, run against the SQLite engine.
import 'package:firebase_database_dart/firebase_database_dart.dart'
    show DatabaseLogLevel;
import 'package:firebase_database_dart/storage_engine.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_storage_engine.dart';
import 'package:test/test.dart';

// The oracles are function files under the client's test/ directory, which no other package can
// import by package URI. KeepSyncedTest is left out: upstream runs it without persistence, and with a
// persistent cache an unsynced query still gets the old cached value offline, as it should.
import '../../firebase_database_dart/test/oracle/persistence_test.dart';
import '../../firebase_database_dart/test/oracle/pruning_test.dart';
import '../../firebase_database_dart/test/oracle/random_persistence_test.dart';
import 'support/store_fixture.dart';

/// How many clean stores are opened before each test. The oracles open engines synchronously and
/// opening a store is async (the lease), so they are opened ahead; a test that needs more fails
/// with a [StateError] naming this number.
const int _storesPerTest = 12;

void main() {
  final List<StoreFixture> fixtures = <StoreFixture>[];
  final List<SqliteStorageEngine> engines = <SqliteStorageEngine>[];
  int handedOut = 0;

  setUp(() async {
    handedOut = 0;
    for (int i = 0; i < _storesPerTest; i++) {
      final StoreFixture fixture = StoreFixture();
      fixtures.add(fixture);
      engines.add(
        SqliteStorageEngine(
          await fixture.open(),
          logger: (DatabaseLogLevel level, String message) {},
        ),
      );
    }
  });

  tearDown(() {
    for (final SqliteStorageEngine engine in engines) {
      engine.close();
    }
    for (final StoreFixture fixture in fixtures) {
      fixture.dispose();
    }
    engines.clear();
    fixtures.clear();
  });

  PersistenceStorageEngine openEngine() {
    if (handedOut == engines.length) {
      throw StateError('A test opened more than $_storesPerTest engines.');
    }
    return engines[handedOut++];
  }

  group('Android oracles on SqliteStorageEngine', () {
    runPersistenceOracle(openEngine);
    runPruningOracle(openEngine, keepsOverwrittenRows: true);
    runRandomPersistenceOracle(openEngine);
  });
}
