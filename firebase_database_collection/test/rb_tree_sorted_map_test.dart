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

    ImmutableSortedMap<String, int> map =
        RBTreeSortedMap.fromMap(data, standardComparator());

    expect(map.length, data.length);
  });

  test('emptyMap', () {
    final Map<String, int> data = <String, int>{};

    ImmutableSortedMap<String, int> map =
        RBTreeSortedMap.fromMap(data, standardComparator());

    expect(map.length, data.length);
    expect(map.isEmpty, isTrue);
  });

  test('almostEmptyMap', () {
    final Map<String, int> data = <String, int>{
      'a': 1,
      'b': null,
    };

    ImmutableSortedMap<String, int> map =
        RBTreeSortedMap.fromMap(data, standardComparator());

    expect(map.length, data.length);
    expect(map.isNotEmpty, isTrue);
  });

  test('searchForASpecificKey', () {
    ImmutableSortedMap<int, int> map =
        RBTreeSortedMap<int, int>(intComparator).insert(1, 1).insert(2, 2);

    expect(map[1], 1);
    expect(map[2], 2);
    expect(map[3], isNull);
  });

  test('removeKeyValuePair', () {
    ImmutableSortedMap<int, int> map =
        RBTreeSortedMap<int, int>(intComparator).insert(1, 1).insert(2, 2);

    map = map.remove(1);

    expect(map[2], 2);
    expect(map[1], isNull);
  });

  test('moreRemovals', () {
    ImmutableSortedMap<int, int> map = RBTreeSortedMap<int, int>(intComparator)
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
    ImmutableSortedMap<int, int> map = RBTreeSortedMap<int, int>(intComparator);
    map = map.insert(1, 1).insert(1, 2);

    expect(map[1], 2);
  });

  test('replacesExistingKey', () {
    ImmutableSortedMap<String, int> map =
        RBTreeSortedMap<String, int>(standardComparator());

    map = map.insert('1', 1).insert('2', 2);

    expect(map.maxKey, isNot('a'));
    expect(map.maxKey, '2');
  });

  test('replaceExactKeyYieldsSameMap', () {
    ImmutableSortedMap<String, int> map =
        RBTreeSortedMap<String, int>(standardComparator());

    map = map.insert('1', 1);

    expect(map, map.insert('1', 1));
  });

  test('removingNonExistentKeyYieldsSameMap', () {
    ImmutableSortedMap<String, int> map =
        RBTreeSortedMap<String, int>(standardComparator());

    map = map.insert('key', 1);

    expect(map, map.remove('no-key'));
  });

  test('predecessorKeyThrowsExceptionIfKeyIsNotPresent', () {
    ImmutableSortedMap<String, int> map =
        RBTreeSortedMap<String, int>(standardComparator());

    map = map.insert('key', 1);
    expect(map.getPredecessorKey('key'), isNull);

    expect(() => map.getPredecessorKey('no-key'), throwsArgumentError);
  });

  // QuickCheck Tests
  final someMaps = CombinedGeneratorsIterables.someMaps;
  final someMapsFromKeysAndValuesOfSize =
      CombinedGeneratorsIterables.someMapsFromKeysAndValuesOfSize;
  final integers = PrimitiveGenerators.integers;

  test('sizeIsCorrect', () {
    for (Map<int, int> any in someMaps(integers(), integers())) {
      expect(RBTreeSortedMap.fromMap(any, intComparator).length, any.length);
    }
  });

  test('addWorks', () {
    for (Map<int, int> any in someMaps(integers(), integers())) {
      ImmutableSortedMap<int, int> map =
          new RBTreeSortedMap<int, int>(intComparator);
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
          RBTreeSortedMap.fromMap<int, int>(any, intComparator);
      for (MapEntry<int, int> entry in any.entries) {
        map = map.remove(entry.key);
      }

      expect(map.length, 0);
    }
  });

  test('iterationIsInOrder', () {
    for (Map<int, int> any in someMaps(integers(), integers())) {
      List<int> expectedKeys = new List<int>.from(any.keys);
      expectedKeys.sort();

      ImmutableSortedMap<int, int> map =
          RBTreeSortedMap.fromMap<int, int>(any, intComparator);

      List<int> actualKeys = new List();
      for (MapEntry<int, int> entry in map) {
        actualKeys.add(entry.key);
      }

      expect(actualKeys, expectedKeys);
    }
  });

  test('iterationFromKeyIsInOrder', () {
    for (Map<int, int> any in someMaps(integers(), integers())) {
      List<int> expectedKeys = new List<int>.from(any.keys);
      int fromKey =
          (expectedKeys.isEmpty || PrimitiveGenerators.booleans().next())
              ? integers().next()
              : expectedKeys[0];
      expectedKeys.sort();
      expectedKeys.removeWhere((int next) => next.compareTo(fromKey) < 0);

      ImmutableSortedMap<int, int> map =
          RBTreeSortedMap.fromMap<int, int>(any, intComparator);

      List<int> actualKeys = new List<int>();
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
      List<int> expectedKeys = new List<int>.from(any.keys);
      expectedKeys.sort();
      expectedKeys = expectedKeys.reversed.toList();

      ImmutableSortedMap<int, int> map =
          RBTreeSortedMap.fromMap<int, int>(any, intComparator);

      List<int> actualKeys = new List<int>();
      final Iterator<MapEntry<int, int>> iteratorFrom = map.reverseIterator;
      while (iteratorFrom.moveNext()) {
        actualKeys.add(iteratorFrom.current.key);
      }

      expect(actualKeys, expectedKeys);
    }
  });

  test('reverseIterationFromKeyIsInOrder', () {
    for (Map<int, int> any in someMaps(integers(), integers())) {
      List<int> expectedKeys = new List<int>.from(any.keys);
      int fromKey =
          (expectedKeys.isEmpty || PrimitiveGenerators.booleans().next())
              ? integers().next()
              : expectedKeys[0];
      expectedKeys.sort();
      expectedKeys = expectedKeys.reversed.toList();
      expectedKeys.removeWhere((int next) => next.compareTo(fromKey) > 0);

      ImmutableSortedMap<int, int> map =
          RBTreeSortedMap.fromMap<int, int>(any, intComparator);

      List<int> actualKeys = new List<int>();
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
      ImmutableSortedMap<int, int> map =
          RBTreeSortedMap.fromMap<int, int>(any, intComparator);

      int predecessorKey;

      for (MapEntry<int, int> entry in map) {
        expect(map.getPredecessorKey(entry.key), predecessorKey);
        predecessorKey = entry.key;
      }
    }
  });

  test('successorKeyIsCorrect', () {
    for (Map<int, int> any in someMaps(integers(), integers())) {
      ImmutableSortedMap<int, int> map =
          RBTreeSortedMap.fromMap<int, int>(any, intComparator);

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

  test('equalsIsCorrect', () {
    ImmutableSortedMap<int, int> map;
    ImmutableSortedMap<int, int> copy;
    ImmutableSortedMap<int, int> arrayCopy;
    ImmutableSortedMap<int, int> copyWithDifferentComparator;
    map = new RBTreeSortedMap<int, int>(intComparator);
    copy = new RBTreeSortedMap<int, int>(intComparator);
    arrayCopy = ArraySortedMap<int, int>(intComparator);
    copyWithDifferentComparator =
        new ArraySortedMap<int, int>((int o1, int o2) => o1.compareTo(o2));

    int size = ImmutableSortedMap.arrayToRbTreeSizeThreshold - 1;
    final Iterator<Map<int, int>> it = someMapsFromKeysAndValuesOfSize(
            integers(), integers(), PrimitiveGenerators.fixedValuesSingle(size))
        .iterator;
    it.moveNext();
    Map<int, int> any = it.current;

    for (MapEntry<int, int> entry in any.entries) {
      int key = entry.key;
      int value = entry.value;
      map = map.insert(key, value);
      copy = copy.insert(key, value);
      arrayCopy = arrayCopy.insert(key, value);
      copyWithDifferentComparator =
          copyWithDifferentComparator.insert(key, value);
    }
    expect(map, copy);
    expect(map, arrayCopy);
    expect(arrayCopy, map);

    expect(map, isNot(copyWithDifferentComparator));
    expect(map, isNot(copy.remove(copy.maxKey)));
    expect(map, isNot(copy.insert(copy.maxKey + 1, 1)));
    expect(map, isNot(arrayCopy.remove(arrayCopy.maxKey)));
  });
}
