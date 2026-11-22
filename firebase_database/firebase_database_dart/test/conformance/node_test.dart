// Ported from the Android SDK, firebase-database/src/test/java/com/google/firebase/database/snapshot/NodeTest.java
// (firebase-android-sdk 2cfdd0389, Apache-2.0).
//
// Android keeps `LongNode` and `DoubleNode`; the skeleton has one number leaf with the JS rule, so
// values are compared as `num` (`1` for `1L`).
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/comparators.dart';
import 'package:firebase_database_dart/src/core/snap/index_map.dart';
import 'package:firebase_database_dart/src/core/snap/leaf_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/priority.dart';
import 'package:firebase_database_dart/src/core/util/sorted_map.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('getHash works correctly', () {
    final node = n({
      'intNode': 4,
      'doubleNode': 4.5623,
      'stringNode': 'hey guys',
      'boolNode': true,
    });

    expect(
      node.getImmediateChild(ck('intNode')).hash(),
      'eVih19a6ZDz3NL32uVBtg9KSgQY=',
    );
    expect(
      node.getImmediateChild(ck('doubleNode')).hash(),
      'vf1CL0tIRwXXunHcG/irRECk3lY=',
    );
    expect(
      node.getImmediateChild(ck('stringNode')).hash(),
      'CUNLXWpCVoJE6z7z1vE57lGaKAU=',
    );
    expect(
      node.getImmediateChild(ck('boolNode')).hash(),
      'E5z61QM0lN/U2WsOnusszCTkR8M=',
    );
    expect(node.hash(), '6Mc4jFmNdrLVIlJJjz2/MakTK9I=');
  });

  test('matchServerHash', () {
    final node = n({
      'c': {'.value': 99, '.priority': 'abc'},
      '.priority': 'def',
    });
    final root = emptyNode.updateChild(p('root'), node);
    expect(root.hash(), 'Fm6tzN4CVEu5WxFDZUdTtqbTVaA=');
  });

  test('leading zeroes work correctly', () {
    final node = n({'1': 1, '01': 2, '001': 3, '0001': 4});

    expect(node.getImmediateChild(ck('1')).toJson(), 1);
    expect(node.getImmediateChild(ck('01')).toJson(), 2);
    expect(node.getImmediateChild(ck('001')).toJson(), 3);
    expect(node.getImmediateChild(ck('0001')).toJson(), 4);
  });

  test('leading zeros do not overwrite other keys', () {
    final node = n({
      '1': 'value1',
      '01': 'value2',
      '001': 'value3',
      '0001': 'value4',
    });

    expect(node.getImmediateChild(ck('1')).toJson(), 'value1');
    expect(node.getImmediateChild(ck('01')).toJson(), 'value2');
    expect(node.getImmediateChild(ck('001')).toJson(), 'value3');
    expect(node.getImmediateChild(ck('0001')).toJson(), 'value4');
  });

  test('leading zeros do not overwrite keys in value', () {
    // Under the JS rule '01' is not an integer key, so no array conversion.
    final data = {'1': 'value1', '01': 'value2'};
    expect(n(data).toJson(), data);
  });

  test('empty node equals empty children node', () {
    final children = ChildrenNode(
      SortedMap<ChildKey, Node>(nameComparator),
      null,
      IndexMap.defaultMap,
    );
    expect(emptyNode, children);
    expect(children, emptyNode);
  });

  test('updating empty children does not overwrite a leaf node', () {
    final Node node = LeafNode('value', emptyNode);
    expect(node.updateChild(p('.priority'), emptyNode), node);
    expect(node.updateChild(p('child'), emptyNode), node);
    expect(node.updateChild(p('child/.priority'), emptyNode), node);
    expect(node.updateImmediateChild(ck('child'), emptyNode), node);
    expect(node.updateImmediateChild(ChildKey.priority, emptyNode), node);
  });

  test('updating priorities on empty nodes is a no-op', () {
    final priority = parsePriority('prio');
    expect(emptyNode.updatePriority(priority).priority.isEmpty, isTrue);
    expect(
      emptyNode.updateChild(p('.priority'), priority).priority.isEmpty,
      isTrue,
    );
    expect(
      emptyNode
          .updateImmediateChild(ChildKey.priority, priority)
          .priority
          .isEmpty,
      isTrue,
    );

    final reemptied = emptyNode
        .updateChild(p('child'), n('value'))
        .updateChild(p('child'), emptyNode);
    expect(reemptied.updatePriority(priority).priority.isEmpty, isTrue);
    expect(
      reemptied.updateChild(p('.priority'), priority).priority.isEmpty,
      isTrue,
    );
    expect(
      reemptied
          .updateImmediateChild(ChildKey.priority, priority)
          .priority
          .isEmpty,
      isTrue,
    );
  });

  test('deleting the last child from a children node removes the priority', () {
    final priority = parsePriority('prio');
    final withPriority = emptyNode
        .updateChild(p('child'), n('value'))
        .updatePriority(priority);
    expect(withPriority.priority, priority);
    final deleted = withPriority.updateChild(p('child'), emptyNode);
    expect(deleted.priority.isEmpty, isTrue);
  });

  test('nodeFromJson returns empty nodes without priority', () {
    final empty1 = n({'.priority': 'prio'});
    expect(empty1.priority.isEmpty, isTrue);

    final empty2 = n({'dummy-node': null, '.priority': 'prio'});
    expect(empty2.priority.isEmpty, isTrue);
  });
}
