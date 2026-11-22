// The array form of SortedMap against the tree form as oracle: random inserts and removes that
// cross the threshold of 25 in both directions, every observation compared after every step.
import 'dart:math' as math;

import 'package:firebase_database_dart/src/core/util/sorted_map.dart';
import 'package:test/test.dart';

int _cmp(int a, int b) => a.compareTo(b);

List<String> _list(Iterable<MapEntry<int, String>> entries) => <String>[
  for (final MapEntry<int, String> e in entries) '${e.key}=${e.value}',
];

void _expectSame(
  SortedMap<int, String> map,
  SortedMap<int, String> tree,
  int keySpace,
  String reason,
) {
  debugCheckSortedMap(map);
  expect(map.length, tree.length, reason: reason);
  expect(map.isEmpty, tree.isEmpty, reason: reason);
  expect(map.minKey, tree.minKey, reason: reason);
  expect(map.maxKey, tree.maxKey, reason: reason);
  expect(_list(map.entries), _list(tree.entries), reason: reason);
  expect(_list(map.reverseEntries), _list(tree.reverseEntries), reason: reason);
  expect(map.entries.length, tree.entries.length, reason: reason);
  expect(map.entries.isEmpty, tree.entries.isEmpty, reason: reason);
  expect('$map', '$tree', reason: reason);
  final List<String> a = <String>[], b = <String>[];
  map.inOrderTraversal((int k, String v) {
    a.add('$k=$v');
    return a.length == 3;
  });
  tree.inOrderTraversal((int k, String v) {
    b.add('$k=$v');
    return b.length == 3;
  });
  expect(a, b, reason: reason);
  a.clear();
  b.clear();
  expect(
    map.reverseTraversal((int k, String v) {
      a.add('$k=$v');
      return false;
    }),
    tree.reverseTraversal((int k, String v) {
      b.add('$k=$v');
      return false;
    }),
    reason: reason,
  );
  expect(a, b, reason: reason);
  // One below and one above the key space too.
  for (int key = -1; key <= keySpace; key++) {
    final String r = '$reason, key $key';
    expect(map[key], tree[key], reason: r);
    expect(map.containsKey(key), tree.containsKey(key), reason: r);
    expect(map.indexOf(key), tree.indexOf(key), reason: r);
    expect(
      _list(map.entriesFrom(key)),
      _list(tree.entriesFrom(key)),
      reason: r,
    );
    expect(
      _list(map.reverseEntriesFrom(key)),
      _list(tree.reverseEntriesFrom(key)),
      reason: r,
    );
    if (tree.containsKey(key)) {
      expect(map.predecessorKey(key), tree.predecessorKey(key), reason: r);
      expect(map.successorKey(key), tree.successorKey(key), reason: r);
    } else {
      expect(() => map.predecessorKey(key), throwsStateError, reason: r);
      expect(() => map.successorKey(key), throwsStateError, reason: r);
    }
  }
}

void main() {
  test(
    'an empty map and a small sorted list are arrays; a larger list is a tree',
    () {
      expect(debugIsArraySortedMap(SortedMap<int, String>(_cmp)), isTrue);
      for (final int n in <int>[0, 1, 24, 25, 26, 100]) {
        final SortedMap<int, String> map =
            SortedMap<int, String>.fromSortedEntries(<MapEntry<int, String>>[
              for (int i = 0; i < n; i++) MapEntry<int, String>(i, 'v$i'),
            ], _cmp);
        expect(debugIsArraySortedMap(map), n <= sortedMapArrayThreshold);
        expect(map.length, n);
        debugCheckSortedMap(map);
      }
    },
  );

  test(
    'the 26th insert makes a tree, and a tree stays one when it shrinks',
    () {
      SortedMap<int, String> map = SortedMap<int, String>(_cmp);
      for (int i = 0; i < 25; i++) {
        map = map.insert(i, 'v$i');
        expect(debugIsArraySortedMap(map), isTrue);
      }
      // Replacing at the threshold adds nothing.
      expect(debugIsArraySortedMap(map.insert(7, 'x')), isTrue);
      map = map.insert(25, 'v25');
      expect(debugIsArraySortedMap(map), isFalse);
      expect(map.length, 26);
      debugCheckSortedMap(map);
      for (int i = 0; i < 20; i++) {
        map = map.remove(i);
      }
      expect(debugIsArraySortedMap(map), isFalse);
      expect(map.length, 6);
    },
  );

  test('insert and remove leave the receiver unchanged', () {
    final SortedMap<int, String> one = SortedMap<int, String>(
      _cmp,
    ).insert(1, 'a').insert(3, 'c');
    final SortedMap<int, String> two = one.insert(2, 'b');
    final SortedMap<int, String> three = two.remove(1);
    final SortedMap<int, String> four = two.insert(2, 'B');
    expect(_list(one.entries), <String>['1=a', '3=c']);
    expect(_list(two.entries), <String>['1=a', '2=b', '3=c']);
    expect(_list(three.entries), <String>['2=b', '3=c']);
    expect(_list(four.entries), <String>['1=a', '2=B', '3=c']);
    expect(identical(one.remove(9), one), isTrue);
  });

  test('random inserts and removes across the threshold match the tree', () {
    const int keySpace = 48;
    for (int seed = 0; seed < 60; seed++) {
      final math.Random random = math.Random(seed);
      SortedMap<int, String> map = SortedMap<int, String>(_cmp);
      SortedMap<int, String> tree = SortedMap<int, String>.treeForTesting(_cmp);
      expect(debugIsArraySortedMap(tree), isFalse);
      bool wasArray = false, wasTree = false;
      // Grow past the threshold, shrink to nothing, grow again: both forms, both directions.
      for (int step = 0; step < 240; step++) {
        final int phase = step ~/ 80;
        final bool insert = random.nextInt(10) < (phase == 1 ? 1 : 9);
        final int key = random.nextInt(keySpace);
        if (insert) {
          map = map.insert(key, 's$step');
          tree = tree.insert(key, 's$step');
        } else {
          map = map.remove(key);
          tree = tree.remove(key);
        }
        if (map.isEmpty && phase == 1) {
          // A new map, as the client makes one for a node that got its first child again.
          map = SortedMap<int, String>(_cmp);
        }
        wasArray = wasArray || debugIsArraySortedMap(map);
        wasTree = wasTree || !debugIsArraySortedMap(map);
        _expectSame(map, tree, keySpace, 'seed $seed, step $step');
      }
      expect(wasArray && wasTree, isTrue, reason: 'seed $seed saw both forms');
    }
  });

  test('a custom order with keys that compare equal keeps the first key', () {
    // The tree keeps the existing key on a replace; so does the array.
    int byTens(int a, int b) => (a ~/ 10).compareTo(b ~/ 10);
    final SortedMap<int, String> map = SortedMap<int, String>(
      byTens,
    ).insert(11, 'a').insert(15, 'b');
    final SortedMap<int, String> tree = SortedMap<int, String>.treeForTesting(
      byTens,
    ).insert(11, 'a').insert(15, 'b');
    expect(_list(map.entries), <String>['11=b']);
    expect(_list(tree.entries), <String>['11=b']);
  });
}
