/// Bulk construction of a balanced sorted map. JS: `core/snap/childSet.ts`; Android:
/// `collection/RBTreeSortedMap.java` (`Builder.buildFrom`).
library;

import 'package:firebase_database_dart/src/core/snap/named_node.dart';
import 'package:firebase_database_dart/src/core/util/sorted_map.dart';

/// Builds a sorted map of [childList] (sorted with [compare] first, in place, as JS does) in
/// linear time after the sort; [keyOf] and [valueOf] turn each named node into the key and the
/// value.
///
/// The map is ordered by [keyCompare] (JS `mapSortFn`); when it is null the keys must be the named
/// nodes themselves and [compare] orders the map.
SortedMap<K, V> buildChildSet<K, V>(
  List<NamedNode> childList,
  Comparator<NamedNode> compare, {
  required K Function(NamedNode node) keyOf,
  required V Function(NamedNode node) valueOf,
  Comparator<K>? keyCompare,
}) {
  childList.sort(compare);
  final List<MapEntry<K, V>> entries = <MapEntry<K, V>>[
    for (final NamedNode node in childList)
      MapEntry<K, V>(keyOf(node), valueOf(node)),
  ];
  final Comparator<K> mapCompare = keyCompare ?? compare as Comparator<K>;
  return SortedMap<K, V>.fromSortedEntries(entries, mapCompare);
}
