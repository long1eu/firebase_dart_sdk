// ignore_for_file: cascade_invocations

import 'package:cloud_firestore_dart/src/database_collection/array_sorted_map.dart';
import 'package:cloud_firestore_dart/src/database_collection/immutable_sorted_map.dart';
import 'package:cloud_firestore_dart/src/database_collection/immutable_sorted_set.dart';
import 'package:cloud_firestore_dart/src/database_collection/llrb_node.dart';
import 'package:cloud_firestore_dart/src/database_collection/rb_tree_sorted_map.dart';
import 'package:test/test.dart';

int _cmp(int a, int b) => a.compareTo(b);

class _Collect extends NodeVisitor<int, String> {
  final List<int> keys = <int>[];

  @override
  void visitEntry(int key, String value) => keys.add(key);
}

class _StopAt implements ShortCircuitingNodeVisitor<int, String> {
  _StopAt(this.stop);

  final int stop;
  final List<int> keys = <int>[];

  @override
  bool shouldContinue(int key, String value) {
    keys.add(key);
    return key != stop;
  }
}

ImmutableSortedMap<int, String> _fill(
  ImmutableSortedMap<int, String> map,
  Iterable<int> keys,
) {
  for (final int k in keys) {
    map = map.insert(k, 'v$k');
  }
  return map;
}

void main() {
  // Inserted out of order so the tree is not a degenerate list.
  final List<int> keys = <int>[for (int i = 0; i < 40; i++) (i * 17) % 40];
  final List<int> sorted = List<int>.of(keys)..sort();

  final Map<String, ImmutableSortedMap<int, String>> maps =
      <String, ImmutableSortedMap<int, String>>{
        'array': _fill(ArraySortedMap<int, String>(_cmp), keys.take(10)),
        'rb tree': _fill(RBTreeSortedMap<int, String>(_cmp), keys),
      };

  maps.forEach((String name, ImmutableSortedMap<int, String> map) {
    final List<int> expected = List<int>.of(
      map.map((MapEntry<int, String> e) => e.key),
    );

    group(name, () {
      test('inOrderTraversal visits keys in order', () {
        final _Collect visitor = _Collect();
        map.inOrderTraversal(visitor);
        expect(visitor.keys, expected);
        expect(visitor.keys, orderedEquals(List<int>.of(visitor.keys)..sort()));
      });

      test('successor and predecessor walk the sorted order', () {
        for (int i = 0; i < expected.length; i++) {
          expect(
            map.getSuccessorKey(expected[i]),
            i == expected.length - 1 ? isNull : expected[i + 1],
          );
          expect(
            map.getPredecessorKey(expected[i]),
            i == 0 ? isNull : expected[i - 1],
          );
        }
      });

      test('neighbours of a missing key are an error', () {
        expect(() => map.getSuccessorKey(1000), throwsArgumentError);
        expect(() => map.getPredecessorKey(-1), throwsArgumentError);
      });

      test('indexOf of a missing key is -1', () {
        expect(map.indexOf(1000), -1);
        expect(map.indexOf(expected.last), expected.length - 1);
      });
    });
  });

  group('rb tree node traversal', () {
    final RBTreeSortedMap<int, String> tree =
        _fill(RBTreeSortedMap<int, String>(_cmp), keys)
            as RBTreeSortedMap<int, String>;

    test('in-order short circuit stops at the requested key', () {
      final _StopAt visitor = _StopAt(sorted[12]);
      expect(tree.root.shortCircuitingInOrderTraversal(visitor), isFalse);
      expect(visitor.keys, sorted.sublist(0, 13));
    });

    test('reverse short circuit stops at the requested key', () {
      final _StopAt visitor = _StopAt(sorted[30]);
      expect(tree.root.shortCircuitingReverseOrderTraversal(visitor), isFalse);
      expect(visitor.keys, sorted.sublist(30).reversed.toList());
    });

    test('a visitor that never stops sees everything', () {
      final _StopAt forward = _StopAt(-1);
      expect(tree.root.shortCircuitingInOrderTraversal(forward), isTrue);
      expect(forward.keys, sorted);
      final _StopAt backward = _StopAt(-1);
      expect(tree.root.shortCircuitingReverseOrderTraversal(backward), isTrue);
      expect(backward.keys, sorted.reversed.toList());
    });

    test('min, max and length of the root agree with the map', () {
      expect(tree.root.min.key, sorted.first);
      expect(tree.root.max.key, sorted.last);
      expect(tree.root.length, sorted.length);
      expect(tree.minKey, sorted.first);
      expect(tree.maxKey, sorted.last);
    });
  });

  group('ImmutableSortedSet reverse iteration', () {
    final ImmutableSortedSet<int> set = ImmutableSortedSet<int>(keys, _cmp);

    List<int> drain(Iterator<int> it) {
      final List<int> out = <int>[];
      while (it.moveNext()) {
        out.add(it.current);
      }
      return out;
    }

    test('reverseIterator', () {
      expect(drain(set.reverseIterator), sorted.reversed.toList());
    });

    test('reverseIteratorFrom starts at the key, inclusive', () {
      expect(
        drain(set.reverseIteratorFrom(sorted[5])),
        sorted.sublist(0, 6).reversed.toList(),
      );
    });

    test('iteratorFrom starts at the key, inclusive', () {
      expect(drain(set.iteratorFrom(sorted[35])), sorted.sublist(35));
    });
  });
}
