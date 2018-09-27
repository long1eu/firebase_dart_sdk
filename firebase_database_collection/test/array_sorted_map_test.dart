// File created by
// Lung Razvan <long1eu>
// on 19/09/2018

import 'package:dart_quickcheck/dart_quickcheck.dart';
import 'package:firebase_database_collection/src/array_sorted_map.dart';
import 'package:firebase_database_collection/src/immutable_sorted_map.dart';
import 'package:firebase_database_collection/src/rb_tree_sorted_map.dart';
import 'package:firebase_database_collection/src/standard_compartor.dart';
import 'package:test/test.dart';

void main() {
  final Comparator<num> intComparator = standardComparator<num>();

  test('basicImmutableSortedMapBuilding', () {
    final Map<String, int> data = <String, int>{
      'a': 1,
      'b': 2,
      'c': 3,
      'd': 4,
      'e': 5,
      'f': 6,
      'g': 7,
      'h': 8,
      'i': 9,
      'j': 10,
    };

    final ImmutableSortedMap<String, int> map =
        ArraySortedMap<String, int>.fromMap(data, standardComparator());

    expect(map.length, data.length);
  });

  test('emptyMap', () {
    final Map<String, int> data = <String, int>{};

    final ImmutableSortedMap<String, int> map =
        ArraySortedMap<String, int>.fromMap(data, standardComparator());

    expect(map.length, data.length);
    expect(map.isEmpty, isTrue);
  });

  test('almostEmptyMap', () {
    final Map<String, int> data = <String, int>{
      'a': 1,
      'b': null,
    };

    final ImmutableSortedMap<String, int> map =
        ArraySortedMap<String, int>.fromMap(data, standardComparator());

    expect(map.length, data.length);
    expect(map.isNotEmpty, isTrue);
  });

  test('searchForASpecificKey', () {
    final ImmutableSortedMap<int, int> map =
        ArraySortedMap<int, int>(intComparator).insert(1, 1).insert(2, 2);

    expect(map[1], 1);
    expect(map[2], 2);
    expect(map[3], isNull);
  });

  test('removeKeyValuePair', () {
    ImmutableSortedMap<int, int> map =
        ArraySortedMap<int, int>(intComparator).insert(1, 1).insert(2, 2);

    map = map.remove(1);

    expect(map[2], 2);
    expect(map[1], isNull);
  });

  test('moreRemovals', () {
    ImmutableSortedMap<int, int> map = ArraySortedMap<int, int>(intComparator)
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

    map = map.remove(7).remove(3).remove(1);

    expect(map[7], isNull);
    expect(map[5], isNull);
    expect(map[1], isNull);
    expect(map[50], 50);
  });

  test('canReplaceExistingItem', () {
    ImmutableSortedMap<int, int> map = ArraySortedMap<int, int>(intComparator);
    map = map.insert(1, 1).insert(1, 2);

    expect(map[1], 2);
  });

  test('replacesExistingKey', () {
    ImmutableSortedMap<String, int> map =
        ArraySortedMap<String, int>(standardComparator());

    map = map.insert('1', 1).insert('2', 2);

    expect(map.maxKey, isNot('a'));
    expect(map.maxKey, '2');
  });

  test('replaceExactKeyYieldsSameMap', () {
    ImmutableSortedMap<String, int> map =
        ArraySortedMap<String, int>(standardComparator());

    map = map.insert('1', 1);

    expect(map, map.insert('1', 1));
  });

  test('removingNonExistentKeyYieldsSameMap', () {
    ImmutableSortedMap<String, int> map =
        ArraySortedMap<String, int>(standardComparator());

    map = map.insert('key', 1);

    expect(map, map.remove('no-key'));
  });

  test('predecessorKeyThrowsExceptionIfKeyIsNotPresent', () {
    ImmutableSortedMap<String, int> map =
        ArraySortedMap<String, int>(standardComparator());

    map = map.insert('key', 1);
    expect(map.getPredecessorKey('key'), isNull);

    expect(() => map.getPredecessorKey('no-key'), throwsArgumentError);
  });

  // QuickCheck Tests
  const Iterable<Map<K, V>> Function<K, V>(
          Generator<K> keys, Generator<V> values) someMaps =
      CombinedGeneratorsIterables.someMaps;
  const Iterable<Map<K, V>> Function<K, V>(
          Generator<K> keys, Generator<V> values, Generator<int> size)
      someMapsFromKeysAndValuesOfSize =
      CombinedGeneratorsIterables.someMapsFromKeysAndValuesOfSize;
  const Generator<int> Function() integers = PrimitiveGenerators.integers;

  test('sizeIsCorrect', () {
    for (Map<int, int> any in someMaps(integers(), integers())) {
      expect(ArraySortedMap<int, int>.fromMap(any, intComparator).length,
          any.length);
    }
  });

  test('addWorks', () {
    for (Map<int, int> any in someMaps(integers(), integers())) {
      ImmutableSortedMap<int, int> map =
          ArraySortedMap<int, int>(intComparator);
      for (MapEntry<int, int> entry in any.entries) {
        map = map.insert(entry.key, entry.value);
      }
      for (MapEntry<int, int> entry in any.entries) {
        expect(map[entry.key], entry.value);
      }
    }
  });

  test('removeWorks', () {
    for (Map<int, int> any in someMaps(integers(), integers())) {
      ImmutableSortedMap<int, int> map =
          ArraySortedMap<int, int>.fromMap(any, intComparator);
      for (MapEntry<int, int> entry in any.entries) {
        map = map.remove(entry.key);
      }

      expect(map.length, 0);
    }
  });

  test('iterationIsInOrder', () {
    for (Map<int, int> any in someMaps(integers(), integers())) {
      final List<int> expectedKeys = List<int>.from(any.keys);
      expectedKeys.sort();

      final ImmutableSortedMap<int, int> map =
          ArraySortedMap<int, int>.fromMap(any, intComparator);

      final List<int> actualKeys = <int>[];
      for (MapEntry<int, int> entry in map) {
        actualKeys.add(entry.key);
      }

      expect(actualKeys, expectedKeys);
    }
  });

  test('iterationFromKeyIsInOrder', () {
    for (Map<int, int> any in someMaps(integers(), integers())) {
      final List<int> expectedKeys = List<int>.from(any.keys);
      final int fromKey =
          (expectedKeys.isEmpty || PrimitiveGenerators.booleans().next())
              ? integers().next()
              : expectedKeys[0];
      expectedKeys.sort();
      expectedKeys.removeWhere((int next) => next.compareTo(fromKey) < 0);

      final ImmutableSortedMap<int, int> map =
          ArraySortedMap<int, int>.fromMap(any, intComparator);

      final List<int> actualKeys = <int>[];
      final Iterator<MapEntry<int, int>> iteratorFrom =
          map.iteratorFrom(fromKey);
      while (iteratorFrom.moveNext()) {
        actualKeys.add(iteratorFrom.current.key);
      }

      expect(actualKeys, expectedKeys);
    }
  });

  test('reverseIterationIsInOrder', () {
    for (Map<int, int> any in someMaps(integers(), integers())) {
      List<int> expectedKeys = List<int>.from(any.keys);
      expectedKeys.sort();
      expectedKeys = expectedKeys.reversed.toList();

      final ImmutableSortedMap<int, int> map =
          ArraySortedMap<int, int>.fromMap(any, intComparator);

      final List<int> actualKeys = <int>[];
      final Iterator<MapEntry<int, int>> iteratorFrom = map.reverseIterator;
      while (iteratorFrom.moveNext()) {
        actualKeys.add(iteratorFrom.current.key);
      }

      expect(actualKeys, expectedKeys);
    }
  });

  test('reverseIterationFromKeyIsInOrder', () {
    for (Map<int, int> any in someMaps(integers(), integers())) {
      List<int> expectedKeys = List<int>.from(any.keys);
      final int fromKey =
          (expectedKeys.isEmpty || PrimitiveGenerators.booleans().next())
              ? integers().next()
              : expectedKeys[0];
      expectedKeys.sort();
      expectedKeys = expectedKeys.reversed.toList();
      expectedKeys.removeWhere((int next) => next.compareTo(fromKey) > 0);

      final ImmutableSortedMap<int, int> map =
          ArraySortedMap<int, int>.fromMap(any, intComparator);

      final List<int> actualKeys = <int>[];
      final Iterator<MapEntry<int, int>> iteratorFrom =
          map.reverseIteratorFrom(fromKey);
      while (iteratorFrom.moveNext()) {
        actualKeys.add(iteratorFrom.current.key);
      }

      expect(actualKeys, expectedKeys);
    }
  });

  test('predecessorKeyIsCorrect', () {
    for (Map<int, int> any in someMaps(integers(), integers())) {
      final ImmutableSortedMap<int, int> map =
          ArraySortedMap<int, int>.fromMap(any, intComparator);

      int predecessorKey;

      for (MapEntry<int, int> entry in map) {
        expect(map.getPredecessorKey(entry.key), predecessorKey);
        predecessorKey = entry.key;
      }
    }
  });

  test('successorKeyIsCorrect', () {
    for (Map<int, int> any in someMaps(integers(), integers())) {
      final ImmutableSortedMap<int, int> map =
          ArraySortedMap<int, int>.fromMap(any, intComparator);

      int lastKey;

      for (MapEntry<int, int> entry in map) {
        if (lastKey != null) {
          expect(map.getSuccessorKey(lastKey), entry.key);
        }
        lastKey = entry.key;
      }

      if (lastKey != null) {
        expect(map.getSuccessorKey(lastKey), null);
      }
    }
  });

  test('addAboveLimitYieldsRBTree', () {
    for (Map<int, int> any
        in CombinedGeneratorsIterables.someMapsFromKeysAndValuesOfSize(
      integers(),
      integers(),
      PrimitiveGenerators.fixedValuesSingle(100),
    )) {
      ImmutableSortedMap<int, int> map =
          ArraySortedMap<int, int>(intComparator);

      for (MapEntry<int, int> entry in any.entries) {
        map = map.insert(entry.key, entry.value);
      }
      expect(map, const TypeMatcher<RBTreeSortedMap<int, int>>());
      for (MapEntry<int, int> entry in any.entries) {
        expect(map[entry.key], entry.value);
      }
    }
  });
  test('equalsIsCorrect', () {
    ImmutableSortedMap<int, int> map;
    ImmutableSortedMap<int, int> copy;
    ImmutableSortedMap<int, int> rbcopy;
    ImmutableSortedMap<int, int> copyWithDifferentComparator;
    map = ArraySortedMap<int, int>(intComparator);
    copy = ArraySortedMap<int, int>(intComparator);
    rbcopy = RBTreeSortedMap<int, int>(intComparator);
    copyWithDifferentComparator =
        ArraySortedMap<int, int>((int o1, int o2) => o1.compareTo(o2));

    const int size = ImmutableSortedMap.arrayToRbTreeSizeThreshold - 1;
    final Iterator<Map<int, int>> it = someMapsFromKeysAndValuesOfSize(
            integers(), integers(), PrimitiveGenerators.fixedValuesSingle(size))
        .iterator;
    it.moveNext();
    final Map<int, int> any = it.current;

    for (MapEntry<int, int> entry in any.entries) {
      final int key = entry.key;
      final int value = entry.value;
      map = map.insert(key, value);
      copy = copy.insert(key, value);
      rbcopy = rbcopy.insert(key, value);
      copyWithDifferentComparator =
          copyWithDifferentComparator.insert(key, value);
    }
    expect(map, copy);
    expect(map, rbcopy);
    expect(rbcopy, map);

    expect(map, isNot(copyWithDifferentComparator));
    expect(map, isNot(copy.remove(copy.maxKey)));
    expect(map, isNot(copy.insert(copy.maxKey + 1, 1)));
    expect(map, isNot(rbcopy.remove(rbcopy.maxKey)));
  });

  test('perf', () {
    ImmutableSortedMap<int, int> map = ArraySortedMap<int, int>(intComparator);

    int total = 0;
    const int tries = 100;
    for (int j = 0; j < tries; j++) {
      final int startTime = DateTime.now().millisecondsSinceEpoch;
      for (int i = 0; i < 50000; i++) {
        map = map.insert(i, i);
      }

      for (int i = 0; i < 50000; i++) {
        map = map.remove(i);
      }
      final int elapsed = DateTime.now().millisecondsSinceEpoch - startTime;
      total += elapsed;
      print('Elapsed: $elapsed');
    }
    print('Average: ${total / tries}');
  });
}
