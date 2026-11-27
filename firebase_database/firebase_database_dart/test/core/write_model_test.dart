// A model-based test of plain writes: random sequences of set, update and remove at paths of
// depth 1 to 3 that turn maps into leaves and back, writes of other clients (overwrite and merge,
// maps and leaves, at and above the listened paths, also while offline), acks and refusals in
// the order the server answers, dropped connections and goOffline/goOnline, run against
// FakeServerActions on a fake clock. One or two listeners at different depths, one of them
// sometimes limitToFirst. After each sequence settles: every completion ran once, no write is
// pending, and what each listener last saw equals a fresh Repo's view of the server's data.
// No dart:io, so it runs in a browser too.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/repo.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';
import 'package:firebase_database_dart/src/core/view/query_params.dart';
import 'package:firebase_database_dart/src/testing/fake_server_actions.dart';
import 'package:test/test.dart';

import '../api/support/fake_time.dart';
import 'repo_harness.dart' hide FakeTime;

const int _steps = 30;

/// The paths written, depth 1 to 3.
const List<String> _paths = <String>['a', 'a/b', 'a/b/c', 'a/d', 'x'];

/// The paths other clients write, the root included.
const List<String> _serverPaths = <String>['', 'a', 'a/b', 'a/b/c', 'x'];

final QueryParams _first1 = QueryParams.defaultParams.limitToFirst(1);

/// The listener setups: (path, params) per listener.
final List<List<(String, QueryParams)>> _setups = <List<(String, QueryParams)>>[
  <(String, QueryParams)>[('a', QueryParams.defaultParams)],
  <(String, QueryParams)>[
    ('a', QueryParams.defaultParams),
    ('a/b', QueryParams.defaultParams),
  ],
  <(String, QueryParams)>[('a/b', QueryParams.defaultParams), ('a', _first1)],
  <(String, QueryParams)>[('', _first1), ('a/b', QueryParams.defaultParams)],
  <(String, QueryParams)>[('a', QueryParams.defaultParams), ('a', _first1)],
];

/// One run of the model for [seed]; fails with the seed and the steps.
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
  late final List<(String, QueryParams)> setup;
  final Map<int, String> lastSeen = <int, String>{};
  final Map<String, int> completions = <String, int>{};
  int _ops = 0;
  bool online = true;
  bool interrupted = false;

  FakeServerActions get server => h.server;

  void flush() => time.elapse(Duration.zero);

  void run() {
    h = RepoHarness();
    server.taggedListensGetWholeData = true;
    setup = _setups[rng.nextInt(_setups.length)];
    server.writeByOtherClient('', <String, Object?>{
      'a': <String, Object?>{
        'b': <String, Object?>{'c': 1},
        'd': 2,
      },
      'x': 3,
    });
    trace.add('listeners $setup, server ${jsonEncode(server.data)}');
    for (int i = 0; i < setup.length; i++) {
      final (String path, QueryParams params) = setup[i];
      h.listen(
        'L$i',
        path,
        params: params,
        after: (DataEvent e) {
          lastSeen[i] = json(e.snapshot);
          trace.add('  L$i sees ${lastSeen[i]}');
        },
      );
      flush();
      _answerListens();
    }
    flush();
    for (int i = 0; i < _steps; i++) {
      _step();
      flush();
    }
    _settle();
    _check();
  }

  /// Answers every listen with the server's data at its path, as the server does when a listen
  /// is sent or replayed.
  void _answerListens() {
    for (final ServerCall call in server.activeListens.values.toList()) {
      final String path = call.spec!.path;
      server.deliverDataUpdate(path, server.dataAt(path), tag: call.tag);
      if (!call.answered) {
        server.respond(call);
      }
    }
  }

  /// A leaf, a null (remove) or a map of depth up to [depth].
  Object? _value(int depth) {
    final int pick = rng.nextInt(10);
    if (pick < 4 || depth == 0) {
      return pick == 0 ? null : rng.nextInt(50);
    }
    return <String, Object?>{
      for (final String key in const <String>['b', 'c', 'd'])
        if (rng.nextBool()) key: _value(depth - 1),
    };
  }

  int _depthLeft(String path) =>
      3 - (path.isEmpty ? 0 : path.split('/').length);

  void _step() {
    final int pick = rng.nextInt(100);
    if (pick < 22) {
      _set();
    } else if (pick < 34) {
      _update();
    } else if (pick < 40) {
      _remove();
    } else if (pick < 54) {
      _otherClient();
    } else if (pick < 60) {
      _goOffline(interrupt: rng.nextBool());
    } else if (pick < 67) {
      _goOnline();
    } else if (pick < 92) {
      _answer('ok');
    } else {
      _answer('permission_denied');
    }
  }

  String _start(String kind) {
    final String id = '$kind#${_ops++}';
    completions[id] = 0;
    trace.add(id);
    return id;
  }

  void _done(String id) => completions[id] = completions[id]! + 1;

  void _set() {
    final String path = _paths[rng.nextInt(_paths.length)];
    final Object? value = _value(_depthLeft(path));
    final String id = _start('set $path=${jsonEncode(value)}');
    h.repo.setValue(
      Path(path),
      nodeFromJson(value),
      onComplete: (_) => _done(id),
    );
  }

  void _remove() {
    final String path = _paths[rng.nextInt(_paths.length)];
    final String id = _start('remove $path');
    h.repo.setValue(
      Path(path),
      nodeFromJson(null),
      onComplete: (_) => _done(id),
    );
  }

  /// An update at the root, `a` or `a/b` with one or two children, some of them deep.
  Map<String, Object?> _children(String path) {
    final List<String> keys = switch (path) {
      '' => const <String>['a', 'a/b', 'a/d', 'x'],
      'a' => const <String>['b', 'b/c', 'd'],
      _ => const <String>['c', 'd'],
    };
    final Map<String, Object?> data = <String, Object?>{};
    for (int i = 0; i < 1 + rng.nextInt(2); i++) {
      final String key = keys[rng.nextInt(keys.length)];
      if (data.keys.any((String k) => k.startsWith(key) || key.startsWith(k))) {
        continue;
      }
      final String full = path.isEmpty ? key : '$path/$key';
      data[key] = _value(_depthLeft(full));
    }
    return data;
  }

  void _update() {
    final String path = const <String>['', 'a', 'a/b'][rng.nextInt(3)];
    final Map<String, Object?> data = _children(path);
    final String id = _start('update /$path ${jsonEncode(data)}');
    h.repo.updateChildren(
      Path(path),
      CompoundWrite.fromValue(data),
      data,
      onComplete: (_) => _done(id),
    );
  }

  void _otherClient() {
    final String path = _serverPaths[rng.nextInt(_serverPaths.length)];
    if (rng.nextBool() && _depthLeft(path) > 0) {
      final Map<String, Object?> data = _children(
        path == 'a/b/c' ? 'a/b' : path,
      );
      final String at = path == 'a/b/c' ? 'a/b' : path;
      if (data.isEmpty) {
        return;
      }
      trace.add('other client merges /$at ${jsonEncode(data)}');
      server.writeByOtherClient(at, data, isMerge: true);
    } else {
      final Object? value = _value(_depthLeft(path));
      trace.add('other client sets /$path=${jsonEncode(value)}');
      server.writeByOtherClient(path, value);
    }
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
    _answerListens();
  }

  /// Answers the oldest pending put or merge: the server answers in order.
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
    trace.add(
      'answer ${call.action} ${call.path} ${jsonEncode(call.data)}: $status',
    );
    if (status == 'ok') {
      server.ackWrite(call);
    } else {
      server.respond(call, status: status, data: 'refused');
    }
  }

  void _settle() {
    trace.add('-- settle');
    _goOnline();
    flush();
    for (int i = 0; i < 1000; i++) {
      if (!server.pendingWrites.any(
        (ServerCall c) => c.action == 'put' || c.action == 'merge',
      )) {
        return;
      }
      _answer('ok');
      flush();
    }
    throw TestFailure('did not settle in 1000 answers');
  }

  /// What a fresh Repo shows for listener [i] over the server's data.
  String _rebuild(int i) {
    final (String path, QueryParams params) = setup[i];
    final RepoHarness fresh = RepoHarness();
    fresh.server.writeByOtherClient('', server.data);
    String? seen;
    fresh.listen(
      'R',
      path,
      params: params,
      after: (DataEvent e) => seen = json(e.snapshot),
    );
    flush();
    for (final ServerCall call in fresh.server.activeListens.values) {
      fresh.server
        ..deliverDataUpdate(
          call.spec!.path,
          fresh.server.dataAt(call.spec!.path),
          tag: call.tag,
        )
        ..respond(call);
    }
    flush();
    return seen ?? 'no event';
  }

  void _check() {
    final Map<String, int> wrong = <String, int>{
      for (final MapEntry<String, int> e in completions.entries)
        if (e.value != 1) e.key: e.value,
    };
    expect(wrong, isEmpty, reason: 'completions run other than once');
    expect(h.repo.debugPendingWriteIds, isEmpty, reason: 'pending writes');
    trace.add('server ${jsonEncode(server.data)}');
    for (int i = 0; i < setup.length; i++) {
      expect(lastSeen[i], _rebuild(i), reason: 'what L$i ${setup[i]} last saw');
    }
  }
}

void main() {
  const List<int> fixedSeeds = <int>[1, 2, 3, 5, 8, 13, 21, 34, 55, 89];
  final Random derive = Random(20261123);
  final List<int> derivedSeeds = <int>[
    for (int i = 0; i < 300; i++) derive.nextInt(1 << 31),
  ];

  test('fixed seeds', () {
    fixedSeeds.forEach(_runSeed);
  });

  test('derived seeds', () {
    derivedSeeds.forEach(_runSeed);
  });
}
