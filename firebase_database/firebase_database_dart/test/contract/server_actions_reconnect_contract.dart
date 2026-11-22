// Owner P. The reconnect part of the ServerActions contract (lib/src/core/connection/
// server_actions.dart): what an implementation that keeps a connection across drops must do, on
// top of runServerActionsContract (server_actions_contract.dart). A function file, no main: P's
// runner (over FakeRtdbServer) imports it and calls runServerActionsReconnectContract. The
// read-only REST client does not run it (it has no connection to lose).

import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/testing/recording_server_actions_delegate.dart';
import 'package:test/test.dart';

import 'server_actions_contract.dart';

/// Plays the server across connections: the core's [ServerActionsHarness] plus reconnects and
/// the pushes that only a live server sends.
///
/// [ServerActionsHarness.received] lists only the actions of the core contract (`q`, `n`, `g`,
/// `p`, `m`, `o`, `om`, `oc`); [actionsOn] lists every action of one connection, `auth`, `gauth`
/// and `appcheck` included.
abstract interface class ServerActionsReconnectHarness
    implements ServerActionsHarness {
  /// The number of the connection (from 1) on which `received[index]` arrived.
  int connectionOf(int index);

  /// Every action (credential actions included) received on connection [number], in order.
  List<String> actionsOn(int number);

  /// Accepts the next connection attempt after a [drop] and sends its hello; completes once the
  /// client's replay has arrived and the delegate heard `connect`.
  Future<void> reconnect();

  /// Pushes `c` (listen revoked) for [path] in the server's form (`users/ada`), with the query
  /// objects [queries] when given.
  Future<void> revokeListen(String path, [List<Map<String, Object?>>? queries]);

  /// Pushes `ac` (auth revoked) with [status] and [explanation].
  Future<void> revokeAuth(String status, String explanation);

  /// Lets every request on the current connection time out once (the server stays silent).
  Future<void> timeOutPending();
}

/// The reconnect contract.
///
/// * replay order after a reconnect: `auth`, `appcheck`, listens (with a freshly computed hash),
///   unacknowledged puts and merges in order, onDisconnect requests not yet sent, outstanding
///   gets; only then `ServerActionsDelegate.onConnect`;
/// * acknowledged puts are not replayed; a sent transaction put (with a hash) completes with
///   [statusDisconnect] instead of being replayed, before `ServerActionsDelegate.onDisconnect`;
/// * a failed listen, and a listen revoked by a `c` push, complete with their status, leave the
///   listen table and are not replayed;
/// * onDisconnect requests made while offline are queued and sent at the next connection;
/// * a `get` outstanding at a drop is re-sent once and completes once; a failed `get` fails with
///   [ServerActionsException] carrying the status and reason;
/// * a request that times out twice on live connections completes with `network_error` and is
///   not replayed again;
/// * an auth revoke closes the connection and the next connection authenticates again.
void runServerActionsReconnectContract(
  ServerActionsReconnectHarness Function() createHarness,
) {
  late ServerActionsReconnectHarness harness;
  late RecordingServerActionsDelegate delegate;
  late ServerActions actions;

  setUp(() async {
    harness = createHarness();
    delegate = RecordingServerActionsDelegate();
    actions = await harness.start(delegate);
  });

  tearDown(() => actions.shutdown());

  List<String> received(int connection) => <String>[
    for (int i = 0; i < harness.received.length; i++)
      if (harness.connectionOf(i) == connection) harness.received[i].action,
  ];

  test('replay order after a reconnect, then onConnect', () async {
    await harness.drop();
    actions.put('/a', 1, onComplete: (_, _) {});
    actions.merge('/b', <String, Object?>{'c': 1}, onComplete: (_, _) {});
    actions.onDisconnectPut('/presence', false);
    actions.listen(
      defaultSpec,
      hashProvider: FixedHash('h'),
      onComplete: (_, _) {},
    );
    final Future<Object?> pending = actions.get(defaultSpec);
    expect(received(2), isEmpty);
    final int connectsBefore = delegate.callsOf('connect').length;
    await harness.reconnect();
    expect(harness.actionsOn(2), <String>[
      'auth',
      'appcheck',
      'q',
      'p',
      'm',
      'o',
      'g',
    ]);
    expect(delegate.callsOf('connect').length, connectsBefore + 1);
    unawaitedIgnore(pending);
  });

  test(
    'acknowledged work is not replayed; a sent transaction put completes with disconnect',
    () async {
      final List<String> results = <String>[];
      actions.put(
        '/acked',
        1,
        onComplete: (String s, _) => results.add('acked $s'),
      );
      actions.put(
        '/tx',
        2,
        hash: 'h',
        onComplete: (String s, _) => results.add('tx $s'),
      );
      await pumpEventQueue();
      await harness.answer('p'); // The oldest put: /acked.
      await harness.drop();
      await harness.reconnect();
      expect(results, <String>['acked $statusOk', 'tx $statusDisconnect']);
      expect(received(2), isNot(contains('p')));
      final int disconnectAt = delegate.methods.indexOf('disconnect');
      expect(disconnectAt, greaterThanOrEqualTo(0));
    },
  );

  test(
    'a failed or revoked listen leaves the table and is not replayed',
    () async {
      final List<String> statuses = <String>[];
      actions.listen(
        defaultSpec,
        hashProvider: FixedHash(''),
        onComplete: (String s, _) => statuses.add('default $s'),
      );
      actions.listen(
        taggedSpec,
        hashProvider: FixedHash(''),
        tag: 1,
        onComplete: (String s, _) => statuses.add('tagged $s'),
      );
      await pumpEventQueue();
      await harness.answer('q', status: 'permission_denied', data: 'denied');
      await harness.revokeListen('users');
      await pumpEventQueue();
      expect(statuses, <String>[
        'default permission_denied',
        'tagged permission_denied',
      ]);
      await harness.drop();
      await harness.reconnect();
      expect(received(2), isNot(contains('q')));
    },
  );

  test(
    'onDisconnect requests made while offline are sent at the next connection',
    () async {
      await harness.drop();
      final List<String> statuses = <String>[];
      actions.onDisconnectPut(
        '/p',
        1,
        onComplete: (String s, _) => statuses.add(s),
      );
      actions.onDisconnectMerge('/p', <String, Object?>{'a': 1});
      actions.onDisconnectCancel('/q');
      await pumpEventQueue();
      expect(received(2), isEmpty);
      await harness.reconnect();
      expect(received(2), <String>['o', 'om', 'oc']);
      final int oc = harness.received.lastIndexWhere((r) => r.action == 'oc');
      expect(harness.received[oc].body, <String, Object?>{
        'p': '/q',
        'd': null,
      });
      await harness.answer('o');
      expect(statuses, <String>[statusOk]);
    },
  );

  test(
    'an outstanding get is re-sent once; a failed get throws ServerActionsException',
    () async {
      final Future<Object?> first = actions.get(defaultSpec);
      await pumpEventQueue();
      await harness.drop();
      await harness.reconnect();
      expect(received(2).where((String a) => a == 'g'), hasLength(1));
      // The expectation listens before the answer, or the error would be unhandled (a connection
      // may complete the get inside the answer; same fix as the core's contract).
      final Future<void> failed = expectLater(
        first,
        throwsA(
          isA<ServerActionsException>()
              .having(
                (ServerActionsException e) => e.status,
                'status',
                'permission_denied',
              )
              .having((ServerActionsException e) => e.reason, 'reason', 'no'),
        ),
      );
      await harness.answer('g', status: 'permission_denied', data: 'no');
      await failed;
    },
  );

  test('a request that times out twice fails with network_error', () async {
    final List<String> statuses = <String>[];
    actions.put('/slow', 1, onComplete: (String s, _) => statuses.add(s));
    await pumpEventQueue();
    await harness.timeOutPending(); // First timeout: the connection closes.
    await harness.reconnect(); // The put is replayed.
    expect(received(2), contains('p'));
    await harness.timeOutPending(); // Second timeout on a live connection.
    await pumpEventQueue();
    expect(statuses, <String>['network_error']);
    await harness.drop();
    await harness.reconnect();
    expect(received(3), isNot(contains('p')));
  });

  test(
    'an auth revoke closes the connection and the next one authenticates again',
    () async {
      final int disconnects = delegate.callsOf('disconnect').length;
      await harness.revokeAuth('invalid_token', 'expired');
      await pumpEventQueue();
      expect(delegate.callsOf('disconnect').length, disconnects + 1);
      await harness.reconnect();
      expect(harness.actionsOn(2).first, anyOf('auth', 'gauth'));
    },
  );
}

/// Marks [future] as intentionally not awaited (its error, if any, is ignored).
void unawaitedIgnore(Future<Object?> future) {
  future.then<void>((_) {}, onError: (Object _) {});
}
