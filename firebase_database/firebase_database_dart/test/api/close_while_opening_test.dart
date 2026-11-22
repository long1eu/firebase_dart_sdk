// close() while the disk cache is still opening: the database must not start afterwards.

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
  test('closed while the store opens: no connection is ever built', () {
    fakeTime((FakeTime time) {
      final Completer<PersistenceStorageEngine> opened =
          Completer<PersistenceStorageEngine>();
      int connectionsBuilt = 0;
      final FirebaseDatabase db = firebaseDatabaseWithConnection(
        newTestApp(),
        connectionFactory: (ServerActionsDelegate delegate, DatabaseLogger? _) {
          connectionsBuilt++;
          return FakeServerActions()..delegate = delegate;
        },
        persistence: databasePersistence(
          opener: (PersistenceKey key, {DatabaseLogger? logger}) =>
              opened.future,
        ),
      );
      bool closed = false;
      unawaited(db.close().then((_) => closed = true));
      time.elapse(Duration.zero);
      expect(closed, isFalse, reason: 'close waits for the store to open');

      opened.complete(InMemoryPersistenceStorageEngine());
      time.elapse(Duration.zero);
      expect(closed, isTrue);
      expect(connectionsBuilt, 0);
    });
  });
}
