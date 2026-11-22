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

  test('every iterator variant is empty on an empty map', () {
    final SortedMap<int, int> empty = SortedMap<int, int>(_cmp);
    expect(empty.entries, isEmpty);
    expect(empty.reverseEntries, isEmpty);
    expect(empty.entriesFrom(1), isEmpty);
    expect(empty.reverseEntriesFrom(1), isEmpty);
    expect(empty.reverseEntries.length, 0);
    expect(empty.entriesFrom(1).length, 0);
    expect(empty.reverseTraversal((int k, int v) => true), isFalse);
    expect(empty.inOrderTraversal((int k, int v) => true), isFalse);
  });

  test('a one-entry map', () {
    final SortedMap<int, int> one = _of(<int>[5]);
    List<int> keys(Iterable<MapEntry<int, int>> e) =>
        e.map((MapEntry<int, int> x) => x.key).toList();
    expect(one.minKey, 5);
    expect(one.maxKey, 5);
    expect(one.predecessorKey(5), isNull);
    expect(one.successorKey(5), isNull);
    expect(keys(one.entries), <int>[5]);
    expect(keys(one.reverseEntries), <int>[5]);
    expect(keys(one.entriesFrom(5)), <int>[5]);
    expect(keys(one.entriesFrom(4)), <int>[5]);
    expect(keys(one.entriesFrom(6)), isEmpty);
    expect(keys(one.reverseEntriesFrom(5)), <int>[5]);
    expect(keys(one.reverseEntriesFrom(6)), <int>[5]);
    expect(keys(one.reverseEntriesFrom(4)), isEmpty);
  });

  test('iterables can be iterated more than once and report their length', () {
    final SortedMap<int, int> map = _of(<int>[10, 20, 30, 40]);
    final Iterable<MapEntry<int, int>> reverse = map.reverseEntries;
    final Iterable<MapEntry<int, int>> from = map.reverseEntriesFrom(25);
    expect(reverse.map((MapEntry<int, int> e) => e.key), <int>[40, 30, 20, 10]);
    expect(reverse.map((MapEntry<int, int> e) => e.key), <int>[40, 30, 20, 10]);
    expect(reverse.length, 4);
    expect(reverse.isEmpty, isFalse);
    expect(from.length, 2);
    expect(from.first.key, 20);
    expect(from.first.key, 20);
    expect(map.reverseEntriesFrom(5).isEmpty, isTrue);
    expect(map.entriesFrom(45).isEmpty, isTrue);
    expect(map.entriesFrom(25).length, 2);
  });

  test('reverseTraversal stops when the action returns true', () {
    final SortedMap<int, int> map = _of(<int>[1, 2, 3, 4]);
    final List<int> seen = <int>[];
    expect(
      map.reverseTraversal((int key, int value) {
        seen.add(key);
        return key == 3;
      }),
      isTrue,
    );
    expect(seen, <int>[4, 3]);
  });

  test('every iterator variant and neighbour lookup match a sorted list', () {
    // Odd keys only, so every even probe falls between two keys (or outside the range). Built both
    // by random inserts and from sorted entries, so both tree shapes are walked.
    final Random random = Random(3);
    for (final int n in <int>[1, 2, 3, 7, 8, 31, 64, 100]) {
      final List<int> sorted = List<int>.generate(n, (int i) => 2 * i + 1);
      final List<SortedMap<int, int>> maps = <SortedMap<int, int>>[
        _of(sorted.toList()..shuffle(random)),
        SortedMap<int, int>.fromSortedEntries(<MapEntry<int, int>>[
          for (final int k in sorted) MapEntry<int, int>(k, -k),
        ], _cmp),
      ];
      for (final SortedMap<int, int> map in maps) {
        List<int> keys(Iterable<MapEntry<int, int>> e) =>
            e.map((MapEntry<int, int> x) => x.key).toList();
        expect(keys(map.entries), sorted);
        expect(keys(map.reverseEntries), sorted.reversed.toList());
        expect(map.minKey, sorted.first);
        expect(map.maxKey, sorted.last);
        for (int probe = 0; probe <= 2 * n + 1; probe++) {
          expect(
            keys(map.entriesFrom(probe)),
            sorted.where((int k) => k >= probe).toList(),
            reason: 'entriesFrom($probe), n=$n',
          );
          expect(
            keys(map.reverseEntriesFrom(probe)),
            sorted.reversed.where((int k) => k <= probe).toList(),
            reason: 'reverseEntriesFrom($probe), n=$n',
          );
        }
        for (int i = 0; i < n; i++) {
          final int k = sorted[i];
          expect(map.predecessorKey(k), i == 0 ? null : sorted[i - 1]);
          expect(map.successorKey(k), i == n - 1 ? null : sorted[i + 1]);
          expect(map.indexOf(k), i);
        }
      }
    }
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
