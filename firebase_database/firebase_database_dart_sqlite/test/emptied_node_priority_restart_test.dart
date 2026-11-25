// A node emptied by a write below it keeps its priority on the server (production check 38). The
// SQLite engine stores export JSON and clears the priority of an emptied node
// (ServerCacheRows._clearEmptiedNodes), so after a restart the client does not hold the kept
// priority: its listen hash differs from the server's, the server sends the node again with
// `{".priority": p}`, and a transaction on the node commits. The server is the client package's
// internal FakeServerActions, which keeps and hashes the priority and sends it as production
// does; the public FakeDatabaseServer reads its answers with the public nodeFromJson and cannot.
// The client package's internal test seam (firebaseDatabaseWithConnection) and the app type it
// takes, as the client's own tests use them.
// ignore_for_file: invalid_use_of_internal_member, depend_on_referenced_packages
import 'dart:async';
import 'dart:io';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:firebase_database_dart/src/api/firebase_database.dart'
    show firebaseDatabaseWithConnection;
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/testing/fake_server_actions.dart';
import 'package:firebase_database_dart_sqlite/firebase_database_dart_sqlite.dart';
import 'package:test/test.dart';

/// sha1('priority:number:4014000000000000:'): the server's hash of the emptied node with
/// priority 5 (production accepted it in check 38 (c)).
const String _emptiedHash = 'Za4HQEOLkfDszOTdKHl8KWNgpRE=';

/// A fake server holding `n` = `{a: 1}` with priority 5, emptied by another client.
FakeServerActions _server() => FakeServerActions()
  ..writeByOtherClient('n', <String, Object?>{'a': 1, '.priority': 5})
  ..writeByOtherClient('n/a', null);

FirebaseDatabase _open(
  FirebaseApp app,
  FakeServerActions server,
  String directory,
) => firebaseDatabaseWithConnection(
  app,
  connectionFactory: (ServerActionsDelegate delegate, DatabaseLogger? _) =>
      server..delegate = delegate,
  persistence: sqlitePersistence(directory),
);

void main() {
  test('after a restart the kept priority is fetched again; a transaction on '
      'the emptied node commits', () async {
    final Directory dir = Directory.systemTemp.createTempSync('rtdb-prio-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final FirebaseApp app = FirebaseApp.withOptions(
      const FirebaseOptions(
        apiKey: 'test-key',
        appId: '1:1234567890:dart:test',
        projectId: 'test-project',
      ),
      name: 'rtdb-sqlite-emptied-priority',
    );

    // First run: the node arrives with its priority and is emptied by another client.
    final FakeServerActions first = FakeServerActions()
      ..writeByOtherClient('n', <String, Object?>{'a': 1, '.priority': 5});
    final FirebaseDatabase db1 = _open(app, first, dir.path);
    final List<(Object?, Object?)> seen1 = <(Object?, Object?)>[];
    final StreamSubscription<DatabaseEvent> sub1 = db1
        .ref('n')
        .onValue
        .listen(
          (DatabaseEvent e) =>
              seen1.add((e.snapshot.value, e.snapshot.priority)),
        );
    await pumpEventQueue();
    first.connect();
    await pumpEventQueue();
    first
      ..deliverDataUpdate('n', first.dataAt('n'))
      ..respond(first.callsOf('listen').single);
    await pumpEventQueue();
    first.writeByOtherClient('n/a', null);
    await pumpEventQueue();
    expect(first.dataAt('n'), <String, Object?>{'.priority': 5});
    expect(seen1.last, (null, null));
    await sub1.cancel();
    await db1.close();

    // Second run on the same database file: the cache does not hold the kept priority, so the
    // listen hash is not the server's and the server sends the node again.
    final FakeServerActions second = _server();
    final FirebaseDatabase db2 = _open(app, second, dir.path);
    addTearDown(db2.close);
    final List<(Object?, Object?)> seen2 = <(Object?, Object?)>[];
    final StreamSubscription<DatabaseEvent> sub2 = db2
        .ref('n')
        .onValue
        .listen(
          (DatabaseEvent e) =>
              seen2.add((e.snapshot.value, e.snapshot.priority)),
        );
    addTearDown(sub2.cancel);
    await pumpEventQueue();
    second.connect();
    await pumpEventQueue();
    final ServerCall listen = second.callsOf('listen').single;
    expect(listen.hashProvider!.simpleHash(), '');
    second
      ..deliverDataUpdate('n', second.dataAt('n'))
      ..respond(listen);
    await pumpEventQueue();
    // Readers see no value and no priority for the emptied node.
    expect(seen2.last, (null, null));

    final List<Object?> runs = <Object?>[];
    final Future<TransactionResult> result = db2.ref('n').runTransaction((
      Object? v,
    ) {
      runs.add(v);
      return Transaction.success(const <String, Object?>{'b': 1});
    });
    await pumpEventQueue();
    for (int i = 0; i < 30 && second.pendingWrites.isNotEmpty; i++) {
      second.ackWrite(second.pendingWrites.first);
      await pumpEventQueue();
    }
    final TransactionResult r = await result;
    expect(r.committed, isTrue);
    expect(runs.length, lessThanOrEqualTo(2), reason: 'runs: $runs');
    expect(second.callsOf('put').last.hash, _emptiedHash);
    expect(second.dataAt('n'), <String, Object?>{'b': 1});
    expect(seen2.last.$1, <String, Object?>{'b': 1});
    expect(seen2.last.$2, isNull);
  });
}
