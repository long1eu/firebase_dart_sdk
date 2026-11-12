// Ported from RBTreeSortedMapTest (upstream): the two tests that inspect the
// root node of the tree.

import 'package:cloud_firestore_dart/src/database_collection/immutable_sorted_map.dart';
import 'package:cloud_firestore_dart/src/database_collection/rb_tree_sorted_map.dart';
import 'package:cloud_firestore_dart/src/database_collection/standard_compartor.dart';
import 'package:test/test.dart';

void main() {
  final Comparator<num> intComparator = standardComparator<num>();

  test('createNode', () {
    ImmutableSortedMap<String, int> map =
        RBTreeSortedMap<String, int>(standardComparator());
    map = map.insert('a', 1);

    final RBTreeSortedMap<String, int> rbMap =
        map as RBTreeSortedMap<String, int>;

    expect(rbMap.root.left.isEmpty, isTrue);
    expect(rbMap.root.right.isEmpty, isTrue);
  });

  test('canInsertNewPairs', () {
    final ImmutableSortedMap<int, int> map =
        RBTreeSortedMap<int, int>(intComparator).insert(1, 1).insert(2, 2);

    final RBTreeSortedMap<int, int> rbMap = map as RBTreeSortedMap<int, int>;

    expect(rbMap.root.key, 2);
    expect(rbMap.root.left.key, 1);
  });
}
