// A node emptied by a write below it keeps its priority on the server (production check 38). The
// SQLite engine stores export JSON and clears the priority of an emptied node
// (ServerCacheRows._clearEmptiedNodes), so after a restart the client does not hold the kept
// priority: its listen hash differs from the server's, the server sends the node again with
// `{".priority": p}`, and a transaction on the node commits. The server is the client package's
// internal FakeServerActions, which keeps and hashes the priority and sends it as production
// does; the public FakeDatabaseServer reads its answers with the public nodeFromJson and cannot.
// The test answers a listen as the server does: data only when the listen's hash differs.
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
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/testing/fake_server_actions.dart';
import 'package:firebase_database_dart_sqlite/firebase_database_dart_sqlite.dart';
import 'package:test/test.dart';

/// sha1('priority:number:4014000000000000:'): the server's hash of the emptied node with
/// priority 5 (production accepted it in check 38 (c)).
const String _emptiedHash = 'Za4HQEOLkfDszOTdKHl8KWNgpRE=';

/// A fake server holding `p` = `{m: 1, n: {a: 1}}`, `n` with priority 5, emptied by another
/// client.
FakeServerActions _server() => FakeServerActions()
  ..writeByOtherClient('p', <String, Object?>{
    'm': 1,
    'n': <String, Object?>{'a': 1, '.priority': 5},
  })
  ..writeByOtherClient('p/n/a', null);

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

/// Answers the open listen at [path] as the server does: the data only when the listen's hash
/// differs from the hash of what the server holds, then the completion. Returns whether data
/// was sent.
bool _answerListen(FakeServerActions server, String path) {
  final ServerCall listen = server
      .callsOf('listen')
      .lastWhere((ServerCall c) => c.spec!.path == '/$path' && !c.answered);
  final Object? data = server.dataAt(path);
  final bool resend =
      listen.hashProvider!.simpleHash() != nodeFromServerJson(data).hash();
  if (resend) {
    server.deliverDataUpdate(path, data);
  }
  server.respond(listen);
  return resend;
}

typedef _Seen = (Object?, Object?);

StreamSubscription<DatabaseEvent> _listen(
  FirebaseDatabase db,
  String path,
  List<_Seen> seen,
) => db
    .ref(path)
    .onValue
    .listen(
      (DatabaseEvent e) => seen.add((e.snapshot.value, e.snapshot.priority)),
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

    // First run: p arrives with n's priority, and another client empties n.
    final FakeServerActions first = FakeServerActions()
      ..writeByOtherClient('p', <String, Object?>{
        'm': 1,
        'n': <String, Object?>{'a': 1, '.priority': 5},
      });
    final FirebaseDatabase db1 = _open(app, first, dir.path);
    final List<_Seen> seen1 = <_Seen>[];
    final StreamSubscription<DatabaseEvent> sub1 = _listen(db1, 'p', seen1);
    await pumpEventQueue();
    first.connect();
    await pumpEventQueue();
    expect(_answerListen(first, 'p'), isTrue);
    await pumpEventQueue();
    first.writeByOtherClient('p/n/a', null);
    await pumpEventQueue();
    expect(first.dataAt('p'), <String, Object?>{
      'm': 1,
      'n': <String, Object?>{'.priority': 5},
    });
    expect(seen1.last.$1, <String, Object?>{'m': 1});
    await sub1.cancel();
    await db1.close();

    // Second run on the same database file. Offline, the cache gives {m: 1}: it was read. It
    // does not hold n's kept priority, so the listen hash is not the server's and the server
    // sends p again.
    final FakeServerActions second = _server();
    final FirebaseDatabase db2 = _open(app, second, dir.path);
    addTearDown(db2.close);
    final List<_Seen> seen2 = <_Seen>[];
    final StreamSubscription<DatabaseEvent> sub2 = _listen(db2, 'p', seen2);
    addTearDown(sub2.cancel);
    await pumpEventQueue();
    expect(seen2.single.$1, <String, Object?>{'m': 1});
    second.connect();
    await pumpEventQueue();
    expect(
      second.callsOf('listen').single.hashProvider!.simpleHash(),
      nodeFromServerJson(<String, Object?>{'m': 1}).hash(),
    );
    expect(_answerListen(second, 'p'), isTrue);
    await pumpEventQueue();
    // Readers see no value and no priority for the emptied n; no new event for p.
    expect(seen2, hasLength(1));

    final List<Object?> runs = <Object?>[];
    final Future<TransactionResult> result = db2.ref('p/n').runTransaction((
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
    expect(second.dataAt('p'), <String, Object?>{
      'm': 1,
      'n': <String, Object?>{'b': 1},
    });
    expect(seen2.last.$1, <String, Object?>{
      'm': 1,
      'n': <String, Object?>{'b': 1},
    });
  });
}
