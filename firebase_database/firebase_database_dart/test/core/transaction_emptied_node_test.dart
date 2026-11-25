// A transaction on a node emptied by a write below it. The server keeps the node's priority and
// counts it in the hash it compares a transaction put against; production (check 38 (c),
// rtdb/from_boss/prodkit_production_run3_2026-11-25.txt) failed such a transaction with
// max-retries when the client hashed the node as empty. FakeServerActions plays that server: it
// keeps the priority, hashes it and sends `{".priority": 5}` as production does.
import 'dart:async';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:firebase_database_dart/src/api/firebase_database.dart'
    show firebaseDatabaseWithConnection;
import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
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
  name: 'rtdb-transaction-emptied-node-${_appCount++}',
);

/// sha1('priority:number:4014000000000000:'): the hash production accepted for the emptied node
/// with priority 5 (check 38 (c)).
const String _emptiedHash = 'Za4HQEOLkfDszOTdKHl8KWNgpRE=';

void main() {
  test(
    'commits on the first or second run; the put carries the server hash',
    () async {
      final FakeServerActions server = FakeServerActions()
        ..writeByOtherClient('n', <String, Object?>{'a': 1, '.priority': 5})
        ..writeByOtherClient('n/a', null);
      expect(server.dataAt('n'), <String, Object?>{'.priority': 5});
      final FirebaseDatabase db = firebaseDatabaseWithConnection(
        _newApp(),
        connectionFactory:
            (ServerActionsDelegate delegate, DatabaseLogger? _) =>
                server..delegate = delegate,
      );
      addTearDown(db.close);
      server.connect();

      final List<Object?> runs = <Object?>[];
      final Future<TransactionResult> result = db.ref('n').runTransaction((
        Object? v,
      ) {
        runs.add(v);
        return Transaction.success(const <String, Object?>{'b': 1});
      });
      await pumpEventQueue();
      final ServerCall listen = server.callsOf('listen').single;
      server
        ..deliverDataUpdate('n', server.dataAt('n'))
        ..respond(listen);
      await pumpEventQueue();
      for (int i = 0; i < 30 && server.pendingWrites.isNotEmpty; i++) {
        server.ackWrite(server.pendingWrites.first);
        await pumpEventQueue();
      }
      final TransactionResult r = await result;
      expect(r.committed, isTrue);
      expect(runs.length, lessThanOrEqualTo(2), reason: 'runs: $runs');
      expect(runs.last, isNull);
      final List<ServerCall> puts = server.callsOf('put');
      expect(puts.last.hash, _emptiedHash);
      // The put carries what the handler returned, never the kept priority.
      for (final ServerCall put in puts) {
        expect(put.data, <String, Object?>{'b': 1});
      }
      // The transaction's set replaces the node: the kept priority goes, as with set(n, value).
      expect(server.dataAt('n'), <String, Object?>{'b': 1});
    },
  );

  test('a fresh listener reads no value and no priority, then the priority '
      'after a refill', () async {
    final FakeServerActions server = FakeServerActions()
      ..writeByOtherClient('n', <String, Object?>{'a': 1, '.priority': 5})
      ..writeByOtherClient('n/a', null);
    final FirebaseDatabase db = firebaseDatabaseWithConnection(
      _newApp(),
      connectionFactory: (ServerActionsDelegate delegate, DatabaseLogger? _) =>
          server..delegate = delegate,
    );
    addTearDown(db.close);
    server.connect();
    final List<(Object?, Object?)> seen = <(Object?, Object?)>[];
    final StreamSubscription<DatabaseEvent> sub = db
        .ref('n')
        .onValue
        .listen(
          (DatabaseEvent e) =>
              seen.add((e.snapshot.value, e.snapshot.priority)),
        );
    addTearDown(sub.cancel);
    await pumpEventQueue();
    server
      ..deliverDataUpdate('n', server.dataAt('n'))
      ..respond(server.callsOf('listen').single);
    await pumpEventQueue();
    expect(seen, <(Object?, Object?)>[(null, null)]);
    final DataSnapshot snapshot = await db.ref('n').get();
    expect(snapshot.exists, isFalse);
    expect(snapshot.priority, isNull);
    final Future<void> written = db.ref('n/b').set(1);
    await pumpEventQueue();
    expect(seen.last.$1, <String, Object?>{'b': 1});
    expect(seen.last.$2, 5);
    expect(server.callsOf('put').single.data, 1);
    server.ackLastWrite();
    await written;
    expect(server.dataAt('n'), <String, Object?>{'b': 1, '.priority': 5});
  });

  test('update {a: null, .priority: 7} on a node without a priority: the client '
      'and the fake server agree', () {
    // The client writes the priority first (the node has a value then) and the emptied node
    // keeps it: {".priority": 7}. FakeServerActions applies the children first, the node is
    // gone and the priority lands on nothing: null. A transaction on such a node fails with
    // max-retries against whichever is wrong. Production measured only a node that had a
    // priority (check 38 (b)), where both orders give 7.
    final Object? client =
        (CompoundWrite.fromValue(<String, Object?>{
                  'a': null,
                  '.priority': 7,
                }).apply(nodeFromJson(<String, Object?>{'a': 1}))
                as ChildrenNode)
            .toServerJson();
    expect(client, <String, Object?>{'.priority': 7});
    final FakeServerActions server = FakeServerActions()
      ..writeByOtherClient('n', <String, Object?>{'a': 1})
      ..writeByOtherClient('n', <String, Object?>{
        'a': null,
        '.priority': 7,
      }, isMerge: true);
    expect(server.dataAt('n'), client);
  }, skip: 'server rule unmeasured, see prodkit_dart_gaps3 Q1');
}
