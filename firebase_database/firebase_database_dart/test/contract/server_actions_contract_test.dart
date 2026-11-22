// Contract of ServerActions and ServerActionsDelegate (lib/src/core/connection/server_actions.dart).
//
// Any connection must pass serverActionsContract with a harness that plays the server; main runs
// it against FakeServerActions. The connection team runs it against its implementation with a
// harness over a local fake WebSocket server.
import 'dart:async';

import 'package:firebase_database_dart/src/core/connection/listen_hash_provider.dart';
import 'package:firebase_database_dart/src/core/connection/listen_spec.dart';
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/core/connection/wire_range_merge.dart';
import 'package:firebase_database_dart/src/testing/fake_server_actions.dart';
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

  /// Pushes `d` or `m`.
  Future<void> push(
    String path,
    Object? data, {
    bool isMerge = false,
    int? tag,
  });

  /// Drops the connection.
  Future<void> drop();
}

/// The contract.
void serverActionsContract(ServerActionsHarness Function() createHarness) {
  late ServerActionsHarness harness;
  late RecordingDelegate delegate;
  late ServerActions actions;

  setUp(() async {
    harness = createHarness();
    delegate = RecordingDelegate();
    actions = await harness.start(delegate);
  });

  const ListenSpec defaultSpec = ListenSpec(
    path: '/users/ada',
    queryObject: <String, Object?>{},
    queryIdentifier: 'default',
    isDefault: true,
    loadsAllData: true,
    indexName: '.priority',
  );
  const ListenSpec taggedSpec = ListenSpec(
    path: '/users',
    queryObject: <String, Object?>{'i': 'age', 'l': 10, 'vf': 'l'},
    queryIdentifier: '{"i":"age","l":10,"vf":"l"}',
    isDefault: false,
    loadsAllData: false,
    indexName: 'age',
  );

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

  test('data pushes reach the delegate with path strings and tags', () async {
    await harness.push(
      '/users',
      <String, Object?>{'ada': 1},
      isMerge: true,
      tag: 3,
    );
    await pumpEventQueue();
    expect(delegate.updates.single, (
      path: '/users',
      data: <String, Object?>{'ada': 1},
      isMerge: true,
      tag: 3,
    ));
  });

  test(
    'a sent transaction put is completed with disconnect before onDisconnect',
    () async {
      final List<String> log = <String>[];
      delegate.log = log;
      actions.put(
        '/counter',
        2,
        hash: 'h1',
        onComplete: (String status, _) => log.add('put $status'),
      );
      actions.put(
        '/plain',
        1,
        onComplete: (String status, _) => log.add('plain $status'),
      );
      await pumpEventQueue();
      await harness.drop();
      await pumpEventQueue();
      expect(log, <String>['put $statusDisconnect', 'onDisconnect']);
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

  test('interrupt reasons are tracked', () {
    actions.interrupt('repo_interrupt');
    expect(actions.isInterrupted('repo_interrupt'), isTrue);
    actions.resume('repo_interrupt');
    expect(actions.isInterrupted('repo_interrupt'), isFalse);
  });
}

/// A delegate that records what it hears.
final class RecordingDelegate implements ServerActionsDelegate {
  /// The data updates.
  final List<({String path, Object? data, bool isMerge, int? tag})> updates =
      <({String path, Object? data, bool isMerge, int? tag})>[];

  /// An optional shared log of lifecycle calls.
  List<String>? log;

  @override
  void onDataUpdate(
    String path,
    Object? data, {
    required bool isMerge,
    int? tag,
  }) => updates.add((path: path, data: data, isMerge: isMerge, tag: tag));

  @override
  void onRangeMergeUpdate(
    String path,
    List<WireRangeMerge> merges, {
    int? tag,
  }) => log?.add('rm $path');

  @override
  void onConnect() => log?.add('onConnect');

  @override
  void onDisconnect() => log?.add('onDisconnect');

  @override
  void onAuthStatus(String status, {String? explanation}) =>
      log?.add('auth $status');

  @override
  void onAppCheckStatus(String status, {String? explanation}) =>
      log?.add('appcheck $status');

  @override
  void onServerShutdown(String reason) => log?.add('shutdown $reason');

  @override
  void onServerInfoUpdate(Map<String, Object?> updates) =>
      log?.add('info $updates');
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

final class _FakeHarness implements ServerActionsHarness {
  late FakeServerActions fake;

  static const Map<String, String> _wire = <String, String>{
    'listen': 'q',
    'unlisten': 'n',
    'get': 'g',
    'put': 'p',
    'merge': 'm',
    'onDisconnectPut': 'o',
    'onDisconnectMerge': 'om',
    'onDisconnectCancel': 'oc',
  };

  @override
  Future<ServerActions> start(ServerActionsDelegate delegate) async {
    fake = FakeServerActions(delegate)..initialize();
    fake.connect();
    return fake;
  }

  @override
  List<({String action, Map<String, Object?> body})> get received =>
      <({String action, Map<String, Object?> body})>[
        for (final ServerCall call in fake.calls)
          if (_wire.containsKey(call.action))
            (
              action: _wire[call.action]!,
              body: <String, Object?>{
                'p': call.spec?.path ?? call.path,
                if (call.action == 'listen')
                  'h': call.hashProvider!.simpleHash(),
                if (call.tag != null || call.action == 'get')
                  'q': call.spec!.queryObject,
                if (call.tag != null) 't': call.tag,
                if (call.data != null) 'd': call.data,
                if (call.hash != null) 'h': call.hash,
              },
            ),
      ];

  @override
  Future<void> answer(
    String action, {
    String status = statusOk,
    Object? data,
  }) async {
    final ServerCall call = fake.calls.firstWhere(
      (ServerCall c) => _wire[c.action] == action && !c.answered,
    );
    fake.respond(call, status: status, data: data);
  }

  @override
  Future<void> push(
    String path,
    Object? data, {
    bool isMerge = false,
    int? tag,
  }) async => fake.deliverDataUpdate(path, data, isMerge: isMerge, tag: tag);

  @override
  Future<void> drop() async => fake.disconnect();
}

void main() {
  group('FakeServerActions', () => serverActionsContract(_FakeHarness.new));
}
