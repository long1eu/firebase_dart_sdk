// Own tests for the WriteTree read helpers (no upstream unit test). Expected values follow Android
// core/WriteTree.java (same logic as JS core/WriteTree.ts).
import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/priority_index.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/value_index.dart';
import 'package:firebase_database_dart/src/core/snap/named_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/view/cache_node.dart';
import 'package:firebase_database_dart/src/core/write_tree.dart';
import 'package:test/test.dart';

Node n(Object? json) => nodeFromJson(json);
Path p(String path) => Path(path);
ChildKey k(String key) => ChildKey(key);
CompoundWrite cw(Map<String, Object?> merge) => CompoundWrite.fromValue(merge);

void main() {
  late WriteTree tree;
  setUp(() => tree = WriteTree());

  group('calcCompleteEventChildren', () {
    test('leaf top-level set gives no children', () {
      tree.addOverwrite(p('a'), n(5), 1, visible: true);
      expect(
        tree.calcCompleteEventChildren(p('a'), n(<String, Object?>{'x': 1})),
        ChildrenNode.empty,
      );
    });

    test('children top-level set gives its children', () {
      tree.addOverwrite(
        p('a'),
        n(<String, Object?>{'x': 1, 'y': 2}),
        1,
        visible: true,
      );
      expect(
        tree.calcCompleteEventChildren(p('a'), n(<String, Object?>{'z': 3})),
        n(<String, Object?>{'x': 1, 'y': 2}),
      );
    });

    test('writes are layered over server children', () {
      tree.addOverwrite(p('a/x/z'), n(9), 1, visible: true);
      tree.addOverwrite(p('a/w'), n(3), 2, visible: true);
      expect(
        tree.calcCompleteEventChildren(
          p('a'),
          n(<String, Object?>{
            'x': <String, Object?>{'k': 1},
            'y': 2,
          }),
        ),
        n(<String, Object?>{
          'x': <String, Object?>{'k': 1, 'z': 9},
          'y': 2,
          'w': 3,
        }),
      );
    });
  });

  group('calcEventCacheAfterServerOverwrite', () {
    test('needs one of the snaps', () {
      expect(
        () =>
            tree.calcEventCacheAfterServerOverwrite(p('a'), p('b'), null, null),
        throwsStateError,
      );
    });

    test('complete write at the path gives null', () {
      tree.addOverwrite(p('a/b'), n(1), 1, visible: true);
      expect(
        tree.calcEventCacheAfterServerOverwrite(
          p('a'),
          p('b'),
          null,
          n(<String, Object?>{'b': 5}),
        ),
        isNull,
      );
    });

    test('write above the path gives null', () {
      tree.addOverwrite(p('a'), n(<String, Object?>{'c': 1}), 1, visible: true);
      expect(
        tree.calcEventCacheAfterServerOverwrite(
          p('a'),
          p('b'),
          n(1),
          n(<String, Object?>{'b': 5}),
        ),
        isNull,
      );
    });

    test('no writes gives the server child', () {
      expect(
        tree.calcEventCacheAfterServerOverwrite(
          p('a'),
          p('b'),
          null,
          n(<String, Object?>{'b': 5, 'c': 6}),
        ),
        n(5),
      );
    });

    test('partial writes are applied to the server child', () {
      tree.addOverwrite(p('a/b/x'), n(1), 1, visible: true);
      expect(
        tree.calcEventCacheAfterServerOverwrite(
          p('a'),
          p('b'),
          null,
          n(<String, Object?>{
            'b': <String, Object?>{'y': 2},
          }),
        ),
        n(<String, Object?>{'x': 1, 'y': 2}),
      );
    });
  });

  group('calcCompleteChild', () {
    test('shadowing write wins', () {
      tree.addOverwrite(p('a/b'), n(1), 1, visible: true);
      expect(
        tree.calcCompleteChild(
          p('a'),
          k('b'),
          CacheNode(
            ChildrenNode.empty,
            fullyInitialized: false,
            filtered: false,
          ),
        ),
        n(1),
      );
    });

    test('complete server child gets the writes', () {
      tree.addOverwrite(p('a/b/x'), n(1), 1, visible: true);
      expect(
        tree.calcCompleteChild(
          p('a'),
          k('b'),
          CacheNode(
            n(<String, Object?>{
              'b': <String, Object?>{'y': 2},
            }),
            fullyInitialized: true,
            filtered: false,
          ),
        ),
        n(<String, Object?>{'x': 1, 'y': 2}),
      );
    });

    test('incomplete server child gives null', () {
      expect(
        tree.calcCompleteChild(
          p('a'),
          k('b'),
          CacheNode(
            n(<String, Object?>{'c': 1}),
            fullyInitialized: false,
            filtered: false,
          ),
        ),
        isNull,
      );
    });
  });

  test('shadowingWrite', () {
    tree.addOverwrite(p('a'), n(<String, Object?>{'b': 1}), 1, visible: true);
    expect(tree.shadowingWrite(p('a/b')), n(1));
    expect(tree.shadowingWrite(p('a/c')), ChildrenNode.empty);
    expect(tree.shadowingWrite(p('x')), isNull);
    expect(tree.shadowingWrite(p('')), isNull);
  });

  group('calcNextNodeAfterPost', () {
    final Node server = n(<String, Object?>{'a': 1, 'b': 2, 'c': 3});

    test('forward and reverse over server data', () {
      final NamedNode postA = NamedNode(k('a'), n(1));
      final NamedNode postB = NamedNode(k('b'), n(2));
      expect(
        tree.calcNextNodeAfterPost(
          p('q'),
          server,
          postA,
          priorityIndex,
          reverse: false,
        ),
        NamedNode(k('b'), n(2)),
      );
      expect(
        tree.calcNextNodeAfterPost(
          p('q'),
          server,
          postA,
          priorityIndex,
          reverse: true,
        ),
        isNull,
      );
      expect(
        tree.calcNextNodeAfterPost(
          p('q'),
          server,
          postB,
          priorityIndex,
          reverse: true,
        ),
        NamedNode(k('a'), n(1)),
      );
    });

    test('writes are applied first', () {
      tree.addOverwrite(p('q/b'), n(null), 1, visible: true);
      expect(
        tree.calcNextNodeAfterPost(
          p('q'),
          server,
          NamedNode(k('a'), n(1)),
          priorityIndex,
          reverse: false,
        ),
        NamedNode(k('c'), n(3)),
      );
    });

    test('shadowing write replaces the server data', () {
      tree.addOverwrite(
        p('q'),
        n(<String, Object?>{'x': 1, 'y': 2}),
        1,
        visible: true,
      );
      expect(
        tree.calcNextNodeAfterPost(
          p('q'),
          server,
          NamedNode(k('a'), n(1)),
          priorityIndex,
          reverse: false,
        ),
        NamedNode(k('x'), n(1)),
      );
    });

    test('value index, forward and reverse', () {
      final Node byValue = n(<String, Object?>{'a': 3, 'b': 1, 'c': 2});
      expect(
        tree.calcNextNodeAfterPost(
          p('q'),
          byValue,
          NamedNode(k('b'), n(1)),
          valueIndex,
          reverse: false,
        ),
        NamedNode(k('c'), n(2)),
      );
      expect(
        tree.calcNextNodeAfterPost(
          p('q'),
          byValue,
          NamedNode(k('c'), n(2)),
          valueIndex,
          reverse: true,
        ),
        NamedNode(k('b'), n(1)),
      );
    });
  });
}
