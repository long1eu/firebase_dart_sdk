// Port of JS test/sortedmap.test.ts, plus the Android extras (successorKey, indexOf, iteration
// from a key) and the linear construction from sorted entries.
import 'dart:math';

import 'package:firebase_database_dart/src/core/util/sorted_map.dart';
import 'package:test/test.dart';

int _cmp(int a, int b) => a.compareTo(b);

SortedMap<int, int> _of(List<int> keys) {
  SortedMap<int, int> map = SortedMap<int, int>(_cmp);
  for (final int k in keys) {
    map = map.insert(k, k);
  }
  return map;
}

void main() {
  test('search a map for a specific key', () {
    final SortedMap<int, int> map = _of(<int>[1, 2]);
    expect(map[1], 1);
    expect(map[2], 2);
    expect(map[3], isNull);
    expect(map.containsKey(2), isTrue);
    expect(map.containsKey(3), isFalse);
  });

  test('remove a key/value pair from the map', () {
    final SortedMap<int, int> map = _of(<int>[1, 2]);
    final SortedMap<int, int> newMap = map.remove(1);
    expect(newMap[2], 2);
    expect(newMap[1], isNull);
    expect(map[1], 1, reason: 'the old map is unchanged');
  });

  test('more removals', () {
    final SortedMap<int, int> map = _of(<int>[
      1, 50, 3, 4, 7, 9, 20, 18, 2, 71, 42, 88, //
    ]);
    final SortedMap<int, int> m3 = map.remove(7).remove(3).remove(1);
    expect(m3.length, 9);
    expect(m3[1], isNull);
    expect(m3[3], isNull);
    expect(m3[7], isNull);
    expect(m3[20], 20);
    debugCheckSortedMap(m3);
  });

  test('removal bug', () {
    final SortedMap<int, int> m1 = _of(<int>[1, 2, 3]).remove(2);
    expect(m1[1], 1);
    expect(m1[3], 3);
  });

  test('increasing inserts and removals keep the tree balanced', () {
    SortedMap<int, int> map = _of(<int>[1]);
    for (int i = 2; i < 100; i++) {
      map = map.insert(i, i);
    }
    debugCheckSortedMap(map);
    for (int i = 2; i < 100; i++) {
      map = map.remove(i);
    }
    debugCheckSortedMap(map);
    expect(map.length, 1);
  });

  test('structure is valid after insertion', () {
    final SortedMap<int, int> map = _of(
      List<int>.generate(12, (int i) => i + 1),
    );
    expect(map.length, 12);
    debugCheckSortedMap(map);
  });

  test('overwrite a value', () {
    final SortedMap<int, int> map = SortedMap<int, int>(
      _cmp,
    ).insert(10, 10).insert(10, 8);
    expect(map[10], 8);
    expect(map.length, 1);
  });

  test('removing the last element returns an empty map', () {
    expect(SortedMap<int, int>(_cmp).insert(10, 10).remove(10).isEmpty, isTrue);
  });

  test('empty map', () {
    final SortedMap<String, int> empty = SortedMap<String, int>(
      (String a, String b) => a.compareTo(b),
    );
    expect(empty['something'], isNull);
    expect(empty.length, 0);
    expect(empty.remove('something').length, 0);
    expect(empty.minKey, isNull);
    expect(empty.maxKey, isNull);
    expect(empty.entries, isEmpty);
  });

  test('reverseTraversal visits in reverse order', () {
    final SortedMap<int, int> map = _of(<int>[1, 5, 3, 2, 4]);
    int next = 5;
    map.reverseTraversal((int key, int value) {
      expect(key, next);
      next--;
      return false;
    });
    expect(next, 0);
  });

  test('traversal stops when the action returns true', () {
    final SortedMap<int, int> map = _of(<int>[1, 2, 3, 4]);
    final List<int> seen = <int>[];
    final bool stopped = map.inOrderTraversal((int key, int value) {
      seen.add(key);
      return key == 2;
    });
    expect(stopped, isTrue);
    expect(seen, <int>[1, 2]);
  });

  test('insertion and removal of 100 items in random order', () {
    const int n = 100;
    final Random random = Random(42);
    final List<int> toInsert = List<int>.generate(n, (int i) => i)
      ..shuffle(random);
    final List<int> toRemove = List<int>.generate(n, (int i) => i)
      ..shuffle(random);
    SortedMap<int, int> map = SortedMap<int, int>(_cmp);
    for (final int k in toInsert) {
      map = map.insert(k, k);
      debugCheckSortedMap(map);
    }
    expect(map.length, n);
    int next = 0;
    map.inOrderTraversal((int key, int value) {
      expect(key, next);
      expect(value, next);
      next++;
      return false;
    });
    expect(next, n);
    for (final int k in toRemove) {
      debugCheckSortedMap(map);
      map = map.remove(k);
    }
    expect(map.length, 0);
  });

  test('iterator over 10 shuffled items', () {
    final List<int> items = List<int>.generate(10, (int i) => i)
      ..shuffle(Random(7));
    final SortedMap<int, int> map = _of(items);
    expect(
      map.entries.map((MapEntry<int, int> e) => e.key),
      List<int>.generate(10, (int i) => i),
    );
    expect(
      map.reverseEntries.map((MapEntry<int, int> e) => e.key),
      List<int>.generate(10, (int i) => 9 - i),
    );
  });

  test('predecessorKey', () {
    final SortedMap<int, int> map = _of(<int>[1, 50, 3, 4, 7, 9]);
    expect(map.predecessorKey(1), isNull);
    expect(map.predecessorKey(3), 1);
    expect(map.predecessorKey(4), 3);
    expect(map.predecessorKey(7), 4);
    expect(map.predecessorKey(9), 7);
    expect(map.predecessorKey(50), 9);
    expect(() => map.predecessorKey(2), throwsStateError);
  });

  test('successorKey', () {
    final SortedMap<int, int> map = _of(<int>[1, 50, 3, 4, 7, 9]);
    expect(map.successorKey(1), 3);
    expect(map.successorKey(9), 50);
    expect(map.successorKey(50), isNull);
    expect(() => map.successorKey(2), throwsStateError);
  });

  test('indexOf, minKey and maxKey', () {
    final SortedMap<int, int> map = _of(<int>[1, 50, 3, 4, 7, 9]);
    expect(map.indexOf(1), 0);
    expect(map.indexOf(7), 3);
    expect(map.indexOf(50), 5);
    expect(map.indexOf(2), -1);
    expect(map.minKey, 1);
    expect(map.maxKey, 50);
  });

  test('entriesFrom and reverseEntriesFrom', () {
    final SortedMap<int, int> map = _of(<int>[10, 20, 30, 40]);
    List<int> keys(Iterable<MapEntry<int, int>> e) =>
        e.map((MapEntry<int, int> x) => x.key).toList();
    expect(keys(map.entriesFrom(20)), <int>[20, 30, 40]);
    expect(keys(map.entriesFrom(25)), <int>[30, 40]);
    expect(keys(map.entriesFrom(45)), isEmpty);
    expect(keys(map.entriesFrom(0)), <int>[10, 20, 30, 40]);
    expect(keys(map.reverseEntriesFrom(30)), <int>[30, 20, 10]);
    expect(keys(map.reverseEntriesFrom(25)), <int>[20, 10]);
    expect(keys(map.reverseEntriesFrom(5)), isEmpty);
  });

  test('fromSortedEntries builds a valid tree for every size up to 300', () {
    for (int n = 0; n <= 300; n++) {
      final SortedMap<int, int> map = SortedMap<int, int>.fromSortedEntries(
        <MapEntry<int, int>>[
          for (int i = 0; i < n; i++) MapEntry<int, int>(i, i * 2),
        ],
        _cmp,
      );
      debugCheckSortedMap(map);
      expect(map.length, n);
      expect(
        map.entries.map((MapEntry<int, int> e) => e.key),
        List<int>.generate(n, (int i) => i),
      );
      if (n > 0) {
        expect(map[n - 1], (n - 1) * 2);
        // Still valid after updates.
        final SortedMap<int, int> updated = map.insert(n, 0).remove(0);
        debugCheckSortedMap(updated);
        expect(updated.length, n);
      }
    }
  });

  test('fromMap sorts the entries', () {
    final SortedMap<int, String> map = SortedMap<int, String>.fromMap(
      <int, String>{3: 'c', 1: 'a', 2: 'b'},
      _cmp,
    );
    expect(map.entries.map((MapEntry<int, String> e) => e.value), <String>[
      'a',
      'b',
      'c',
    ]);
    debugCheckSortedMap(map);
  });
}
