/// Immutable sorted map (left-leaning red-black tree). JS: `core/util/SortedMap.ts`; Android:
/// `com.google.firebase.database.collection.ImmutableSortedMap` (shared with Firestore).
///
/// To be filled by copying this repository's `cloud_firestore_dart/lib/src/database_collection`
/// (`ImmutableSortedMap`, `LLRBNode`, `ArraySortedMap`, `RBTreeSortedMap`) into this package and
/// adapting it to this API; no dependency on `cloud_firestore_dart`.
library;

/// An immutable map whose entries are ordered by [comparator]; every update returns a new map
/// sharing structure with the old one.
abstract class SortedMap<K, V> {
  /// Creates an empty map ordered by [comparator].
  factory SortedMap(Comparator<K> comparator) => throw UnimplementedError();

  /// Creates a map of [entries] ordered by [comparator].
  factory SortedMap.fromMap(Map<K, V> entries, Comparator<K> comparator) =>
      throw UnimplementedError();

  /// The order of the keys.
  Comparator<K> get comparator;

  /// A map with [key] set to [value].
  SortedMap<K, V> insert(K key, V value);

  /// A map without [key].
  SortedMap<K, V> remove(K key);

  /// The value of [key], or null.
  V? operator [](K key);

  /// Whether [key] is present.
  bool containsKey(K key);

  /// The key before [key], or null when [key] is the first; [key] must be present.
  K? predecessorKey(K key);

  /// The key after [key], or null when [key] is the last; [key] must be present.
  K? successorKey(K key);

  /// The position of [key], or -1.
  int indexOf(K key);

  /// Whether the map is empty.
  bool get isEmpty;

  /// The number of entries.
  int get length;

  /// The smallest key, or null when empty.
  K? get minKey;

  /// The largest key, or null when empty.
  K? get maxKey;

  /// Visits the entries in order until [action] returns true; returns whether it did.
  bool inOrderTraversal(bool Function(K key, V value) action);

  /// Visits the entries in reverse order until [action] returns true; returns whether it did.
  bool reverseTraversal(bool Function(K key, V value) action);

  /// The entries in order.
  Iterable<MapEntry<K, V>> get entries;

  /// The entries in order, starting at the first key not smaller than [key].
  Iterable<MapEntry<K, V>> entriesFrom(K key);

  /// The entries in reverse order.
  Iterable<MapEntry<K, V>> get reverseEntries;

  /// The entries in reverse order, starting at the last key not greater than [key].
  Iterable<MapEntry<K, V>> reverseEntriesFrom(K key);
}
