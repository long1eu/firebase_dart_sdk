// A random check of the local view (Repo, sync tree, write tree, views) over sequences of
// client writes, server answers and other clients' writes, with a server model playing the
// server on a FakeServerActions. Two properties:
//
// A. Whenever nothing is pending (no unanswered write, every listen answered), each value
//    listener's last value equals its view's server cache, filtered by its query, and a view of
//    a query that loads all data holds the hidden state of its server cache (equal hashes). This
//    needs no model: it compares the client with itself.
// B. Once everything is answered, every listener, a new listener per query and get() equal the
//    model's data; a new listener and get() of a query that loads all data also hash as the
//    model's server does.
//
// The model is the shared server model of lib/src/testing/json_server_model.dart (a plain JSON
// tree, no client node code), which FakeServerActions plays too. Measured on production
// (rtdb/from_boss/prodkit_production_run3_2026-11-25.txt checks 27 and 38; run 2 check 22;
// prodkit_production_run4_check39_2026-11-25.txt check 39;
// prodkit_production_run8_check39_q11_2026-11-25.txt): writes apply in the order sent; a
// node whose last child is removed by a write below it keeps its priority, and a write at or
// above it drops it; one update is applied in two passes whatever its key order: every value
// entry first, then every priority entry, parents first, each landing only on a node that at
// that moment has a value or holds hidden state (Q1, Q6, Q10, F1 to F9 of run 8; three separate
// writes keep it, Q4); a node holding only emptied children takes a priority (Q2); a priority on
// a node that does not exist refuses the write (check 27); the hash counts kept priorities;
// listen and get answers carry `{".priority": p}` for an emptied node, also inside its parent;
// the compound hash counts a kept priority as a `.priority` leaf (Q5).
//
// Model rules no production frame covers (the model's choice; the client agrees):
// - M1. An update that writes a priority and creates its node in the same message is refused,
//   as a priority on a missing node.
// - M2. `.priority: null` on an emptied node drops it.
// - M3. Whole data pushed to a listen below another client's write carries `{".priority": p}`
//   like a listen answer.
// - M4. The children of a limit window are sent with their `{".priority": p}` descendants; an
//   emptied child is not a window member, and a child leaving the window because it was emptied
//   is sent as null.
// - M5. A write forwarded as written to a listen at or above it carries nothing more.
// - M6. The model never sends a range merge (`rm`) and ignores compound hashes.
// - M7. A leaf with a priority at depth 3 takes `.priority` writes like any node with a value.
// - M8. A value written below a leaf keeps the leaf's priority on the new children (the
//   generator never writes below a leaf).
//
// The server sends a write to the listens it holds, from reading a listen to reading its
// unlisten: as written to a plain listen at or above it, as whole data to one below it. To the
// limit query it sends the frames measured for a key-ordered limitToFirst query
// (rtdb/from_helper/reports/limit_query_frames.md): a set at or above its path puts the whole
// window; an update at or above it merges its relative paths when the window keeps its children,
// the entering child whole and the removed one null when it changes, and nothing when no window
// child is touched (its own priority included); an update that writes below one window child
// next to a key outside the window puts that child whole at its path; a write below it goes as
// written while its child stays in the window, a put of null at the child's path when it empties
// a window child and none enters, nothing for a child outside, the entering child alone at its
// path when it pushes another out, and a merge of the entering children and the leaving ones
// otherwise: null for a removed child, whole for one moved out by its priority. The production
// run of 2026-11-25 (rtdb/from_boss/prodkit_production_run_2026-11-25.txt, checks 28, 29 and 37)
// sent the same frames for the shapes it covered, the tagged frame first; the put of null for an
// emptied child was measured on the emulator only. Not measured, and kept as the model's guess:
// the order by priority of this query beyond a child moved in and out by its priority, an update
// that changes one window child while another enters or that pushes a child out (the whole
// window is put), an update key at or above the query path, and a window merge whose entering
// child sorts before a child that stays (measured only after it).
//
// The test fails when a seed outside [_knownFailures] fails, or a listed seed passes.
//
// A wider range, by hand on the VM (the list covers [_defaultSeeds] only, so every failing seed
// outside it is reported, with its sequence); FUZZ_DUMP writes the failing seeds as JSON lines:
//   dart run --enable-asserts -DFUZZ_SEEDS=0-100000 -DFUZZ_DUMP=/tmp/seeds.jsonl \
//     test/core/sync_tree_property_test.dart
import 'dart:convert';
import 'dart:io';
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
import 'package:firebase_database_dart/src/testing/json_server_model.dart';
import 'package:test/test.dart';

const (int, int) _defaultSeeds = (0, 10000);

/// The failing seeds by cause; [_defaultSeeds] holds none. A new group starts with its shortest
/// sequence, found by shrinking one of its seeds; data as in [_initial].
const Map<String, List<int>> _knownFailures = <String, List<int>>{
  // The groups of rtdb/from_helper/reports/wide_seeds_round3_limit_classification.md (seeds 0 to
  // 299999, limit query /a orderByPriority limitToFirst(2)); in none does hidden state decide the
  // failure, and all fail the same on the trunk.
  // dart format off
  // Group R: the limit view's server cache short after a default listen took over (row 7 of
  // "Behaviours shared with the JS SDK that are kept"); 24768, 165358 and 167845 leave the
  // listener wrong (property B), the others the cache only. Shortest (95040): listen
  // /a:{"l":2,"vf":"l"}; serve; listen /a:default; set /a/x/u 1; serve; other update /a {"x":null}
  'group R: limit view server cache short after a default listen took over': <int>[
    6892, 12944, 15580, 17434, 22925, 24768, 28802, 53038, 60676, 61383, 81628, 95040, 95959,
    108626, 118921, 130468, 131009, 137624, 152480, 153895, 155494, 156387, 165358, 167845,
    174285, 177344, 178722, 210298, 215182, 227643, 250134, 251256, 251431, 252308, 255037,
    255287, 256221, 256506, 288075,
  ],
  // Group S: a server merge refills a full window from the pre-merge complete cache (JS passes
  // the same cache to every child; a trunk matter). Shortest (245589): listen
  // /a:{"l":2,"vf":"l"}; listen /:default; serve; serve (refuse a write); serve (refuse a
  // write); other update /a {"y/.priority":2,"z":{"v":3,"u":2}}; other update /a
  // {".priority":null,"z":{"u":3,"v":{".value":3,".priority":1},".priority":2},"y/.priority":3}
  'group S: a server merge refills the window from the pre-merge cache': <int>[
    4614, 11541, 174519, 245589,
  ],
  // Group V: a refused update at the view path reverted over a filtered cache (row 5).
  'group V: a revert at the view path over a filtered cache': <int>[279390],
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
    'x': <String, Object?>{'u': 1},
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
// The generator. Depths 1 (a, b) and 2 (a/x, ...) only ever hold objects and leaves sit at depth
// 3, where nothing is written below them, so no write meets the unmeasured case of a priority on
// a leaf that turns into children. Priorities are written at every depth that holds values.

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
  if (depth == 3) {
    final int leaf = 1 + r.nextInt(3);
    return r.nextInt(4) == 0
        ? <String, Object?>{'.value': leaf, '.priority': 1 + r.nextInt(3)}
        : leaf;
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
const List<String> _priorityNodes = <String>[
  'a',
  'b',
  'a/x',
  'a/y',
  'b/x',
  'a/x/u',
];
const Map<String, List<String>> _updateKeys = <String, List<String>>{
  '': <String>[
    'a',
    'b',
    'a/x',
    'b/y',
    'a/.priority',
    'b/.priority',
    'a/x/.priority',
  ],
  'a': <String>[
    'x',
    'y',
    'z',
    'x/u',
    '.priority',
    'x/.priority',
    'y/.priority',
  ],
  'b': <String>['x', 'y', 'x/v', '.priority', 'x/.priority'],
  'a/x': <String>['u', 'v', '.priority', 'u/.priority'],
};

_Write _write(math.Random r, {required bool ours}) {
  final int c = r.nextInt(10);
  if (c < 2) {
    final String node = _priorityNodes[r.nextInt(_priorityNodes.length)];
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
// The server model: a plain JSON tree, built without the client's node code.

bool _covers(String outer, String inner) =>
    outer == '/' || inner == outer || inner.startsWith('$outer/');

String _wire(String path) => '/$path'.replaceAll('//', '/');

List<String> _keys(String path) =>
    path.split('/').where((String k) => k.isNotEmpty).toList();

// The server's data and rules: the shared model of lib/src/testing/json_server_model.dart,
// which FakeServerActions plays too.
typedef _M = JsonServerNode;

/// Whether [n] has a value (a leaf, or a child with one).
bool _visible(_M? n) => n != null && n.hasValue;

/// The export JSON of [n]: what readers see, or with [hidden] what the server sends.
Object? _export(_M? n, {required bool hidden}) => n?.toJson(hidden: hidden);

/// The hash the server compares (kept priorities included).
String _hash(_M? n) => n?.hash() ?? '';

List<MapEntry<String, _M>> _byPriority(Map<String, _M> children) =>
    JsonServerNode.byPriority(children);

_M? _get(_M? n, List<String> keys) {
  _M? at = n;
  for (final String k in keys) {
    at = at?.children[k];
  }
  return at;
}

/// The window of the limit query at [n]: its first two children with a value by priority.
Map<String, _M> _window(_M? n) => <String, _M>{
  if (n != null)
    for (final MapEntry<String, _M> e in _byPriority(<String, _M>{
      for (final MapEntry<String, _M> c in n.children.entries)
        if (_visible(c.value)) c.key: c.value,
    }).take(2))
      e.key: e.value,
};

/// What [q] shows of [n], as the server sends it ([hidden]) or as readers see it.
Object? _shownJson(QuerySpec q, _M? n, {required bool hidden}) {
  if (q.loadsAllData) {
    return _export(n, hidden: hidden);
  }
  final Map<String, Object?> m = <String, Object?>{
    for (final MapEntry<String, _M> e in _window(n).entries)
      e.key: _export(e.value, hidden: hidden),
  };
  return m.isEmpty ? null : m;
}

/// [json] with map keys sorted, for comparing.
Object? _canonical(Object? json) => json is Map
    ? <String, Object?>{
        for (final String k
            in (json.keys.map((Object? k) => '$k').toList()..sort()))
          k: _canonical(json[k]),
      }
    : json;

String _jsonOf(Object? json) => jsonEncode(_canonical(json));

Node _shown(QuerySpec q, Node data) => q.loadsAllData
    ? data
    : nodeFilterFor(q.params).updateFullNode(
        ChildrenNode.empty.withIndex(q.index),
        data.withIndex(q.index),
        null,
      );

String _json(Node? n) =>
    n == null ? 'nothing' : jsonEncode(n.toJson(exportFormat: true));

/// [n] as the server would send it (kept priorities included).
String _server(Node n) => jsonEncode(
  n is ChildrenNode ? n.toServerJson() : n.toJson(exportFormat: true),
);

final class _Server {
  _Server(this.fake);
  final FakeServerActions fake;
  JsonServerModel model = JsonServerModel(_initial);

  /// The root node.
  _M? get data => model.root;

  /// The listens the server holds (it has handled the listen and not the unlisten).
  final List<ServerCall> listens = <ServerCall>[];

  /// How many of the client's messages the server has handled.
  int handled = 0;

  _M? at(String path) => model.at(path);

  /// The data at [path] as the server sends it (kept priorities included).
  Object? sent(String path) => _export(at(path), hidden: true);

  /// Applies [w] as the server does ([JsonServerModel.write]); false when the server refuses it.
  bool apply(_Write w) {
    final _M? before = data?.copy();
    if (!model.write(w.path, w.data, merge: w.merge)) {
      return false;
    }
    _publish(w, before);
    return true;
  }

  /// Sends [w] to the listens it touches; [before] is the data before it. A plain listen at or
  /// above the write gets it as written, one below it its whole data.
  void _publish(_Write w, _M? before) {
    final String wp = _wire(w.path);
    // The emulator sends a write's tagged frames before the untagged ones (measured, 18 runs:
    // reports/limit_merge_order.md). The other order would let an untagged put push a child out of
    // the limit view's server cache before the tagged merge removes another one.
    for (final ServerCall l in <ServerCall>[
      ...listens.where((ServerCall l) => l.tag != null),
      ...listens.where((ServerCall l) => l.tag == null),
    ]) {
      final String lp = l.spec!.path;
      if (l.tag != null) {
        if (_covers(lp, wp) || _covers(wp, lp)) {
          _publishTagged(l, w, before);
        }
      } else if (_covers(lp, wp)) {
        fake.deliverDataUpdate(wp, w.data, isMerge: w.merge);
      } else if (_covers(wp, lp)) {
        fake.deliverDataUpdate(lp, sent(lp));
      }
    }
  }

  /// Sends [w] to the limit query's listen [l] in the frames the emulator sent for a key-ordered
  /// `limitToFirst(2)` query (rtdb/from_helper/reports/limit_query_frames.md, cases A1 to C5),
  /// as production sent them (prodkit_production_run_2026-11-25.txt, checks 28 and 37).
  /// Shapes neither measured keep the whole window as a put at the query path.
  void _publishTagged(ServerCall l, _Write w, _M? before) {
    final QuerySpec q = _queries.firstWhere(
      (QuerySpec q) => q.toListenSpec() == l.spec,
    );
    final String lp = l.spec!.path;
    final List<String> qKeys = _keys(lp);
    void send(String path, Object? json, {bool merge = false}) =>
        fake.deliverDataUpdate(path, json, isMerge: merge, tag: l.tag);
    void sendWindow() => send(lp, _shownJson(q, at(lp), hidden: true));
    final Map<String, _M> was = _window(_get(before, qKeys));
    final Map<String, _M> now = _window(at(lp));
    final List<String> left = <String>[
      for (final String k in was.keys)
        if (!now.containsKey(k)) k,
    ];
    final List<String> entered = <String>[
      for (final String k in now.keys)
        if (!was.containsKey(k)) k,
    ];
    // A child that left the window but still has a value was pushed out by one that entered.
    bool removed(String k) => !_visible(at('$lp/$k'));
    Object? whole(String k) => _export(at('$lp/$k'), hidden: true);
    // The entering children whole; a leaving child null when it was removed, else whole with its
    // new value and priority (production: c4 moved out by its priority, check 37).
    final Map<String, Object?> diff = <String, Object?>{
      for (final String k in entered) k: whole(k),
      for (final String k in left) k: removed(k) ? null : whole(k),
    };
    final Path at_ = Path(w.path);
    if (at_.length > q.path.length) {
      final String child = Path.relative(q.path, at_).front!.name;
      if (left.isEmpty && entered.isEmpty) {
        // In the window: as written (C1, C5); outside it: nothing (C3).
        if (was.containsKey(child)) {
          send(_wire(w.path), w.data, merge: w.merge);
        }
      } else if (entered.length == 1 &&
          entered.single == child &&
          !left.any(removed)) {
        // The entering child alone, whole; the client drops what it pushes out (C4).
        send('$lp/$child', whole(child));
      } else if (entered.isEmpty) {
        // A window child emptied by a write below it, nothing entering: a put of null at the
        // child's path, not the write as written (emulator: set a/x/u null on x {u}).
        if (removed(child)) {
          send('$lp/$child', null);
        } else if (was.containsKey(child)) {
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
      final Path full = at_.childPath(Path(e.key));
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
    final Map<String, Object?> inWindow = <String, Object?>{
      for (final MapEntry<String, Object?> e in below.entries)
        if (now.containsKey(e.key.split('/').first)) e.key: e.value,
    };
    final Set<String> changed = <String>{
      for (final String k in inWindow.keys) k.split('/').first,
    };
    if (left.isEmpty && entered.isEmpty) {
      if (inWindow.length < below.length &&
          changed.length == 1 &&
          inWindow.keys.any((String k) => k.contains('/'))) {
        // One window child written below it, next to a key outside the window: that child
        // whole at its path (production, line mixed: update a/n and d/n).
        send('$lp/${changed.single}', whole(changed.single));
      } else {
        send(lp, inWindow, merge: true); // A3, B3
      }
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
          fake.deliverDataUpdate(
            c.spec!.path,
            _shownJson(q, at(c.spec!.path), hidden: true),
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
          fake.respond(c, data: sent(c.spec!.path));
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
      if (_jsonOf(l.value!.toJson(exportFormat: true)) !=
          _jsonOf(cache.toJson(exportFormat: true))) {
        return 'A: listener ${l.query} shows ${_json(l.value)}, '
            'its server cache ${_json(cache)}';
      }
      // Kept priorities raise no event, so the view's event cache, not the last value, must
      // hold the server cache's hidden state.
      if (l.query.loadsAllData &&
          view.eventCache.hash() != view.serverCache.hash()) {
        return 'A: view ${l.query} holds ${_server(view.eventCache)}, '
            'its server cache ${_server(view.serverCache)}';
      }
    }
    return null;
  }

  /// [got] against the model: the value readers see, and with [hash] the hash the server
  /// compares (kept priorities included), for a query that loads all data.
  String? matchesServer(
    String who,
    QuerySpec q,
    Node? got, {
    bool hash = false,
  }) {
    final _M? at = server.at(q.path.toString());
    final Object? want = _shownJson(q, at, hidden: false);
    if (got == null ||
        _jsonOf(got.toJson(exportFormat: true)) != _jsonOf(want)) {
      return 'B: $who $q shows ${_json(got)}, server ${_jsonOf(want)}';
    }
    if (hash && q.loadsAllData && got.hash() != _hash(at)) {
      return 'B: $who $q holds ${_server(got)}, '
          'server ${_jsonOf(_export(at, hidden: true))}';
    }
    return null;
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
    final String? failure = matchesServer(
      'new listener',
      l.query,
      l.value,
      hash: true,
    );
    if (failure != null) {
      return failure;
    }
  }
  for (final QuerySpec q in _queries.where((QuerySpec q) => q.loadsAllData)) {
    final Future<Node> got = repo.getValue(q);
    server.drain();
    final String? failure = matchesServer('get()', q, await got, hash: true);
    if (failure != null) {
      return failure;
    }
  }
  return ownCache();
}

/// The `FUZZ_SEEDS` define, `<first>-<end>` (end excluded), or empty.
const String _range = String.fromEnvironment('FUZZ_SEEDS');

/// The `FUZZ_DUMP` define: a file that receives every failing seed as a JSON line
/// (`{"seed": n, "f": "<failure>\n    <sequence>"}`), or empty.
const String _dump = String.fromEnvironment('FUZZ_DUMP');

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
      if (_dump.isNotEmpty) {
        File(_dump).writeAsStringSync(
          <String>[
            for (final MapEntry<int, String> e in failing.entries)
              '${jsonEncode(<String, Object?>{'seed': e.key, 'f': e.value})}\n',
          ].join(),
        );
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
