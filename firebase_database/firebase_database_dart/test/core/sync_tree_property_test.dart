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
// The model is a plain JSON tree (no client node code). Measured on production
// (rtdb/from_boss/prodkit_production_run3_2026-11-25.txt check 38; run 2 check 22; check 27):
// writes apply in the order sent; a node whose last child is removed by a write below it keeps
// its priority (no value, the priority kept), and a write at or above it drops it; an update
// writing `.priority` on a node with a priority while emptying it keeps the new one; setPriority
// on an emptied node that keeps a priority is accepted and kept; a priority on a node that never
// existed refuses the write; the hash counts kept priorities (JS `ChildrenNode.hash`); listen
// answers and get answers carry `{".priority": p}` for an emptied node, also inside its parent.
//
// Model rules no production frame covers (the model's choice, the client agrees):
// - M1. In one update, a priority on a node WITHOUT a priority that the children empty: the
//   priority is written first and kept (priority_merge_test.dart has the skipped test that
//   states both outcomes; FakeServerActions drops it). On a node with a priority both orders
//   give the same result (measured).
// - M2. A priority on a node holding only emptied children (no priority of its own) is refused
//   as a write, and inside an update it is dropped.
// - M3. A priority written by `.priority: null` on an emptied node drops it (by analogy with M1).
// - M4. Whole data pushed to a listen below another client's write carries `{".priority": p}`
//   like a listen answer.
// - M5. The children of a limit window are sent with their `{".priority": p}` descendants; an
//   emptied child is not a window member, and a child leaving the window because it was emptied
//   is sent as null.
// - M6. A write forwarded as written to a listen at or above it carries nothing more.
// - M7. Range merges (`rm`) and compound hashes are not modelled (the model never sends `rm`).
// - M8. A leaf with a priority at depth 3 takes `.priority` writes like any node with a value.
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
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

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

/// The failing seeds by cause; [_defaultSeeds] holds none. A new group starts with its shortest
/// sequence, found by shrinking one of its seeds; data as in [_initial].
const Map<String, List<int>> _knownFailures = <String, List<int>>{
  // A limit query by priority after a default listen at its path took over, with a priority
  // moved inside the window: the limit view's caches disagree (6892: the listener is right and
  // the view's server cache short, the group R shape of
  // rtdb/from_helper/reports/wide_seeds_limit_groups.md; 4614: the listener keeps a child the
  // server removed). No hidden state in either minimal sequence; not traced in the client.
  // 4614 shrinks to: listen /a:{"l":2,"vf":"l"}; set /a/x/.priority 1; serve; other update /a
  // {"y":{"u":2},"z":{"v":{".value":1,".priority":1}}}; serve; listen /a:default; serve; serve;
  // other update /a {"z":null,"y/.priority":1,"x":null}
  // dart format off
  'limit view after a default listen took over, priority moved in the window': <int>[
    4614, 6892,
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

/// A node the model server holds: a leaf, or children; either with a priority. A node with no
/// value keeps its priority (and its children that keep one): the server's rule.
final class _M {
  Object? leaf;
  Object? priority;
  final Map<String, _M> children = <String, _M>{};

  /// Nothing left: no value, no priority, no child.
  bool get isAbsent => leaf == null && priority == null && children.isEmpty;

  _M copy() {
    final _M c = _M()
      ..leaf = leaf
      ..priority = priority;
    children.forEach((String k, _M v) => c.children[k] = v.copy());
    return c;
  }
}

/// Whether [n] has a value (a leaf, or a child with one).
bool _visible(_M? n) =>
    n != null && (n.leaf != null || n.children.values.any(_visible));

/// Whether a priority written on [n] lands: it has a value or keeps a priority of its own.
bool _takesPriority(_M? n) => n != null && (_visible(n) || n.priority != null);

/// The node of a user's value in export form; an object without children is no value.
_M? _fromUser(Object? json) {
  if (json == null) {
    return null;
  }
  if (json is Map<String, Object?>) {
    if (json.containsKey('.value')) {
      return _M()
        ..leaf = json['.value']
        ..priority = json['.priority'];
    }
    final _M n = _M()..priority = json['.priority'];
    json.forEach((String k, Object? v) {
      final _M? c = k.startsWith('.') ? null : _fromUser(v);
      if (c != null) {
        n.children[k] = c;
      }
    });
    return n.children.isEmpty ? null : n;
  }
  return _M()..leaf = json;
}

/// The export JSON of [n]: what readers see, or with [hidden] what the server sends (a node
/// with no value that keeps a priority as `{".priority": p}`, check 38 (a)).
Object? _export(_M? n, {required bool hidden}) {
  if (n == null) {
    return null;
  }
  if (n.leaf != null) {
    return n.priority == null
        ? n.leaf
        : <String, Object?>{'.value': n.leaf, '.priority': n.priority};
  }
  final Map<String, Object?> m = <String, Object?>{};
  n.children.forEach((String k, _M c) {
    final Object? json = _export(c, hidden: hidden);
    if (json != null) {
      m[k] = json;
    }
  });
  if (m.isEmpty && (!hidden || n.priority == null)) {
    return null;
  }
  if (n.priority != null) {
    m['.priority'] = n.priority;
  }
  return m;
}

/// The priority order of the JS SDK for the generator's data: no priority, numbers, strings;
/// then the key (the generator's keys are letters).
int _comparePriority(Object? a, Object? b) {
  int rank(Object? p) => p == null ? 0 : (p is num ? 1 : 2);
  if (rank(a) != rank(b)) {
    return rank(a) - rank(b);
  }
  if (a is num && b is num) {
    return a.compareTo(b);
  }
  return a is String && b is String ? a.compareTo(b) : 0;
}

List<MapEntry<String, _M>> _byPriority(Map<String, _M> children) =>
    children.entries.toList()
      ..sort((MapEntry<String, _M> a, MapEntry<String, _M> b) {
        final int c = _comparePriority(a.value.priority, b.value.priority);
        return c != 0 ? c : a.key.compareTo(b.key);
      });

String _sha1(String text) =>
    base64.encode(sha1.convert(utf8.encode(text)).bytes);

String _ieee754(num value) {
  final ByteData bytes = ByteData(8)..setFloat64(0, value.toDouble());
  return <String>[
    for (int i = 0; i < 8; i++)
      bytes.getUint8(i).toRadixString(16).padLeft(2, '0'),
  ].join();
}

String _hashText(Object value) => switch (value) {
  final num n => 'number:${_ieee754(n)}',
  final bool b => 'boolean:$b',
  _ => 'string:$value',
};

/// The hash the server compares (JS `LeafNode.hash` and `ChildrenNode.hash`), kept priorities
/// included (check 38 (c)).
String _hash(_M? n) {
  if (n == null) {
    return '';
  }
  final StringBuffer text = StringBuffer();
  if (n.priority != null) {
    text.write('priority:${_hashText(n.priority!)}:');
  }
  if (n.leaf != null) {
    text.write(_hashText(n.leaf!));
    return _sha1(text.toString());
  }
  for (final MapEntry<String, _M> e in _byPriority(n.children)) {
    final String h = _hash(e.value);
    if (h.isNotEmpty) {
      text.write(':${e.key}:$h');
    }
  }
  return text.isEmpty ? '' : _sha1(text.toString());
}

_M? _get(_M? n, List<String> keys) {
  _M? at = n;
  for (final String k in keys) {
    at = at?.children[k];
  }
  return at;
}

/// [n] with [value] at [keys] from [i]; a node left with nothing is removed.
_M? _put(_M? n, List<String> keys, int i, _M? value) {
  if (i == keys.length) {
    return value;
  }
  if (n == null || n.leaf != null) {
    // Nothing to remove below a leaf or nothing; a value below a leaf replaces it (the
    // generator's leaves carry no priority).
    if (value == null) {
      return n;
    }
  }
  final _M node = n == null || n.leaf != null ? _M() : n;
  final _M? child = _put(node.children[keys[i]], keys, i + 1, value);
  if (child == null) {
    node.children.remove(keys[i]);
  } else {
    node.children[keys[i]] = child;
  }
  return node.isAbsent ? null : node;
}

/// [n] with [priority] on the node at [keys] from [i], when that node takes it.
_M? _putPriority(_M? n, List<String> keys, int i, Object? priority) {
  if (n == null) {
    return null;
  }
  if (i == keys.length) {
    if (_takesPriority(n)) {
      n.priority = priority;
    }
    return n.isAbsent ? null : n;
  }
  final _M? child = _putPriority(n.children[keys[i]], keys, i + 1, priority);
  if (child == null) {
    n.children.remove(keys[i]);
  } else {
    n.children[keys[i]] = child;
  }
  return n.isAbsent ? null : n;
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
  _M? data = _fromUser(_initial);

  /// The listens the server holds (it has handled the listen and not the unlisten).
  final List<ServerCall> listens = <ServerCall>[];

  /// How many of the client's messages the server has handled.
  int handled = 0;

  _M? at(String path) => _get(data, _keys(path));

  /// The data at [path] as the server sends it (kept priorities included).
  Object? sent(String path) => _export(at(path), hidden: true);

  /// Applies [w] as one write: the children first, then the priorities; false when the server
  /// refuses it (a priority on a node that holds no value and no priority of its own).
  bool apply(_Write w) {
    final _M? before = data?.copy();
    final List<String> at = _keys(w.path);
    final Map<String, Object?> entries = w.merge
        ? (w.data! as Map<String, Object?>)
        : <String, Object?>{'': w.data};
    bool isPriority(String k) =>
        <String>[...at, ..._keys(k)].lastOrNull == '.priority';
    for (final String k in entries.keys.where(isPriority)) {
      final List<String> full = <String>[...at, ..._keys(k)];
      if (!_takesPriority(_get(data, full.sublist(0, full.length - 1)))) {
        return false;
      }
    }
    // A priority lands on a node that takes one before the children change (written first,
    // emptying the node then keeps it), else on one the children leave with a value.
    void priorities({required bool first}) {
      for (final MapEntry<String, Object?> e in entries.entries) {
        if (!isPriority(e.key)) {
          continue;
        }
        final List<String> full = <String>[...at, ..._keys(e.key)];
        final List<String> owner = full.sublist(0, full.length - 1);
        if (_takesPriority(_get(before, owner)) == first) {
          data = _putPriority(data, owner, 0, e.value);
        }
      }
    }

    priorities(first: true);
    for (final MapEntry<String, Object?> e in entries.entries) {
      if (!isPriority(e.key)) {
        data = _put(
          data,
          <String>[...at, ..._keys(e.key)],
          0,
          _fromUser(e.value),
        );
      }
    }
    priorities(first: false);
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
