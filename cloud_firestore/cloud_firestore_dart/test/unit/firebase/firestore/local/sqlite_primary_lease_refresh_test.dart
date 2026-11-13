// A primary that finds at its refresh that the lease row names another client gives up being primary, also when it did
// not see a commit of another connection (SQLiteClientMetadata._update, the JS
// updateClientMetadataAndTryBecomePrimary that verifies the lease of a primary first).

@TestOn('vm')
library;

import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:test/test.dart';

import '../../../../util/sqlite3_database.dart';
import 'sqlite_primary_lease_test.dart'
    show FakeClock, createClient, newName, validity;

void main() {
  late String name;
  late FakeClock clock;
  late SQLitePersistence a;

  setUp(() async {
    name = newName();
    clock = FakeClock();
    a = await createClient(name, 'A', clock.call);
    await a.start();
  });

  tearDown(() async {
    if (a.started) {
      await a.shutdown();
    }
    DatabaseMock.deleteDatabaseFiles(name);
  });

  Future<String?> owner() async {
    final List<Map<String, dynamic>> rows = await a.query(
      'SELECT owner_id FROM primary_client',
    );
    return rows.isEmpty ? null : rows.single['owner_id'] as String;
  }

  test(
    'a primary whose lease row names another client yields at its refresh',
    () async {
      expect(a.isPrimary, isTrue);
      final List<bool> states = <bool>[];
      a.clientMetadata.primaryStateListener = states.add;

      // Written through A's own connection, so A sees no foreign commit: only the lease row tells it.
      await a.execute(
        'UPDATE primary_client SET owner_id = ?, lease_timestamp_ms = ?',
        <Object?>['Z', clock.now],
      );
      await a.refreshClientMetadata();

      expect(a.isPrimary, isFalse);
      expect(states, <bool>[false]);
      expect(await owner(), 'Z', reason: 'the valid lease of Z is left alone');

      // Once the lease of Z expires, A takes it back.
      clock.advance(validity + 1);
      await a.refreshClientMetadata();
      expect(a.isPrimary, isTrue);
      expect(states, <bool>[false, true]);
      expect(await owner(), 'A');
    },
  );
}
