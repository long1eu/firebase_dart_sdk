// Calls made while the disk cache is still opening wait for it, and their local effects apply in
// call order. The order in which their requests then leave is not pinned here.

import 'dart:async';

import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:firebase_database_dart/src/api/firebase_database.dart'
    show firebaseDatabaseWithConnection;
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/core/persistence/database_persistence.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_storage_engine.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_storage_engine_opener.dart';
import 'package:firebase_database_dart/src/testing/fake_server_actions.dart';
import 'package:firebase_database_dart/src/testing/in_memory_persistence_storage_engine.dart';
import 'package:test/test.dart';

import 'support/fake_time.dart';
import 'support/harness.dart';

void main() {
  test(
    'set, listen, set while the store opens: events show the writes in call order',
    () {
      fakeTime((FakeTime time) {
        final Completer<PersistenceStorageEngine> opened =
            Completer<PersistenceStorageEngine>();
        final FirebaseDatabase db = firebaseDatabaseWithConnection(
          newTestApp(),
          connectionFactory:
              (ServerActionsDelegate delegate, DatabaseLogger? _) =>
                  FakeServerActions()..delegate = delegate,
          persistence: databasePersistence(
            opener: (PersistenceKey key, {DatabaseLogger? logger}) =>
                opened.future,
          ),
        );
        final DatabaseReference a = db.ref('a');
        final List<Object?> seen = <Object?>[];
        unawaited(a.set(1));
        final StreamSubscription<DatabaseEvent> sub = a.onValue.listen(
          (DatabaseEvent e) => seen.add(e.snapshot.value),
        );
        unawaited(a.set(2));
        time.elapse(Duration.zero);
        expect(seen, isEmpty, reason: 'every call waits for the store');

        opened.complete(InMemoryPersistenceStorageEngine());
        time.elapse(Duration.zero);
        expect(seen, <Object?>[1, 2]);
        unawaited(sub.cancel());
      });
    },
  );
}
