// The first run of a transaction happens inside runTransaction, as in JS and Android, while
// events still wait for the dispatcher's microtask. Driven through the public API over
// FakeServerActions.
import 'dart:async';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:firebase_database_dart/src/api/firebase_database.dart'
    show firebaseDatabaseWithConnection;
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/testing/fake_server_actions.dart';
import 'package:test/test.dart';

int _appCount = 0;

FirebaseApp _newApp() => FirebaseApp.withOptions(
  const FirebaseOptions(
    apiKey: 'test-key',
    appId: '1:1234567890:dart:test',
    projectId: 'test-project',
  ),
  name: 'rtdb-transaction-first-run-${_appCount++}',
);

/// Answers the oldest unanswered put as the server does: the data is stored and pushed, then
/// the put is acknowledged; a transaction put whose hash no longer matches gets `datastale`.
void _ackOldestPut(FakeServerActions server) {
  final ServerCall call = server.pendingWrites.firstWhere(
    (ServerCall c) => c.action == 'put',
  );
  final String path = call.path!;
  if (call.hash != null &&
      nodeFromJson(server.dataAt(path)).hash() != call.hash) {
    server.respond(call, status: 'datastale');
    return;
  }
  server.deliverDataUpdate(path, call.data);
  server.respond(call);
}

void main() {
  test('runTransaction(h); set(5): h runs inside the call, no event before the '
      'next microtask, the server ends with 5', () async {
    final FakeServerActions server = FakeServerActions();
    final FirebaseDatabase db = firebaseDatabaseWithConnection(
      _newApp(),
      connectionFactory: (ServerActionsDelegate delegate, DatabaseLogger? _) =>
          server..delegate = delegate,
    );
    addTearDown(db.close);
    server.connect();
    final List<Object?> seen = <Object?>[];
    final StreamSubscription<DatabaseEvent> sub = db
        .ref('c')
        .onValue
        .listen((DatabaseEvent e) => seen.add(e.snapshot.value));
    addTearDown(sub.cancel);
    await pumpEventQueue();
    server
      ..deliverDataUpdate('c', 0)
      ..respond(server.callsOf('listen').single);
    await pumpEventQueue();
    expect(seen, <Object?>[0]);
    seen.clear();

    final List<String> order = <String>[];
    final Future<TransactionResult> result = db.ref('c').runTransaction((
      Object? v,
    ) {
      order.add('handler($v)');
      return Transaction.success((v! as int) + 1);
    });
    order.add('returned');
    final Future<void> written = db.ref('c').set(5);
    expect(order, <String>['handler(0)', 'returned']);
    expect(seen, isEmpty, reason: 'no event inside the calls');
    await pumpEventQueue();
    expect(seen, <Object?>[1, 5]);

    expect(server.callsOf('put').map((ServerCall c) => c.hash != null), <bool>[
      true,
      false,
    ]);
    _ackOldestPut(server);
    _ackOldestPut(server);
    final TransactionResult r = await result;
    await written;
    expect(r.committed, isTrue);
    expect(server.dataAt('c'), 5);
    await pumpEventQueue();
    expect(seen.last, 5);
  });
}
