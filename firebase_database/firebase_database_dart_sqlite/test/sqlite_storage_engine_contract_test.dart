// The client's storage engine contract run against the SQLite engine: builder B's first target.
// Fails with UnimplementedError until SqliteStorageEngine is written (expected).
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

    // The contract opens synchronously; opening a store is async (the lease), so each test opens a
    // fresh store in a fresh directory here, and the contract's open hands it over.
    setUp(() async {
      fixture = StoreFixture();
      final SqliteConnection connection = await fixture.open();
      opened = SqliteStorageEngine(
        connection,
        cacheSizeBytes: 10 * 1024 * 1024,
      );
    });
    tearDown(() {
      opened.close();
      fixture.dispose();
    });

    runStorageEngineContract(() => opened);
  });
}
