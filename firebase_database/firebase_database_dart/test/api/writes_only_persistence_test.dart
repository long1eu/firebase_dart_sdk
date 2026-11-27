// `databasePersistence(cacheServerData: false)` through the public API: pending writes survive a
// restart and are sent again; server data seen before the restart is not served after it.
import 'dart:async';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:firebase_database_dart/src/api/fake_database.dart';
import 'package:firebase_database_dart/src/api/fake_database_server.dart';
import 'package:firebase_database_dart/src/core/persistence/database_persistence.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_storage_engine.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_storage_engine_opener.dart';
import 'package:firebase_database_dart/src/testing/in_memory_persistence_storage_engine.dart';
import 'package:test/test.dart';

import 'support/fake_time.dart';

int _apps = 0;

FirebaseDatabase _open(
  FakeDatabaseServer server,
  PersistenceStorageEngine engine, {
  required bool cacheServerData,
}) => databaseWithFakeServer(
  FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'test-key',
      appId: '1:1234567890:dart:test',
      projectId: 'test-project',
    ),
    name: 'writes-only-${_apps++}',
  ),
  server,
  persistence: databasePersistence(
    opener: (PersistenceKey key, {DatabaseLogger? logger}) async => engine,
    cacheServerData: cacheServerData,
  ),
);

void main() {
  for (final bool cacheServerData in <bool>[false, true]) {
    test('cacheServerData $cacheServerData: a pending write is sent after a '
        'restart; cached server data is served only when true', () {
      fakeTime<void>((FakeTime time) {
        final PersistenceStorageEngine engine =
            InMemoryPersistenceStorageEngine();

        // First run: see a server value, then write while offline.
        final FakeDatabaseServer server1 = FakeDatabaseServer();
        final FirebaseDatabase db1 = _open(
          server1,
          engine,
          cacheServerData: cacheServerData,
        );
        final List<Object?> seen = <Object?>[];
        final StreamSubscription<DatabaseEvent> sub1 = db1
            .ref('foo')
            .onValue
            .listen((DatabaseEvent e) => seen.add(e.snapshot.value));
        time.elapse(const Duration(seconds: 2));
        server1.answerListen('foo', 'server-value');
        time.elapse(Duration.zero);
        expect(seen, <Object?>['server-value']);
        db1.goOffline();
        unawaited(db1.ref('bar').set('pending-value'));
        time.elapse(Duration.zero);
        unawaited(sub1.cancel());

        // Second run on the same storage.
        final FakeDatabaseServer server2 = FakeDatabaseServer();
        final FirebaseDatabase db2 = _open(
          server2,
          engine,
          cacheServerData: cacheServerData,
        );
        db2.goOffline();
        final List<Object?> afterRestart = <Object?>[];
        final StreamSubscription<DatabaseEvent> sub2 = db2
            .ref('foo')
            .onValue
            .listen((DatabaseEvent e) => afterRestart.add(e.snapshot.value));
        time.elapse(Duration.zero);
        expect(
          afterRestart,
          cacheServerData ? <Object?>['server-value'] : isEmpty,
        );

        db2.goOnline();
        time.elapse(const Duration(seconds: 2));
        expect(server2.requests, contains('p /bar'));
        unawaited(sub2.cancel());
        time.elapse(Duration.zero);
      });
    });
  }
}
