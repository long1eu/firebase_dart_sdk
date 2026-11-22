// Contract of ServerActions and ServerActionsDelegate (lib/src/core/connection/server_actions.dart).
//
// Any connection must pass runServerActionsContract with a harness that plays the server; a
// read-only connection (the REST client) must also pass runReadOnlyServerActionsContract.
// server_actions_contract_test.dart runs both against FakeServerActions; the connection team runs
// them against its implementations with a harness over a local fake server. No main here: other
// packages import this file.
import 'dart:async';

import 'package:firebase_database_dart/src/core/connection/listen_hash_provider.dart';
import 'package:firebase_database_dart/src/core/connection/listen_spec.dart';
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/testing/recording_server_actions_delegate.dart';
import 'package:test/test.dart';

/// Plays the server side for a [ServerActions] under test.
abstract interface class ServerActionsHarness {
  /// Creates the connection under test reporting to [delegate], and brings it up.
  Future<ServerActions> start(ServerActionsDelegate delegate);

  /// The requests the server received so far, as (action, body) with the wire action names
  /// (`q`, `n`, `g`, `p`, `m`, `o`, `om`, `oc`).
  List<({String action, Map<String, Object?> body})> get received;

  /// Answers the oldest unanswered request with [action].
  Future<void> answer(String action, {String status = statusOk, Object? data});

  /// Pushes `d` or `m` at [path] in the server's form: `users/ada`, `''` for the root.
  Future<void> push(
    String path,
    Object? data, {
    bool isMerge = false,
    int? tag,
  });

  /// Drops the connection.
  Future<void> drop();
}

/// A default listen spec at `/users/ada`.
const ListenSpec defaultSpec = ListenSpec(
  path: '/users/ada',
  queryObject: <String, Object?>{},
  queryIdentifier: 'default',
  isDefault: true,
  loadsAllData: true,
  indexName: '.priority',
  restParams: <String, String>{},
);

/// A tagged (limited) listen spec at `/users`.
const ListenSpec taggedSpec = ListenSpec(
  path: '/users',
  queryObject: <String, Object?>{'i': 'age', 'l': 10, 'vf': 'l'},
  queryIdentifier: '{"i":"age","l":10,"vf":"l"}',
  isDefault: false,
  loadsAllData: false,
  indexName: 'age',
  restParams: <String, String>{'orderBy': '"age"', 'limitToFirst': '10'},
);

/// The contract every connection passes.
void runServerActionsContract(ServerActionsHarness Function() create) {
  late ServerActionsHarness harness;
  late RecordingServerActionsDelegate delegate;
  late ServerActions actions;

  setUp(() async {
    harness = create();
    delegate = RecordingServerActionsDelegate();
    actions = await harness.start(delegate);
  });

  test('a default listen sends p and h only', () async {
    actions.listen(
      defaultSpec,
      hashProvider: FixedHash('abc'),
      onComplete: (_, _) {},
    );
    await pumpEventQueue();
    final Map<String, Object?> body = harness.received.last.body;
    expect(harness.received.last.action, 'q');
    expect(body['p'], '/users/ada');
    expect(body['h'], 'abc');
    expect(body.containsKey('q'), isFalse);
    expect(body.containsKey('t'), isFalse);
  });

  test('a tagged listen sends q and t', () async {
    actions.listen(
      taggedSpec,
      hashProvider: FixedHash(''),
      tag: 1,
      onComplete: (_, _) {},
    );
    await pumpEventQueue();
    final Map<String, Object?> body = harness.received.last.body;
    expect(body['q'], taggedSpec.queryObject);
    expect(body['t'], 1);
    expect(body['h'], '');
  });

  test('a listen completes once, never synchronously', () async {
    final List<String> statuses = <String>[];
    actions.listen(
      defaultSpec,
      hashProvider: FixedHash(''),
      onComplete: (String s, _) {
        statuses.add(s);
      },
    );
    expect(statuses, isEmpty);
    await harness.answer('q');
    await pumpEventQueue();
    expect(statuses, <String>[statusOk]);
  });

  test('pushed paths reach the delegate as /a/b, with tags', () async {
    await harness.push(
      'users',
      <String, Object?>{'ada': 1},
      isMerge: true,
      tag: 3,
    );
    await pumpEventQueue();
    final DelegateCall call = delegate.callsOf('dataUpdate').single;
    expect(call.path, '/users');
    expect(call.data, <String, Object?>{'ada': 1});
    expect(call.isMerge, isTrue);
    expect(call.tag, 3);
  });

  test('a push at the root reaches the delegate as /', () async {
    await harness.push('', 'x');
    await pumpEventQueue();
    final DelegateCall call = delegate.callsOf('dataUpdate').single;
    expect(call.path, '/');
    expect(call.data, 'x');
    expect(call.isMerge, isFalse);
  });

  test('merge keys are handed over as the server sent them', () async {
    await harness.push('users', <String, Object?>{
      'ada/name': 'Ada',
      'bob': null,
    }, isMerge: true);
    await pumpEventQueue();
    expect(delegate.callsOf('dataUpdate').single.data, <String, Object?>{
      'ada/name': 'Ada',
      'bob': null,
    });
  });

  test(
    'a sent transaction put is completed with disconnect before onDisconnect',
    () async {
      final List<String> log = <String>[];
      actions.put(
        '/counter',
        2,
        hash: 'h1',
        onComplete: (String status, _) {
          log.add('put $status');
          if (delegate.methods.contains('disconnect')) {
            log.add('too late');
          }
        },
      );
      actions.put(
        '/plain',
        1,
        onComplete: (String status, _) => log.add('plain $status'),
      );
      await pumpEventQueue();
      await harness.drop();
      await pumpEventQueue();
      expect(log, <String>['put $statusDisconnect']);
      expect(delegate.methods, contains('disconnect'));
    },
  );

  test('a get completes with the data', () async {
    final Future<Object?> result = actions.get(defaultSpec);
    await pumpEventQueue();
    expect(harness.received.last.action, 'g');
    expect(harness.received.last.body['q'], <String, Object?>{});
    await harness.answer('g', data: 'Ada');
    expect(await result, 'Ada');
  });

  test('a failed get fails with ServerActionsException', () async {
    final Future<Object?> result = actions.get(defaultSpec);
    await pumpEventQueue();
    await harness.answer('g', status: 'permission_denied', data: 'denied');
    await expectLater(
      result,
      throwsA(
        isA<ServerActionsException>()
            .having(
              (ServerActionsException e) => e.status,
              'status',
              'permission_denied',
            )
            .having((ServerActionsException e) => e.reason, 'reason', 'denied'),
      ),
    );
  });

  test('interrupt reasons are tracked', () {
    actions.interrupt('repo_interrupt');
    expect(actions.isInterrupted('repo_interrupt'), isTrue);
    actions.resume('repo_interrupt');
    expect(actions.isInterrupted('repo_interrupt'), isFalse);
  });

  test('shutdown completes', () async {
    await actions.shutdown();
  });
}

/// The contract of a read-only connection (the REST client): every write and onDisconnect
/// request completes, asynchronously, with [statusReadOnly]. [start] creates the connection
/// reporting to the given delegate.
void runReadOnlyServerActionsContract(
  Future<ServerActions> Function(ServerActionsDelegate delegate) start,
) {
  late ServerActions actions;

  setUp(() async {
    actions = await start(RecordingServerActionsDelegate());
  });

  test(
    'every write and onDisconnect request completes with read_only',
    () async {
      final List<String> statuses = <String>[];
      void record(String status, Object? _) => statuses.add(status);

      actions.put('/a', 1, onComplete: record);
      actions.put('/a', 1, hash: 'h', onComplete: record);
      actions.merge('/a', <String, Object?>{'b': 1}, onComplete: record);
      actions.onDisconnectPut('/a', 1, onComplete: record);
      actions.onDisconnectMerge('/a', <String, Object?>{
        'b': 1,
      }, onComplete: record);
      actions.onDisconnectCancel('/a', onComplete: record);
      expect(statuses, isEmpty);
      await pumpEventQueue();
      expect(statuses, List<String>.filled(6, statusReadOnly));
    },
  );
}

/// A hash provider with a fixed simple hash and no compound hash.
final class FixedHash implements ListenHashProvider {
  /// Creates the provider.
  FixedHash(this.hash);

  /// The hash.
  final String hash;

  @override
  String simpleHash() => hash;

  @override
  bool shouldIncludeCompoundHash() => false;

  @override
  WireCompoundHash compoundHash() =>
      const WireCompoundHash(posts: <String>[], hashes: <String>['']);
}
