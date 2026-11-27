// Own tests for WriteTree (no upstream unit test). Expected values follow Android
// core/WriteTree.java (same logic as JS core/WriteTree.ts).
import 'dart:math' as math;

import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/user_write_record.dart';
import 'package:firebase_database_dart/src/core/write_tree.dart';
import 'package:test/test.dart';

Node n(Object? json) => nodeFromJson(json);
Path p(String path) => Path(path);
ChildKey k(String key) => ChildKey(key);
CompoundWrite cw(Map<String, Object?> merge) => CompoundWrite.fromValue(merge);

void main() {
  late WriteTree tree;
  setUp(() => tree = WriteTree());

  group('add', () {
    test('visible overwrite is complete write data', () {
      tree.addOverwrite(p('a'), n(1), 1, visible: true);
      expect(tree.getCompleteWriteData(p('a')), n(1));
      expect(tree.getCompleteWriteData(p('a/b')), ChildrenNode.empty);
      expect(tree.getCompleteWriteData(p('')), isNull);
      expect(tree.getCompleteWriteData(p('b')), isNull);
    });

    test('hidden overwrite is not in the visible writes', () {
      tree.addOverwrite(p('a'), n(1), 1, visible: false);
      expect(tree.getCompleteWriteData(p('a')), isNull);
      expect(tree.getWrite(1)!.visible, isFalse);
    });

    test('merge sets its children only', () {
      tree.addMerge(p('a'), cw(<String, Object?>{'b': 1, 'c': 2}), 1);
      expect(tree.getCompleteWriteData(p('a/b')), n(1));
      expect(tree.getCompleteWriteData(p('a/c')), n(2));
      expect(tree.getCompleteWriteData(p('a')), isNull);
    });

    test('ids must increase', () {
      tree.addOverwrite(p('a'), n(1), 2, visible: true);
      expect(
        () => tree.addOverwrite(p('b'), n(1), 1, visible: true),
        throwsStateError,
      );
      expect(
        () => tree.addMerge(p('b'), cw(<String, Object?>{'c': 1}), 2),
        throwsStateError,
      );
      tree.addMerge(p('b'), cw(<String, Object?>{'c': 1}), 3);
      expect(tree.getWrite(3)!.isMerge, isTrue);
    });
  });

  group('getWrite and purgeAllWrites', () {
    test('getWrite finds the record', () {
      tree.addOverwrite(p('a'), n(1), 1, visible: true);
      expect(
        tree.getWrite(1),
        UserWriteRecord.overwrite(1, p('a'), n(1), visible: true),
      );
      expect(tree.getWrite(2), isNull);
    });

    test('purge returns every write in order and empties the tree', () {
      tree.addOverwrite(p('a'), n(1), 1, visible: true);
      tree.addMerge(p('b'), cw(<String, Object?>{'c': 2}), 2);
      final List<UserWriteRecord> purged = tree.purgeAllWrites();
      expect(purged, <UserWriteRecord>[
        UserWriteRecord.overwrite(1, p('a'), n(1), visible: true),
        UserWriteRecord.merge(2, p('b'), cw(<String, Object?>{'c': 2})),
      ]);
      expect(tree.getWrite(1), isNull);
      expect(tree.getCompleteWriteData(p('a')), isNull);
      expect(tree.getCompleteWriteData(p('b/c')), isNull);
      final Node server = n(<String, Object?>{'x': 1});
      expect(tree.calcCompleteEventCache(p(''), server), same(server));
    });

    test('purge keeps the last write id (Android)', () {
      tree.addOverwrite(p('a'), n(1), 2, visible: true);
      tree.purgeAllWrites();
      expect(
        () => tree.addOverwrite(p('a'), n(1), 1, visible: true),
        throwsStateError,
      );
      tree.addOverwrite(p('a'), n(1), 3, visible: true);
    });
  });

  group('removeWrite', () {
    test('nonexistent id throws', () {
      expect(() => tree.removeWrite(1), throwsStateError);
    });

    test('lone overwrite is removed and was visible', () {
      tree.addOverwrite(p('a'), n(1), 1, visible: true);
      expect(tree.removeWrite(1), isTrue);
      expect(tree.getCompleteWriteData(p('a')), isNull);
      expect(tree.getWrite(1), isNull);
    });

    test('hidden write was not visible', () {
      tree.addOverwrite(p('a'), n(1), 1, visible: false);
      expect(tree.removeWrite(1), isFalse);
      expect(tree.getWrite(1), isNull);
    });

    test('merge removes each of its children', () {
      tree.addMerge(p('a'), cw(<String, Object?>{'b': 1, 'c': 2}), 1);
      expect(tree.removeWrite(1), isTrue);
      expect(tree.getCompleteWriteData(p('a/b')), isNull);
      expect(tree.getCompleteWriteData(p('a/c')), isNull);
    });

    test('write shadowed by a later overwrite was not visible', () {
      tree.addOverwrite(p('a/b'), n(1), 1, visible: true);
      tree.addOverwrite(p('a'), n(<String, Object?>{'c': 2}), 2, visible: true);
      expect(tree.removeWrite(1), isFalse);
      expect(tree.getCompleteWriteData(p('a')), n(<String, Object?>{'c': 2}));
    });

    test('write shadowed by a later merge was not visible', () {
      tree.addOverwrite(p('a/b'), n(1), 1, visible: true);
      tree.addMerge(p('a'), cw(<String, Object?>{'b': 2, 'c': 3}), 2);
      expect(tree.removeWrite(1), isFalse);
      expect(tree.getCompleteWriteData(p('a/b')), n(2));
    });

    test('later hidden write does not shadow', () {
      tree.addOverwrite(p('a'), n(1), 1, visible: true);
      tree.addOverwrite(p('a'), n(2), 2, visible: false);
      expect(tree.removeWrite(1), isTrue);
      expect(tree.getCompleteWriteData(p('a')), isNull);
    });

    test('disjoint writes are removed without a rebuild', () {
      tree.addOverwrite(p('a'), n(1), 1, visible: true);
      tree.addOverwrite(p('b'), n(2), 2, visible: true);
      expect(tree.removeWrite(1), isTrue);
      expect(tree.getCompleteWriteData(p('a')), isNull);
      expect(tree.getCompleteWriteData(p('b')), n(2));
    });

    test('removed write covering an earlier one rebuilds the tree', () {
      tree.addOverwrite(p('a/b'), n(1), 1, visible: true);
      tree.addOverwrite(p('a'), n(<String, Object?>{'c': 2}), 3, visible: true);
      expect(tree.removeWrite(3), isTrue);
      expect(tree.getCompleteWriteData(p('a/b')), n(1));
      expect(tree.getCompleteWriteData(p('a')), isNull);
      expect(tree.getCompleteWriteData(p('a/c')), isNull);
      // The rebuild resets the last write id to the last remaining write (1).
      tree.addOverwrite(p('x'), n(5), 2, visible: true);
      expect(tree.getCompleteWriteData(p('x')), n(5));
    });

    test('rebuild keeps hidden writes out', () {
      tree.addOverwrite(p('a/b'), n(1), 1, visible: false);
      tree.addOverwrite(p('a/c'), n(2), 2, visible: true);
      tree.addOverwrite(p('a'), n(<String, Object?>{'d': 3}), 3, visible: true);
      expect(tree.removeWrite(3), isTrue);
      expect(tree.getCompleteWriteData(p('a/b')), isNull);
      expect(tree.getCompleteWriteData(p('a/c')), n(2));
    });

    // Not in JS or Android, which treat a write as shadowed only when one later write contains
    // its whole path: a merge whose every child later writes rewrite is not visible either.
    test('merge rewritten child by child by later writes was not visible', () {
      tree.addMerge(p('a'), cw(<String, Object?>{'b/x': 1, 'c': 2}), 1);
      tree.addOverwrite(
        p('a/b'),
        n(<String, Object?>{'y': 3}),
        2,
        visible: true,
      );
      tree.addMerge(p(''), cw(<String, Object?>{'a/c': 4, 'z': 5}), 3);
      expect(tree.removeWrite(1), isFalse);
      expect(tree.getCompleteWriteData(p('a/b')), n(<String, Object?>{'y': 3}));
      expect(tree.getCompleteWriteData(p('a/c')), n(4));
    });

    test('merge rewritten only in part stays visible', () {
      tree.addMerge(p('a'), cw(<String, Object?>{'b': 1, 'c': 2}), 1);
      tree.addMerge(p('a'), cw(<String, Object?>{'b': 3}), 2);
      expect(tree.removeWrite(1), isTrue);
      expect(tree.getCompleteWriteData(p('a/b')), n(3));
      expect(tree.getCompleteWriteData(p('a/c')), isNull);
    });

    test('a hidden later merge does not rewrite a merge', () {
      tree.addMerge(p('a'), cw(<String, Object?>{'b': 1}), 1);
      tree.addOverwrite(p('a/b'), n(2), 2, visible: false);
      expect(tree.removeWrite(1), isTrue);
      expect(tree.getCompleteWriteData(p('a/b')), isNull);
    });

    // The bench scenario write_update_same: n pending `update` calls of the same children,
    // acknowledged in order. Only the last acknowledgement changes the visible writes, so the
    // others need no events (with JS's rule each one rebuilds the visible writes of all pending).
    test(
      'acks of merges of the same children need no events until the last',
      () {
        const int count = 50;
        for (int i = 1; i <= count; i++) {
          tree.addMerge(
            p('r'),
            cw(<String, Object?>{'x/i': i, 'x/name': 'n$i'}),
            i,
          );
        }
        for (int i = 1; i < count; i++) {
          expect(tree.removeWrite(i), isFalse, reason: 'write $i');
          expect(tree.getCompleteWriteData(p('r/x/i')), n(count));
        }
        expect(tree.removeWrite(count), isTrue);
        expect(tree.getCompleteWriteData(p('r/x/i')), isNull);
      },
    );
  });

  group('calcCompleteEventCache', () {
    test('no writes returns the server cache', () {
      final Node server = n(<String, Object?>{'a': 1});
      expect(tree.calcCompleteEventCache(p(''), null), isNull);
      expect(tree.calcCompleteEventCache(p(''), server), same(server));
    });

    test('shadowing write wins', () {
      tree.addOverwrite(p(''), n(<String, Object?>{'a': 1}), 1, visible: true);
      expect(tree.calcCompleteEventCache(p('a'), n(9)), n(1));
    });

    test('deeper write is layered over the server cache', () {
      tree.addOverwrite(p('a/b'), n(5), 1, visible: true);
      expect(
        tree.calcCompleteEventCache(
          p('a'),
          n(<String, Object?>{'b': 1, 'c': 2}),
        ),
        n(<String, Object?>{'b': 5, 'c': 2}),
      );
      expect(tree.calcCompleteEventCache(p('a'), null), isNull);
    });

    test('merge without a server cache is incomplete', () {
      tree.addMerge(p('a'), cw(<String, Object?>{'b': 1, 'c': 2}), 1);
      expect(tree.calcCompleteEventCache(p('a'), null), isNull);
      expect(
        tree.calcCompleteEventCache(p('a'), n(<String, Object?>{'d': 3})),
        n(<String, Object?>{'b': 1, 'c': 2, 'd': 3}),
      );
    });

    test('excluded ids are skipped', () {
      tree.addOverwrite(p('a/b'), n(5), 1, visible: true);
      tree.addOverwrite(p('a/c'), n(6), 2, visible: true);
      final Node server = n(<String, Object?>{'b': 1, 'c': 2});
      expect(
        tree.calcCompleteEventCache(
          p('a'),
          server,
          writeIdsToExclude: <int>[1],
        ),
        n(<String, Object?>{'b': 1, 'c': 6}),
      );
      expect(
        tree.calcCompleteEventCache(
          p('a'),
          server,
          writeIdsToExclude: <int>[1, 2],
        ),
        server,
      );
      expect(
        tree.calcCompleteEventCache(p('a'), null, writeIdsToExclude: <int>[1]),
        isNull,
      );
    });

    test('exclusion with no visible writes at the path returns the server', () {
      tree.addOverwrite(p('x'), n(1), 1, visible: true);
      final Node server = n(<String, Object?>{'b': 1});
      expect(
        tree.calcCompleteEventCache(
          p('a'),
          server,
          writeIdsToExclude: <int>[99],
        ),
        same(server),
      );
    });

    test('hidden writes only with includeHiddenWrites', () {
      tree.addOverwrite(
        p('a'),
        n(<String, Object?>{'b': 1}),
        1,
        visible: false,
      );
      expect(tree.calcCompleteEventCache(p('a'), null), isNull);
      expect(
        tree.calcCompleteEventCache(p('a'), null, includeHiddenWrites: true),
        n(<String, Object?>{'b': 1}),
      );
      expect(
        tree.calcCompleteEventCache(
          p(''),
          n(<String, Object?>{'c': 2}),
          includeHiddenWrites: true,
        ),
        n(<String, Object?>{
          'a': <String, Object?>{'b': 1},
          'c': 2,
        }),
      );
    });

    test('hidden overwrite above the path gives its child', () {
      tree.addOverwrite(
        p(''),
        n(<String, Object?>{
          'a': <String, Object?>{'b': 1},
        }),
        1,
        visible: false,
      );
      expect(
        tree.calcCompleteEventCache(p('a/b'), null, includeHiddenWrites: true),
        n(1),
      );
    });

    test('merge above the path applies only a complete node', () {
      // layerTree: a merge above the root only contributes getCompleteNode(relativePath).
      tree.addMerge(p(''), cw(<String, Object?>{'a/b': 1}), 1);
      expect(
        tree.calcCompleteEventCache(
          p('a'),
          n(<String, Object?>{'c': 2}),
          writeIdsToExclude: <int>[99],
        ),
        n(<String, Object?>{'c': 2}),
      );
    });

    test('merge above the path that sets the path replaces it', () {
      tree.addMerge(
        p(''),
        cw(<String, Object?>{
          'a': <String, Object?>{'b': 1},
        }),
        1,
      );
      expect(
        tree.calcCompleteEventCache(
          p('a'),
          n(<String, Object?>{'c': 2}),
          writeIdsToExclude: <int>[99],
        ),
        n(<String, Object?>{'b': 1}),
      );
    });
  });

  test('childWrites', () {
    final ref = tree.childWrites(p('a/b'));
    expect(ref.treePath, p('a/b'));
    expect(ref.writeTree, same(tree));
  });

  // A write folded into the node of an earlier write above it can change that node in ways a later
  // rewrite of its paths does not undo, so later writes do not shadow it. Found by review; the
  // overwrite-only case fails on JS's rule too.
  group('removeWrite of a write folded into an earlier one', () {
    void expectRebuilt(WriteTree t, List<void Function(WriteTree)> remaining) {
      final WriteTree rebuilt = WriteTree();
      for (final void Function(WriteTree) add in remaining) {
        add(rebuilt);
      }
      expect(
        t.calcCompleteEventCache(p(''), ChildrenNode.empty),
        rebuilt.calcCompleteEventCache(p(''), ChildrenNode.empty),
      );
    }

    test('a null child that emptied a prioritised node (A)', () {
      void w1(WriteTree t) => t.addOverwrite(
        p('a'),
        n(<String, Object?>{'x': 1, '.priority': 7}),
        1,
        visible: true,
      );
      void w3(WriteTree t) => t.addOverwrite(p('a/x'), n(2), 3, visible: true);
      w1(tree);
      tree.addMerge(p('a'), cw(<String, Object?>{'x': null}), 2);
      w3(tree);
      expect(tree.removeWrite(2), isTrue);
      expectRebuilt(tree, <void Function(WriteTree)>[w1, w3]);
      expect(
        tree.getCompleteWriteData(p('a')),
        n(<String, Object?>{'x': 2, '.priority': 7}),
      );
    });

    test('a merge child under a leaf, later deleted (B)', () {
      void w1(WriteTree t) => t.addOverwrite(p('a'), n(5), 1, visible: true);
      void w3(WriteTree t) =>
          t.addOverwrite(p('a/b'), n(null), 3, visible: true);
      w1(tree);
      tree.addMerge(p('a'), cw(<String, Object?>{'b': 1}), 2);
      w3(tree);
      expect(tree.removeWrite(2), isTrue);
      expectRebuilt(tree, <void Function(WriteTree)>[w1, w3]);
      expect(tree.getCompleteWriteData(p('a')), n(5));
    });

    test('an overwrite under a leaf, later deleted (JS rule)', () {
      void w1(WriteTree t) => t.addOverwrite(p('a'), n(5), 1, visible: true);
      void w3(WriteTree t) =>
          t.addOverwrite(p('a/b'), n(null), 3, visible: true);
      w1(tree);
      tree.addOverwrite(p('a/b'), n(1), 2, visible: true);
      w3(tree);
      expect(tree.removeWrite(2), isTrue);
      expectRebuilt(tree, <void Function(WriteTree)>[w1, w3]);
      expect(tree.getCompleteWriteData(p('a')), n(5));
    });
  });

  group('removeWrite of merges at one location', () {
    // Upstream rebuilds the visible writes whenever two merges share a location; here merges of
    // different children are removed one by one. The state must be the one a rebuild gives.
    Node visible(WriteTree t) =>
        t.calcCompleteEventCache(p('r'), ChildrenNode.empty)!;

    test('any removal order gives the state of a rebuild', () {
      const List<String> keys = <String>['a', 'b', 'c', 'a/x', 'a/y', 'b/x'];
      for (int seed = 0; seed < 200; seed++) {
        final math.Random random = math.Random(seed);
        final Map<int, CompoundWrite> pending = <int, CompoundWrite>{};
        final WriteTree tree = WriteTree();
        for (int id = 1; id <= 12; id++) {
          final CompoundWrite merge = cw(<String, Object?>{
            for (int j = 0; j <= random.nextInt(3); j++)
              keys[random.nextInt(keys.length)]: id * 10 + j,
          });
          pending[id] = merge;
          tree.addMerge(p('r'), merge, id);
        }
        final List<int> order = pending.keys.toList()..shuffle(random);
        for (final int id in order) {
          tree.removeWrite(id);
          pending.remove(id);
          final WriteTree rebuilt = WriteTree();
          pending.forEach(
            (int id, CompoundWrite merge) =>
                rebuilt.addMerge(p('r'), merge, id),
          );
          expect(
            visible(tree),
            visible(rebuilt),
            reason: 'seed $seed, after $id',
          );
        }
      }
    });

    // Random writes at several depths: overwrites (one in five hidden, as transactions make) and
    // merges, with leaf, null, empty and prioritised values, `.priority` children, deep merge child
    // paths and empty merges, removed in random order. After each removal the visible data, over
    // an empty and over a non-empty server node, must equal a tree rebuilt from the remaining
    // writes, and removeWrite may return false only when that data did not change.
    test('random writes: any removal order gives a rebuild', () {
      expect(_removalFailures(0, 2000), isEmpty);
    });

    test('1000 merges of different children are removed without a rebuild', () {
      final WriteTree tree = WriteTree();
      for (int id = 1; id <= 1000; id++) {
        tree.addMerge(
          p('r'),
          cw(<String, Object?>{'$id/a': id, '$id/b': id}),
          id,
        );
      }
      final Stopwatch watch = Stopwatch()..start();
      for (int id = 1; id <= 1000; id++) {
        expect(tree.removeWrite(id), isTrue);
      }
      // About 20 ms; the rebuild on every removal took about a second.
      expect(watch.elapsedMilliseconds, lessThan(500));
      expect(visible(tree), ChildrenNode.empty);
    });
  });
}

/// Runs seeds [from] to [to] (exclusive) of the random removal check and returns one line per
/// failing seed: the visible data after a removal differs from a rebuild, or removeWrite returned
/// false although the visible data changed.
List<String> _removalFailures(int from, int to) {
  const List<String> locations = <String>['', 'a', 'a/b', 'a/x', 'r', 'a/b/c'];
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
  const List<Object?> priorities = <Object?>[null, 1, 'v'];
  final Node server = n(<String, Object?>{
    'a': <String, Object?>{'b': 1, 'x': 2},
    'r': 3,
    '.priority': 1,
  });
  List<Node?> visible(WriteTree t) => <Node?>[
    t.calcCompleteEventCache(p(''), ChildrenNode.empty),
    t.calcCompleteEventCache(p(''), server),
  ];
  final List<String> failures = <String>[];
  for (int seed = from; seed < to; seed++) {
    final math.Random random = math.Random(seed);
    final Map<int, void Function(WriteTree)> pending =
        <int, void Function(WriteTree)>{};
    final WriteTree tree = WriteTree();
    final int count = 2 + random.nextInt(5);
    for (int id = 1; id <= count; id++) {
      final Path at = p(locations[random.nextInt(locations.length)]);
      final void Function(WriteTree) add;
      if (random.nextBool()) {
        final Node value = n(values[random.nextInt(values.length)]);
        final bool isVisible = random.nextInt(5) != 0;
        add = (WriteTree t) =>
            t.addOverwrite(at, value, id, visible: isVisible);
      } else {
        final Map<String, Object?> merge = <String, Object?>{
          for (int j = random.nextInt(4); j > 0; j--)
            if (keys[random.nextInt(keys.length)] case final String key)
              key: key.endsWith('.priority')
                  ? priorities[random.nextInt(priorities.length)]
                  : values[random.nextInt(values.length)],
        };
        final CompoundWrite children = cw(merge);
        add = (WriteTree t) => t.addMerge(at, children, id);
      }
      pending[id] = add;
      add(tree);
    }
    final List<int> order = pending.keys.toList()..shuffle(random);
    for (final int id in order) {
      final List<Node?> before = visible(tree);
      final bool result = tree.removeWrite(id);
      pending.remove(id);
      final WriteTree rebuilt = WriteTree();
      for (final void Function(WriteTree) add in pending.values) {
        add(rebuilt);
      }
      final List<Node?> expected = visible(rebuilt);
      final List<Node?> actual = visible(tree);
      if (actual[0] != expected[0] || actual[1] != expected[1]) {
        failures.add('seed $seed: data after removing $id');
        break;
      }
      if (!result && (before[0] != expected[0] || before[1] != expected[1])) {
        failures.add('seed $seed: false after removing $id');
        break;
      }
    }
  }
  return failures;
}
