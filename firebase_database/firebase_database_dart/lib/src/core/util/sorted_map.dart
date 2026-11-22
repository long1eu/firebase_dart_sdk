/// Immutable sorted map: a sorted array while small, a left-leaning red-black tree above
/// [sortedMapArrayThreshold] entries. JS: `core/util/SortedMap.ts` (tree only); Android:
/// `com.google.firebase.database.collection.ImmutableSortedMap` with `ArraySortedMap` and
/// `RBTreeSortedMap` (shared with Firestore).
///
/// Most nodes of real data have a handful of children; an array holds them in two lists instead
/// of one tree node per entry, and is built and walked without recursion. As on Android, an array
/// map becomes a tree when an insert takes it past the threshold, and a tree stays a tree.
///
/// A single-file port of JS `SortedMap` / `LLRBNode` (the same algorithm as this repository's
/// Firestore `database_collection`), with the empty tree as `null`, a size cached in every node
/// (so `length` and [SortedMap.indexOf] are not linear) and the Android extras
/// (`successorKey`, `indexOf`, iteration from a key). No dependency on `cloud_firestore_dart`.
library;

import 'package:meta/meta.dart';

/// An immutable map whose entries are ordered by [comparator]; every update returns a new map
/// sharing structure with the old one.
abstract class SortedMap<K, V> {
  /// Creates an empty map ordered by [comparator].
  factory SortedMap(Comparator<K> comparator) =>
      _ArraySortedMap<K, V>(comparator, <K>[], <V>[]);

  /// An empty map that is a tree at every size: the oracle of the array form in tests.
  @visibleForTesting
  factory SortedMap.treeForTesting(Comparator<K> comparator) =>
      _LlrbSortedMap<K, V>(comparator, null);

  /// Creates a map of [entries] ordered by [comparator].
  factory SortedMap.fromMap(Map<K, V> entries, Comparator<K> comparator) {
    final List<MapEntry<K, V>> list = entries.entries.toList()
      ..sort((MapEntry<K, V> a, MapEntry<K, V> b) => comparator(a.key, b.key));
    return SortedMap<K, V>.fromSortedEntries(list, comparator);
  }

  /// Creates a map of [entries], which must already be sorted by [comparator] with distinct keys,
  /// in linear time (Hinze's construction, JS `childSet.ts`).
  factory SortedMap.fromSortedEntries(
    List<MapEntry<K, V>> entries,
    Comparator<K> comparator,
  ) {
    if (entries.length > sortedMapArrayThreshold) {
      return _LlrbSortedMap<K, V>(comparator, _buildFromSorted(entries));
    }
    final int n = entries.length;
    return _ArraySortedMap<K, V>(
      comparator,
      List<K>.generate(n, (int i) => entries[i].key, growable: false),
      List<V>.generate(n, (int i) => entries[i].value, growable: false),
    );
  }

  /// Creates a map of the [count] entries [keyAt] and [valueAt] give by position, already sorted
  /// by [comparator] with distinct keys. As [SortedMap.fromSortedEntries], without the entry
  /// objects when the map is small.
  factory SortedMap.fromSorted(
    int count,
    K Function(int index) keyAt,
    V Function(int index) valueAt,
    Comparator<K> comparator,
  ) {
    if (count > sortedMapArrayThreshold) {
      return _LlrbSortedMap<K, V>(
        comparator,
        _buildFromSorted(<MapEntry<K, V>>[
          for (int i = 0; i < count; i++) MapEntry<K, V>(keyAt(i), valueAt(i)),
        ]),
      );
    }
    return _ArraySortedMap<K, V>(
      comparator,
      List<K>.generate(count, keyAt, growable: false),
      List<V>.generate(count, valueAt, growable: false),
    );
  }

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

/// The largest size of the array form. Android: `ArraySortedMap.Builder.ARRAY_TO_RB_TREE_SIZE_THRESHOLD`.
const int sortedMapArrayThreshold = 25;

/// Whether [map] is in the array form. Tests only.
@visibleForTesting
bool debugIsArraySortedMap(SortedMap<Object?, Object?> map) =>
    map is _ArraySortedMap<Object?, Object?>;

/// Checks the red-black invariants of [map] (red links lean left, no two reds in a row, equal
/// black depth, depth bounded by the size) and throws a [StateError] when one is broken. Tests
/// only (JS `checkMaxDepth_`).
@visibleForTesting
void debugCheckSortedMap(SortedMap<Object?, Object?> map) {
  if (map is _ArraySortedMap<Object?, Object?>) {
    map._check();
    return;
  }
  final _Node<Object?, Object?>? root =
      (map as _LlrbSortedMap<Object?, Object?>)._root;
  if (root == null) {
    return;
  }
  if (root.color == _red) {
    throw StateError('Root is red');
  }
  final int blackDepth = _check(root);
  if ((1 << blackDepth) > root.size + 1) {
    throw StateError('Tree too deep');
  }
}

int _check<K, V>(_Node<K, V>? node) {
  if (node == null) {
    return 0;
  }
  if (node.color == _red && _isRed(node.left)) {
    throw StateError('Red node has red child(${node.key},${node.value})');
  }
  if (_isRed(node.right)) {
    throw StateError('Right child of (${node.key},${node.value}) is red');
  }
  final int blackDepth = _check(node.left);
  if (blackDepth != _check(node.right)) {
    throw StateError('Black depths differ');
  }
  if (node.size != (node.left?.size ?? 0) + 1 + (node.right?.size ?? 0)) {
    throw StateError('Wrong size at ${node.key}');
  }
  return blackDepth + (node.color == _red ? 0 : 1);
}

const bool _red = true;
const bool _black = false;

final class _Node<K, V> {
  _Node(this.key, this.value, this.color, this.left, this.right)
    : size = (left?.size ?? 0) + 1 + (right?.size ?? 0);

  final K key;
  final V value;
  final bool color;
  final _Node<K, V>? left;
  final _Node<K, V>? right;
  final int size;

  _Node<K, V> withLeft(_Node<K, V>? newLeft) =>
      _Node<K, V>(key, value, color, newLeft, right);

  _Node<K, V> withRight(_Node<K, V>? newRight) =>
      _Node<K, V>(key, value, color, left, newRight);

  _Node<K, V> withColor(bool newColor) =>
      newColor == color ? this : _Node<K, V>(key, value, newColor, left, right);
}

bool _isRed(_Node<Object?, Object?>? node) => node != null && node.color;

_Node<K, V> _insert<K, V>(
  _Node<K, V>? n,
  K key,
  V value,
  Comparator<K> comparator,
) {
  if (n == null) {
    return _Node<K, V>(key, value, _red, null, null);
  }
  final int cmp = comparator(key, n.key);
  final _Node<K, V> result;
  if (cmp < 0) {
    result = n.withLeft(_insert(n.left, key, value, comparator));
  } else if (cmp == 0) {
    // JS keeps the existing key and replaces the value.
    result = _Node<K, V>(n.key, value, n.color, n.left, n.right);
  } else {
    result = n.withRight(_insert(n.right, key, value, comparator));
  }
  return _fixUp(result);
}

_Node<K, V> _min<K, V>(_Node<K, V> n) {
  _Node<K, V> node = n;
  while (node.left != null) {
    node = node.left!;
  }
  return node;
}

_Node<K, V>? _removeMin<K, V>(_Node<K, V> node) {
  if (node.left == null) {
    return null;
  }
  _Node<K, V> n = node;
  if (!_isRed(n.left) && !_isRed(n.left!.left)) {
    n = _moveRedLeft(n);
  }
  n = n.withLeft(_removeMin(n.left!));
  return _fixUp(n);
}

_Node<K, V>? _remove<K, V>(_Node<K, V>? node, K key, Comparator<K> comparator) {
  if (node == null) {
    return null;
  }
  _Node<K, V> n = node;
  if (comparator(key, n.key) < 0) {
    if (n.left != null && !_isRed(n.left) && !_isRed(n.left!.left)) {
      n = _moveRedLeft(n);
    }
    n = n.withLeft(_remove(n.left, key, comparator));
  } else {
    if (_isRed(n.left)) {
      n = _rotateRight(n);
    }
    if (n.right != null && !_isRed(n.right) && !_isRed(n.right!.left)) {
      n = _moveRedRight(n);
    }
    if (comparator(key, n.key) == 0) {
      if (n.right == null) {
        return null;
      } else {
        final _Node<K, V> smallest = _min(n.right!);
        n = _Node<K, V>(
          smallest.key,
          smallest.value,
          n.color,
          n.left,
          _removeMin(n.right!),
        );
      }
    }
    // As JS: runs after a replacement too (the key is then no longer in the right subtree).
    n = n.withRight(_remove(n.right, key, comparator));
  }
  return _fixUp(n);
}

_Node<K, V> _fixUp<K, V>(_Node<K, V> node) {
  _Node<K, V> n = node;
  if (_isRed(n.right) && !_isRed(n.left)) {
    n = _rotateLeft(n);
  }
  if (_isRed(n.left) && _isRed(n.left!.left)) {
    n = _rotateRight(n);
  }
  if (_isRed(n.left) && _isRed(n.right)) {
    n = _colorFlip(n);
  }
  return n;
}

_Node<K, V> _moveRedLeft<K, V>(_Node<K, V> node) {
  _Node<K, V> n = _colorFlip(node);
  if (n.right != null && _isRed(n.right!.left)) {
    n = n.withRight(_rotateRight(n.right!));
    n = _rotateLeft(n);
    n = _colorFlip(n);
  }
  return n;
}

_Node<K, V> _moveRedRight<K, V>(_Node<K, V> node) {
  _Node<K, V> n = _colorFlip(node);
  if (n.left != null && _isRed(n.left!.left)) {
    n = _rotateRight(n);
    n = _colorFlip(n);
  }
  return n;
}

_Node<K, V> _rotateLeft<K, V>(_Node<K, V> n) {
  final _Node<K, V> r = n.right!;
  final _Node<K, V> newLeft = _Node<K, V>(n.key, n.value, _red, n.left, r.left);
  return _Node<K, V>(r.key, r.value, n.color, newLeft, r.right);
}

_Node<K, V> _rotateRight<K, V>(_Node<K, V> n) {
  final _Node<K, V> l = n.left!;
  final _Node<K, V> newRight = _Node<K, V>(
    n.key,
    n.value,
    _red,
    l.right,
    n.right,
  );
  return _Node<K, V>(l.key, l.value, n.color, l.left, newRight);
}

_Node<K, V> _colorFlip<K, V>(_Node<K, V> n) {
  final _Node<K, V>? left = n.left?.withColor(!n.left!.color);
  final _Node<K, V>? right = n.right?.withColor(!n.right!.color);
  return _Node<K, V>(n.key, n.value, !n.color, left, right);
}

bool _inOrder<K, V>(_Node<K, V>? n, bool Function(K key, V value) action) {
  if (n == null) {
    return false;
  }
  return _inOrder(n.left, action) ||
      action(n.key, n.value) ||
      _inOrder(n.right, action);
}

bool _reverse<K, V>(_Node<K, V>? n, bool Function(K key, V value) action) {
  if (n == null) {
    return false;
  }
  return _reverse(n.right, action) ||
      action(n.key, n.value) ||
      _reverse(n.left, action);
}

/// Hinze's linear construction of a red-black tree from sorted entries, as JS `buildChildSet`
/// (`core/snap/childSet.ts`).
_Node<K, V>? _buildFromSorted<K, V>(List<MapEntry<K, V>> list) {
  _Node<K, V>? buildBalancedTree(int low, int high) {
    final int length = high - low;
    if (length == 0) {
      return null;
    }
    if (length == 1) {
      final MapEntry<K, V> e = list[low];
      return _Node<K, V>(e.key, e.value, _black, null, null);
    }
    final int middle = length ~/ 2 + low;
    final _Node<K, V>? left = buildBalancedTree(low, middle);
    final _Node<K, V>? right = buildBalancedTree(middle + 1, high);
    final MapEntry<K, V> e = list[middle];
    return _Node<K, V>(e.key, e.value, _black, left, right);
  }

  // Base12Num of JS: count = floor(log2(length + 1)), bits = (length + 1) & mask(count).
  final int total = list.length + 1;
  final int count = total.bitLength - 1;
  final int bits = total & ((1 << count) - 1);
  int current = count - 1;
  int index = list.length;

  // Pennants in attach order: each one becomes the left child of the previous one.
  final List<int> pennantLow = <int>[];
  final List<bool> pennantColor = <bool>[];
  final List<_Node<K, V>?> pennantRight = <_Node<K, V>?>[];
  void buildPennant(int chunkSize, bool color) {
    final int low = index - chunkSize;
    final int high = index;
    index -= chunkSize;
    pennantRight.add(buildBalancedTree(low + 1, high));
    pennantLow.add(low);
    pennantColor.add(color);
  }

  for (int i = 0; i < count; ++i) {
    final bool isOne = (bits & (1 << current)) == 0;
    current--;
    final int chunkSize = 1 << (count - (i + 1));
    if (isOne) {
      buildPennant(chunkSize, _black);
    } else {
      buildPennant(chunkSize, _black);
      buildPennant(chunkSize, _red);
    }
  }

  _Node<K, V>? root;
  for (int i = pennantLow.length - 1; i >= 0; i--) {
    final MapEntry<K, V> e = list[pennantLow[i]];
    root = _Node<K, V>(e.key, e.value, pennantColor[i], root, pennantRight[i]);
  }
  return root;
}

/// The array form: keys in order in one list, their values at the same positions in another.
/// Android: `ArraySortedMap`. The lists are never changed after construction.
final class _ArraySortedMap<K, V> implements SortedMap<K, V> {
  _ArraySortedMap(this.comparator, this._keys, this._values);

  @override
  final Comparator<K> comparator;

  final List<K> _keys;
  final List<V> _values;

  /// The position of [key], or `-(insertion point) - 1` when absent.
  int _search(K key) {
    int low = 0;
    int high = _keys.length - 1;
    while (low <= high) {
      final int mid = (low + high) >> 1;
      final int cmp = comparator(_keys[mid], key);
      if (cmp == 0) {
        return mid;
      } else if (cmp < 0) {
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return -low - 1;
  }

  void _check() {
    if (_keys.length != _values.length) {
      throw StateError('Keys and values differ in length');
    }
    if (_keys.length > sortedMapArrayThreshold) {
      throw StateError('Array map above the threshold');
    }
    for (int i = 1; i < _keys.length; i++) {
      if (comparator(_keys[i - 1], _keys[i]) >= 0) {
        throw StateError('Keys out of order at $i');
      }
    }
  }

  @override
  SortedMap<K, V> insert(K key, V value) {
    final int found = _search(key);
    final int n = _keys.length;
    if (found >= 0) {
      // The existing key is kept and the value replaced, as in the tree.
      return _ArraySortedMap<K, V>(
        comparator,
        _keys,
        List<V>.of(_values, growable: false)..[found] = value,
      );
    }
    final int at = -found - 1;
    if (n >= sortedMapArrayThreshold) {
      final List<MapEntry<K, V>> all = <MapEntry<K, V>>[
        for (int i = 0; i < at; i++) MapEntry<K, V>(_keys[i], _values[i]),
        MapEntry<K, V>(key, value),
        for (int i = at; i < n; i++) MapEntry<K, V>(_keys[i], _values[i]),
      ];
      return _LlrbSortedMap<K, V>(comparator, _buildFromSorted(all));
    }
    return _ArraySortedMap<K, V>(
      comparator,
      List<K>.generate(
        n + 1,
        (int i) => i < at ? _keys[i] : (i == at ? key : _keys[i - 1]),
        growable: false,
      ),
      List<V>.generate(
        n + 1,
        (int i) => i < at ? _values[i] : (i == at ? value : _values[i - 1]),
        growable: false,
      ),
    );
  }

  @override
  SortedMap<K, V> remove(K key) {
    final int at = _search(key);
    if (at < 0) {
      return this;
    }
    final int n = _keys.length - 1;
    return _ArraySortedMap<K, V>(
      comparator,
      List<K>.generate(
        n,
        (int i) => i < at ? _keys[i] : _keys[i + 1],
        growable: false,
      ),
      List<V>.generate(
        n,
        (int i) => i < at ? _values[i] : _values[i + 1],
        growable: false,
      ),
    );
  }

  @override
  V? operator [](K key) {
    final int at = _search(key);
    return at < 0 ? null : _values[at];
  }

  @override
  bool containsKey(K key) => _search(key) >= 0;

  @override
  K? predecessorKey(K key) {
    final int at = _search(key);
    if (at < 0) {
      throw StateError(
        'Attempted to find predecessor key for a nonexistent key: $key',
      );
    }
    return at == 0 ? null : _keys[at - 1];
  }

  @override
  K? successorKey(K key) {
    final int at = _search(key);
    if (at < 0) {
      throw StateError(
        'Attempted to find successor key for a nonexistent key: $key',
      );
    }
    return at == _keys.length - 1 ? null : _keys[at + 1];
  }

  @override
  int indexOf(K key) {
    final int at = _search(key);
    return at < 0 ? -1 : at;
  }

  @override
  bool get isEmpty => _keys.isEmpty;

  @override
  int get length => _keys.length;

  @override
  K? get minKey => _keys.isEmpty ? null : _keys.first;

  @override
  K? get maxKey => _keys.isEmpty ? null : _keys.last;

  @override
  bool inOrderTraversal(bool Function(K key, V value) action) {
    for (int i = 0; i < _keys.length; i++) {
      if (action(_keys[i], _values[i])) {
        return true;
      }
    }
    return false;
  }

  @override
  bool reverseTraversal(bool Function(K key, V value) action) {
    for (int i = _keys.length - 1; i >= 0; i--) {
      if (action(_keys[i], _values[i])) {
        return true;
      }
    }
    return false;
  }

  Iterable<MapEntry<K, V>> _forward(int from) sync* {
    for (int i = from; i < _keys.length; i++) {
      yield MapEntry<K, V>(_keys[i], _values[i]);
    }
  }

  Iterable<MapEntry<K, V>> _backward(int from) sync* {
    for (int i = from; i >= 0; i--) {
      yield MapEntry<K, V>(_keys[i], _values[i]);
    }
  }

  @override
  Iterable<MapEntry<K, V>> get entries => _forward(0);

  @override
  Iterable<MapEntry<K, V>> entriesFrom(K key) {
    final int at = _search(key);
    return _forward(at >= 0 ? at : -at - 1);
  }

  @override
  Iterable<MapEntry<K, V>> get reverseEntries => _backward(_keys.length - 1);

  @override
  Iterable<MapEntry<K, V>> reverseEntriesFrom(K key) {
    final int at = _search(key);
    return _backward(at >= 0 ? at : -at - 2);
  }

  @override
  String toString() {
    final StringBuffer buffer = StringBuffer('{');
    for (int i = 0; i < _keys.length; i++) {
      if (i > 0) {
        buffer.write(', ');
      }
      buffer.write('${_keys[i]}: ${_values[i]}');
    }
    buffer.write('}');
    return buffer.toString();
  }
}

final class _LlrbSortedMap<K, V> implements SortedMap<K, V> {
  _LlrbSortedMap(this.comparator, this._root);

  @override
  final Comparator<K> comparator;

  final _Node<K, V>? _root;

  _Node<K, V>? _find(K key) {
    _Node<K, V>? node = _root;
    while (node != null) {
      final int cmp = comparator(key, node.key);
      if (cmp == 0) {
        return node;
      }
      node = cmp < 0 ? node.left : node.right;
    }
    return null;
  }

  @override
  SortedMap<K, V> insert(K key, V value) => _LlrbSortedMap<K, V>(
    comparator,
    _insert(_root, key, value, comparator).withColor(_black),
  );

  @override
  SortedMap<K, V> remove(K key) {
    if (_find(key) == null) {
      return this;
    }
    return _LlrbSortedMap<K, V>(
      comparator,
      _remove(_root, key, comparator)?.withColor(_black),
    );
  }

  @override
  V? operator [](K key) => _find(key)?.value;

  @override
  bool containsKey(K key) => _find(key) != null;

  @override
  K? predecessorKey(K key) {
    _Node<K, V>? node = _root;
    _Node<K, V>? rightParent;
    while (node != null) {
      final int cmp = comparator(key, node.key);
      if (cmp == 0) {
        if (node.left != null) {
          node = node.left!;
          while (node!.right != null) {
            node = node.right;
          }
          return node.key;
        } else if (rightParent != null) {
          return rightParent.key;
        } else {
          return null;
        }
      } else if (cmp < 0) {
        node = node.left;
      } else {
        rightParent = node;
        node = node.right;
      }
    }
    throw StateError(
      'Attempted to find predecessor key for a nonexistent key: $key',
    );
  }

  @override
  K? successorKey(K key) {
    _Node<K, V>? node = _root;
    _Node<K, V>? leftParent;
    while (node != null) {
      final int cmp = comparator(key, node.key);
      if (cmp == 0) {
        if (node.right != null) {
          node = node.right!;
          while (node!.left != null) {
            node = node.left;
          }
          return node.key;
        } else if (leftParent != null) {
          return leftParent.key;
        } else {
          return null;
        }
      } else if (cmp < 0) {
        leftParent = node;
        node = node.left;
      } else {
        node = node.right;
      }
    }
    throw StateError(
      'Attempted to find successor key for a nonexistent key: $key',
    );
  }

  @override
  int indexOf(K key) {
    int pruned = 0;
    _Node<K, V>? node = _root;
    while (node != null) {
      final int cmp = comparator(key, node.key);
      if (cmp == 0) {
        return pruned + (node.left?.size ?? 0);
      } else if (cmp < 0) {
        node = node.left;
      } else {
        pruned += (node.left?.size ?? 0) + 1;
        node = node.right;
      }
    }
    return -1;
  }

  @override
  bool get isEmpty => _root == null;

  @override
  int get length => _root?.size ?? 0;

  @override
  K? get minKey => _root == null ? null : _min(_root).key;

  @override
  K? get maxKey {
    _Node<K, V>? node = _root;
    if (node == null) {
      return null;
    }
    while (node!.right != null) {
      node = node.right;
    }
    return node.key;
  }

  @override
  bool inOrderTraversal(bool Function(K key, V value) action) =>
      _inOrder(_root, action);

  @override
  bool reverseTraversal(bool Function(K key, V value) action) =>
      _reverse(_root, action);

  @override
  Iterable<MapEntry<K, V>> get entries =>
      _EntryIterable<K, V>(_root, null, false, comparator, false);

  @override
  Iterable<MapEntry<K, V>> entriesFrom(K key) =>
      _EntryIterable<K, V>(_root, key, true, comparator, false);

  @override
  Iterable<MapEntry<K, V>> get reverseEntries =>
      _EntryIterable<K, V>(_root, null, false, comparator, true);

  @override
  Iterable<MapEntry<K, V>> reverseEntriesFrom(K key) =>
      _EntryIterable<K, V>(_root, key, true, comparator, true);

  @override
  String toString() {
    final StringBuffer buffer = StringBuffer('{');
    bool first = true;
    _inOrder<K, V>(_root, (K key, V value) {
      if (!first) {
        buffer.write(', ');
      }
      first = false;
      buffer.write('$key: $value');
      return false;
    });
    buffer.write('}');
    return buffer.toString();
  }
}

final class _EntryIterable<K, V> extends Iterable<MapEntry<K, V>> {
  _EntryIterable(
    this._root,
    this._startKey,
    this._hasStart,
    this._comparator,
    this._reverse,
  );

  final _Node<K, V>? _root;
  final K? _startKey;
  final bool _hasStart;
  final Comparator<K> _comparator;
  final bool _reverse;

  @override
  Iterator<MapEntry<K, V>> get iterator =>
      _EntryIterator<K, V>(_root, _startKey, _hasStart, _comparator, _reverse);

  @override
  int get length {
    if (!_hasStart) {
      return _root?.size ?? 0;
    }
    return super.length;
  }

  @override
  bool get isEmpty => !iterator.moveNext();
}

/// JS `SortedMapIterator`: a stack of the nodes still to visit.
final class _EntryIterator<K, V> implements Iterator<MapEntry<K, V>> {
  _EntryIterator(
    _Node<K, V>? root,
    K? startKey,
    bool hasStart,
    Comparator<K> comparator,
    this._reverse,
  ) {
    _Node<K, V>? node = root;
    while (node != null) {
      // Without a start key every node is "after" it in the iteration direction. JS computes
      // cmp = 1 and then negates it for reverse, which would skip the whole tree; flip only a
      // real comparison (Android `ImmutableSortedMapIterator` pushes the right spine instead).
      int cmp = 1;
      if (hasStart) {
        cmp = comparator(node.key, startKey as K);
        if (_reverse) {
          cmp = -cmp;
        }
      }
      if (cmp < 0) {
        node = _reverse ? node.left : node.right;
      } else if (cmp == 0) {
        _stack.add(node);
        break;
      } else {
        _stack.add(node);
        node = _reverse ? node.right : node.left;
      }
    }
  }

  final bool _reverse;
  final List<_Node<K, V>> _stack = <_Node<K, V>>[];
  MapEntry<K, V>? _current;

  @override
  MapEntry<K, V> get current => _current as MapEntry<K, V>;

  @override
  bool moveNext() {
    if (_stack.isEmpty) {
      _current = null;
      return false;
    }
    final _Node<K, V> node = _stack.removeLast();
    _current = MapEntry<K, V>(node.key, node.value);
    if (_reverse) {
      _Node<K, V>? n = node.left;
      while (n != null) {
        _stack.add(n);
        n = n.right;
      }
    } else {
      _Node<K, V>? n = node.right;
      while (n != null) {
        _stack.add(n);
        n = n.left;
      }
    }
    return true;
  }
}
