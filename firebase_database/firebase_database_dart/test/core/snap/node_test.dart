// Port of JS test/node.test.ts (LeafNode, ChildrenNode, hashes), plus the hash rules measured on
// the emulator (addendum 1) and the memoised value form (addendum 2).
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/comparators.dart';
import 'package:firebase_database_dart/src/core/snap/index_map.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/priority_index.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/value_index.dart';
import 'package:firebase_database_dart/src/core/snap/leaf_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/util/sorted_map.dart';
import 'package:test/test.dart';

ChildKey k(String name) => ChildKey(name);

void main() {
  group('LeafNode', () {
    test('create leaf nodes of various types', () {
      LeafNode x = LeafNode(5, LeafNode(42));
      expect(x.value, 5);
      expect(x.priority.value, 42);
      expect(x.isLeafNode, isTrue);
      expect(x.leafType, LeafType.number);

      x = LeafNode('test');
      expect(x.value, 'test');
      expect(x.leafType, LeafType.string);
      x = LeafNode(true);
      expect(x.value, true);
      expect(x.leafType, LeafType.boolean);
      x = LeafNode(<String, Object?>{'.sv': 'timestamp'});
      expect(x.leafType, LeafType.deferredValue);
    });

    test('updatePriority returns a new leaf without changing the old', () {
      final LeafNode x = LeafNode('test', LeafNode(42));
      final Node y = x.updatePriority(LeafNode(187));
      expect(x.value, 'test');
      expect(x.priority.value, 42);
      expect((y as LeafNode).value, 'test');
      expect(y.priority.value, 187);
    });

    test('updateImmediateChild returns a new children node', () {
      final LeafNode x = LeafNode('test', LeafNode(42));
      final Node y = x.updateImmediateChild(k('test'), LeafNode('foo'));
      expect(y.isLeafNode, isFalse);
      expect(y.priority.value, 42);
      expect((y.getImmediateChild(k('test')) as LeafNode).value, 'foo');
    });

    test('getImmediateChild and getChild return the empty node', () {
      final LeafNode x = LeafNode('test');
      expect(
        identical(x.getImmediateChild(k('foo')), ChildrenNode.empty),
        isTrue,
      );
      expect(
        identical(x.getChild(Path('foo/bar')), ChildrenNode.empty),
        isTrue,
      );
      expect(x.getChild(Path.empty), same(x));
    });

    test('an invalid priority is rejected', () {
      expect(() => LeafNode(1, LeafNode(true)), throwsStateError);
      expect(
        () => LeafNode(1, LeafNode('p', LeafNode('pp'))),
        throwsStateError,
      );
    });

    test('ordering: deferred < boolean < number < string; empty first', () {
      final List<Node> ordered = <Node>[
        LeafNode(<String, Object?>{'.sv': 'timestamp'}),
        LeafNode(false),
        LeafNode(true),
        LeafNode(-1.5),
        LeafNode(0),
        LeafNode(2),
        LeafNode('a'),
        LeafNode('b'),
      ];
      for (int i = 0; i < ordered.length - 1; i++) {
        expect(ordered[i].compareTo(ordered[i + 1]), lessThan(0));
        expect(ordered[i + 1].compareTo(ordered[i]), greaterThan(0));
        expect(LeafNode(1).compareTo(ChildrenNode.empty), 1);
      }
      expect(LeafNode(0).compareTo(LeafNode(-0.0)), 0);
      expect(
        LeafNode(1).compareTo(nodeFromJson(<String, Object?>{'a': 1})),
        -1,
      );
      expect(LeafNode(1).compareTo(MaxNode.instance), -1);
    });

    test('equality', () {
      expect(LeafNode(1), LeafNode(1.0));
      expect(LeafNode(1).hashCode, LeafNode(1.0).hashCode);
      expect(LeafNode('a', LeafNode(1)), LeafNode('a', LeafNode(1)));
      expect(LeafNode('a', LeafNode(1)), isNot(LeafNode('a', LeafNode(2))));
      expect(LeafNode('1'), isNot(LeafNode(1)));
    });
  });

  group('ChildrenNode', () {
    test('updatePriority shares the children', () {
      final Node x = ChildrenNode.empty.updateImmediateChild(
        k('child'),
        LeafNode(5),
      );
      final SortedMap<ChildKey, Node> children = (x as ChildrenNode).children;
      final Node y = x.updatePriority(LeafNode(17));
      expect((y as ChildrenNode).children, same(children));
      expect(x.priority.value, isNull);
      expect(y.priority.value, 17);
    });

    test('updateImmediateChild leaves the old node unchanged', () {
      final SortedMap<ChildKey, Node> children = SortedMap<ChildKey, Node>(
        nameComparator,
      );
      final ChildrenNode x = ChildrenNode(
        children,
        ChildrenNode.empty,
        IndexMap.defaultMap,
      );
      final LeafNode newValue = LeafNode('new value');
      final Node y = x.updateImmediateChild(k('test'), newValue);
      expect(x.children, same(children));
      expect((y as ChildrenNode).children[k('test')], same(newValue));
    });

    test('updateChild leaves the old node unchanged', () {
      final SortedMap<ChildKey, Node> children = SortedMap<ChildKey, Node>(
        nameComparator,
      );
      final ChildrenNode x = ChildrenNode(
        children,
        ChildrenNode.empty,
        IndexMap.defaultMap,
      );
      final LeafNode newValue = LeafNode('new value');
      final Node y = x.updateChild(Path('test/foo'), newValue);
      expect(x.children, same(children));
      expect(y.getChild(Path('test/foo')), same(newValue));
    });

    test('an empty node cannot have a priority', () {
      expect(
        () => ChildrenNode(
          SortedMap<ChildKey, Node>(nameComparator),
          LeafNode(1),
          IndexMap.defaultMap,
        ),
        throwsStateError,
      );
      expect(
        ChildrenNode.empty.updatePriority(LeafNode(1)),
        same(ChildrenNode.empty),
      );
    });

    test('getPredecessorChildKey in key order', () {
      final Node node = nodeFromJson(<String, Object?>{
        'd': true,
        'a': true,
        'g': true,
        'c': true,
        'e': true,
      });
      Node child(String name) => node.getImmediateChild(k(name));
      expect(
        node.getPredecessorChildKey(k('a'), child('a'), priorityIndex),
        isNull,
      );
      expect(
        node.getPredecessorChildKey(k('c'), child('c'), priorityIndex),
        k('a'),
      );
      expect(
        node.getPredecessorChildKey(k('d'), child('d'), priorityIndex),
        k('c'),
      );
      expect(
        node.getPredecessorChildKey(k('e'), child('e'), priorityIndex),
        k('d'),
      );
      expect(
        node.getPredecessorChildKey(k('g'), child('g'), priorityIndex),
        k('e'),
      );
    });

    test('getPredecessorChildKey in priority order', () {
      final Node node = nodeFromJson(<String, Object?>{
        'd': <String, Object?>{'.value': true, '.priority': 22},
        'a': <String, Object?>{'.value': true, '.priority': 25},
        'g': <String, Object?>{'.value': true, '.priority': 19},
        'c': <String, Object?>{'.value': true, '.priority': 23},
        'e': <String, Object?>{'.value': true, '.priority': 21},
      });
      ChildKey? pred(String name) => node.getPredecessorChildKey(
        k(name),
        node.getImmediateChild(k(name)),
        priorityIndex,
      );
      expect(pred('a'), k('c'));
      expect(pred('c'), k('d'));
      expect(pred('d'), k('e'));
      expect(pred('e'), k('g'));
      expect(pred('g'), isNull);
    });

    test('updateImmediateChild on a node sorted by priority', () {
      Node node = nodeFromJson(<String, Object?>{
        'd': <String, Object?>{'.value': true, '.priority': 22},
        'a': <String, Object?>{'.value': true, '.priority': 25},
        'g': <String, Object?>{'.value': true, '.priority': 19},
        'c': <String, Object?>{'.value': true, '.priority': 23},
        'e': <String, Object?>{'.value': true, '.priority': 21},
        '.priority': 1000,
      });
      node = node.updateImmediateChild(k('c'), nodeFromJson(false));
      expect((node.getImmediateChild(k('c')) as LeafNode).value, false);
      expect(node.getImmediateChild(k('c')).priority.value, isNull);
      expect(node.priority.value, 1000);
      expect(
        (node as ChildrenNode)
            .childrenInOrder(priorityIndex)
            .map((n) => n.name.name),
        <String>['c', 'g', 'e', 'd', 'a'],
      );
    });

    test('removing nodes removes intermediate nodes with no children left', () {
      final Node node = nodeFromJson(<String, Object?>{
        'a': <String, Object?>{
          'b': <String, Object?>{'c': 1},
        },
      });
      expect(
        node.updateChild(Path('a/b/c'), ChildrenNode.empty).isEmpty,
        isTrue,
      );
    });

    test('removing nodes leaves intermediate nodes with other children', () {
      final Node node = nodeFromJson(<String, Object?>{
        'a': <String, Object?>{
          'b': <String, Object?>{'c': 1},
          'd': 2,
        },
      });
      final Node newNode = node.updateChild(Path('a/b/c'), ChildrenNode.empty);
      expect(newNode.isEmpty, isFalse);
      expect(newNode.getChild(Path('a/b/c')).isEmpty, isTrue);
      expect(newNode.getChild(Path('a/d')).value, 2);
    });

    test('removing nodes leaves other leaf nodes', () {
      final Node node = nodeFromJson(<String, Object?>{
        'a': <String, Object?>{
          'b': <String, Object?>{'c': 1, 'd': 2},
        },
      });
      final Node newNode = node.updateChild(Path('a/b/c'), ChildrenNode.empty);
      expect(newNode.isEmpty, isFalse);
      expect(newNode.getChild(Path('a/b/c')).isEmpty, isTrue);
      expect(newNode.getChild(Path('a/b/d')).value, 2);
    });

    test('removing nodes removes the root', () {
      expect(
        nodeFromJson(null).updateChild(Path.empty, ChildrenNode.empty).isEmpty,
        isTrue,
      );
      expect(
        nodeFromJson(<String, Object?>{
          'a': 1,
        }).updateChild(Path('a'), ChildrenNode.empty).isEmpty,
        isTrue,
      );
    });

    test("updating empty children doesn't overwrite a leaf node", () {
      final Node empty = ChildrenNode.empty;
      final Node node = nodeFromJson('value');
      expect(node.updateChild(Path('.priority'), empty), node);
      expect(node.updateChild(Path('child'), empty), node);
      expect(node.updateChild(Path('child/.priority'), empty), node);
      expect(node.updateImmediateChild(k('child'), empty), node);
      expect(node.updateImmediateChild(ChildKey.priority, empty), node);
    });

    test('equality ignores construction order', () {
      final Node a = nodeFromJson(<String, Object?>{'x': 1, 'y': 2});
      final Node b = ChildrenNode.empty
          .updateImmediateChild(k('y'), LeafNode(2))
          .updateImmediateChild(k('x'), LeafNode(1));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(nodeFromJson(<String, Object?>{'x': 1})));
      expect(ChildrenNode.empty, isNot(MaxNode.instance));
      expect(MaxNode.instance, MaxNode.instance);
    });

    test('compareTo', () {
      final Node children = nodeFromJson(<String, Object?>{'a': 1});
      expect(ChildrenNode.empty.compareTo(ChildrenNode.empty), 0);
      expect(ChildrenNode.empty.compareTo(LeafNode(1)), -1);
      expect(children.compareTo(LeafNode(1)), 1);
      expect(children.compareTo(ChildrenNode.empty), 1);
      expect(children.compareTo(MaxNode.instance), -1);
      expect(children.compareTo(nodeFromJson(<String, Object?>{'b': 2})), 0);
      expect(MaxNode.instance.compareTo(children), 1);
      expect(MaxNode.instance.compareTo(MaxNode.instance), 0);
    });

    test('forEachChild on an index that was never added throws', () {
      final Node node = nodeFromJson(<String, Object?>{'a': 1});
      expect(
        () => node.forEachChild(valueIndex, (ChildKey key, Node n) => false),
        throwsStateError,
      );
      expect(node.isIndexed(valueIndex), isFalse);
      expect(node.withIndex(valueIndex).isIndexed(valueIndex), isTrue);
    });
  });

  group('hash', () {
    test('matches the JS SDK', () {
      final Node node = nodeFromJson(<String, Object?>{
        'intNode': 4,
        'doubleNode': 4.5623,
        'stringNode': 'hey guys',
        'boolNode': true,
      });
      // These hashes must match what the server generates.
      expect(
        node.getImmediateChild(k('intNode')).hash(),
        'eVih19a6ZDz3NL32uVBtg9KSgQY=',
      );
      expect(
        node.getImmediateChild(k('doubleNode')).hash(),
        'vf1CL0tIRwXXunHcG/irRECk3lY=',
      );
      expect(
        node.getImmediateChild(k('stringNode')).hash(),
        'CUNLXWpCVoJE6z7z1vE57lGaKAU=',
      );
      expect(
        node.getImmediateChild(k('boolNode')).hash(),
        'E5z61QM0lN/U2WsOnusszCTkR8M=',
      );
      expect(node.hash(), '6Mc4jFmNdrLVIlJJjz2/MakTK9I=');
    });

    test('with priorities', () {
      final Node node = nodeFromJson(<String, Object?>{
        'root': <String, Object?>{
          'c': <String, Object?>{'.value': 99, '.priority': 'abc'},
          '.priority': 'def',
        },
      });
      expect(node.hash(), 'Fm6tzN4CVEu5WxFDZUdTtqbTVaA=');
    });

    test('with number priorities', () {
      final Node node = nodeFromJson(<String, Object?>{
        'root': <String, Object?>{
          'c': <String, Object?>{'.value': 99, '.priority': 42},
          '.priority': 3.14,
        },
      });
      expect(node.hash(), 'B15QCqrzCxrI5zz1y00arWqFRFg=');
    });

    test('stress', () {
      final Node node = nodeFromJson(<String, Object?>{
        'a': -1.7976931348623157e308,
        'b': 1.7976931348623157e308,
        'c': 'unicode ✔ 🐵 🌴 x͢',
        'd': 3.1415926535897932384626433832795,
        'e': <String, Object?>{'.value': 12345678901234568, '.priority': '🐵'},
        '✔': 'foo',
        '.priority': '✔',
      });
      expect(
        node.getImmediateChild(k('a')).hash(),
        '7HxgOBDEC92uQwhCuuvKA2rbXDA=',
      );
      expect(
        node.getImmediateChild(k('b')).hash(),
        '8R+ekVQmxs6ZWP0fdzFHxVeGnWo=',
      );
      expect(
        node.getImmediateChild(k('c')).hash(),
        'JoKoFUnbmg3/DlY70KaDWslfYPk=',
      );
      expect(
        node.getImmediateChild(k('d')).hash(),
        'Y41iC5+92GIqXfabOm33EanRI8s=',
      );
      expect(
        node.getImmediateChild(k('e')).hash(),
        '+E+Mxlqh5MhT+On05bjsZ6JaaxI=',
      );
      expect(
        node.getImmediateChild(k('✔')).hash(),
        'MRRL/+aA/uibaL//jghUpxXS/uY=',
      );
      expect(node.hash(), 'CyC0OU8GSkOAKnsPjheWtWC0Yxo=');
    });

    test('int 1 and double 1.0 hash the same', () {
      expect(LeafNode(1).hash(), LeafNode(1.0).hash());
      expect(LeafNode(1).hash(), 'YPVfR2bXt/lcDjiQZ8pOkAd3qkQ=');
      expect(
        nodeFromJson(<String, Object?>{'a': 1}).hash(),
        nodeFromJson(<String, Object?>{'a': 1.0}).hash(),
      );
    });

    test('-0.0 from the server keeps its sign bit', () {
      final LeafNode node = nodeFromJson(-0.0) as LeafNode;
      expect(node.hashText(), 'number:8000000000000000');
      expect(node.hash(), 'm/gA365Q5OBo06Bg8wdybAAiMSQ=');
      expect(node.hash(), isNot(LeafNode(0).hash()));
      final Object v = node.value;
      expect(v is double && v.isNegative && v == 0, isTrue);
    });

    test('the empty node hashes to the empty string', () {
      expect(ChildrenNode.empty.hash(), '');
    });

    test('a deferred value hashes as JS concatenates an object', () {
      expect(
        LeafNode(<String, Object?>{'.sv': 'timestamp'}).hashText(),
        'object:[object Object]',
      );
    });

    test('is memoised', () {
      final Node node = nodeFromJson(<String, Object?>{'a': 1});
      expect(identical(node.hash(), node.hash()), isTrue);
    });
  });
}
