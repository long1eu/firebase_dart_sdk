// Ported from the Android SDK, firebase-database/src/test/java/com/google/firebase/database/core/CompoundWriteTest.java
// (firebase-android-sdk 2cfdd0389, Apache-2.0). The iOS twin (FCompoundWriteTest.m) repeats these
// cases; its differing ones are in f_compound_write_test.dart.
import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/leaf_node.dart';
import 'package:firebase_database_dart/src/core/snap/named_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:test/test.dart';

import 'support.dart';

final Node _leaf = n('leaf-node');
final Node _prio = n('prio');
final Map<String, Object?> _base = {'child-1': 'value-1', 'child-2': 'value-2'};

void _expectPriority(CompoundWrite write, Node node, Node priority) {
  if (node.isEmpty) {
    expect(write.apply(node), emptyNode);
  } else {
    expect(write.apply(node), node.updatePriority(priority));
  }
}

void main() {
  test('empty merge is empty', () {
    expect(CompoundWrite.empty.isEmpty, isTrue);
  });

  test('compound write with priority update is not empty', () {
    expect(
      CompoundWrite.empty.addChildWrite(ChildKey.priority, _prio).isEmpty,
      isFalse,
    );
  });

  test('compound write with update is not empty', () {
    expect(CompoundWrite.empty.addWrite(p('foo/bar'), _leaf).isEmpty, isFalse);
  });

  test('compound write with root update is not empty', () {
    expect(CompoundWrite.empty.addWrite(Path.empty, _leaf).isEmpty, isFalse);
  });

  test('compound write with empty root update is not empty', () {
    expect(
      CompoundWrite.empty.addWrite(Path.empty, emptyNode).isEmpty,
      isFalse,
    );
  });

  test(
    'compound write with root priority update and child merge is not empty',
    () {
      final write = CompoundWrite.empty.addChildWrite(ChildKey.priority, _prio);
      expect(write.childCompoundWrite(p('.priority')).isEmpty, isFalse);
    },
  );

  test('applies leaf overwrite', () {
    final write = CompoundWrite.empty.addWrite(Path.empty, _leaf);
    expect(write.apply(emptyNode), _leaf);
  });

  test('applies children overwrite', () {
    final childNode = emptyNode.updateImmediateChild(ck('child'), _leaf);
    final write = CompoundWrite.empty.addWrite(Path.empty, childNode);
    expect(write.apply(emptyNode), childNode);
  });

  test('adds child node', () {
    final key = ck('child');
    final expected = emptyNode.updateImmediateChild(key, _leaf);
    final write = CompoundWrite.empty.addChildWrite(key, _leaf);
    expect(write.apply(emptyNode), expected);
  });

  test('adds deep child node', () {
    final path = p('deep/deep/node');
    final expected = emptyNode.updateChild(path, _leaf);
    final write = CompoundWrite.empty.addWrite(path, _leaf);
    expect(write.apply(emptyNode), expected);
  });

  test('overwrites existing child', () {
    final baseNode = n(_base);
    final path = p('child-1');
    final write = CompoundWrite.empty.addWrite(path, _leaf);
    expect(
      write.apply(baseNode),
      baseNode.updateImmediateChild(path.front!, _leaf),
    );
  });

  test('updates existing child', () {
    final baseNode = n(_base);
    final path = p('child-1/foo');
    final write = CompoundWrite.empty.addWrite(path, _leaf);
    expect(write.apply(baseNode), baseNode.updateChild(path, _leaf));
  });

  test('does not update priority on empty node', () {
    final write = CompoundWrite.empty.addChildWrite(
      ChildKey.priority,
      n('prio'),
    );
    _expectPriority(write, emptyNode, emptyNode);
  });

  test('updates priority on node', () {
    final write = CompoundWrite.empty.addChildWrite(ChildKey.priority, _prio);
    _expectPriority(write, n('value'), _prio);
  });

  test('updates priority of child', () {
    final baseNode = n(_base);
    final path = p('child-1/.priority');
    final write = CompoundWrite.empty.addWrite(path, _prio);
    expect(write.apply(baseNode), baseNode.updateChild(path, _prio));
  });

  test('does not update priority of non-existent child', () {
    final baseNode = n(_base);
    final write = CompoundWrite.empty.addWrite(p('child-3/.priority'), _prio);
    expect(write.apply(baseNode), baseNode);
  });

  test('priority update on previous empty child write is ignored', () {
    var write = CompoundWrite.empty.addChildWrite(ck('child'), emptyNode);
    write = write.addWrite(p('child/.priority'), _prio);
    final applied = write.apply(emptyNode);
    expect(applied.getChild(p('child')).priority, emptyNode);
    expect(write.getCompleteNode(p('child'))!.priority, emptyNode);
    for (final NamedNode node in write.getCompleteChildren()) {
      expect(node.node.priority, emptyNode);
    }
  });

  test('deep update existing updates', () {
    final baseNode = n(_base);
    final updateOne = n({'foo': 'foo-value', 'bar': 'bar-value'});
    final updateTwo = n('baz-value');
    final updateThree = n('new-foo-value');
    var write = CompoundWrite.empty.addWrite(p('child-1'), updateOne);
    write = write.addWrite(p('child-1/baz'), updateTwo);
    write = write.addWrite(p('child-1/foo'), updateThree);
    final expected = baseNode.updateImmediateChild(
      ck('child-1'),
      n({'foo': 'new-foo-value', 'bar': 'bar-value', 'baz': 'baz-value'}),
    );
    expect(write.apply(baseNode), expected);
  });

  test('shallow update removes deep update', () {
    final baseNode = n(_base);
    final updateOne = n('new-foo-value');
    final updateTwo = n('baz-value');
    final updateThree = n({'foo': 'foo-value', 'bar': 'bar-value'});
    var write = CompoundWrite.empty.addWrite(p('child-1/foo'), updateOne);
    write = write.addWrite(p('child-1/baz'), updateTwo);
    write = write.addWrite(p('child-1'), updateThree);
    final expected = baseNode.updateImmediateChild(
      ck('child-1'),
      n({'foo': 'foo-value', 'bar': 'bar-value'}),
    );
    expect(write.apply(baseNode), expected);
  });

  test('child priority does not update empty node priority on child merge', () {
    final write = CompoundWrite.empty.addWrite(p('child-1/.priority'), _prio);
    _expectPriority(
      write.childCompoundWrite(p('child-1')),
      emptyNode,
      emptyNode,
    );
  });

  test('child priority updates priority on child merge', () {
    final write = CompoundWrite.empty.addWrite(p('child-1/.priority'), _prio);
    _expectPriority(write.childCompoundWrite(p('child-1')), n('value'), _prio);
  });

  test('child priority updates empty priority on child merge', () {
    final write = CompoundWrite.empty.addWrite(
      p('child-1/.priority'),
      emptyNode,
    );
    final node = LeafNode('foo', _prio);
    _expectPriority(write.childCompoundWrite(p('child-1')), node, emptyNode);
  });

  test('deep priority set works on empty node when other set is available', () {
    var write = CompoundWrite.empty.addWrite(p('foo/.priority'), _prio);
    write = write.addWrite(p('foo/child'), _leaf);
    final node = write.apply(emptyNode);
    expect(node.getChild(p('foo')).priority, _prio);
  });

  test('child merge looks into update node', () {
    final update = n({'foo': 'foo-value', 'bar': 'bar-value'});
    final write = CompoundWrite.empty.addWrite(Path.empty, update);
    expect(write.childCompoundWrite(p('foo')).apply(emptyNode), n('foo-value'));
  });

  test('child merge removes node on deeper paths', () {
    final update = n({'foo': 'foo-value', 'bar': 'bar-value'});
    final write = CompoundWrite.empty.addWrite(Path.empty, update);
    expect(
      write.childCompoundWrite(p('foo/not/existing')).apply(_leaf),
      emptyNode,
    );
  });

  test('child merge with empty path is same merge', () {
    final update = n({'foo': 'foo-value', 'bar': 'bar-value'});
    final write = CompoundWrite.empty.addWrite(Path.empty, update);
    expect(identical(write, write.childCompoundWrite(Path.empty)), isTrue);
  });

  test('root update removes root priority', () {
    var write = CompoundWrite.empty.addWrite(p('.priority'), _prio);
    write = write.addWrite(Path.empty, n('foo'));
    expect(write.apply(emptyNode), n('foo'));
  });

  test('deep update removes priority there', () {
    var write = CompoundWrite.empty.addWrite(p('foo/.priority'), _prio);
    write = write.addWrite(p('foo'), n('bar'));
    expect(write.apply(emptyNode), n({'foo': 'bar'}));
  });

  test('adding updates at path works', () {
    final updates = CompoundWrite.fromChildMerge({
      ck('foo'): n('foo-value'),
      ck('bar'): n('bar-value'),
    });
    final write = CompoundWrite.empty.addWrites(p('child-1'), updates);
    final baseNode = n(_base);
    final expected = baseNode.updateImmediateChild(
      ck('child-1'),
      n({'foo': 'foo-value', 'bar': 'bar-value'}),
    );
    expect(write.apply(baseNode), expected);
  });

  test('adding updates at root works', () {
    final updates = CompoundWrite.fromChildMerge({
      ck('child-1'): n('new-value-1'),
      ck('child-2'): emptyNode,
      ck('child-3'): n('value-3'),
    });
    final write = CompoundWrite.empty.addWrites(Path.empty, updates);
    expect(
      write.apply(n(_base)),
      n({'child-1': 'new-value-1', 'child-3': 'value-3'}),
    );
  });

  test('child merge of root priority works', () {
    final write = CompoundWrite.empty.addWrite(p('.priority'), _prio);
    expect(write.childCompoundWrite(p('.priority')).apply(emptyNode), _prio);
  });

  test('complete children only returns complete overwrites', () {
    final write = CompoundWrite.empty.addWrite(p('child-1'), _leaf);
    expect(write.getCompleteChildren(), [NamedNode(ck('child-1'), _leaf)]);
  });

  test('complete children only returns empty overwrites', () {
    final write = CompoundWrite.empty.addWrite(p('child-1'), emptyNode);
    expect(write.getCompleteChildren(), [NamedNode(ck('child-1'), emptyNode)]);
  });

  test('complete children does not return deep overwrites', () {
    final write = CompoundWrite.empty.addWrite(p('child-1/deep/path'), _leaf);
    expect(write.getCompleteChildren(), isEmpty);
  });

  test('complete children return all complete children but no incomplete', () {
    var write = CompoundWrite.empty.addWrite(p('child-1/deep/path'), _leaf);
    write = write.addWrite(p('child-2'), _leaf);
    write = write.addWrite(p('child-3'), emptyNode);
    final actual = {
      for (final node in write.getCompleteChildren()) node.name: node.node,
    };
    expect(actual, {ck('child-2'): _leaf, ck('child-3'): emptyNode});
  });

  test('complete children return all children for root set', () {
    final write = CompoundWrite.empty.addWrite(Path.empty, n(_base));
    final actual = {
      for (final node in write.getCompleteChildren()) node.name: node.node,
    };
    expect(actual, {ck('child-1'): n('value-1'), ck('child-2'): n('value-2')});
  });

  test('empty merge has no shadowing write', () {
    expect(CompoundWrite.empty.hasCompleteWrite(Path.empty), isFalse);
  });

  test('compound write with empty root has shadowing write', () {
    final write = CompoundWrite.empty.addWrite(Path.empty, emptyNode);
    expect(write.hasCompleteWrite(Path.empty), isTrue);
    expect(write.hasCompleteWrite(p('child')), isTrue);
  });

  test('compound write with root has shadowing write', () {
    final write = CompoundWrite.empty.addWrite(Path.empty, _leaf);
    expect(write.hasCompleteWrite(Path.empty), isTrue);
    expect(write.hasCompleteWrite(p('child')), isTrue);
  });

  test('compound write with deep update has shadowing write', () {
    final write = CompoundWrite.empty.addWrite(p('deep/update'), _leaf);
    expect(write.hasCompleteWrite(Path.empty), isFalse);
    expect(write.hasCompleteWrite(p('deep')), isFalse);
    expect(write.hasCompleteWrite(p('deep/update')), isTrue);
  });

  test('compound write with priority update has shadowing write', () {
    final write = CompoundWrite.empty.addWrite(p('.priority'), _prio);
    expect(write.hasCompleteWrite(Path.empty), isFalse);
    expect(write.hasCompleteWrite(p('.priority')), isTrue);
  });

  test('updates can be removed', () {
    final baseNode = n(_base);
    final update = n({'foo': 'foo-value', 'bar': 'bar-value'});
    var write = CompoundWrite.empty.addWrite(p('child-1'), update);
    write = write.removeWrite(p('child-1'));
    expect(write.apply(baseNode), baseNode);
  });

  CompoundWrite deepWrites() {
    var write = CompoundWrite.empty.addWrite(
      p('child-1'),
      n({'foo': 'foo-value', 'bar': 'bar-value'}),
    );
    write = write.addWrite(p('child-1/baz'), n('baz-value'));
    write = write.addWrite(p('child-1/foo'), n('new-foo-value'));
    return write;
  }

  test('deep removes have no effect on overlaying set', () {
    final baseNode = n(_base);
    final write = deepWrites().removeWrite(p('child-1/foo'));
    final expected = baseNode.updateImmediateChild(
      ck('child-1'),
      n({'foo': 'new-foo-value', 'bar': 'bar-value', 'baz': 'baz-value'}),
    );
    expect(write.apply(baseNode), expected);
  });

  test('remove at path without set is without effect', () {
    final baseNode = n(_base);
    final write = deepWrites().removeWrite(p('child-2'));
    final expected = baseNode.updateImmediateChild(
      ck('child-1'),
      n({'foo': 'new-foo-value', 'bar': 'bar-value', 'baz': 'baz-value'}),
    );
    expect(write.apply(baseNode), expected);
  });

  test('can remove priority', () {
    var write = CompoundWrite.empty.addWrite(p('.priority'), _prio);
    write = write.removeWrite(p('.priority'));
    _expectPriority(write, _leaf, emptyNode);
  });

  test('removing only affects removed path', () {
    final updates = CompoundWrite.fromChildMerge({
      ck('child-1'): n('new-value-1'),
      ck('child-2'): emptyNode,
      ck('child-3'): n('value-3'),
    });
    var write = CompoundWrite.empty.addWrites(Path.empty, updates);
    write = write.removeWrite(p('child-2'));
    expect(
      write.apply(n(_base)),
      n({'child-1': 'new-value-1', 'child-2': 'value-2', 'child-3': 'value-3'}),
    );
  });

  test('remove removes all deeper sets', () {
    final baseNode = n(_base);
    var write = CompoundWrite.empty.addWrite(p('child-1/baz'), n('baz-value'));
    write = write.addWrite(p('child-1/foo'), n('new-foo-value'));
    write = write.removeWrite(p('child-1'));
    expect(write.apply(baseNode), baseNode);
  });

  test('remove at root also removes priority', () {
    var write = CompoundWrite.empty.addWrite(
      Path.empty,
      LeafNode('foo', _prio),
    );
    write = write.removeWrite(Path.empty);
    _expectPriority(write, n('value'), emptyNode);
  });

  test('updating priority does not overwrite leaf node', () {
    var write = CompoundWrite.empty.addWrite(Path.empty, _leaf);
    write = write.addWrite(p('child/.priority'), _prio);
    expect(write.apply(emptyNode), _leaf);
  });

  test('updating empty node does not overwrite leaf node', () {
    var write = CompoundWrite.empty.addWrite(Path.empty, _leaf);
    write = write.addWrite(p('child'), emptyNode);
    expect(write.apply(emptyNode), _leaf);
  });
}
