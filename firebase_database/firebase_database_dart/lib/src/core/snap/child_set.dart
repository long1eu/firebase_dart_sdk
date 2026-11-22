/// Bulk construction of a balanced sorted map. JS: `core/snap/childSet.ts`; Android:
/// `collection/RBTreeSortedMap.java` (`Builder.buildFrom`).
library;

import 'package:firebase_database_dart/src/core/snap/named_node.dart';
import 'package:firebase_database_dart/src/core/util/sorted_map.dart';

/// Builds a sorted map of [childList] (sorted with [compare] first) in linear time; [keyOf] and
/// [valueOf] turn each named node into the key and the value.
SortedMap<K, V> buildChildSet<K, V>(
  List<NamedNode> childList,
  Comparator<NamedNode> compare, {
  required K Function(NamedNode node) keyOf,
  required V Function(NamedNode node) valueOf,
}) => throw UnimplementedError();
