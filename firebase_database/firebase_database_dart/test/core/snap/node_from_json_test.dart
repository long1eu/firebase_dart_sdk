// JSON to node and back: JS nodeFromJSON.ts and ChildrenNode.val (node.test.ts cases), the list
// rule, the export form, the memoised value form (addendum 2) and number handling (addendum 1).
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/priority_index.dart';
import 'package:firebase_database_dart/src/core/snap/leaf_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/snap/priority.dart';
import 'package:test/test.dart';

void main() {
  test('null is the empty node', () {
    expect(nodeFromJson(null), same(ChildrenNode.empty));
    expect(nodeFromJson(<String, Object?>{}), same(ChildrenNode.empty));
    expect(
      nodeFromJson(<String, Object?>{'a': null}),
      same(ChildrenNode.empty),
    );
  });

  test('ignores null values', () {
    final Node node = nodeFromJson(<String, Object?>{'a': 1, 'b': null});
    expect((node as ChildrenNode).children[ChildKey('b')], isNull);
    expect(node.numChildren, 1);
  });

  test('ignores metadata keys', () {
    final Node node = nodeFromJson(<String, Object?>{'a': 1, '.foo': 2});
    expect(node.value, <String, Object?>{'a': 1});
  });

  test('leading zeroes in a path are handled properly', () {
    final Node tree = nodeFromJson(<String, Object?>{
      '1': 1,
      '01': 2,
      '001': 3,
    });
    expect(tree.getChild(Path('1')).value, 1);
    expect(tree.getChild(Path('01')).value, 2);
    expect(tree.getChild(Path('001')).value, 3);
  });

  test('treats leading zeroes as objects, not arrays', () {
    final Map<String, Object?> json = <String, Object?>{'3': 1, '03': 2};
    expect(nodeFromJson(json).value, json);
    final Map<String, Object?> json2 = <String, Object?>{'0': 'a', '01': 'b'};
    final Object? value = nodeFromJson(json2).value;
    expect(value, isA<Map<String, Object?>>());
    expect(value, json2);
  });

  test('list rule: integer keys with more than half present become a list', () {
    expect(
      nodeFromJson(<String, Object?>{'0': 'a', '1': 'b', '2': 'c'}).value,
      <Object?>['a', 'b', 'c'],
    );
    expect(nodeFromJson(<String, Object?>{'0': 'a', '2': 'c'}).value, <Object?>[
      'a',
      null,
      'c',
    ]);
    // maxKey 3 is not below 2 * 2 keys.
    expect(
      nodeFromJson(<String, Object?>{'1': 'b', '3': 'd'}).value,
      isA<Map<String, Object?>>(),
    );
    expect(nodeFromJson(<Object?>['a', null, 'c']).value, <Object?>[
      'a',
      null,
      'c',
    ]);
    // The export form never turns into a list.
    expect(
      nodeFromJson(<Object?>['a', 'b']).toJson(exportFormat: true),
      <String, Object?>{'0': 'a', '1': 'b'},
    );
  });

  test('export form round trip with priorities', () {
    final Map<String, Object?> json = <String, Object?>{
      'a': <String, Object?>{'.value': 1, '.priority': 'p'},
      'b': <String, Object?>{'c': true, '.priority': 2},
      '.priority': 'root',
    };
    final Node node = nodeFromJson(json);
    expect(node.toJson(exportFormat: true), json);
    expect(node.toJson(), <String, Object?>{
      'a': 1,
      'b': <String, Object?>{'c': true},
    });
    expect(node.priority.value, 'root');
    expect(nodeFromJson(node.toJson(exportFormat: true)), node);
  });

  test('a priority argument is used unless the JSON has one', () {
    expect(nodeFromJson('x', 5).priority.value, 5);
    expect(
      nodeFromJson(<String, Object?>{
        '.value': 'x',
        '.priority': 6,
      }, 5).priority.value,
      6,
    );
    expect(() => nodeFromJson('x', true), throwsArgumentError);
  });

  test('server values are leaves', () {
    final Node node = nodeFromJson(<String, Object?>{'.sv': 'timestamp'});
    expect(node, isA<LeafNode>());
    expect((node as LeafNode).leafType, LeafType.deferredValue);
  });

  test('children with priorities build the priority index eagerly', () {
    final Node node = nodeFromJson(<String, Object?>{
      'a': <String, Object?>{'.value': 1, '.priority': 2},
      'b': <String, Object?>{'.value': 1, '.priority': 1},
    });
    expect((node as ChildrenNode).indexMap.get('.priority'), isNotNull);
    expect(node.firstChildKey(priorityIndex), ChildKey('b'));
    expect(node.lastChildKey(priorityIndex), ChildKey('a'));
  });

  test('large maps build in key order', () {
    final Map<String, Object?> json = <String, Object?>{
      for (int i = 0; i < 5000; i++) 'k$i': i,
    };
    final ChildrenNode node = nodeFromJson(json) as ChildrenNode;
    expect(node.numChildren, 5000);
    final List<String> keys = node
        .childrenInOrder(priorityIndex)
        .map((n) => n.name.name)
        .toList();
    expect(keys, List<String>.of(json.keys)..sort());
  });

  group('numbers (addendum 1)', () {
    test('kept as given in the node and normalised when read', () {
      expect(nodeFromJson(1.0).value, isA<int>());
      expect(nodeFromJson(1.0).value, 1);
      expect(nodeFromJson(1.5).value, 1.5);
      expect(nodeFromJson(1.0).toJson(exportFormat: true), 1.0);
    });

    test('accepts numbers parsed from 1.0E21 and 4.9E-324', () {
      expect(nodeFromJson(double.parse('1.0E21')).value, 1e21);
      expect(nodeFromJson(double.parse('4.9E-324')).value, 4.9e-324);
    });

    test('negative zero stays a double -0.0', () {
      final Object? v = nodeFromJson(-0.0).value;
      expect(v, isA<double>());
      expect((v! as double).isNegative, isTrue);
    });
  });

  group('memoised value form (addendum 2)', () {
    final Map<String, Object?> json = <String, Object?>{
      'a': <String, Object?>{
        'b': <String, Object?>{'c': 1, 'd': 'x'},
        'l': <Object?>['p', 'q'],
      },
      's': <String, Object?>{'.sv': 'timestamp'},
    };

    test('the second read returns the same object', () {
      final Node node = nodeFromJson(json);
      expect(identical(node.value, node.value), isTrue);
      final Map<String, Object?> value = node.value! as Map<String, Object?>;
      expect(
        identical(value['a'], node.getImmediateChild(ChildKey('a')).value),
        isTrue,
      );
    });

    test('mutation throws UnsupportedError at every depth', () {
      final Node node = nodeFromJson(json);
      final Map<String, Object?> value = node.value! as Map<String, Object?>;
      expect(() => value['z'] = 1, throwsUnsupportedError);
      final Map<String, Object?> a = value['a']! as Map<String, Object?>;
      expect(() => a.remove('b'), throwsUnsupportedError);
      final Map<String, Object?> b = a['b']! as Map<String, Object?>;
      expect(() => b['c'] = 2, throwsUnsupportedError);
      final List<Object?> l = a['l']! as List<Object?>;
      expect(() => l[0] = 'z', throwsUnsupportedError);
      expect(() => l.add('z'), throwsUnsupportedError);
      final Map<String, Object?> s = value['s']! as Map<String, Object?>;
      expect(() => s['.sv'] = 'x', throwsUnsupportedError);
    });

    test('runtime types at depth 3', () {
      final Node node = nodeFromJson(json);
      final Object? value = node.value;
      expect(value, isA<Map<String, Object?>>());
      final Object? a = (value! as Map<String, Object?>)['a'];
      expect(a, isA<Map<String, Object?>>());
      final Object? b = (a! as Map<String, Object?>)['b'];
      expect(b, isA<Map<String, Object?>>());
      expect(b, isNot(isA<Map<String, int>>()));
      expect((a as Map<String, Object?>)['l'], isA<List<Object?>>());
    });

    test('toJson returns a fresh mutable copy', () {
      final Node node = nodeFromJson(json);
      final Map<String, Object?> copy = node.toJson()! as Map<String, Object?>;
      expect(identical(copy, node.toJson()), isFalse);
      copy['z'] = 1;
      ((copy['a']! as Map<String, Object?>)['b']!
              as Map<String, Object?>)['c'] =
          2;
      expect(node.getChild(Path('a/b/c')).value, 1);
      expect(node.value, isNot(contains('z')));
    });
  });

  test('parsePriority', () {
    expect(parsePriority(null), same(ChildrenNode.empty));
    expect(parsePriority(3).value, 3);
    expect(parsePriority('p').value, 'p');
    expect(priorityHashText(3), 'number:4008000000000000');
    expect(priorityHashText('p'), 'string:p');
  });
}
