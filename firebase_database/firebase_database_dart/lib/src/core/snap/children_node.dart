/// Nodes with children, the empty node and the max sentinel. JS: `core/snap/ChildrenNode.ts`
/// (`ChildrenNode`, `MaxNode`, `MAX_NODE`, `EMPTY_NODE`); Android: `snapshot/ChildrenNode.java`,
/// `snapshot/EmptyNode.java`, `snapshot/IndexedNode.java` (whose role [IndexMap] takes here).
library;

import 'dart:collection';

import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/comparators.dart';
import 'package:firebase_database_dart/src/core/snap/index_map.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/index.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/key_index.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/priority_index.dart';
import 'package:firebase_database_dart/src/core/snap/named_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/priority.dart';
import 'package:firebase_database_dart/src/core/util/hash.dart';
import 'package:firebase_database_dart/src/core/util/sorted_map.dart';

/// A node with children (or none: the empty node), a priority and lazily built indexes.
///
/// Hidden state. The server keeps the priority of a node whose last child is removed by a write
/// below it, and sends it as `{".priority": p}`, also inside the parent's data; a write at or
/// above the node (or `.priority: null`) drops it. Such a node has no value: it [isEmpty], its
/// [priority] reads empty and it is `==` to the empty node, but it keeps the priority in
/// [keptPriority]. Its parent holds it as a hidden child: not in [children], not counted, not
/// visited, not indexed, but returned by [getImmediateChild] so that a later write below it
/// refills it with its priority. [hash] counts the hidden state, as the server's hash does;
/// [toJson], [value], [priority], `==` and [hashCode] do not.
class ChildrenNode implements Node {
  /// Creates a node of [children] with [priorityNode] (empty when null) and [indexMap].
  ///
  /// With no children, [priorityNode] is kept as [keptPriority].
  factory ChildrenNode(
    SortedMap<ChildKey, Node> children,
    Node? priorityNode,
    IndexMap indexMap,
  ) => ChildrenNode.withHidden(children, priorityNode, indexMap, null);

  /// As the default constructor, with the [hidden] children (each an empty node that holds
  /// hidden state, see [holdsHiddenState]); null or empty for none.
  factory ChildrenNode.withHidden(
    SortedMap<ChildKey, Node> children,
    Node? priorityNode,
    IndexMap indexMap,
    SortedMap<ChildKey, Node>? hidden,
  ) {
    if (priorityNode != null) {
      validatePriorityNode(priorityNode);
    }
    return ChildrenNode._(
      children,
      priorityNode,
      indexMap,
      hidden == null || hidden.isEmpty ? null : hidden,
    );
  }

  ChildrenNode._(
    this._children,
    this._priorityNode,
    this._indexMap, [
    this._hidden,
    this._hiddenOrder,
  ]);

  final SortedMap<ChildKey, Node> _children;

  /// Null for the empty node (which cannot be its own priority) and the max node; kept when the
  /// last child goes.
  final Node? _priorityNode;

  final IndexMap _indexMap;

  /// The hidden children by key; null when there are none.
  final SortedMap<ChildKey, Node>? _hidden;

  /// The hidden children in [hash] order (kept priority, then key), built on the first [hash]
  /// and then carried to the versions this node makes; null when not built.
  SortedMap<NamedNode, Node>? _hiddenOrder;

  String? _lazyHash;
  Object? _lazyValue;
  bool _valueBuilt = false;
  int? _lazyHashCode;

  /// The empty node (no value, no children, no priority).
  static ChildrenNode get empty => _empty;

  static final ChildrenNode _empty = ChildrenNode._(
    SortedMap<ChildKey, Node>(nameComparator),
    null,
    IndexMap.defaultMap,
  );

  /// The children by key.
  SortedMap<ChildKey, Node> get children => _children;

  /// The built indexes.
  IndexMap get indexMap => _indexMap;

  @override
  bool get isLeafNode => false;

  /// The priority; empty while the node has no children (see [keptPriority]).
  @override
  Node get priority => _children.isEmpty ? _empty : (_priorityNode ?? _empty);

  /// The priority the server holds for this node: [priority], or for a node emptied by a write
  /// below it the priority it kept.
  Node get keptPriority => _priorityNode ?? _empty;

  /// The keys of the hidden children, in key order.
  Iterable<ChildKey> get hiddenKeys =>
      _hidden?.entries.map((MapEntry<ChildKey, Node> e) => e.key) ??
      const <ChildKey>[];

  /// Whether this is an empty node that holds hidden state: a kept priority or hidden children.
  bool get holdsHiddenState =>
      _children.isEmpty &&
      (_hidden != null || !(_priorityNode?.isEmpty ?? true));

  /// The node at [path] below [node] as the server holds it: as [Node.getChild], except that a
  /// path ending in `.priority` gives the [keptPriority] of an empty node. For reading data back
  /// to apply it again (acks, write tree), never for a reader of the value.
  static Node storedChild(Node node, Path path) {
    final ChildKey? back = path.back;
    if (back == null || !back.isPriorityKey) {
      return node.getChild(path);
    }
    final Node owner = node.getChild(path.parent!);
    return keepsPriority(owner)
        ? (owner as ChildrenNode).keptPriority
        : owner.getImmediateChild(back);
  }

  /// Whether [node] is an empty node that keeps a priority: a priority written there replaces it.
  static bool keepsPriority(Node node) =>
      node is ChildrenNode &&
      node._children.isEmpty &&
      !(node._priorityNode?.isEmpty ?? true);

  /// [newPriority] on a node with children. On an empty node that keeps a priority, it replaces
  /// the kept one (empty clears it), as the server accepts a priority written there; on any other
  /// empty node it is ignored.
  @override
  Node updatePriority(Node newPriority) {
    if (_children.isEmpty) {
      if (_priorityNode == null || _priorityNode.isEmpty) {
        return this;
      }
      if (newPriority.isEmpty) {
        return ChildrenNode._(
          _children,
          null,
          _indexMap,
          _hidden,
          _hiddenOrder,
        );
      }
    }
    validatePriorityNode(newPriority);
    return ChildrenNode._(
      _children,
      newPriority,
      _indexMap,
      _hidden,
      _hiddenOrder,
    );
  }

  /// The child [key]: a visible child, else a hidden one, else the empty node. `.priority` gives
  /// [priority] (empty for a node without children).
  @override
  Node getImmediateChild(ChildKey key) {
    if (key.isPriorityKey) {
      return priority;
    }
    return _children[key] ?? _hidden?[key] ?? _empty;
  }

  @override
  Node getChild(Path path) {
    final ChildKey? front = path.front;
    if (front == null) {
      return this;
    }
    return getImmediateChild(front).getChild(path.popFront());
  }

  @override
  ChildKey? getPredecessorChildKey(ChildKey key, Node child, Index index) {
    final SortedMap<NamedNode, Node>? idx = _resolveIndex(index);
    if (idx != null) {
      return idx.predecessorKey(NamedNode(key, child))?.name;
    }
    return _children.predecessorKey(key);
  }

  @override
  Node updateImmediateChild(ChildKey key, Node newChild) {
    if (key.isPriorityKey) {
      return updatePriority(newChild);
    }
    final NamedNode namedNode = NamedNode(key, newChild);
    final SortedMap<ChildKey, Node> newChildren;
    final IndexMap newIndexMap;
    SortedMap<ChildKey, Node>? newHidden = _hidden;
    if (newChild.isEmpty) {
      newChildren = _children.remove(key);
      newIndexMap = _indexMap.removeFromIndexes(namedNode, _children);
      if (newChild is ChildrenNode && newChild.holdsHiddenState) {
        newHidden = (newHidden ?? SortedMap<ChildKey, Node>(nameComparator))
            .insert(key, newChild);
      } else {
        newHidden = _withoutHidden(key);
      }
    } else {
      newChildren = _children.insert(key, newChild);
      newIndexMap = _indexMap.addToIndexes(namedNode, _children);
      newHidden = _withoutHidden(key);
    }
    // The priority stays when the last child goes: the server keeps it.
    return ChildrenNode._(
      newChildren,
      _priorityNode,
      newIndexMap,
      newHidden,
      _hiddenOrderAfter(key, newHidden?[key]),
    );
  }

  /// [_hiddenOrder] with the hidden child [key] replaced by [newHidden] (removed when null); null
  /// when it is not built or nothing is left.
  SortedMap<NamedNode, Node>? _hiddenOrderAfter(ChildKey key, Node? newHidden) {
    SortedMap<NamedNode, Node>? order = _hiddenOrder;
    if (order == null) {
      return null;
    }
    final Node? old = _hidden?[key];
    if (old != null) {
      order = order.remove(NamedNode(key, old));
    }
    if (newHidden != null) {
      order = order.insert(NamedNode(key, newHidden), newHidden);
    }
    return order.isEmpty ? null : order;
  }

  /// [_hidden] without [key]; null when nothing is left.
  SortedMap<ChildKey, Node>? _withoutHidden(ChildKey key) {
    final SortedMap<ChildKey, Node>? hidden = _hidden;
    if (hidden == null || !hidden.containsKey(key)) {
      return hidden;
    }
    final SortedMap<ChildKey, Node> rest = hidden.remove(key);
    return rest.isEmpty ? null : rest;
  }

  @override
  Node updateChild(Path path, Node newChild) {
    final ChildKey? front = path.front;
    if (front == null) {
      return newChild;
    }
    assert(
      !front.isPriorityKey || path.length == 1,
      '.priority must be the last token in a path',
    );
    final Node newImmediateChild = getImmediateChild(
      front,
    ).updateChild(path.popFront(), newChild);
    return updateImmediateChild(front, newImmediateChild);
  }

  @override
  bool hasChild(ChildKey key) => _children.containsKey(key);

  @override
  bool get isEmpty => _children.isEmpty;

  @override
  int get numChildren => _children.length;

  @override
  bool forEachChild(Index index, ChildVisitor action) {
    final SortedMap<NamedNode, Node>? idx = _resolveIndex(index);
    if (idx != null) {
      return idx.inOrderTraversal(
        (NamedNode wrapped, Node _) => action(wrapped.name, wrapped.node),
      );
    }
    return _children.inOrderTraversal(action);
  }

  static final RegExp _integerRegExp = RegExp(r'^(0|[1-9]\d*)$');

  /// The array length when the keys follow the JS list rule (every key matches
  /// `^(0|[1-9]\d*)$` and the largest is below twice the count), else null.
  int? _arrayLength() {
    int numKeys = 0;
    int maxKey = 0;
    bool allIntegerKeys = true;
    _children.inOrderTraversal((ChildKey key, Node _) {
      numKeys++;
      final String name = key.name;
      final int? parsed = _integerRegExp.hasMatch(name)
          ? int.tryParse(name)
          : null;
      if (parsed == null) {
        allIntegerKeys = false;
        return true;
      }
      if (parsed > maxKey) {
        maxKey = parsed;
      }
      return false;
    });
    if (allIntegerKeys && maxKey < 2 * numKeys) {
      return maxKey + 1;
    }
    return null;
  }

  @override
  Object? get value {
    if (_valueBuilt) {
      return _lazyValue;
    }
    _lazyValue = _buildValue();
    _valueBuilt = true;
    return _lazyValue;
  }

  Object? _buildValue() {
    if (isEmpty) {
      return null;
    }
    final int? arrayLength = _arrayLength();
    if (arrayLength != null) {
      final List<Object?> array = List<Object?>.filled(arrayLength, null);
      _children.inOrderTraversal((ChildKey key, Node child) {
        array[int.parse(key.name)] = child.value;
        return false;
      });
      return List<Object?>.unmodifiable(array);
    }
    final Map<String, Object?> obj = <String, Object?>{};
    forEachChild(priorityIndex, (ChildKey key, Node child) {
      obj[key.name] = child.value;
      return false;
    });
    return UnmodifiableMapView<String, Object?>(obj);
  }

  @override
  Object? toJson({bool exportFormat = false}) {
    if (isEmpty) {
      return null;
    }
    if (!exportFormat) {
      final int? arrayLength = _arrayLength();
      if (arrayLength != null) {
        final List<Object?> array = List<Object?>.filled(arrayLength, null);
        _children.inOrderTraversal((ChildKey key, Node child) {
          array[int.parse(key.name)] = child.toJson();
          return false;
        });
        return array;
      }
    }
    final Map<String, Object?> obj = <String, Object?>{};
    forEachChild(priorityIndex, (ChildKey key, Node child) {
      obj[key.name] = child.toJson(exportFormat: exportFormat);
      return false;
    });
    final Node p = priority;
    if (exportFormat && !p.isEmpty && !identical(p, this)) {
      obj['.priority'] = p.toJson(exportFormat: true);
    }
    return obj;
  }

  /// JS `ChildrenNode.hash` of the node the server holds: the kept priority and the hidden
  /// children count, the hidden children in priority order among the visible ones.
  @override
  String hash() {
    final String? cached = _lazyHash;
    if (cached != null) {
      return cached;
    }
    final StringBuffer toHash = StringBuffer();
    final Node p = keptPriority;
    if (!p.isEmpty) {
      toHash
        ..write('priority:')
        ..write(priorityHashText(p.value!))
        ..write(':');
    }
    void add(ChildKey key, Node child) {
      final String childHash = child.hash();
      if (childHash.isNotEmpty) {
        toHash
          ..write(':')
          ..write(key.name)
          ..write(':')
          ..write(childHash);
      }
    }

    if (_hidden == null) {
      forEachChild(priorityIndex, (ChildKey key, Node child) {
        add(key, child);
        return false;
      });
    } else {
      for (final NamedNode n in _childrenWithHidden()) {
        add(n.name, n.node);
      }
    }
    final String text = toHash.toString();
    return _lazyHash = text.isEmpty ? '' : sha1Base64(text);
  }

  /// The visible and the hidden children in the server's priority order: by priority (kept
  /// priority for a hidden child), then by key.
  List<NamedNode> _childrenWithHidden() {
    final List<NamedNode> hidden = (_hiddenOrder ??= _buildHiddenOrder())
        .entries
        .map((MapEntry<NamedNode, Node> e) => e.key)
        .toList();
    final List<NamedNode> merged = <NamedNode>[];
    int h = 0;
    forEachChild(priorityIndex, (ChildKey key, Node child) {
      final NamedNode visible = NamedNode(key, child);
      while (h < hidden.length &&
          _comparePriorityKept(hidden[h], visible) < 0) {
        merged.add(hidden[h++]);
      }
      merged.add(visible);
      return false;
    });
    merged.addAll(hidden.skip(h));
    return merged;
  }

  SortedMap<NamedNode, Node> _buildHiddenOrder() {
    SortedMap<NamedNode, Node> order = SortedMap<NamedNode, Node>(
      _comparePriorityKept,
    );
    _hidden!.inOrderTraversal((ChildKey key, Node child) {
      order = order.insert(NamedNode(key, child), child);
      return false;
    });
    return order;
  }

  /// The priority index order, with the kept priority of an empty node.
  static int _comparePriorityKept(NamedNode a, NamedNode b) {
    final int cmp = _sortPriority(a.node).compareTo(_sortPriority(b.node));
    return cmp == 0 ? a.name.compareTo(b.name) : cmp;
  }

  static Node _sortPriority(Node node) =>
      node is ChildrenNode ? node.keptPriority : node.priority;

  /// Whether [a] and [b] hold the same hidden state along [path]: at each node on the path the
  /// kept priority of an empty node and the hidden children, and the whole subtree at the end
  /// of [path] (a path ending in `.priority` ends at its node). Meant for nodes that are `==`
  /// and differ at most along [path], as a write leaves them; identical subtrees are not walked.
  static bool sameHiddenAlong(Node a, Node b, Path path) {
    Node x = a;
    Node y = b;
    for (final ChildKey key in path.segments) {
      if (identical(x, y)) {
        return true;
      }
      if (key.isPriorityKey) {
        break;
      }
      if (!_sameOwnHidden(x, y)) {
        return false;
      }
      x = x.getImmediateChild(key);
      y = y.getImmediateChild(key);
    }
    return sameHidden(x, y);
  }

  /// Whether [a] and [b] hold the same hidden state at every depth. Meant for nodes that are
  /// `==`; identical subtrees are not walked.
  static bool sameHidden(Node a, Node b) {
    if (identical(a, b)) {
      return true;
    }
    if (!_sameOwnHidden(a, b)) {
      return false;
    }
    if (a is! ChildrenNode || b is! ChildrenNode) {
      return true;
    }
    final Iterator<MapEntry<ChildKey, Node>> ai = a._children.entries.iterator;
    final Iterator<MapEntry<ChildKey, Node>> bi = b._children.entries.iterator;
    while (ai.moveNext()) {
      if (!bi.moveNext() || ai.current.key != bi.current.key) {
        return false;
      }
      if (!sameHidden(ai.current.value, bi.current.value)) {
        return false;
      }
    }
    return !bi.moveNext();
  }

  /// The kept priority of an empty node and the hidden children of [a] and [b] are the same.
  static bool _sameOwnHidden(Node a, Node b) {
    final ChildrenNode? x = a is ChildrenNode ? a : null;
    final ChildrenNode? y = b is ChildrenNode ? b : null;
    final Node px = x != null && x._children.isEmpty ? x.keptPriority : _empty;
    final Node py = y != null && y._children.isEmpty ? y.keptPriority : _empty;
    if (px != py) {
      return false;
    }
    final SortedMap<ChildKey, Node>? hx = x?._hidden;
    final SortedMap<ChildKey, Node>? hy = y?._hidden;
    if (identical(hx, hy)) {
      return true;
    }
    if (hx == null || hy == null || hx.length != hy.length) {
      return false;
    }
    final Iterator<MapEntry<ChildKey, Node>> ix = hx.entries.iterator;
    final Iterator<MapEntry<ChildKey, Node>> iy = hy.entries.iterator;
    while (ix.moveNext() && iy.moveNext()) {
      if (ix.current.key != iy.current.key ||
          !sameHidden(ix.current.value, iy.current.value)) {
        return false;
      }
    }
    return true;
  }

  /// The key of the first child in [index] order, or null.
  ChildKey? firstChildKey(Index index) {
    final SortedMap<NamedNode, Node>? idx = _resolveIndex(index);
    if (idx != null) {
      return idx.minKey?.name;
    }
    return _children.minKey;
  }

  /// The first child in [index] order, or null.
  NamedNode? firstChild(Index index) {
    final ChildKey? key = firstChildKey(index);
    return key == null ? null : NamedNode(key, _children[key]!);
  }

  /// The key of the last child in [index] order, or null.
  ChildKey? lastChildKey(Index index) {
    final SortedMap<NamedNode, Node>? idx = _resolveIndex(index);
    if (idx != null) {
      return idx.maxKey?.name;
    }
    return _children.maxKey;
  }

  /// The last child in [index] order, or null.
  NamedNode? lastChild(Index index) {
    final ChildKey? key = lastChildKey(index);
    return key == null ? null : NamedNode(key, _children[key]!);
  }

  /// The children in [index] order.
  Iterable<NamedNode> childrenInOrder(Index index) {
    final SortedMap<NamedNode, Node>? idx = _resolveIndex(index);
    if (idx != null) {
      return idx.entries.map((MapEntry<NamedNode, Node> e) => e.key);
    }
    return _children.entries.map(_wrap);
  }

  /// The children in [index] order starting at the first post not smaller than [start].
  Iterable<NamedNode> childrenFrom(NamedNode start, Index index) {
    final SortedMap<NamedNode, Node>? idx = _resolveIndex(index);
    if (idx != null) {
      return idx.entriesFrom(start).map((MapEntry<NamedNode, Node> e) => e.key);
    }
    return _children
        .entriesFrom(start.name)
        .map(_wrap)
        .skipWhile((NamedNode next) => index.compare(next, start) < 0);
  }

  /// The children in reverse [index] order.
  Iterable<NamedNode> reverseChildren(Index index) {
    final SortedMap<NamedNode, Node>? idx = _resolveIndex(index);
    if (idx != null) {
      return idx.reverseEntries.map((MapEntry<NamedNode, Node> e) => e.key);
    }
    return _children.reverseEntries.map(_wrap);
  }

  /// The children in reverse [index] order starting at the last post not greater than [start].
  Iterable<NamedNode> reverseChildrenFrom(NamedNode start, Index index) {
    final SortedMap<NamedNode, Node>? idx = _resolveIndex(index);
    if (idx != null) {
      return idx
          .reverseEntriesFrom(start)
          .map((MapEntry<NamedNode, Node> e) => e.key);
    }
    return _children
        .reverseEntriesFrom(start.name)
        .map(_wrap)
        .skipWhile((NamedNode next) => index.compare(next, start) > 0);
  }

  static NamedNode _wrap(MapEntry<ChildKey, Node> e) =>
      NamedNode(e.key, e.value);

  @override
  int compareTo(Node other) {
    if (isEmpty) {
      return other.isEmpty ? 0 : -1;
    } else if (other.isLeafNode || other.isEmpty) {
      return 1;
    } else if (identical(other, MaxNode.instance)) {
      return -1;
    } else {
      // Must be another node with children.
      return 0;
    }
  }

  @override
  Node withIndex(Index index) {
    if (index is KeyIndex || _indexMap.hasIndex(index)) {
      return this;
    }
    return ChildrenNode._(
      _children,
      _priorityNode,
      _indexMap.addIndex(index, _children),
      _hidden,
      _hiddenOrder,
    );
  }

  @override
  bool isIndexed(Index index) => index is KeyIndex || _indexMap.hasIndex(index);

  /// JS `equals`: equal priorities and the same children with equal nodes (compared in key
  /// order, which gives the same answer as JS's priority order).
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! ChildrenNode || other is MaxNode) {
      return false;
    }
    if (_children.length != other._children.length) {
      return false;
    }
    if (priority != other.priority) {
      return false;
    }
    final Iterator<MapEntry<ChildKey, Node>> a = _children.entries.iterator;
    final Iterator<MapEntry<ChildKey, Node>> b =
        other._children.entries.iterator;
    while (a.moveNext()) {
      if (!b.moveNext()) {
        return false;
      }
      if (a.current.key != b.current.key ||
          a.current.value != b.current.value) {
        return false;
      }
    }
    return !b.moveNext();
  }

  @override
  int get hashCode {
    final int? cached = _lazyHashCode;
    if (cached != null) {
      return cached;
    }
    if (isEmpty) {
      return _lazyHashCode = 0;
    }
    int h = priority.isEmpty ? 0 : priority.hashCode;
    _children.inOrderTraversal((ChildKey key, Node child) {
      h = Object.hash(h, key, child);
      return false;
    });
    return _lazyHashCode = h;
  }

  /// The export JSON of the node the server holds: as [toJson] with `exportFormat`, plus every
  /// node that keeps hidden state as `{".priority": p}` (or its hidden children), as the server
  /// sends such a node. Null for a node with no value and no hidden state.
  Object? toServerJson() {
    final Map<String, Object?> obj = <String, Object?>{};
    void add(ChildKey key, Node child) {
      final Object? json = child is ChildrenNode
          ? child.toServerJson()
          : child.toJson(exportFormat: true);
      if (json != null) {
        obj[key.name] = json;
      }
    }

    forEachChild(priorityIndex, (ChildKey key, Node child) {
      add(key, child);
      return false;
    });
    _hidden?.inOrderTraversal((ChildKey key, Node child) {
      add(key, child);
      return false;
    });
    if (obj.isEmpty && keptPriority.isEmpty) {
      return null;
    }
    final Node p = keptPriority;
    if (!p.isEmpty && !identical(p, this)) {
      obj['.priority'] = p.toJson(exportFormat: true);
    }
    return obj;
  }

  @override
  String toString() => 'ChildrenNode(${toJson(exportFormat: true)})';

  /// The sorted map of [index], or null when the key order serves (JS `resolveIndex_`).
  SortedMap<NamedNode, Node>? _resolveIndex(Index index) {
    if (index is KeyIndex) {
      return null;
    }
    return _indexMap.get(index.queryDefinition);
  }
}

/// The node that sorts after every other node; used for the max post of indexes.
final class MaxNode extends ChildrenNode {
  MaxNode._()
    : super._(
        SortedMap<ChildKey, Node>(nameComparator),
        null,
        IndexMap.defaultMap,
      );

  static final MaxNode _instance = MaxNode._();

  /// The single instance.
  static MaxNode get instance => _instance;

  @override
  int compareTo(Node other) => identical(other, this) ? 0 : 1;

  @override
  bool operator ==(Object other) => identical(other, this);

  @override
  int get hashCode => identityHashCode(this);

  @override
  Node get priority => this;

  @override
  Node getImmediateChild(ChildKey key) => ChildrenNode.empty;

  @override
  bool get isEmpty => false;

  @override
  String toString() => 'MaxNode';
}
