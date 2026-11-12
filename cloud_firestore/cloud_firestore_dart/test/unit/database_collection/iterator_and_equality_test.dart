import 'package:cloud_firestore_dart/src/database_collection/immutable_sorted_map.dart';
import 'package:cloud_firestore_dart/src/database_collection/immutable_sorted_set.dart';
import 'package:cloud_firestore_dart/src/database_collection/rb_tree_sorted_map.dart';
import 'package:cloud_firestore_dart/src/database_collection/standard_compartor.dart';
import 'package:test/test.dart';

ImmutableSortedMap<int, int> _rbMap(int n) {
  final Map<int, int> data = <int, int>{for (int i = 0; i < n; i++) i: i * 10};
  return RBTreeSortedMap<int, int>.fromMap(data, standardComparator<num>());
}

void main() {
  group('RB tree map iterator', () {
    test('moveNext advances and current has no side effects', () {
      final Iterator<MapEntry<int, int>> it = _rbMap(40).iterator;
      expect(it.moveNext(), isTrue);
      expect(it.current.key, 0);
      expect(it.current.key, 0);
      expect(it.moveNext(), isTrue);
      expect(it.current.key, 1);
      expect(it.current.key, 1);
    });

    test('skip and elementAt see the right entries', () {
      final ImmutableSortedMap<int, int> map = _rbMap(40);
      expect(map.skip(3).first.key, 3);
      expect(map.elementAt(30).key, 30);
      expect(map.map((MapEntry<int, int> e) => e.key).toList(),
          List<int>.generate(40, (int i) => i));
    });

    test('moveNext without reading current still walks the whole map', () {
      final Iterator<MapEntry<int, int>> it = _rbMap(40).iterator;
      int count = 0;
      while (it.moveNext()) {
        count++;
      }
      expect(count, 40);
      expect(it.moveNext(), isFalse);
      expect(() => it.current, throwsStateError);
    });

    test('reverse and from-key iterators', () {
      final ImmutableSortedMap<int, int> map = _rbMap(40);
      Iterator<MapEntry<int, int>> it = map.reverseIterator;
      expect(it.moveNext(), isTrue);
      expect(it.current.key, 39);
      expect(it.moveNext(), isTrue);
      expect(it.current.key, 38);

      it = map.iteratorFrom(10);
      expect(it.moveNext(), isTrue);
      expect(it.current.key, 10);
      expect(it.moveNext(), isTrue);
      expect(it.current.key, 11);

      it = map.reverseIteratorFrom(10);
      expect(it.moveNext(), isTrue);
      expect(it.current.key, 10);
      expect(it.moveNext(), isTrue);
      expect(it.current.key, 9);
    });

    test('current before moveNext throws', () {
      expect(() => _rbMap(40).iterator.current, throwsStateError);
    });
  });

  group('default comparator equality', () {
    // `expect(a, b)` would compare iterables element by element, so use ==.
    bool same(Object a, Object b) => a == b && b == a;

    test('sets built without a comparator are equal', () {
      expect(
          same(ImmutableSortedSet<int>().insert(1),
              ImmutableSortedSet<int>().insert(1)),
          isTrue);
      expect(
          same(ImmutableSortedSet<int>(<int>[3, 1, 2]),
              ImmutableSortedSet<int>(<int>[1, 2, 3])),
          isTrue);
      expect(ImmutableSortedSet<int>(<int>[1]).hashCode,
          ImmutableSortedSet<int>(<int>[1]).hashCode);
      expect(
          ImmutableSortedSet<int>().insert(1) ==
              ImmutableSortedSet<int>().insert(2),
          isFalse);
      expect(
          same(ImmutableSortedSet<String>().insert('a'),
              ImmutableSortedSet<String>().insert('a')),
          isTrue);
    });

    test('explicit and default comparators stay distinct', () {
      expect(
          ImmutableSortedSet<int>(<int>[1], (int a, int b) => b.compareTo(a)) ==
              ImmutableSortedSet<int>(<int>[1]),
          isFalse);
    });

    test('large sets built without a comparator are equal', () {
      final List<int> items = List<int>.generate(100, (int i) => i);
      expect(
          same(ImmutableSortedSet<int>(List<int>.of(items)),
              ImmutableSortedSet<int>(items.reversed.toList())),
          isTrue);
    });
  });
}
