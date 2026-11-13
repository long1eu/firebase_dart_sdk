// Copyright 2017 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Port of the JS SDK test/unit/util/sorted_map.test.ts. The JS SortedMap is a
// left-leaning red-black tree, like the port's RBTreeSortedMap, so the tests
// run against RBTreeSortedMap. JS `root.checkMaxDepth()` is the test helper
// [checkMaxDepth] here, and a JS SortedMapIterator is a Dart Iterator.

import 'dart:math';

import 'package:cloud_firestore_dart/src/database_collection/immutable_sorted_map.dart';
import 'package:cloud_firestore_dart/src/database_collection/llrb_node.dart';
import 'package:cloud_firestore_dart/src/database_collection/rb_tree_sorted_map.dart';
import 'package:cloud_firestore_dart/src/database_collection/standard_compartor.dart';
import 'package:test/test.dart';

final Random _random = Random();

void shuffle(List<int> arr) {
  for (int i = arr.length - 1; i > 0; i--) {
    // Choose a random array index in [0, i] (inclusive with i).
    final int j = _random.nextInt(i + 1);
    final int tmp = arr[i];
    arr[i] = arr[j];
    arr[j] = tmp;
  }
}

/// The JS LLRBNode.check(): verifies the red-black invariants and returns the
/// black depth of [node].
int _check(LLRBNode<dynamic, dynamic> node) {
  if (node.isEmpty) {
    return 0;
  }
  if (node.isRed && node.left.isRed) {
    fail('Red node has red child(${node.key},${node.value})');
  }
  if (node.right.isRed) {
    fail('Right child of (${node.key},${node.value}) is red');
  }
  final int blackDepth = _check(node.left);
  if (blackDepth != _check(node.right)) {
    fail('Black depths differ');
  }
  return blackDepth + (node.isRed ? 0 : 1);
}

/// The JS LLRBNode.checkMaxDepth().
bool checkMaxDepth(LLRBNode<dynamic, dynamic> node) {
  final int blackDepth = _check(node);
  return pow(2, blackDepth) <= node.length + 1;
}

class _Visitor<K, V> implements ShortCircuitingNodeVisitor<K, V> {
  _Visitor(this._onEntry);

  final bool Function(K key, V value) _onEntry;

  @override
  bool shouldContinue(K key, V value) => _onEntry(key, value);
}

LLRBNode<K, V> rootOf<K, V>(ImmutableSortedMap<K, V> map) =>
    (map as RBTreeSortedMap<K, V>).root;

void main() {
  final Comparator<Object?> primitiveComparator = naturalComparator<Object?>();

  RBTreeSortedMap<Object?, Object?> newMap() =>
      RBTreeSortedMap<Object?, Object?>(primitiveComparator);

  /// Returns a map with (i, i) entries for i in [0, 9] inclusive.
  ImmutableSortedMap<int, int> getMapOfNumbersZeroToNine() {
    final List<int> items = <int>[for (int i = 0; i < 10; i++) i];
    shuffle(items);

    ImmutableSortedMap<int, int> map = RBTreeSortedMap<int, int>(
      naturalComparator<int>(),
    );
    for (int i = 0; i < 10; i++) {
      map = map.insert(items[i], items[i]);
    }
    return map;
  }

  /// Validates that the given iterator covers the given range by counting from
  /// the given `from` argument to the given `to` argument (inclusive).
  void validateIteratorCoversRange(
    Iterator<MapEntry<int, int>> iterator,
    int from,
    int to,
  ) {
    final bool countUp = from <= to;
    int expected = from;
    while (iterator.moveNext()) {
      final MapEntry<int, int> n = iterator.current;
      expect(n.key, expected);
      expect(n.value, expected);
      expected = countUp ? expected + 1 : expected - 1;
    }
    expect(expected, countUp ? to + 1 : to - 1);
  }

  void expectExhausted(Iterator<MapEntry<int, int>> iterator) {
    expect(iterator.moveNext(), isFalse);
    expect(() => iterator.current, throwsStateError);
  }

  test('Create node', () {
    final ImmutableSortedMap<Object?, Object?> map = newMap().insert(
      'key',
      'value',
    );
    expect(rootOf(map).left.isEmpty, isTrue);
    expect(rootOf(map).right.isEmpty, isTrue);
  });

  test('You can search a map for a specific key', () {
    final ImmutableSortedMap<Object?, Object?> map = newMap()
        .insert(1, 1)
        .insert(2, 2);
    expect(map[1], 1);
    expect(map[2], 2);
    expect(map[3], isNull);
  });

  test('You can insert a new key/value pair into the tree', () {
    final ImmutableSortedMap<Object?, Object?> map = newMap()
        .insert(1, 1)
        .insert(2, 2);
    expect(rootOf(map).key, 2);
    expect(rootOf(map).left.key, 1);
  });

  test('You can remove a key/value pair from the map', () {
    final ImmutableSortedMap<Object?, Object?> map = newMap()
        .insert(1, 1)
        .insert(2, 2);
    final ImmutableSortedMap<Object?, Object?> newMap2 = map.remove(1);
    expect(newMap2[2], 2);
    expect(newMap2[1], isNull);
  });

  test('More removals', () {
    final ImmutableSortedMap<Object?, Object?> map = newMap()
        .insert(1, 1)
        .insert(50, 50)
        .insert(3, 3)
        .insert(4, 4)
        .insert(7, 7)
        .insert(9, 9)
        .insert(20, 20)
        .insert(18, 18)
        .insert(2, 2)
        .insert(71, 71)
        .insert(42, 42)
        .insert(88, 88);

    final ImmutableSortedMap<Object?, Object?> m1 = map.remove(7);
    final ImmutableSortedMap<Object?, Object?> m2 = m1.remove(3);
    final ImmutableSortedMap<Object?, Object?> m3 = m2.remove(1);
    expect(m3.length, 9);
    expect(m3[1], isNull);
    expect(m3[3], isNull);
    expect(m3[7], isNull);
    expect(m3[20], 20);
  });

  test('Removal bug', () {
    final ImmutableSortedMap<Object?, Object?> map = newMap()
        .insert(1, 1)
        .insert(2, 2)
        .insert(3, 3);

    final ImmutableSortedMap<Object?, Object?> m1 = map.remove(2);
    expect(m1[1], 1);
    expect(m1[3], 3);
  });

  test('Test increasing', () {
    const int total = 100;
    int item;
    ImmutableSortedMap<Object?, Object?> map = newMap().insert(1, 1);
    for (item = 2; item < total; item++) {
      map = map.insert(item, item);
    }
    expect(checkMaxDepth(rootOf(map)), isTrue);
    for (item = 2; item < total; item++) {
      map = map.remove(item);
    }
    expect(checkMaxDepth(rootOf(map)), isTrue);
  });

  test('The structure should be valid after insertion (1)', () {
    final ImmutableSortedMap<Object?, Object?> map = newMap()
        .insert(1, 1)
        .insert(2, 2)
        .insert(3, 3);

    expect(rootOf(map).key, 2);
    expect(rootOf(map).left.key, 1);
    expect(rootOf(map).right.key, 3);
  });

  test('The structure should be valid after insertion (2)', () {
    final ImmutableSortedMap<Object?, Object?> map = newMap()
        .insert(1, 1)
        .insert(2, 2)
        .insert(3, 3)
        .insert(4, 4)
        .insert(5, 5)
        .insert(6, 6)
        .insert(7, 7)
        .insert(8, 8)
        .insert(9, 9)
        .insert(10, 10)
        .insert(11, 11)
        .insert(12, 12);

    expect(map.length, 12);
    expect(checkMaxDepth(rootOf(map)), isTrue);
  });

  test(
    'Rotate left leaves the tree in a valid state',
    skip:
        'LLRBValueNode._rotateLeft is private in the port; the rotations are '
        'covered by the checkMaxDepth structure tests',
    () {},
  );

  test(
    'Rotate right leaves the tree in a valid state',
    skip:
        'LLRBValueNode._rotateRight is private in the port; the rotations are '
        'covered by the checkMaxDepth structure tests',
    () {},
  );

  test('The structure should be valid after insertion (3)', () {
    final ImmutableSortedMap<Object?, Object?> map = newMap()
        .insert(1, 1)
        .insert(50, 50)
        .insert(3, 3)
        .insert(4, 4)
        .insert(7, 7)
        .insert(9, 9);

    expect(map.length, 6);
    expect(checkMaxDepth(rootOf(map)), isTrue);

    final ImmutableSortedMap<Object?, Object?> m2 = map
        .insert(20, 20)
        .insert(18, 18)
        .insert(2, 2);

    expect(m2.length, 9);
    expect(checkMaxDepth(rootOf(m2)), isTrue);

    final ImmutableSortedMap<Object?, Object?> m3 = m2
        .insert(71, 71)
        .insert(42, 42)
        .insert(88, 88);

    expect(m3.length, 12);
    expect(checkMaxDepth(rootOf(m3)), isTrue);
  });

  test('you can overwrite a value', () {
    final ImmutableSortedMap<Object?, Object?> map = newMap()
        .insert(10, 10)
        .insert(10, 8);
    expect(map[10], 8);
  });

  test('removing the last element returns an empty map', () {
    final ImmutableSortedMap<Object?, Object?> map = newMap()
        .insert(10, 10)
        .remove(10);
    expect(map.isEmpty, isTrue);
  });

  test('empty .get()', () {
    final RBTreeSortedMap<Object?, Object?> empty = newMap();
    expect(empty['something'], isNull);
  });

  test('empty .size', () {
    final RBTreeSortedMap<Object?, Object?> empty = newMap();
    expect(empty.length, 0);
  });

  test('empty .remove()', () {
    final RBTreeSortedMap<Object?, Object?> empty = newMap();
    expect(empty.remove('something').length, 0);
  });

  test('.reverseTraversal() works.', () {
    final ImmutableSortedMap<Object?, Object?> map = newMap()
        .insert(1, 1)
        .insert(5, 5)
        .insert(3, 3)
        .insert(2, 2)
        .insert(4, 4);
    int next = 5;
    rootOf(map).shortCircuitingReverseOrderTraversal(
      _Visitor<Object?, Object?>((Object? key, Object? _) {
        expect(key, next);
        next--;
        return true;
      }),
    );
    expect(next, 0);
  });

  test('insertion and removal of 100 items in random order.', () {
    const int n = 100;
    final List<int> toInsert = <int>[];
    final List<int> toRemove = <int>[];
    for (int i = 0; i < n; i++) {
      toInsert.add(i);
      toRemove.add(i);
    }

    shuffle(toInsert);
    shuffle(toRemove);

    ImmutableSortedMap<Object?, Object?> map = newMap();

    for (int i = 0; i < n; i++) {
      map = map.insert(toInsert[i], toInsert[i]);
      expect(checkMaxDepth(rootOf(map)), isTrue);
    }
    expect(map.length, n);

    // Ensure order is correct.
    int next = 0;
    rootOf(map).shortCircuitingInOrderTraversal(
      _Visitor<Object?, Object?>((Object? key, Object? value) {
        expect(key, next);
        expect(value, next);
        next++;
        return true;
      }),
    );
    expect(next, n);

    for (int i = 0; i < n; i++) {
      expect(checkMaxDepth(rootOf(map)), isTrue);
      map = map.remove(toRemove[i]);
    }
    expect(map.length, 0);
  });

  // The JS benchmarks are it.skip upstream as well.
  test('Perf', skip: 'Benchmark, skipped upstream', () {});
  test(
    'Perf: Insertion and removal with various # of items.',
    skip: 'Benchmark, skipped upstream',
    () {},
  );
  test(
    'Perf: Comparison with {}: Insertion and removal with various # of items.',
    skip: 'Benchmark, skipped upstream',
    () {},
  );

  test('SortedMapIterator empty test.', () {
    final RBTreeSortedMap<int, int> map = RBTreeSortedMap<int, int>(
      naturalComparator<int>(),
    );
    expectExhausted(map.iterator);
  });

  test('forward iterator without start key', () {
    final Iterator<MapEntry<int, int>> iterator =
        getMapOfNumbersZeroToNine().iterator;
    validateIteratorCoversRange(iterator, 0, 9);
  });

  test('forward iterator with start key.', () {
    final Iterator<MapEntry<int, int>> iterator = getMapOfNumbersZeroToNine()
        .iteratorFrom(5);
    validateIteratorCoversRange(iterator, 5, 9);
  });

  test('forward iterator with start key larger than max key', () {
    expectExhausted(getMapOfNumbersZeroToNine().iteratorFrom(50));
  });

  test('forward iterator with start key smaller than min key', () {
    final Iterator<MapEntry<int, int>> iterator = getMapOfNumbersZeroToNine()
        .iteratorFrom(-50);
    validateIteratorCoversRange(iterator, 0, 9);
  });

  test('reverse iterator without start key', () {
    final Iterator<MapEntry<int, int>> iterator =
        getMapOfNumbersZeroToNine().reverseIterator;
    validateIteratorCoversRange(iterator, 9, 0);
  });

  test('reverse iterator with start key.', () {
    final Iterator<MapEntry<int, int>> iterator = getMapOfNumbersZeroToNine()
        .reverseIteratorFrom(7);
    validateIteratorCoversRange(iterator, 7, 0);
  });

  test('reverse iterator with start key smaller than min key', () {
    expectExhausted(getMapOfNumbersZeroToNine().reverseIteratorFrom(-50));
  });

  test('reverse iterator with start key larger than max key', () {
    final Iterator<MapEntry<int, int>> iterator = getMapOfNumbersZeroToNine()
        .reverseIteratorFrom(50);
    validateIteratorCoversRange(iterator, 9, 0);
  });

  test('SortedMap.indexOf returns index.', () {
    final ImmutableSortedMap<Object?, Object?> map = newMap()
        .insert(1, 1)
        .insert(50, 50)
        .insert(3, 3)
        .insert(4, 4)
        .insert(7, 7)
        .insert(9, 9);

    expect(map.indexOf(0), -1);
    expect(map.indexOf(1), 0);
    expect(map.indexOf(2), -1);
    expect(map.indexOf(3), 1);
    expect(map.indexOf(4), 2);
    expect(map.indexOf(5), -1);
    expect(map.indexOf(6), -1);
    expect(map.indexOf(7), 3);
    expect(map.indexOf(8), -1);
    expect(map.indexOf(9), 4);
    expect(map.indexOf(50), 5);

    final RBTreeSortedMap<Object?, Object?> emptyMap = newMap();
    expect(emptyMap.indexOf(1), -1);
  });
}
