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

// Port of the JS SDK test/unit/util/sorted_set.test.ts against
// ImmutableSortedSet, which has the Android API: add is insert, delete is
// remove, has is contains, first/last are minEntry/maxEntry. The JS
// forEachInRange, forEachWhile and firstAfterOrEqual helpers are all walks
// from a start element, which the port (like Android) does with iteratorFrom.
// The JS diffSortedSets is Util.diffCollections in the port.

import 'package:cloud_firestore_dart/src/database_collection/immutable_sorted_set.dart';
import 'package:cloud_firestore_dart/src/database_collection/standard_compartor.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart';
import 'package:test/test.dart';

class _Entry {
  const _Entry(this.key, this.value);

  final int key;
  final String value;

  @override
  bool operator ==(Object other) =>
      other is _Entry && key == other.key && value == other.value;

  @override
  int get hashCode => Object.hash(key, value);

  @override
  String toString() => '{key: $key, value: $value}';
}

void main() {
  final Comparator<int> primitiveComparator = naturalComparator<int>();

  ImmutableSortedSet<int> emptySet() =>
      ImmutableSortedSet<int>(<int>[], primitiveComparator);

  /// Calls [visit] for every element from [start] on, until it returns false.
  void forEachFrom(
    ImmutableSortedSet<int> set,
    int start,
    bool Function(int elem) visit,
  ) {
    final Iterator<int> iterator = set.iteratorFrom(start);
    while (iterator.moveNext()) {
      if (!visit(iterator.current)) {
        return;
      }
    }
  }

  /// The JS forEachInRange([start, end], cb): every element in [start, end).
  void forEachInRange(
    ImmutableSortedSet<int> set,
    List<int> range,
    void Function(int elem) cb,
  ) {
    forEachFrom(set, range[0], (int elem) {
      if (primitiveComparator(elem, range[1]) >= 0) {
        return false;
      }
      cb(elem);
      return true;
    });
  }

  /// The JS firstAfterOrEqual(elem).
  int? firstAfterOrEqual(ImmutableSortedSet<int> set, int elem) {
    final Iterator<int> iterator = set.iteratorFrom(elem);
    return iterator.moveNext() ? iterator.current : null;
  }

  test('keeps elements in the right order', () {
    ImmutableSortedSet<int> set = emptySet();

    set = set.insert(4).insert(2).insert(-1).insert(0);

    expect(set.toList(), <int>[-1, 0, 2, 4]);

    expect(set.minEntry, -1);
    expect(set.maxEntry, 4);

    expect(set.contains(4), isTrue);
    expect(set.contains(2), isTrue);
    expect(set.contains(-1), isTrue);
    expect(set.contains(0), isTrue);
  });

  test('adds and deletes elements', () {
    ImmutableSortedSet<int> set = emptySet()
        .insert(5)
        .insert(2)
        .insert(1)
        .insert(0)
        .remove(-1) // missing elem
        .remove(2);
    expect(set.toList(), <int>[0, 1, 5]);

    set = set.remove(0);
    expect(set.toList(), <int>[1, 5]);
  });

  test('updates elements', () {
    ImmutableSortedSet<_Entry> set = ImmutableSortedSet<_Entry>(
      <_Entry>[],
      (_Entry left, _Entry right) => primitiveComparator(left.key, right.key),
    );

    // This is a weird case where comparator returns 0 for two elements that
    // differ. Yet we should handle it correctly.

    set = set.insert(const _Entry(1, 'old'));
    expect(set.toList(), <_Entry>[const _Entry(1, 'old')]);

    set = set.insert(const _Entry(1, 'new'));
    expect(set.toList(), <_Entry>[const _Entry(1, 'new')]);
  });

  test('can iterate over all elements within a range', () {
    final ImmutableSortedSet<int> set = emptySet()
        .insert(0)
        .insert(2)
        .insert(5)
        .insert(10)
        .insert(12);

    final List<int> arr = <int>[];
    forEachInRange(set, <int>[2, 10], arr.add);
    expect(arr, <int>[2, 5]);

    // Few cases that iterate over nothing.
    forEachInRange(set, <int>[2, 0], (int elem) => fail('$elem'));
    forEachInRange(set, <int>[-10, -5], (int elem) => fail('$elem'));
    forEachInRange(set, <int>[15, 18], (int elem) => fail('$elem'));
  });

  test('can iterate over all elements while condition', () {
    final ImmutableSortedSet<int> set = emptySet()
        .insert(0)
        .insert(2)
        .insert(5)
        .insert(10)
        .insert(12);

    List<int> arr = <int>[];
    const int start = 2;
    forEachFrom(set, start, (int elem) {
      if (elem >= 10) {
        return false;
      } else {
        arr.add(elem);
        return true;
      }
    });
    expect(arr, <int>[2, 5]);

    arr = <int>[];
    final Iterator<int> iterator = set.iterator;
    while (iterator.moveNext()) {
      final int elem = iterator.current;
      if (elem >= 10) {
        break;
      }
      arr.add(elem);
    }
    expect(arr, <int>[0, 2, 5]);

    forEachFrom(set, 15, (int elem) {
      fail('$elem');
    });
  });

  test('can find element equal or greater to provided.', () {
    final ImmutableSortedSet<int> empty = emptySet();
    final ImmutableSortedSet<int> set = empty
        .insert(0)
        .insert(2)
        .insert(5)
        .insert(10)
        .insert(12);

    expect(firstAfterOrEqual(set, 2), 2);
    expect(firstAfterOrEqual(set, 3), 5);
    expect(firstAfterOrEqual(set, 13), isNull);
    expect(firstAfterOrEqual(empty, 1), isNull);
  });

  test('can unionWith another set.', () {
    final ImmutableSortedSet<int> empty = emptySet();
    final ImmutableSortedSet<int> set = empty.insert(0).insert(1).insert(2);
    final ImmutableSortedSet<int> set2 = empty.insert(2).insert(3).insert(4);
    final ImmutableSortedSet<int> expected = empty
        .insert(0)
        .insert(1)
        .insert(2)
        .insert(3)
        .insert(4);
    expect(set.unionWith(set2), expected);
  });

  test('returns indexes of elements', () {
    final ImmutableSortedSet<int> set = emptySet()
        .insert(-1)
        .insert(5)
        .insert(1)
        .insert(2)
        .insert(0);

    expect(set.indexOf(-1), 0);
    expect(set.indexOf(0), 1);
    expect(set.indexOf(1), 2);
    expect(set.indexOf(2), 3);
    expect(set.indexOf(3), -1);
    expect(set.indexOf(4), -1);
    expect(set.indexOf(5), 4);
  });

  Future<({List<String> added, List<String> removed})> computeDiffs(
    List<String> before,
    List<String> after,
  ) async {
    final Comparator<String> stringComparator = naturalComparator<String>();
    ImmutableSortedSet<String> beforeSorted = ImmutableSortedSet<String>(
      <String>[],
      stringComparator,
    );
    ImmutableSortedSet<String> afterSorted = ImmutableSortedSet<String>(
      <String>[],
      stringComparator,
    );
    for (final String v in before) {
      beforeSorted = beforeSorted.insert(v);
    }
    for (final String v in after) {
      afterSorted = afterSorted.insert(v);
    }

    final List<String> added = <String>[];
    final List<String> removed = <String>[];
    await diffCollections(
      beforeSorted,
      afterSorted,
      stringComparator,
      added.add,
      removed.add,
    );
    return (added: added, removed: removed);
  }

  test('diff sorted sets with missing element', () async {
    final (:List<String> added, :List<String> removed) = await computeDiffs(
      <String>['a', 'b', 'c'],
      <String>['a', 'b'],
    );
    expect(added, isEmpty);
    expect(removed, <String>['c']);
  });

  test('diff sorted sets with added element', () async {
    final (:List<String> added, :List<String> removed) = await computeDiffs(
      <String>['a', 'b'],
      <String>['a', 'b', 'c'],
    );
    expect(added, <String>['c']);
    expect(removed, isEmpty);
  });

  test('diff sorted sets with empty sets', () async {
    {
      final (:List<String> added, :List<String> removed) = await computeDiffs(
        <String>['a'],
        <String>[],
      );
      expect(added, isEmpty);
      expect(removed, <String>['a']);
    }
    {
      final (:List<String> added, :List<String> removed) = await computeDiffs(
        <String>[],
        <String>['a'],
      );
      expect(added, <String>['a']);
      expect(removed, isEmpty);
    }
    {
      final (:List<String> added, :List<String> removed) = await computeDiffs(
        <String>[],
        <String>[],
      );
      expect(added, isEmpty);
      expect(removed, isEmpty);
    }
  });
}
