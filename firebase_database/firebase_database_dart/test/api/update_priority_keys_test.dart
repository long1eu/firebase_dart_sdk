// An update whose keys create a node and set its priority separately,
// `{'x/v': 1, 'x/.priority': 3}` with x missing. Measured on production and the emulator
// (2026-11-26, rtdb/from_boss/prodkit_production_run9_check39_q12_2026-11-26.txt, case q12): the
// server refuses the whole merge, in either key order, with `invalid_parameters` "could not set
// priority on non-existent node" and writes nothing; the object form
// `{'x': {'v': 1, '.priority': 3}}` is accepted. These tests pin what a caller sees: the local
// events, the Future's error and the revert. With the listens answered before the write, the local
// event shows x without its priority; the emulator showed the same sequence
// (rtdb/from_helper/reports/update_priority_keys_emulator.txt, run 1).
//
// FakeDatabaseServer.failLastWrite sends a fixed reason, so the tests drive a FakeServerActions
// directly to answer with the server's own reason.

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:firebase_database_dart/src/api/firebase_database.dart'
    show firebaseDatabaseWithConnection;
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/testing/fake_server_actions.dart';
import 'package:test/test.dart';

import 'support/fake_time.dart';
import 'support/harness.dart';

const String _reason = 'could not set priority on non-existent node';

int _appCount = 0;

/// A database over a [FakeServerActions] holding `r = {k: 1}`, with value listeners at `r` (`S`)
/// and `r/x` (`X`) logging `name:<value>/<priority>`.
final class _Wire {
  _Wire(this.time) {
    db = firebaseDatabaseWithConnection(
      FirebaseApp.withOptions(
        const FirebaseOptions(
          apiKey: 'test-key',
          appId: '1:1234567890:dart:test',
          projectId: 'test-project',
        ),
        name: 'rtdb-update-priority-keys-${_appCount++}',
      ),
      connectionFactory: (ServerActionsDelegate delegate, DatabaseLogger? _) =>
          server..delegate = delegate,
    );
    settle();
    server.connect();
    settle();
    listen('S', db.ref('r'));
    listen('X', db.ref('r/x'));
    settle();
    server.deliverDataUpdate('/r', <String, Object?>{'k': 1});
    for (final ServerCall call in server.callsOf('listen')) {
      server.respond(call);
    }
    settle();
  }

  final FakeTime time;
  final FakeServerActions server = FakeServerActions();
  final List<String> log = <String>[];
  late final FirebaseDatabase db;

  void settle() => time.elapse(Duration.zero);

  void listen(String name, Query query) => query.onValue.listen(
    (DatabaseEvent e) =>
        log.add('$name:${bare(e.snapshot.value)}/${e.snapshot.priority}'),
  );

  /// Logs `name:ok` or `name:E(code|message|serverStatus)`.
  void track(String name, Future<void> future) => future.then<void>(
    (_) => log.add('$name:ok'),
    onError: (Object e) => log.add(
      e is FirebaseDatabaseException
          ? '$name:E(${e.code}|${e.message}|${e.serverStatus})'
          : '$name:E($e)',
    ),
  );
}

void main() {
  void wired(String name, void Function(_Wire w) body) {
    test(name, () => fakeTime((FakeTime time) => body(_Wire(time))));
  }

  for (final Map<String, Object?> keys in <Map<String, Object?>>[
    <String, Object?>{'x/v': 1, 'x/.priority': 3},
    <String, Object?>{'x/.priority': 3, 'x/v': 1},
  ]) {
    wired('update ${keys.keys.join(', ')} on a missing x: shown, refused, '
        'reverted', (_Wire w) {
      expect(w.log, <String>['X:null/null', 'S:{k:1}/null']);
      w.log.clear();

      w.track('W', w.db.ref('r').update(keys));
      w.settle();
      expect(w.server.callsOf('merge').single.data, keys);
      expect(w.log, <String>['X:{v:1}/null', 'S:{k:1,x:{v:1}}/null']);

      w.server.failLastWrite('invalid_parameters', reason: _reason);
      w.settle();
      expect(w.log, <String>[
        'X:{v:1}/null',
        'S:{k:1,x:{v:1}}/null',
        'X:null/null',
        'S:{k:1}/null',
        'W:E(unknown|$_reason|invalid_parameters: $_reason)',
      ]);
      expect(w.server.dataAt('/r'), <String, Object?>{'k': 1});
    });
  }

  wired('update with x as one object is accepted', (_Wire w) {
    w.log.clear();
    w.track(
      'W',
      w.db.ref('r').update(<String, Object?>{
        'x': <String, Object?>{'v': 1, '.priority': 3},
      }),
    );
    w.settle();
    w.server.ackLastWrite();
    w.settle();
    expect(w.log, <String>['X:{v:1}/3', 'S:{k:1,x:{v:1}}/null', 'W:ok']);
    expect(w.server.dataAt('/r'), <String, Object?>{
      'k': 1,
      'x': <String, Object?>{'.priority': 3, 'v': 1},
    });
  });
}
