// Ported from the iOS SDK, FirebaseDatabase/Tests/Unit/FNodeTests.m (firebase-ios-sdk cef246fea,
// Apache-2.0). The cases that duplicate Android's NodeTest are in node_test.dart; this file has the
// equality and hash tests, and the leading-zero value test.
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('leaf node equals and hashCode', () {
    final falseNode = n(false);
    final trueNode = n(true);
    final stringOne = n('one');
    final stringTwo = n('two');
    final zero = n(0);
    final one = n(1);
    final empty1 = n(null);
    final empty2 = n(null);

    expect(falseNode, n(false));
    expect(falseNode.hashCode, n(false).hashCode);
    expect(trueNode, n(true));
    expect(trueNode.hashCode, n(true).hashCode);
    expect(falseNode, isNot(trueNode));
    expect(falseNode, isNot(one));
    expect(falseNode, isNot(stringOne));
    expect(falseNode, isNot(empty1));

    expect(stringOne, n('one'));
    expect(stringOne.hashCode, n('one').hashCode);
    expect(stringOne, isNot(stringTwo));
    expect(stringOne, isNot(empty1));
    expect(stringOne, isNot(one));
    expect(stringOne, isNot(trueNode));

    expect(zero, n(0));
    expect(zero.hashCode, n(0).hashCode);
    expect(zero, isNot(one));
    expect(zero, isNot(empty1));
    expect(zero, isNot(falseNode));

    expect(empty1, empty2);
    expect(empty1.hashCode, empty2.hashCode);
  });

  test('leaf node priorities equals and hashCode', () {
    final oneOne = n(1, 1);
    final stringOne = n('value', 1);
    final oneString = n(1, 'value');
    final stringString = n('value', 'value');

    expect(oneOne, n(1, 1));
    expect(oneOne.hashCode, n(1, 1).hashCode);
    expect(oneOne, isNot(stringOne));
    expect(oneOne, isNot(oneString));
    expect(oneOne, isNot(stringString));

    expect(stringOne, n('value', 1));
    expect(stringOne.hashCode, n('value', 1).hashCode);
    expect(stringOne, isNot(oneOne));
    expect(stringOne, isNot(oneString));
    expect(stringOne, isNot(stringString));

    expect(oneString, n(1, 'value'));
    expect(oneString.hashCode, n(1, 'value').hashCode);
    expect(oneString, isNot(stringOne));
    expect(oneString, isNot(oneOne));
    expect(oneString, isNot(stringString));

    expect(stringString, n('value', 'value'));
    expect(stringString.hashCode, n('value', 'value').hashCode);
    expect(stringString, isNot(stringOne));
    expect(stringString, isNot(oneString));
    expect(stringString, isNot(oneOne));
  });

  test('children node equals and hashCode', () {
    final nodeOne = n({'one': 1, 'two': 2, '.priority': 'prio'});
    var nodeTwo = emptyNode.updateImmediateChild(ck('one'), n(1));
    nodeTwo = nodeTwo.updateImmediateChild(ck('two'), n(2));
    nodeTwo = nodeTwo.updatePriority(n('prio'));

    expect(nodeOne, nodeTwo);
    expect(nodeOne.hashCode, nodeTwo.hashCode);
    expect(nodeOne.updatePriority(emptyNode), isNot(nodeOne));
    expect(nodeOne.updateImmediateChild(ck('one'), emptyNode), isNot(nodeOne));
    expect(nodeOne.updateImmediateChild(ck('one'), n(2)), isNot(nodeOne));
  });

  test('leading zeros work correctly', () {
    final node = n({'1': 1, '01': 2, '001': 3, '0001': 4});
    expect(node.getImmediateChild(ck('1')).toJson(), 1);
    expect(node.getImmediateChild(ck('01')).toJson(), 2);
    expect(node.getImmediateChild(ck('001')).toJson(), 3);
    expect(node.getImmediateChild(ck('0001')).toJson(), 4);
  });

  test('leading zeros are preserved in the value', () {
    final data = {'1': 1, '01': 2, '001': 3, '0001': 4};
    expect(n(data).toJson(), data);
  });

  test('empty node equals empty children node and has the same hashCode', () {
    expect(emptyNode, ChildrenNode.empty);
    expect(emptyNode.hashCode, ChildrenNode.empty.hashCode);
    expect(emptyNode.isEmpty, isTrue);
  });
}
