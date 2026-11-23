// A random check of the local view (Repo, sync tree, write tree, views) over sequences of
// client writes, server answers and other clients' writes, with a server model playing the
// server on a FakeServerActions. Two properties:
//
// A. Whenever nothing is pending (no unanswered write, every listen answered), each value
//    listener's last value equals its view's server cache, filtered by its query. This needs no
//    model: it compares the client with itself.
// B. Once everything is answered, every listener, a new listener per query and get() equal the
//    model's data.
//
// The model follows what was measured on the emulator (docs/database_decisions.md section 25):
// writes apply in the order sent; a priority written on a node that does not exist refuses the
// whole write; one update applies all its children at once, so its node keeps its priority unless
// the update writes `.priority`; a node with no value and no children has no priority, except
// that the emulator keeps it when the node is emptied by a write below it (not verified on
// production), so B accepts either answer. The server sends a write to the listens it holds,
// from reading a listen to reading its unlisten: as written to a plain listen at or above it,
// as whole data to one below it. To the limit query it sends the frames measured for a
// key-ordered limitToFirst query (rtdb/from_helper/reports/limit_query_frames.md): a set at or
// above its path puts the whole window; an update at or above it merges its relative paths
// when the window keeps its children, the entering child whole and the removed one null when it
// changes, and nothing when no window child is touched (its own priority included); a write
// below it goes as written while its child stays in the window, nothing for a child outside, the
// entering child alone at its path when it pushes another out, and a merge of entering and
// removed children otherwise. Not measured, and kept as the model's guess: the order by
// priority of this query, an update that changes one window child while another enters or that
// pushes a child out (the whole window is put), an update key at or above the query path, and
// a window merge whose entering child sorts before a child that stays (measured only after it).
//
// The unchanged code fails some seeds, for behaviours that are documented and kept. The test
// fails when a seed outside [_knownFailures] fails, or a listed seed passes.
//
// A wider range, by hand on the VM (the list covers [_defaultSeeds] only, so every failing seed
// outside it is reported, with its sequence):
//   dart run -DFUZZ_SEEDS=0-100000 test/core/sync_tree_property_test.dart
import 'dart:convert';
import 'dart:math' as math;

import 'package:firebase_database_dart/src/core/callback_event_registration.dart';
import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/repo.dart';
import 'package:firebase_database_dart/src/core/repo_info.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/priority_index.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/sync_tree.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';
import 'package:firebase_database_dart/src/core/view/event_dispatcher.dart';
import 'package:firebase_database_dart/src/core/view/filter/node_filter.dart';
import 'package:firebase_database_dart/src/core/view/query_params.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:firebase_database_dart/src/core/view/view.dart';
import 'package:firebase_database_dart/src/testing/fake_server_actions.dart';
import 'package:test/test.dart';

const (int, int) _defaultSeeds = (0, 10000);

/// The failing seeds of [_defaultSeeds] by cause: a row of the table "Behaviours shared with the
/// JS SDK that are kept" (docs/database_decisions.md section 25) or, where no row fits, a
/// listener that differs from its own server cache with nothing pending. Each group starts with
/// its shortest sequence, found by shrinking one of its seeds; data as in [_initial].
const Map<String, List<int>> _knownFailures = <String, List<int>>{
  // listen /b; update /b {y: 1, x: null}. The listener shows {y: 1} without the priority 3 the
  // server keeps (seed 9709). The other seeds lose a priority the same way, in the listener or in
  // the client's server cache (then property A fails first): an update that writes the priority
  // itself, two writes of this client refilled by another client's (4302), and a refused write
  // whose revert refills the node (6434).
  // dart format off
  'row 2: an emptied and refilled node loses its priority': <int>[
    867, 1177, 1219, 2311, 2372, 2963, 3038, 3054, 3223, 3579, 3977, 4302, 4451, 4933, 5098,
    5358, 5915, 6026, 6108, 6169, 6171, 6268, 6434, 6598, 6626, 7138, 7192, 7391, 7564, 7642,
    7873, 8224, 8911, 9550, 9709,
  ],
  // listen /; set /b/x null; set /b/x 1. Settled, the listener shows b with its priority 3 and
  // the client's server cache shows b without it (seed 9964). The server emptied b in between;
  // the emulator would keep the priority (row 4), so the listener agrees with the emulator and
  // the cache with a server that drops it.
  'listener differs from own server cache, nothing pending': <int>[
    1984, 2717, 3289, 6012, 9798, 9964,
  ],
  // dart format on
};

/// The queries of the listeners: three depths, a sibling, and a limit query by priority.
final List<QuerySpec> _queries = <QuerySpec>[
  QuerySpec.defaultAt(Path('')),
  QuerySpec.defaultAt(Path('a')),
  QuerySpec.defaultAt(Path('a/x')),
  QuerySpec.defaultAt(Path('b')),
  QuerySpec(
    Path('a'),
    QueryParams.defaultParams.orderBy(priorityIndex).limitToFirst(2),
  ),
];

/// The server's data before the client starts.
const Map<String, Object?> _initial = <String, Object?>{
  'a': <String, Object?>{
    'x': 1,
    'y': <String, Object?>{'u': 2, '.priority': 2},
    '.priority': 1,
  },
  'b': <String, Object?>{
    'x': <String, Object?>{'u': 1, '.priority': 2},
    '.priority': 3,
  },
};

sealed class _Op {
  const _Op();
}

/// A set (`.priority` last: a priority write) or an update, by this client or another one.
final class _Write extends _Op {
  const _Write(this.path, this.data, {required this.ours, this.merge = false});
  final String path;
  final Object? data;
  final bool ours;
  final bool merge;

  @override
  String toString() =>
      '${ours ? '' : 'other '}${merge ? 'update' : 'set'} /$path '
      '${jsonEncode(data)}';
}

final class _Listen extends _Op {
  const _Listen(this.query);
  final int query;

  @override
  String toString() => 'listen ${_queries[query]}';
}

/// The server handles the client's next message; a write is refused when [refuse] (a rule).
final class _Serve extends _Op {
  const _Serve({required this.refuse});
  final bool refuse;

  @override
  String toString() => refuse ? 'serve (refuse a write)' : 'serve';
}

// ---------------------------------------------------------------------------------------------
// The generator. Depth 1 (a, b) only ever holds objects, and leaves carry no priority, so no
// write meets the unmeasured case of a priority on a leaf that turns into children.

const List<List<String>> _keysAt = <List<String>>[
  <String>['a', 'b'],
  <String>['x', 'y', 'z'],
  <String>['u', 'v'],
];

Object? _priority(math.Random r) => r.nextInt(4) == 0 ? null : 1 + r.nextInt(3);

/// A value for a node at [depth] (0 is the root).
Object? _value(math.Random r, int depth, {bool nullable = true}) {
  if (nullable && r.nextInt(4) == 0) {
    return null;
  }
  if (depth == 3 || depth == 2 && r.nextBool()) {
    return 1 + r.nextInt(3);
  }
  final Map<String, Object?> m = <String, Object?>{};
  final List<String> keys = _keysAt[depth];
  for (int i = 1 + r.nextInt(2); i > 0; i--) {
    m[keys[r.nextInt(keys.length)]] = _value(r, depth + 1, nullable: false);
  }
  if (depth > 0 && r.nextBool()) {
    m['.priority'] = 1 + r.nextInt(3);
  }
  return m;
}

int _depth(String path) => Path(path).length;

const List<String> _setPaths = <String>['a', 'b', 'a/x', 'a/y', 'b/x', 'a/x/u'];
const Map<String, List<String>> _updateKeys = <String, List<String>>{
  '': <String>['a', 'b', 'a/x', 'b/y', 'a/.priority', 'b/.priority'],
  'a': <String>['x', 'y', 'z', 'x/u', '.priority'],
  'b': <String>['x', 'y', 'x/v', '.priority'],
  'a/x': <String>['u', 'v'],
};

_Write _write(math.Random r, {required bool ours}) {
  final int c = r.nextInt(10);
  if (c < 2) {
    final String node = r.nextBool() ? 'a' : 'b';
    return _Write('$node/.priority', _priority(r), ours: ours);
  }
  if (c < 6) {
    final String path = r.nextInt(8) == 0
        ? ''
        : _setPaths[r.nextInt(_setPaths.length)];
    return _Write(path, _value(r, _depth(path)), ours: ours);
  }
  final List<String> bases = _updateKeys.keys.toList();
  final String base = bases[r.nextInt(bases.length)];
  final List<String> keys = _updateKeys[base]!;
  final Map<String, Object?> m = <String, Object?>{};
  for (int i = 1 + r.nextInt(3); i > 0; i--) {
    final String k = keys[r.nextInt(keys.length)];
    // The API refuses an update holding a path and one of its descendants.
    if (m.keys.any(
      (String o) => Path(o).contains(Path(k)) || Path(k).contains(Path(o)),
    )) {
      continue;
    }
    m[k] = k.endsWith('.priority')
        ? _priority(r)
        : _value(r, _depth(base) + _depth(k));
  }
  return _Write(base, m, ours: ours, merge: true);
}

List<_Op> _generate(int seed) {
  final math.Random r = math.Random(seed);
  final List<int> unheard = List<int>.generate(_queries.length, (int i) => i)
    ..shuffle(r);
  return <_Op>[
    for (int i = 8 + r.nextInt(16); i > 0; i--)
      switch (r.nextInt(100)) {
        < 15 when unheard.isNotEmpty => _Listen(unheard.removeLast()),
        < 50 => _write(r, ours: true),
        < 60 => _write(r, ours: false),
        _ => _Serve(refuse: r.nextInt(5) == 0),
      },
  ];
}

// ---------------------------------------------------------------------------------------------
// The server model.

bool _covers(String outer, String inner) =>
    outer == '/' || inner == outer || inner.startsWith('$outer/');

String _wire(String path) => '/$path'.replaceAll('//', '/');

Node _shown(QuerySpec q, Node data) => q.loadsAllData
    ? data
    : nodeFilterFor(q.params).updateFullNode(
        ChildrenNode.empty.withIndex(q.index),
        data.withIndex(q.index),
        null,
      );

/// The children of [n] in export form, by key.
Map<String, Object?> _children(Node n) => <String, Object?>{
  for (final MapEntry<String, Object?> e
      in ((n.toJson(exportFormat: true) as Map<String, Object?>?) ??
              <String, Object?>{})
          .entries)
    if (e.key != '.priority') e.key: e.value,
};

String _json(Node? n) =>
    n == null ? 'nothing' : jsonEncode(n.toJson(exportFormat: true));

final class _Server {
  _Server(this.fake);
  final FakeServerActions fake;
  Node data = nodeFromJson(_initial);

  /// The listens the server holds (it has handled the listen and not the unlisten).
  final List<ServerCall> listens = <ServerCall>[];

  /// How many of the client's messages the server has handled.
  int handled = 0;

  /// Applies [w]; false when the server refuses it.
  bool apply(_Write w) {
    final Node before = data;
    final Path at = Path(w.path);
    final Map<String, Object?> entries = w.merge
        ? (w.data! as Map<String, Object?>)
        : <String, Object?>{'': w.data};
    for (final String k in entries.keys) {
      final Path p = at.childPath(Path(k));
      if ((p.back?.isPriorityKey ?? false) &&
          data.getChild(p.parent!).isEmpty) {
        return false;
      }
    }
    // New children first, then removals, then priorities: the update's node is empty
    // afterwards only when it is empty once the whole update is applied.
    int rank(MapEntry<String, Object?> e) => e.key.endsWith('.priority')
        ? 2
        : (nodeFromJson(e.value).isEmpty ? 1 : 0);
    final List<MapEntry<String, Object?>> ordered = entries.entries.toList()
      ..sort((a, b) => rank(a) - rank(b));
    for (final MapEntry<String, Object?> e in ordered) {
      final Path p = at.childPath(Path(e.key));
      final Node n = nodeFromJson(e.value);
      data = data.updateChild(p, n);
      _emulate(p, n);
    }
    _publish(w, before);
    return true;
  }

  /// [data] as the emulator holds it: a node emptied by a write below it keeps its priority,
  /// and shows it again once a later write below it refills it. The answer of a production
  /// server is not known, so a listener may show either.
  Node emulator = nodeFromJson(_initial);

  /// The kept priorities of the empty nodes of [emulator], by path.
  final Map<String, Node> _kept = <String, Node>{};

  void _emulate(Path p, Node n) {
    // A write at or above an empty node replaces it, priority and all.
    _kept.removeWhere((String k, Node _) => p.contains(Path(k)));
    final Node before = emulator;
    emulator = emulator.updateChild(p, n);
    for (Path? up = p.parent; up != null; up = up.parent) {
      final Node priority = before.getChild(up).priority;
      if (!priority.isEmpty && emulator.getChild(up).isEmpty) {
        _kept['$up'] = priority;
      }
    }
    for (final String k in _kept.keys.toList()) {
      final Node node = emulator.getChild(Path(k));
      if (!node.isEmpty) {
        emulator = emulator.updateChild(
          Path(k),
          node.updatePriority(_kept.remove(k)!),
        );
      }
    }
  }

  /// Sends [w] to the listens it touches; [before] is the data before it. A plain listen at or
  /// above the write gets it as written, one below it its whole data.
  void _publish(_Write w, Node before) {
    final String wp = _wire(w.path);
    for (final ServerCall l in listens) {
      final String lp = l.spec!.path;
      if (l.tag != null) {
        if (_covers(lp, wp) || _covers(wp, lp)) {
          _publishTagged(l, w, before);
        }
      } else if (_covers(lp, wp)) {
        fake.deliverDataUpdate(wp, w.data, isMerge: w.merge);
      } else if (_covers(wp, lp)) {
        fake.deliverDataUpdate(
          lp,
          data.getChild(Path(lp)).toJson(exportFormat: true),
        );
      }
    }
  }

  /// Sends [w] to the limit query's listen [l] in the frames the emulator sent for a key-ordered
  /// `limitToFirst(2)` query (rtdb/from_helper/reports/limit_query_frames.md, cases A1 to C5).
  /// Shapes it did not measure keep the whole window as a put at the query path.
  void _publishTagged(ServerCall l, _Write w, Node before) {
    final QuerySpec q = _queries.firstWhere(
      (QuerySpec q) => q.toListenSpec() == l.spec,
    );
    final String lp = l.spec!.path;
    void send(String path, Object? json, {bool merge = false}) =>
        fake.deliverDataUpdate(path, json, isMerge: merge, tag: l.tag);
    final Node window = _shown(q, data.getChild(q.path));
    void sendWindow() => send(lp, window.toJson(exportFormat: true));
    final Map<String, Object?> was = _children(
      _shown(q, before.getChild(q.path)),
    );
    final Map<String, Object?> now = _children(window);
    final List<String> left = <String>[
      for (final String k in was.keys)
        if (!now.containsKey(k)) k,
    ];
    final List<String> entered = <String>[
      for (final String k in now.keys)
        if (!was.containsKey(k)) k,
    ];
    // A child that left the window but still exists was pushed out by one that entered.
    bool removed(String k) => data.getChild(q.path.childPath(Path(k))).isEmpty;
    final Map<String, Object?> diff = <String, Object?>{
      for (final String k in entered) k: now[k],
      for (final String k in left) k: null,
    };
    final Path at = Path(w.path);
    if (at.length > q.path.length) {
      final String child = Path.relative(q.path, at).front!.name;
      if (left.isEmpty && entered.isEmpty) {
        // In the window: as written (C1, C5); outside it: nothing (C3).
        if (was.containsKey(child)) {
          send(_wire(w.path), w.data, merge: w.merge);
        }
      } else if (entered.length == 1 &&
          entered.single == child &&
          !left.any(removed)) {
        // The entering child alone, whole; the client drops what it pushes out (C4).
        send('$lp/$child', now[child]);
      } else if (entered.isEmpty) {
        if (was.containsKey(child)) {
          send(_wire(w.path), w.data, merge: w.merge);
        }
      } else {
        send(lp, diff, merge: true); // C2
      }
      return;
    }
    if (!w.merge) {
      sendWindow(); // A1, A2, B1
      return;
    }
    // An update at or above the query path, by its paths below the query path.
    final Map<String, Object?> below = <String, Object?>{};
    for (final MapEntry<String, Object?> e
        in (w.data! as Map<String, Object?>).entries) {
      final Path full = at.childPath(Path(e.key));
      if (full.contains(q.path)) {
        sendWindow(); // replaces the query node: not measured
        return;
      }
      if (q.path.contains(full)) {
        final Path relative = Path.relative(q.path, full);
        // The query node's own priority moves no child (A6, B4).
        if (!relative.front!.isPriorityKey) {
          below[relative.segments.map((k) => k.name).join('/')] = e.value;
        }
      }
    }
    final Set<String> touched = <String>{
      for (final String k in below.keys) k.split('/').first,
    };
    if (!touched.any((String k) => was.containsKey(k) || now.containsKey(k))) {
      return; // A5, A6, B4
    }
    if (left.isEmpty && entered.isEmpty) {
      send(lp, <String, Object?>{
        for (final MapEntry<String, Object?> e in below.entries)
          if (now.containsKey(e.key.split('/').first)) e.key: e.value,
      }, merge: true); // A3, B3
    } else if (left.every(removed) &&
        !touched.any((String k) => was.containsKey(k) && now.containsKey(k))) {
      send(lp, diff, merge: true); // A4, B2
    } else {
      sendWindow(); // a child pushed out, or one changed while another enters: not measured
    }
  }

  /// Handles the client's next listen, unlisten, get or write ([refuse]: refuses a write).
  void serve({required bool refuse}) {
    while (handled < fake.calls.length) {
      final ServerCall c = fake.calls[handled++];
      switch (c.action) {
        case 'put' || 'merge':
          final _Write w = _Write(
            c.path!.substring(1),
            c.data,
            ours: true,
            merge: c.action == 'merge',
          );
          if (refuse) {
            fake.respond(c, status: 'permission_denied');
          } else {
            fake.respond(c, status: apply(w) ? statusOk : 'invalid_parameters');
          }
          return;
        case 'listen':
          final QuerySpec q = _queries.firstWhere(
            (QuerySpec q) => q.toListenSpec() == c.spec,
          );
          final Node at = data.getChild(Path(c.spec!.path));
          fake.deliverDataUpdate(
            c.spec!.path,
            _shown(q, at).toJson(exportFormat: true),
            tag: c.tag,
          );
          listens.add(c);
          fake.respond(c);
          return;
        case 'unlisten':
          listens.removeWhere(
            (ServerCall l) => l.spec == c.spec && l.tag == c.tag,
          );
          return;
        case 'get':
          fake.respond(
            c,
            data: data.getChild(Path(c.spec!.path)).toJson(exportFormat: true),
          );
          return;
      }
    }
  }

  void drain() {
    while (handled < fake.calls.length) {
      serve(refuse: false);
    }
  }
}

// ---------------------------------------------------------------------------------------------
// The run.

final class _Listener {
  _Listener(this.query);
  final QuerySpec query;
  Node? value;
}

/// Plays [ops]; returns the first property that fails, or null.
Future<String?> _check(List<_Op> ops) async {
  late final FakeServerActions fake;
  final Repo repo = Repo(
    repoInfo: const RepoInfo(
      host: 'test.firebaseio.com',
      namespace: 'test',
      secure: true,
    ),
    connectionFactory: (delegate, logger) => fake = FakeServerActions(delegate),
    clock: () => DateTime.utc(2026),
    // Events are delivered inside the call that raised them, so no step needs a microtask.
    dispatcher: EventDispatcher(schedule: (void Function() f) => f()),
  );
  fake.connect();
  final _Server server = _Server(fake);
  final List<_Listener> listeners = <_Listener>[];

  _Listener listen(QuerySpec q) {
    final _Listener l = _Listener(q);
    listeners.add(l);
    repo.addEventCallback(
      CallbackEventRegistration(
        q,
        const <EventType>{EventType.value},
        onEvent: (DataEvent e) => l.value = e.snapshot,
        // The model answers every listen.
        onCancel: (DatabaseError e) => throw StateError('$q cancelled: $e'),
      ),
    );
    return l;
  }

  String? ownCache() {
    final bool pending = fake.calls.any(
      (ServerCall c) =>
          const <String>{'put', 'merge', 'listen'}.contains(c.action) &&
          !c.answered,
    );
    if (pending) {
      return null;
    }
    final SyncTree tree = repo.serverSyncTree as SyncTree;
    for (final _Listener l in listeners) {
      if (l.value == null) {
        continue;
      }
      final View view = tree.syncPointTree
          .get(l.query.path)!
          .viewForQuery(l.query)!;
      // A limit query's view can hold more than its window (the data of a listen above it),
      // and a limit query does not show the priority of its node.
      final Node cache = _shown(l.query, view.serverCache);
      if (cache.hash() != l.value!.hash()) {
        return 'A: listener ${l.query} shows ${_json(l.value)}, '
            'its server cache ${_json(cache)}';
      }
    }
    return null;
  }

  String? matchesServer(String who, QuerySpec q, Node? got) {
    final Node want = _shown(q, server.data.getChild(q.path));
    final Node kept = _shown(q, server.emulator.getChild(q.path));
    if (got != null &&
        (got.hash() == want.hash() || got.hash() == kept.hash())) {
      return null;
    }
    return 'B: $who $q shows ${_json(got)}, server ${_json(want)}'
        '${kept.hash() == want.hash() ? '' : ' (emulator ${_json(kept)})'}';
  }

  for (int i = 0; i < ops.length; i++) {
    switch (ops[i]) {
      case _Listen(:final int query):
        listen(_queries[query]);
      case _Serve(:final bool refuse):
        server.serve(refuse: refuse);
      case final _Write w when !w.ours:
        server.apply(w);
      case final _Write w when w.merge:
        final Map<String, Object?> m = w.data! as Map<String, Object?>;
        repo.updateChildren(Path(w.path), CompoundWrite.fromValue(m), m);
      case final _Write w:
        repo.setValue(Path(w.path), nodeFromJson(w.data));
    }
    final String? failure = ownCache();
    if (failure != null) {
      return '$failure (after op $i)';
    }
  }

  server.drain();
  final String? settled = ownCache();
  if (settled != null) {
    return '$settled (settled)';
  }
  for (final _Listener l in listeners) {
    final String? failure = matchesServer('listener', l.query, l.value);
    if (failure != null) {
      return failure;
    }
  }
  final List<_Listener> fresh = <_Listener>[
    for (final QuerySpec q in _queries) listen(q),
  ];
  server.drain();
  for (final _Listener l in fresh) {
    final String? failure = matchesServer('new listener', l.query, l.value);
    if (failure != null) {
      return failure;
    }
  }
  for (final QuerySpec q in _queries.where((QuerySpec q) => q.loadsAllData)) {
    final Future<Node> got = repo.getValue(q);
    server.drain();
    final String? failure = matchesServer('get()', q, await got);
    if (failure != null) {
      return failure;
    }
  }
  return ownCache();
}

/// The `FUZZ_SEEDS` define, `<first>-<end>` (end excluded), or empty.
const String _range = String.fromEnvironment('FUZZ_SEEDS');

(int, int) _seeds() {
  if (_range.isEmpty) {
    return _defaultSeeds;
  }
  final List<int?> ends = _range.split('-').map(int.tryParse).toList();
  if (ends.length != 2 || ends.contains(null)) {
    throw ArgumentError.value(
      _range,
      'FUZZ_SEEDS',
      'Use <first>-<end>, as 0-100000',
    );
  }
  return (ends[0]!, ends[1]!);
}

void main() {
  final (int first, int end) = _seeds();
  test(
    'random sequences: listeners match their server cache and the server '
    '(seeds $first to ${end - 1})',
    () async {
      final Map<int, String> failing = <int, String>{};
      for (int seed = first; seed < end; seed++) {
        final List<_Op> ops = _generate(seed);
        final String? failure = await _check(ops);
        if (failure != null) {
          failing[seed] = '$failure\n    ${ops.join('; ')}';
        }
      }
      final Set<int> known = <int>{
        for (final List<int> seeds in _knownFailures.values)
          ...seeds.where((int s) => s >= first && s < end),
      };
      final List<String> unknown = <String>[
        for (final MapEntry<int, String> e in failing.entries)
          if (!known.contains(e.key)) 'seed ${e.key}: ${e.value}',
      ];
      expect(
        unknown,
        isEmpty,
        reason: '${unknown.length} seeds fail for an unlisted cause',
      );
      final List<int> passing = known
          .where((int s) => !failing.containsKey(s))
          .toList();
      expect(
        passing,
        isEmpty,
        reason: 'these seeds pass now: remove them from _knownFailures',
      );
    },
    // A range given by hand can run for minutes.
    timeout: _range.isEmpty ? null : Timeout.none,
  );
}
