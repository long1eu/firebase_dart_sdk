// A random check of WriteTree.removeWrite, written by the reviewer of the removeWrite change
// independently of the generator in write_tree_test.dart (`_removalFailures`). Keep the two
// independent: two generators by different authors reach different shapes, and both must pass.
//
// Oracle: after each removal the visible data (the event cache at `/`, over an empty server node
// and over a non-empty one) must equal that of a tree rebuilt from the remaining writes, and
// removeWrite may return false only when the visible data before the removal equals the rebuilt
// one.
import 'dart:math' as math;

import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/write_tree.dart';
import 'package:test/test.dart';

typedef _Add = void Function(WriteTree t);

final Node _server = nodeFromJson(<String, Object?>{
  'a': <String, Object?>{'b': 1, 'x': 2},
  'r': 3,
  '.priority': 1,
});

List<Node?> _views(WriteTree t) => <Node?>[
  t.calcCompleteEventCache(Path(''), ChildrenNode.empty),
  t.calcCompleteEventCache(Path(''), _server),
];

bool _same(List<Node?> a, List<Node?> b) => a[0] == b[0] && a[1] == b[1];

/// Runs [seeds] seeds; returns the failure count per kind and the shortest example of each.
(Map<String, int>, Map<String, String>) _fuzz(int seeds) {
  const List<String> locs = <String>['', 'a', 'a/b', 'a/x', 'r', 'a/b/c'];
  const List<String> keys = <String>[
    'a',
    'b',
    'x',
    'c',
    'a/b',
    'a/x',
    'b/c',
    '.priority',
    'x/.priority',
  ];
  const List<Object?> values = <Object?>[
    null,
    1,
    5,
    'v',
    <String, Object?>{'c': 1},
    <String, Object?>{'x': 1, '.priority': 7},
    <String, Object?>{'.value': 4, '.priority': 2},
    <String, Object?>{},
  ];
  final Map<String, int> found = <String, int>{};
  final Map<String, String> example = <String, String>{};
  for (int seed = 0; seed < seeds; seed++) {
    final math.Random r = math.Random(seed);
    final Map<int, _Add> pending = <int, _Add>{};
    final Map<int, String> desc = <int, String>{};
    final WriteTree t = WriteTree();
    final int count = 2 + r.nextInt(5);
    for (int id = 1; id <= count; id++) {
      final Path at = Path(locs[r.nextInt(locs.length)]);
      final _Add add;
      final String d;
      if (r.nextInt(2) == 0) {
        final Object? v = values[r.nextInt(values.length)];
        final bool vis = r.nextInt(5) != 0;
        add = (WriteTree t) =>
            t.addOverwrite(at, nodeFromJson(v), id, visible: vis);
        d = 'set($at, $v${vis ? '' : ', hidden'})';
      } else {
        final Map<String, Object?> m = <String, Object?>{};
        final int kc = r.nextInt(4); // 0: an empty merge
        for (int j = 0; j < kc; j++) {
          final String key = keys[r.nextInt(keys.length)];
          m[key] = key.endsWith('.priority')
              ? const <Object?>[null, 1, 'v'][r.nextInt(3)]
              : values[r.nextInt(values.length)];
        }
        final CompoundWrite cwv = CompoundWrite.fromValue(m);
        add = (WriteTree t) => t.addMerge(at, cwv, id);
        d = 'update($at, $m)';
      }
      pending[id] = add;
      desc[id] = '$id:$d';
      add(t);
    }
    final List<int> order = pending.keys.toList()..shuffle(r);
    final List<String> log = <String>[];
    for (final int id in order) {
      final List<Node?> before = _views(t);
      final bool ret = t.removeWrite(id);
      pending.remove(id);
      log.add('remove $id -> $ret');
      final WriteTree rb = WriteTree();
      for (final _Add a in pending.values) {
        a(rb);
      }
      final List<Node?> exp = _views(rb);
      String? kind;
      if (!_same(_views(t), exp)) {
        kind = 'data';
      } else if (!ret && !_same(before, exp)) {
        kind = 'return';
      }
      if (kind != null) {
        kind =
            '$kind/${desc[id]!.contains('update(') ? 'merge' : 'set'}-removed';
        found[kind] = (found[kind] ?? 0) + 1;
        final String s = '${desc.values.join('; ')} | ${log.join(', ')}';
        if (!example.containsKey(kind) || s.length < example[kind]!.length) {
          example[kind] = s;
        }
        break;
      }
    }
  }
  return (found, example);
}

void main() {
  test(
    'removeWrite matches a rebuild and its return contract (independent fuzzer)',
    () {
      final (Map<String, int> found, Map<String, String> example) = _fuzz(3000);
      expect(found, isEmpty, reason: '$example');
    },
  );
}
