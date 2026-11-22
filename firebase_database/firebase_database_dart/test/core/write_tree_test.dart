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
