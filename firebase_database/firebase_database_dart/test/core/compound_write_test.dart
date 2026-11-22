// Port of Android CompoundWriteTest.java (the same cases as JS test/compound_write.test.ts).
import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/leaf_node.dart';
import 'package:firebase_database_dart/src/core/snap/named_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:test/test.dart';

Node get leafNode => nodeFromJson('leaf-node');
Node get prioNode => nodeFromJson('prio');
Node get empty => ChildrenNode.empty;
Node get baseNode =>
    nodeFromJson(<String, Object?>{'child-1': 'value-1', 'child-2': 'value-2'});

void assertNodeGetsCorrectPriority(
  CompoundWrite compoundWrite,
  Node node,
  Node priority,
) {
  if (node.isEmpty) {
    expect(compoundWrite.apply(node), empty);
  } else {
    expect(compoundWrite.apply(node), node.updatePriority(priority));
  }
}

Map<ChildKey, Node> asMap(List<NamedNode> nodes) => <ChildKey, Node>{
  for (final NamedNode n in nodes) n.name: n.node,
};

void main() {
  test('empty merge is empty', () {
    expect(CompoundWrite.empty.isEmpty, isTrue);
  });

  test('compound write with priority update is not empty', () {
    expect(
      CompoundWrite.empty.addChildWrite(ChildKey.priority, prioNode).isEmpty,
      isFalse,
    );
  });

  test('compound write with update is not empty', () {
    expect(
      CompoundWrite.empty.addWrite(Path('foo/bar'), leafNode).isEmpty,
      isFalse,
    );
  });

  test('compound write with root update is not empty', () {
    expect(CompoundWrite.empty.addWrite(Path.empty, leafNode).isEmpty, isFalse);
  });

  test('compound write with empty root update is not empty', () {
    expect(CompoundWrite.empty.addWrite(Path.empty, empty).isEmpty, isFalse);
  });

  test('root priority update and child merge is not empty', () {
    final CompoundWrite cw = CompoundWrite.empty.addChildWrite(
      ChildKey.priority,
      prioNode,
    );
    expect(cw.childCompoundWrite(Path('.priority')).isEmpty, isFalse);
  });

  test('applies leaf overwrite', () {
    final CompoundWrite cw = CompoundWrite.empty.addWrite(Path.empty, leafNode);
    expect(cw.apply(empty), leafNode);
  });

  test('applies children overwrite', () {
    final Node childNode = empty.updateImmediateChild(
      ChildKey('child'),
      leafNode,
    );
    final CompoundWrite cw = CompoundWrite.empty.addWrite(
      Path.empty,
      childNode,
    );
    expect(cw.apply(empty), childNode);
  });

  test('adds child node', () {
    final ChildKey childKey = ChildKey('child');
    final Node expected = empty.updateImmediateChild(childKey, leafNode);
    final CompoundWrite cw = CompoundWrite.empty.addChildWrite(
      childKey,
      leafNode,
    );
    expect(cw.apply(empty), expected);
  });

  test('adds deep child node', () {
    final Path path = Path('deep/deep/node');
    final Node expected = empty.updateChild(path, leafNode);
    final CompoundWrite cw = CompoundWrite.empty.addWrite(path, leafNode);
    expect(cw.apply(empty), expected);
  });

  test('overwrites existing child', () {
    final Path path = Path('child-1');
    final CompoundWrite cw = CompoundWrite.empty.addWrite(path, leafNode);
    expect(
      cw.apply(baseNode),
      baseNode.updateImmediateChild(path.front!, leafNode),
    );
  });

  test('updates existing child', () {
    final Path path = Path('child-1/foo');
    final CompoundWrite cw = CompoundWrite.empty.addWrite(path, leafNode);
    expect(cw.apply(baseNode), baseNode.updateChild(path, leafNode));
  });

  test("doesn't update priority on empty node", () {
    final CompoundWrite cw = CompoundWrite.empty.addChildWrite(
      ChildKey.priority,
      nodeFromJson('prio'),
    );
    assertNodeGetsCorrectPriority(cw, empty, empty);
  });

  test('updates priority on node', () {
    final CompoundWrite cw = CompoundWrite.empty.addChildWrite(
      ChildKey.priority,
      prioNode,
    );
    assertNodeGetsCorrectPriority(cw, nodeFromJson('value'), prioNode);
  });

  test('updates priority of child', () {
    final Path path = Path('child-1/.priority');
    final CompoundWrite cw = CompoundWrite.empty.addWrite(path, prioNode);
    expect(cw.apply(baseNode), baseNode.updateChild(path, prioNode));
  });

  test("doesn't update priority of nonexistent child", () {
    final CompoundWrite cw = CompoundWrite.empty.addWrite(
      Path('child-3/.priority'),
      prioNode,
    );
    expect(cw.apply(baseNode), baseNode);
  });

  test('priority update on previous empty child write is ignored', () {
    final CompoundWrite cw = CompoundWrite.empty
        .addChildWrite(ChildKey('child'), empty)
        .addWrite(Path('child/.priority'), prioNode);
    final Node applied = cw.apply(empty);
    expect(applied.getChild(Path('child')).priority, empty);
    expect(cw.getCompleteNode(Path('child'))!.priority, empty);
    for (final NamedNode node in cw.getCompleteChildren()) {
      expect(node.node.priority, empty);
    }
  });

  test('deep update existing updates', () {
    final Node updateOne = nodeFromJson(<String, Object?>{
      'foo': 'foo-value',
      'bar': 'bar-value',
    });
    final CompoundWrite cw = CompoundWrite.empty
        .addWrite(Path('child-1'), updateOne)
        .addWrite(Path('child-1/baz'), nodeFromJson('baz-value'))
        .addWrite(Path('child-1/foo'), nodeFromJson('new-foo-value'));
    final Node expected = baseNode.updateImmediateChild(
      ChildKey('child-1'),
      nodeFromJson(<String, Object?>{
        'foo': 'new-foo-value',
        'bar': 'bar-value',
        'baz': 'baz-value',
      }),
    );
    expect(cw.apply(baseNode), expected);
  });

  test('shallow update removes deep update', () {
    final CompoundWrite cw = CompoundWrite.empty
        .addWrite(Path('child-1/foo'), nodeFromJson('new-foo-value'))
        .addWrite(Path('child-1/baz'), nodeFromJson('baz-value'))
        .addWrite(
          Path('child-1'),
          nodeFromJson(<String, Object?>{
            'foo': 'foo-value',
            'bar': 'bar-value',
          }),
        );
    final Node expected = baseNode.updateImmediateChild(
      ChildKey('child-1'),
      nodeFromJson(<String, Object?>{'foo': 'foo-value', 'bar': 'bar-value'}),
    );
    expect(cw.apply(baseNode), expected);
  });

  test("child priority doesn't update empty node priority on child merge", () {
    final CompoundWrite cw = CompoundWrite.empty.addWrite(
      Path('child-1/.priority'),
      prioNode,
    );
    assertNodeGetsCorrectPriority(
      cw.childCompoundWrite(Path('child-1')),
      empty,
      empty,
    );
  });

  test('child priority updates priority on child merge', () {
    final CompoundWrite cw = CompoundWrite.empty.addWrite(
      Path('child-1/.priority'),
      prioNode,
    );
    assertNodeGetsCorrectPriority(
      cw.childCompoundWrite(Path('child-1')),
      nodeFromJson('value'),
      prioNode,
    );
  });

  test('child priority updates empty priority on child merge', () {
    final CompoundWrite cw = CompoundWrite.empty.addWrite(
      Path('child-1/.priority'),
      empty,
    );
    assertNodeGetsCorrectPriority(
      cw.childCompoundWrite(Path('child-1')),
      LeafNode('foo', prioNode),
      empty,
    );
  });

  test('deep priority set works on empty node when other set is available', () {
    final CompoundWrite cw = CompoundWrite.empty
        .addWrite(Path('foo/.priority'), prioNode)
        .addWrite(Path('foo/child'), leafNode);
    expect(cw.apply(empty).getChild(Path('foo')).priority, prioNode);
  });

  test('child merge looks into update node', () {
    final CompoundWrite cw = CompoundWrite.empty.addWrite(
      Path.empty,
      nodeFromJson(<String, Object?>{'foo': 'foo-value', 'bar': 'bar-value'}),
    );
    expect(
      cw.childCompoundWrite(Path('foo')).apply(empty),
      nodeFromJson('foo-value'),
    );
  });

  test('child merge removes node on deeper paths', () {
    final CompoundWrite cw = CompoundWrite.empty.addWrite(
      Path.empty,
      nodeFromJson(<String, Object?>{'foo': 'foo-value', 'bar': 'bar-value'}),
    );
    expect(
      cw.childCompoundWrite(Path('foo/not/existing')).apply(leafNode),
      empty,
    );
  });

  test('child merge with empty path is same merge', () {
    final CompoundWrite cw = CompoundWrite.empty.addWrite(
      Path.empty,
      nodeFromJson(<String, Object?>{'foo': 'foo-value', 'bar': 'bar-value'}),
    );
    expect(identical(cw.childCompoundWrite(Path.empty), cw), isTrue);
  });

  test('root update removes root priority', () {
    final CompoundWrite cw = CompoundWrite.empty
        .addWrite(Path('.priority'), prioNode)
        .addWrite(Path.empty, nodeFromJson('foo'));
    expect(cw.apply(empty), nodeFromJson('foo'));
  });

  test('deep update removes priority there', () {
    final CompoundWrite cw = CompoundWrite.empty
        .addWrite(Path('foo/.priority'), prioNode)
        .addWrite(Path('foo'), nodeFromJson('bar'));
    expect(cw.apply(empty), nodeFromJson(<String, Object?>{'foo': 'bar'}));
  });

  test('adding updates at path works', () {
    final CompoundWrite cw = CompoundWrite.empty.addWrites(
      Path('child-1'),
      CompoundWrite.fromChildMerge(<ChildKey, Node>{
        ChildKey('foo'): nodeFromJson('foo-value'),
        ChildKey('bar'): nodeFromJson('bar-value'),
      }),
    );
    final Node expected = baseNode.updateImmediateChild(
      ChildKey('child-1'),
      nodeFromJson(<String, Object?>{'foo': 'foo-value', 'bar': 'bar-value'}),
    );
    expect(cw.apply(baseNode), expected);
  });

  test('adding updates at root works', () {
    final CompoundWrite cw = CompoundWrite.empty.addWrites(
      Path.empty,
      CompoundWrite.fromChildMerge(<ChildKey, Node>{
        ChildKey('child-1'): nodeFromJson('new-value-1'),
        ChildKey('child-2'): empty,
        ChildKey('child-3'): nodeFromJson('value-3'),
      }),
    );
    expect(
      cw.apply(baseNode),
      nodeFromJson(<String, Object?>{
        'child-1': 'new-value-1',
        'child-3': 'value-3',
      }),
    );
  });

  test('child merge of root priority works', () {
    final CompoundWrite cw = CompoundWrite.empty.addWrite(
      Path('.priority'),
      prioNode,
    );
    expect(cw.childCompoundWrite(Path('.priority')).apply(empty), prioNode);
  });

  test('complete children only returns complete overwrites', () {
    final CompoundWrite cw = CompoundWrite.empty.addWrite(
      Path('child-1'),
      leafNode,
    );
    expect(cw.getCompleteChildren(), <NamedNode>[
      NamedNode(ChildKey('child-1'), leafNode),
    ]);
  });

  test('complete children only returns empty overwrites', () {
    final CompoundWrite cw = CompoundWrite.empty.addWrite(
      Path('child-1'),
      empty,
    );
    expect(cw.getCompleteChildren(), <NamedNode>[
      NamedNode(ChildKey('child-1'), empty),
    ]);
  });

  test("complete children doesn't return deep overwrites", () {
    final CompoundWrite cw = CompoundWrite.empty.addWrite(
      Path('child-1/deep/path'),
      leafNode,
    );
    expect(cw.getCompleteChildren(), isEmpty);
  });

  test('complete children return all complete children but no incomplete', () {
    final CompoundWrite cw = CompoundWrite.empty
        .addWrite(Path('child-1/deep/path'), leafNode)
        .addWrite(Path('child-2'), leafNode)
        .addWrite(Path('child-3'), empty);
    expect(asMap(cw.getCompleteChildren()), <ChildKey, Node>{
      ChildKey('child-2'): leafNode,
      ChildKey('child-3'): empty,
    });
  });

  test('complete children return all children for root set', () {
    final CompoundWrite cw = CompoundWrite.empty.addWrite(Path.empty, baseNode);
    expect(asMap(cw.getCompleteChildren()), <ChildKey, Node>{
      ChildKey('child-1'): nodeFromJson('value-1'),
      ChildKey('child-2'): nodeFromJson('value-2'),
    });
  });

  test('empty merge has no shadowing write', () {
    expect(CompoundWrite.empty.hasCompleteWrite(Path.empty), isFalse);
  });

  test('compound write with empty root has shadowing write', () {
    final CompoundWrite cw = CompoundWrite.empty.addWrite(Path.empty, empty);
    expect(cw.hasCompleteWrite(Path.empty), isTrue);
    expect(cw.hasCompleteWrite(Path('child')), isTrue);
  });

  test('compound write with root has shadowing write', () {
    final CompoundWrite cw = CompoundWrite.empty.addWrite(Path.empty, leafNode);
    expect(cw.hasCompleteWrite(Path.empty), isTrue);
    expect(cw.hasCompleteWrite(Path('child')), isTrue);
  });

  test('compound write with deep update has shadowing write', () {
    final CompoundWrite cw = CompoundWrite.empty.addWrite(
      Path('deep/update'),
      leafNode,
    );
    expect(cw.hasCompleteWrite(Path.empty), isFalse);
    expect(cw.hasCompleteWrite(Path('deep')), isFalse);
    expect(cw.hasCompleteWrite(Path('deep/update')), isTrue);
  });

  test('compound write with priority update has shadowing write', () {
    final CompoundWrite cw = CompoundWrite.empty.addWrite(
      Path('.priority'),
      prioNode,
    );
    expect(cw.hasCompleteWrite(Path.empty), isFalse);
    expect(cw.hasCompleteWrite(Path('.priority')), isTrue);
  });

  test('updates can be removed', () {
    final CompoundWrite cw = CompoundWrite.empty
        .addWrite(
          Path('child-1'),
          nodeFromJson(<String, Object?>{
            'foo': 'foo-value',
            'bar': 'bar-value',
          }),
        )
        .removeWrite(Path('child-1'));
    expect(cw.apply(baseNode), baseNode);
  });

  CompoundWrite threeWrites() => CompoundWrite.empty
      .addWrite(
        Path('child-1'),
        nodeFromJson(<String, Object?>{'foo': 'foo-value', 'bar': 'bar-value'}),
      )
      .addWrite(Path('child-1/baz'), nodeFromJson('baz-value'))
      .addWrite(Path('child-1/foo'), nodeFromJson('new-foo-value'));

  Node threeWritesExpected() => baseNode.updateImmediateChild(
    ChildKey('child-1'),
    nodeFromJson(<String, Object?>{
      'foo': 'new-foo-value',
      'bar': 'bar-value',
      'baz': 'baz-value',
    }),
  );

  test('deep removes has no effect on overlaying set', () {
    final CompoundWrite cw = threeWrites().removeWrite(Path('child-1/foo'));
    expect(cw.apply(baseNode), threeWritesExpected());
  });

  test('remove at path without set is without effect', () {
    final CompoundWrite cw = threeWrites().removeWrite(Path('child-2'));
    expect(cw.apply(baseNode), threeWritesExpected());
  });

  test('can remove priority', () {
    final CompoundWrite cw = CompoundWrite.empty
        .addWrite(Path('.priority'), prioNode)
        .removeWrite(Path('.priority'));
    assertNodeGetsCorrectPriority(cw, leafNode, empty);
  });

  test('removing only affects removed path', () {
    final CompoundWrite cw = CompoundWrite.empty
        .addWrites(
          Path.empty,
          CompoundWrite.fromChildMerge(<ChildKey, Node>{
            ChildKey('child-1'): nodeFromJson('new-value-1'),
            ChildKey('child-2'): empty,
            ChildKey('child-3'): nodeFromJson('value-3'),
          }),
        )
        .removeWrite(Path('child-2'));
    expect(
      cw.apply(baseNode),
      nodeFromJson(<String, Object?>{
        'child-1': 'new-value-1',
        'child-2': 'value-2',
        'child-3': 'value-3',
      }),
    );
  });

  test('remove removes all deeper sets', () {
    final CompoundWrite cw = CompoundWrite.empty
        .addWrite(Path('child-1/baz'), nodeFromJson('baz-value'))
        .addWrite(Path('child-1/foo'), nodeFromJson('new-foo-value'))
        .removeWrite(Path('child-1'));
    expect(cw.apply(baseNode), baseNode);
  });

  test('remove at root also removes priority', () {
    final CompoundWrite cw = CompoundWrite.empty
        .addWrite(Path.empty, LeafNode('foo', prioNode))
        .removeWrite(Path.empty);
    assertNodeGetsCorrectPriority(cw, nodeFromJson('value'), empty);
  });

  test("updating priority doesn't overwrite leaf node", () {
    final CompoundWrite cw = CompoundWrite.empty
        .addWrite(Path.empty, leafNode)
        .addWrite(Path('child/.priority'), prioNode);
    expect(cw.apply(empty), leafNode);
  });

  test("updating empty node doesn't overwrite leaf node", () {
    final CompoundWrite cw = CompoundWrite.empty
        .addWrite(Path.empty, leafNode)
        .addWrite(Path('child'), empty);
    expect(cw.apply(empty), leafNode);
  });

  group('Dart additions', () {
    test('fromValue reads relative path keys', () {
      final CompoundWrite cw = CompoundWrite.fromValue(<String, Object?>{
        'a/b': 1,
        'c': 'x',
      });
      expect(cw.getCompleteNode(Path('a/b')), nodeFromJson(1));
      expect(cw.getCompleteNode(Path('c')), nodeFromJson('x'));
    });

    test('toJson round-trips through fromValue and equality', () {
      final CompoundWrite cw = CompoundWrite.fromPathMerge(<Path, Node>{
        Path('a/b'): nodeFromJson(1),
        Path('c'): nodeFromJson(<String, Object?>{'d': true}),
      });
      final CompoundWrite back = CompoundWrite.fromValue(cw.toJson());
      expect(back, cw);
      expect(back.hashCode, cw.hashCode);
    });

    test('entries lists every write with its path', () {
      final CompoundWrite cw = CompoundWrite.empty
          .addWrite(Path('a'), nodeFromJson(1))
          .addWrite(Path('b/c'), nodeFromJson(2));
      expect(
        <String, Node>{
          for (final MapEntry<Path, Node> e in cw.entries) '${e.key}': e.value,
        },
        <String, Node>{'/a': nodeFromJson(1), '/b/c': nodeFromJson(2)},
      );
    });

    test('childCompoundWrites splits by immediate child', () {
      final CompoundWrite cw = CompoundWrite.empty
          .addWrite(Path('a/x'), nodeFromJson(1))
          .addWrite(Path('b'), nodeFromJson(2));
      final Map<ChildKey, CompoundWrite> children = cw.childCompoundWrites();
      expect(children.keys, <ChildKey>[ChildKey('a'), ChildKey('b')]);
      expect(
        children[ChildKey('a')]!.getCompleteNode(Path('x')),
        nodeFromJson(1),
      );
      expect(children[ChildKey('b')]!.rootWrite(), nodeFromJson(2));
    });
  });
}
