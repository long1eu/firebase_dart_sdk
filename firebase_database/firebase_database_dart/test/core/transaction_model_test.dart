// A model-based test of transactions: random sequences of transactions, sets, updates, purges,
// dropped connections, goOffline/goOnline and server answers (ok, datastale, permission_denied,
// other clients' writes), run against FakeServerActions on a fake clock. After each sequence
// settles: every completion ran once, no write is pending, no transaction is queued, what the
// listeners last saw is the server's data, and removing the listeners leaves nothing registered.
// No dart:io, so it runs in a browser too.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_database_dart/src/core/callback_event_registration.dart';
import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/repo.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/transaction_data.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:firebase_database_dart/src/testing/fake_server_actions.dart';
import 'package:test/test.dart';

import '../api/support/fake_time.dart';
import 'repo_harness.dart' hide FakeTime;

const List<String> _paths = <String>['a', 'a/x', 'a/y', 'b'];
const List<String> _listened = <String>['a', 'b'];
const int _steps = 40;

/// One run of the model for [seed]; throws a [TestFailure] that names the seed and the steps.
void _runSeed(int seed) {
  final List<String> trace = <String>[];
  final List<Object> uncaught = <Object>[];
  try {
    runZonedGuarded(
      () => fakeTime((FakeTime time) => _Model(seed, time, trace).run()),
      (Object error, StackTrace stack) => uncaught.add('$error\n$stack'),
    );
    if (uncaught.isNotEmpty) {
      throw TestFailure('uncaught: ${uncaught.first}');
    }
  } on Object catch (e, st) {
    final String detail = e is TestFailure ? e.message ?? '$e' : '$e\n$st';
    fail('seed $seed failed: $detail\nsteps:\n  ${trace.join('\n  ')}');
  }
}

final class _Model {
  _Model(int seed, this.time, this.trace) : rng = Random(seed);

  final Random rng;
  final FakeTime time;
  final List<String> trace;
  late final RepoHarness h;
  final Map<String, CallbackEventRegistration> listeners =
      <String, CallbackEventRegistration>{};
  final Map<String, String> lastSeen = <String, String>{};

  /// Completion count per started operation.
  final Map<String, int> completions = <String, int>{};
  int _ops = 0;
  bool online = true;
  bool interrupted = false;

  FakeServerActions get server => h.server;

  void flush() => time.elapse(Duration.zero);

  String _start(String kind) {
    final String id = '$kind#${_ops++}';
    completions[id] = 0;
    return id;
  }

  void _done(String id) => completions[id] = completions[id]! + 1;

  void run() {
    h = RepoHarness();
    server.deliverDataUpdate('', <String, Object?>{
      'a': <String, Object?>{'x': 0, 'y': 0},
      'b': 0,
    });
    for (final String path in _listened) {
      final CallbackEventRegistration registration = CallbackEventRegistration(
        QuerySpec.defaultAt(Path(path)),
        const <EventType>{EventType.value},
        onEvent: (DataEvent e) {
          lastSeen[path] = json(e.snapshot);
          trace.add('  $path sees ${lastSeen[path]}');
        },
        onCancel: (_) => lastSeen[path] = 'cancelled',
      );
      listeners[path] = registration;
      h.repo.addEventCallback(registration);
      flush();
      server.deliverDataUpdate(path, server.dataAt(path));
      server.respond(server.callsOf('listen').last);
    }
    flush();
    for (int i = 0; i < _steps; i++) {
      _step();
      flush();
    }
    _settle();
    _check();
  }

  String _path() => _paths[rng.nextInt(_paths.length)];

  void _step() {
    final int pick = rng.nextInt(100);
    if (pick < 25) {
      _transaction();
    } else if (pick < 37) {
      _set(_path(), rng.nextInt(100));
    } else if (pick < 45) {
      _update();
    } else if (pick < 49) {
      trace.add('purge');
      h.repo.purgeOutstandingWrites();
    } else if (pick < 55) {
      _goOffline(interrupt: rng.nextBool());
    } else if (pick < 63) {
      _goOnline();
    } else if (pick < 71) {
      if (online) {
        final String path = _path();
        final int value = 100 + rng.nextInt(100);
        trace.add('server write $path=$value');
        server.deliverDataUpdate(path, value);
      }
    } else if (pick < 89) {
      _answer('ok');
    } else if (pick < 95) {
      _answer('permission_denied');
    } else {
      _answer('datastale');
    }
  }

  void _transaction() {
    final String path = _path();
    final int kind = rng.nextInt(6);
    final bool applyLocally = rng.nextInt(4) != 0;
    final String id = _start('tx $path k$kind');
    trace.add('$id applyLocally=$applyLocally');
    int runs = 0;
    h.repo.startTransaction(
      Path(path),
      (Object? value) {
        runs++;
        switch (kind) {
          case 0:
            return TransactionSuccess(value is int ? value + 1 : 1);
          case 1:
            return value is int && value.isEven
                ? TransactionOutcome.abort
                : TransactionSuccess(rng.nextInt(50));
          case 2:
            if (runs == 2) {
              throw StateError('handler failure');
            }
            return TransactionSuccess(7);
          case 3:
            // Writes to its own path on its second run.
            if (runs == 2) {
              _set(path, 60 + rng.nextInt(10));
            }
            return TransactionSuccess(runs);
          case 4:
            return TransactionSuccess(<String, Object?>{'n': runs});
          default:
            if (runs == 3) {
              trace.add('  purge from handler');
              h.repo.purgeOutstandingWrites();
            }
            return TransactionSuccess(runs * 10);
        }
      },
      applyLocally: applyLocally,
      onComplete: (_, _, _) => _done(id),
    );
  }

  void _set(String path, int value) {
    final String id = _start('set $path=$value');
    trace.add(id);
    h.repo.setValue(
      Path(path),
      nodeFromJson(value),
      onComplete: (_) => _done(id),
    );
  }

  void _update() {
    final bool atRoot = rng.nextBool();
    final int value = rng.nextInt(100);
    final Map<String, Object?> data = atRoot
        ? <String, Object?>{'a/y': value, 'b': value}
        : <String, Object?>{'x': value};
    final String path = atRoot ? '' : 'a';
    final String id = _start('update /$path ${jsonEncode(data)}');
    trace.add(id);
    h.repo.updateChildren(
      Path(path),
      CompoundWrite.fromValue(data),
      data,
      onComplete: (_) => _done(id),
    );
  }

  void _goOffline({required bool interrupt}) {
    if (!online) {
      return;
    }
    trace.add(interrupt ? 'goOffline' : 'connection drops');
    online = false;
    if (interrupt) {
      interrupted = true;
      h.repo.interrupt();
    }
    server.disconnect();
  }

  void _goOnline() {
    if (online) {
      return;
    }
    trace.add('reconnect');
    online = true;
    if (interrupted) {
      interrupted = false;
      h.repo.resume();
    }
    server.connect();
    // The connection replays the listens; the server answers them with its data.
    for (final String path in _listened) {
      server.deliverDataUpdate(path, server.dataAt(path));
    }
  }

  /// Answers the oldest pending put or merge, as the server answers in order.
  void _answer(String status) {
    if (!online) {
      return;
    }
    final List<ServerCall> pending = server.pendingWrites
        .where((ServerCall c) => c.action == 'put' || c.action == 'merge')
        .toList();
    if (pending.isEmpty) {
      return;
    }
    final ServerCall call = pending.first;
    final String path = call.path!;
    if (status == 'datastale' && call.hash == null) {
      status = 'ok';
    }
    if (status == 'ok' &&
        call.hash != null &&
        nodeFromJson(server.dataAt(path)).hash() != call.hash) {
      status = 'datastale';
    }
    trace.add('answer ${call.action} $path ${jsonEncode(call.data)}: $status');
    if (status == 'ok') {
      server.deliverDataUpdate(
        path,
        call.data,
        isMerge: call.action == 'merge',
      );
    }
    server.respond(
      call,
      status: status,
      data: status == 'ok' ? null : 'refused',
    );
  }

  void _settle() {
    trace.add('-- settle');
    _goOnline();
    flush();
    for (int i = 0; i < 1000; i++) {
      final bool pending = server.pendingWrites.any(
        (ServerCall c) => c.action == 'put' || c.action == 'merge',
      );
      if (!pending) {
        return;
      }
      _answer('ok');
      flush();
    }
    throw TestFailure('did not settle in 1000 answers');
  }

  void _check() {
    final Map<String, int> wrong = <String, int>{
      for (final MapEntry<String, int> e in completions.entries)
        if (e.value != 1) e.key: e.value,
    };
    expect(wrong, isEmpty, reason: 'completions run other than once');
    expect(h.repo.debugPendingWriteIds, isEmpty, reason: 'pending writes');
    expect(h.repo.debugTransactionQueueEmpty, isTrue, reason: 'queued');
    for (final String path in _listened) {
      expect(
        lastSeen[path],
        jsonEncode(server.dataAt(path)),
        reason: 'what the listener at $path last saw',
      );
    }
    for (final CallbackEventRegistration registration in listeners.values) {
      h.repo.removeEventCallback(registration);
    }
    flush();
    expect(h.repo.debugServerSyncTreeEmpty, isTrue, reason: 'registrations');
    expect(server.activeListens, isEmpty, reason: 'server listens');
  }
}

void main() {
  const List<int> fixedSeeds = <int>[1, 2, 3, 5, 8, 13, 21, 34, 55, 89];
  final Random derive = Random(20261122);
  final List<int> derivedSeeds = <int>[
    for (int i = 0; i < 300; i++) derive.nextInt(1 << 31),
  ];

  test('fixed seeds', () {
    fixedSeeds.forEach(_runSeed);
  });

  test('derived seeds', () {
    derivedSeeds.forEach(_runSeed);
  });

  test('a sent transaction marked for abort by purgeOutstandingWrites commits '
      'when the server answers ok', () async {
    final RepoHarness h = RepoHarness();
    h.listen('S', 'c');
    h.answer('c', 0);
    await settle();
    h.log.clear();
    h.transaction('c', (Object? v) => TransactionSuccess((v! as int) + 1));
    await settle();
    final ServerCall put = h.server.callsOf('put').single;
    // The server stores the value, pushes it and accepts the put; the connection has the answer
    // but has not delivered it when the purge runs.
    h.server
      ..deliverDataUpdate('c', 1)
      ..queueResponse(put);
    h.repo.purgeOutstandingWrites();
    await settle();
    expect(h.log, <String>['H(0)', 'S:V(1)', 'T:committed(1)']);
    expect(h.repo.debugPendingWriteIds, isEmpty);
    expect(h.repo.debugTransactionQueueEmpty, isTrue);
  });
}
