// Scenarios shared by the four sorted map conformance tests (not a test file). The upstream suites
// are two per platform (array-backed and tree-backed map); the skeleton has one `SortedMap` type
// whose factory picks the representation, so the same behaviour is exercised at two sizes.
import 'dart:math';

import 'package:firebase_database_dart/src/core/util/sorted_map.dart';
import 'package:test/test.dart';

int _cmp(int a, int b) => a.compareTo(b);

/// An empty map ordered by int keys.
SortedMap<int, int> emptyIntMap() => SortedMap<int, int>(_cmp);

/// A map of [keys] with each key as its value.
SortedMap<int, int> intMap(Iterable<int> keys) {
  var map = emptyIntMap();
  for (final key in keys) {
    map = map.insert(key, key);
  }
  return map;
}

/// 0 to [count] - 1, shuffled by [random].
List<int> shuffled(int count, Random random) =>
    List<int>.generate(count, (i) => i)..shuffle(random);

List<int> _keys(Iterable<MapEntry<int, int>> entries) => [
  for (final entry in entries) entry.key,
];

/// The behaviour of iOS `FArraySortedDictionaryTests` / `FTreeSortedDictionaryTests`, with
/// [count] items where the iOS tests use 20 (array) or 100 (tree).
void iosScenarios(int count) {
  final random = Random(20);

  test('create node', () {
    final map = SortedMap<String, String>(
      (a, b) => a.compareTo(b),
    ).insert('key', 'value');
    expect(map.length, 1);
  });

  test('search for a specific key', () {
    final map = intMap([1, 2]);
    expect(map[1], 1);
    expect(map[2], 2);
    expect(map[3], isNull);
    expect(map.containsKey(3), isFalse);
  });

  test('remove key value pair leaves the original unchanged', () {
    final map = intMap([1, 2]);
    final newMap = map.remove(1);
    expect(newMap[2], 2);
    expect(newMap[1], isNull);
    expect(map[1], 1);
    expect(map[2], 2);
  });

  test('more removals', () {
    final map = intMap([1, 50, 3, 4, 7, 9, 20, 18, 2, 71, 42, 88]);
    expect(map[7], isNotNull);
    expect(map[3], isNotNull);
    expect(map[1], isNotNull);

    final m1 = map.remove(7);
    final m2 = map.remove(3);
    final m3 = map.remove(1);

    expect(m1[7], isNull);
    expect(m1[3], isNotNull);
    expect(m1[1], isNotNull);
    expect(m2[3], isNull);
    expect(m2[7], isNotNull);
    expect(m2[1], isNotNull);
    expect(m3[1], isNull);
    expect(m3[7], isNotNull);
    expect(m3[3], isNotNull);
  });

  test('removal bug', () {
    final map = intMap([1, 2, 3]);
    expect([map[1], map[2], map[3]], [1, 2, 3]);
    final m1 = map.remove(2);
    expect(m1[1], 1);
    expect(m1[3], 3);
    expect(m1[2], isNull);
  });

  test('increasing', () {
    var map = emptyIntMap();
    for (var i = 0; i < count; i++) {
      map = map.insert(i, i);
    }
    expect(map.length, count);
    for (var i = 0; i < count; i++) {
      map = map.remove(i);
    }
    expect(map.length, 0);
  });

  test('override', () {
    final map = emptyIntMap().insert(10, 10).insert(10, 8);
    expect(map[10], 8);
    expect(map.length, 1);
  });

  test('empty', () {
    expect(emptyIntMap().insert(10, 10).remove(10).isEmpty, isTrue);
  });

  test('empty get', () {
    expect(emptyIntMap()[5], isNull);
  });

  test('empty count', () {
    expect(emptyIntMap().length, 0);
  });

  test('empty removal', () {
    expect(emptyIntMap().remove(5).length, 0);
  });

  test('reverse traversal', () {
    final map = intMap([1, 5, 3, 2, 4]);
    var next = 5;
    final stopped = map.reverseTraversal((key, value) {
      expect(key, next);
      next--;
      return false;
    });
    expect(stopped, isFalse);
    expect(next, 0);
  });

  test('insertion and removal of many items', () {
    final toInsert = shuffled(count, random);
    final toRemove = shuffled(count, random);
    var map = emptyIntMap();
    for (final key in toInsert) {
      map = map.insert(key, key);
    }
    expect(map.length, count);

    var next = 0;
    map.inOrderTraversal((key, value) {
      expect(key, next);
      expect(value, next);
      next++;
      return false;
    });
    expect(next, count);

    for (final key in toRemove) {
      map = map.remove(key);
    }
    expect(map.length, 0);
  });

  test('order is correct', () {
    final map = intMap([1, 7, 8, 5, 2, 6, 4, 0, 3]);
    expect(map.length, 9);
    expect(_keys(map.entries), [0, 1, 2, 3, 4, 5, 6, 7, 8]);
  });

  test('predecessor key', () {
    final map = intMap([1, 50, 3, 4, 7, 9]);
    expect(map.predecessorKey(1), isNull);
    expect(map.predecessorKey(3), 1);
    expect(map.predecessorKey(4), 3);
    expect(map.predecessorKey(7), 4);
    expect(map.predecessorKey(9), 7);
    expect(map.predecessorKey(50), 9);
    expect(() => map.predecessorKey(777), throwsA(anything));
  });

  test('enumerator', () {
    final map = intMap(shuffled(count, random));
    expect(map.length, count);
    expect(_keys(map.entries), List<int>.generate(count, (i) => i));
  });

  test('reverse enumerator', () {
    final map = intMap(shuffled(count, random));
    expect(map.length, count);
    expect(
      _keys(map.reverseEntries),
      List<int>.generate(count, (i) => count - 1 - i),
    );
  });

  test('enumerator from', () {
    final map = intMap(shuffled(count, random).map((i) => i * 2));
    expect(map.length, count);
    // From between keys.
    expect(_keys(map.entriesFrom(11)), [
      for (var k = 12; k < count * 2; k += 2) k,
    ]);
    // From a key in the map.
    expect(_keys(map.entriesFrom(10)), [
      for (var k = 10; k < count * 2; k += 2) k,
    ]);
  });

  test('reverse enumerator from', () {
    final map = intMap(shuffled(count, random).map((i) => i * 2));
    expect(map.length, count);
    // From between keys.
    expect(_keys(map.reverseEntriesFrom(11)), [
      for (var k = 10; k >= 0; k -= 2) k,
    ]);
    // From a key in the map.
    expect(_keys(map.reverseEntriesFrom(10)), [
      for (var k = 10; k >= 0; k -= 2) k,
    ]);
  });

  test('conversion from a small to a large map keeps order and size', () {
    // iOS: threshold + 5 items, checking the representation at each step (not observable here).
    final n = count + 30;
    var map = emptyIntMap();
    final keys = shuffled(n, random);
    for (var i = 0; i < n; i++) {
      map = map.insert(keys[i], keys[i]);
      expect(map.length, i + 1);
    }
    expect(_keys(map.entries), List<int>.generate(n, (i) => i));
  });
}

/// The quickcheck properties of Android `ArraySortedMapTest` / `RBTreeSortedMapTest` over seeded
/// random int maps of up to [maxSize] entries, each tried [rounds] times.
void androidProperties(int maxSize, {int rounds = 60}) {
  final random = Random(7);

  Map<int, int> anyMap([int? size]) {
    final length = size ?? random.nextInt(maxSize + 1);
    return {
      for (var i = 0; i < length; i++)
        random.nextInt(1 << 30) - (1 << 29): random.nextInt(1 << 30),
    };
  }

  SortedMap<int, int> fromMap(Map<int, int> data) =>
      SortedMap<int, int>.fromMap(data, _cmp);

  void forEachMap(void Function(Map<int, int> data) body) {
    for (var i = 0; i < rounds; i++) {
      body(anyMap());
    }
  }

  test('basic immutable sorted map building', () {
    final data = {
      for (final (i, k) in 'abcdefghij'.split('').indexed) k: i + 1,
    };
    final map = SortedMap<String, int>.fromMap(data, (a, b) => a.compareTo(b));
    expect(map.length, 10);
  });

  test('empty map', () {
    final map = SortedMap<String, int>.fromMap({}, (a, b) => a.compareTo(b));
    expect(map.length, 0);
    expect(map.isEmpty, isTrue);
  });

  test('almost empty map', () {
    final map = SortedMap<String, int?>.fromMap({
      'a': 1,
      'b': null,
    }, (a, b) => a.compareTo(b));
    expect(map.length, 2);
    expect(map.isEmpty, isFalse);
  });

  test('can replace an existing item', () {
    final map = emptyIntMap().insert(1, 1).insert(1, 2);
    expect(map[1], 2);
  });

  test('predecessor key throws if the key is not present', () {
    final map = SortedMap<String, int>(
      (a, b) => a.compareTo(b),
    ).insert('key', 1);
    expect(map.predecessorKey('key'), isNull);
    expect(() => map.predecessorKey('no-key'), throwsA(anything));
  });

  test('size is correct', () {
    forEachMap((data) => expect(fromMap(data).length, data.length));
  });

  test('add works', () {
    forEachMap((data) {
      var map = emptyIntMap();
      data.forEach((key, value) => map = map.insert(key, value));
      data.forEach((key, value) => expect(map[key], value));
    });
  });

  test('remove works', () {
    forEachMap((data) {
      var map = fromMap(data);
      for (final key in data.keys) {
        map = map.remove(key);
      }
      expect(map.length, 0);
    });
  });

  test('iteration is in order', () {
    forEachMap((data) {
      final expected = data.keys.toList()..sort();
      expect(_keys(fromMap(data).entries), expected);
    });
  });

  test('iteration from key is in order', () {
    forEachMap((data) {
      final keys = data.keys.toList()..sort();
      final fromKey = keys.isEmpty || random.nextBool()
          ? random.nextInt(1 << 30) - (1 << 29)
          : keys.first;
      final expected = keys.where((k) => k >= fromKey).toList();
      expect(_keys(fromMap(data).entriesFrom(fromKey)), expected);
    });
  });

  test('reverse iteration is in order', () {
    forEachMap((data) {
      final expected = (data.keys.toList()..sort()).reversed.toList();
      expect(_keys(fromMap(data).reverseEntries), expected);
    });
  });

  test('reverse iteration from key is in order', () {
    forEachMap((data) {
      final keys = data.keys.toList()..sort();
      final fromKey = keys.isEmpty || random.nextBool()
          ? random.nextInt(1 << 30) - (1 << 29)
          : keys.first;
      final expected = keys
          .where((k) => k <= fromKey)
          .toList()
          .reversed
          .toList();
      expect(_keys(fromMap(data).reverseEntriesFrom(fromKey)), expected);
    });
  });

  test('predecessor key is correct', () {
    forEachMap((data) {
      final map = fromMap(data);
      int? predecessor;
      for (final entry in map.entries) {
        expect(map.predecessorKey(entry.key), predecessor);
        predecessor = entry.key;
      }
    });
  });

  test('successor key is correct', () {
    forEachMap((data) {
      final map = fromMap(data);
      int? last;
      for (final entry in map.entries) {
        if (last != null) {
          expect(map.successorKey(last), entry.key);
        }
        last = entry.key;
      }
      if (last != null) {
        expect(map.successorKey(last), isNull);
      }
    });
  });

  test('add above the array limit keeps every item', () {
    final data = anyMap(100);
    var map = emptyIntMap();
    data.forEach((key, value) => map = map.insert(key, value));
    data.forEach((key, value) => expect(map[key], value));
    expect(map.length, data.length);
  });
}
