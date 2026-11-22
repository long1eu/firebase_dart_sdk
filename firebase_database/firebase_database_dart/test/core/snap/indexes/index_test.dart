// The four indexes (JS indexes/*.ts), IndexMap upkeep and iteration of a children node by index.
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/child_set.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/comparators.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/index.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/key_index.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/path_index.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/priority_index.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/value_index.dart';
import 'package:firebase_database_dart/src/core/snap/leaf_node.dart';
import 'package:firebase_database_dart/src/core/snap/named_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/util/sorted_map.dart';
import 'package:test/test.dart';

ChildKey k(String name) => ChildKey(name);

List<String> names(Iterable<NamedNode> nodes) =>
    nodes.map((NamedNode n) => n.name.name).toList();

void main() {
  final Node scores = nodeFromJson(<String, Object?>{
    'a': <String, Object?>{'score': 3, '.priority': 'z'},
    'b': <String, Object?>{'score': 1, '.priority': 1},
    'c': <String, Object?>{'score': 2},
    'd': <String, Object?>{'other': 1},
  });

  test('query definitions and toString', () {
    expect(keyIndex.queryDefinition, '.key');
    expect(priorityIndex.queryDefinition, '.priority');
    expect(valueIndex.queryDefinition, '.value');
    expect(PathIndex(Path('a/b')).queryDefinition, 'a/b');
    expect(PathIndex(Path('a/b')).toString(), 'a/b');
    expect(PathIndex(Path('a/b')), PathIndex(Path('a/b')));
  });

  test('key index orders by key, integers first', () {
    final Node node = nodeFromJson(<String, Object?>{
      'b': 1,
      '10': 1,
      '2': 1,
      'a': 1,
    });
    expect(names((node as ChildrenNode).childrenInOrder(keyIndex)), <String>[
      '2',
      '10',
      'a',
      'b',
    ]);
    expect(keyIndex.indexedValueChanged(LeafNode(1), LeafNode(2)), isFalse);
    expect(keyIndex.makePost(LeafNode('x'), k('ignored')).name, k('x'));
    expect(() => keyIndex.makePost(LeafNode(1), k('a')), throwsArgumentError);
  });

  test('priority index: no priority, numbers, strings', () {
    final ChildrenNode node = scores as ChildrenNode;
    expect(names(node.childrenInOrder(priorityIndex)), <String>[
      'c',
      'd',
      'b',
      'a',
    ]);
    expect(names(node.reverseChildren(priorityIndex)), <String>[
      'a',
      'b',
      'd',
      'c',
    ]);
    expect(priorityIndex.isDefinedOn(node.getImmediateChild(k('c'))), isFalse);
    expect(
      priorityIndex.indexedValueChanged(
        LeafNode(1, LeafNode(1)),
        LeafNode(2, LeafNode(1)),
      ),
      isFalse,
    );
    expect(
      priorityIndex.indexedValueChanged(
        LeafNode(1, LeafNode(1)),
        LeafNode(1, LeafNode(2)),
      ),
      isTrue,
    );
  });

  test('value index orders integers beyond 2^53 exactly', () {
    // Measured on the emulator (probe addendum 4): orderByValue with limitToFirst(1) returns the
    // child holding ...992, not ...993. dart2js cannot tell them apart (web limitation).
    final Node node = nodeFromJson(<String, Object?>{
      'x': int.parse('9007199254740993'),
      'y': int.parse('9007199254740992'),
      'z': 9007199254740994.0,
    }).withIndex(valueIndex);
    expect(names((node as ChildrenNode).childrenInOrder(valueIndex)), <String>[
      'y',
      'x',
      'z',
    ]);
    expect(
      LeafNode(int.parse('9007199254740993')) ==
          LeafNode(int.parse('9007199254740992')),
      isFalse,
    );
  }, testOn: '!js');

  test('value index after withIndex', () {
    final Node node = nodeFromJson(<String, Object?>{
      'a': 'str',
      'b': 2,
      'c': true,
      'd': <String, Object?>{'x': 1},
      'e': 1,
    }).withIndex(valueIndex);
    expect(names((node as ChildrenNode).childrenInOrder(valueIndex)), <String>[
      'c',
      'e',
      'b',
      'a',
      'd',
    ]);
    expect(valueIndex.indexedValueChanged(LeafNode(1), LeafNode(1.0)), isFalse);
    expect(valueIndex.indexedValueChanged(LeafNode(1), LeafNode(2)), isTrue);
  });

  test('path index orders by the child value, missing values first', () {
    final PathIndex index = PathIndex(Path('score'));
    final ChildrenNode node = scores.withIndex(index) as ChildrenNode;
    expect(names(node.childrenInOrder(index)), <String>['d', 'b', 'c', 'a']);
    expect(index.isDefinedOn(node.getImmediateChild(k('d'))), isFalse);
    expect(index.isDefinedOn(node.getImmediateChild(k('a'))), isTrue);
    expect(node.firstChild(index)!.name, k('d'));
    expect(node.lastChild(index)!.name, k('a'));
  });

  test('iteration from a post', () {
    final PathIndex index = PathIndex(Path('score'));
    final ChildrenNode node = scores.withIndex(index) as ChildrenNode;
    final NamedNode start = index.makePost(LeafNode(2), ChildKey.min);
    expect(names(node.childrenFrom(start, index)), <String>['c', 'a']);
    final NamedNode end = index.makePost(LeafNode(2), ChildKey.max);
    expect(names(node.reverseChildrenFrom(end, index)), <String>[
      'c',
      'b',
      'd',
    ]);
    expect(names(node.childrenFrom(index.minPost, index)), <String>[
      'd',
      'b',
      'c',
      'a',
    ]);
    expect(names(node.reverseChildrenFrom(index.maxPost, index)), <String>[
      'a',
      'c',
      'b',
      'd',
    ]);
  });

  test('iteration from a post on the fallback (no priorities)', () {
    final ChildrenNode node =
        nodeFromJson(<String, Object?>{'a': 1, 'b': 2, 'c': 3}) as ChildrenNode;
    expect(node.indexMap.get('.priority'), isNull);
    expect(
      names(
        node.childrenFrom(NamedNode(k('b'), ChildrenNode.empty), priorityIndex),
      ),
      <String>['b', 'c'],
    );
    expect(
      names(
        node.reverseChildrenFrom(
          NamedNode(k('b'), ChildrenNode.empty),
          priorityIndex,
        ),
      ),
      <String>['b', 'a'],
    );
    expect(
      names(node.childrenFrom(priorityIndex.minPost, priorityIndex)),
      <String>['a', 'b', 'c'],
    );
    expect(
      names(node.reverseChildrenFrom(priorityIndex.maxPost, priorityIndex)),
      <String>['c', 'b', 'a'],
    );
  });

  test('index upkeep through updates', () {
    final PathIndex index = PathIndex(Path('score'));
    Node node = scores.withIndex(index);
    node = node.updateChild(Path('d/score'), LeafNode(0));
    expect(names((node as ChildrenNode).childrenInOrder(index)), <String>[
      'd',
      'b',
      'c',
      'a',
    ]);
    node = node.updateChild(Path('a/score'), LeafNode(-1));
    expect(names((node as ChildrenNode).childrenInOrder(index)), <String>[
      'a',
      'd',
      'b',
      'c',
    ]);
    node = node.updateImmediateChild(k('d'), ChildrenNode.empty);
    expect(names((node as ChildrenNode).childrenInOrder(index)), <String>[
      'a',
      'b',
      'c',
    ]);
    expect(node.isIndexed(index), isTrue);
    // The priority index is built when the first child gets a priority.
    Node plain = nodeFromJson(<String, Object?>{'x': 1, 'y': 2});
    expect((plain as ChildrenNode).indexMap.get('.priority'), isNull);
    plain = plain.updateImmediateChild(k('y'), LeafNode(2, LeafNode(-5)));
    expect((plain as ChildrenNode).indexMap.get('.priority'), isNotNull);
    expect(names(plain.childrenInOrder(priorityIndex)), <String>['x', 'y']);
    expect(
      plain.getPredecessorChildKey(
        k('y'),
        plain.getImmediateChild(k('y')),
        priorityIndex,
      ),
      k('x'),
    );
  });

  test('indexedValueChanged of the base index uses compare', () {
    final Index index = PathIndex(Path('a'));
    expect(
      index.indexedValueChanged(
        nodeFromJson(<String, Object?>{'a': 1, 'b': 1}),
        nodeFromJson(<String, Object?>{'a': 1, 'b': 2}),
      ),
      isFalse,
    );
    expect(
      index.indexedValueChanged(
        nodeFromJson(<String, Object?>{'a': 1}),
        nodeFromJson(<String, Object?>{'a': 2}),
      ),
      isTrue,
    );
  });

  test('min and max posts bound every child', () {
    final NamedNode child = NamedNode(k('m'), LeafNode('zzz', LeafNode('zzz')));
    for (final Index index in <Index>[
      keyIndex,
      priorityIndex,
      valueIndex,
      PathIndex(Path('a')),
    ]) {
      expect(
        index.compare(index.minPost, child),
        lessThan(0),
        reason: '$index',
      );
      expect(
        index.compare(index.maxPost, child),
        greaterThan(0),
        reason: '$index',
      );
    }
  });

  test('NamedNode min and max', () {
    expect(NamedNode.min.name, ChildKey.min);
    expect(NamedNode.max.node, same(MaxNode.instance));
    expect(NamedNode(k('a'), LeafNode(1)), NamedNode(k('a'), LeafNode(1)));
  });

  test('buildChildSet builds by key and by index', () {
    final List<NamedNode> list = <NamedNode>[
      NamedNode(k('c'), LeafNode(1)),
      NamedNode(k('a'), LeafNode(3)),
      NamedNode(k('b'), LeafNode(2)),
    ];
    final SortedMap<ChildKey, Node> byKey = buildChildSet<ChildKey, Node>(
      List<NamedNode>.of(list),
      nameOnlyComparator,
      keyOf: (NamedNode n) => n.name,
      valueOf: (NamedNode n) => n.node,
      keyCompare: nameComparator,
    );
    debugCheckSortedMap(byKey);
    expect(
      byKey.entries.map((MapEntry<ChildKey, Node> e) => e.key.name),
      <String>['a', 'b', 'c'],
    );
    final SortedMap<NamedNode, Node> byValue = buildChildSet<NamedNode, Node>(
      List<NamedNode>.of(list),
      valueIndex.comparator,
      keyOf: (NamedNode n) => n,
      valueOf: (NamedNode n) => n.node,
    );
    expect(
      names(byValue.entries.map((MapEntry<NamedNode, Node> e) => e.key)),
      <String>['c', 'b', 'a'],
    );
  });
}
