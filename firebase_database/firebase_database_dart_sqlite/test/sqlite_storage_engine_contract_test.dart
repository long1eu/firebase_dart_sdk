// The client's storage engine contract run against the SQLite engine.
import 'package:firebase_database_dart/firebase_database_dart.dart'
    show DatabaseLogLevel;
import 'package:firebase_database_dart_sqlite/src/sqlite_connection.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_storage_engine.dart';
import 'package:test/test.dart';

// The contract is a function file under the client's test/ directory, which no other package can
// import by package URI; switch to its lib/ location when the client moves it there.
import '../../firebase_database_dart/test/contract/persistence_storage_engine_contract.dart';
import 'support/store_fixture.dart';

void main() {
  group('SqliteStorageEngine', () {
    late StoreFixture fixture;
    late SqliteStorageEngine opened;
    late List<String> engineLog;

    // The contract opens synchronously; opening a store is async (the lease), so each test opens a
    // fresh store in a fresh directory here, and the contract's open hands it over.
    setUp(() async {
      fixture = StoreFixture();
      final SqliteConnection connection = await fixture.open();
      engineLog = <String>[];
      opened = SqliteStorageEngine(
        connection,
        logger: (DatabaseLogLevel level, String message) =>
            engineLog.add(message),
      );
    });
    tearDown(() {
      opened.close();
      fixture.dispose();
      // A stored row skipped as unreadable would make a contract check pass on less data.
      expect(
        engineLog.where((String m) => m.contains('could not be read')),
        isEmpty,
      );
    });

    runStorageEngineContract(() => opened);
  });
}
