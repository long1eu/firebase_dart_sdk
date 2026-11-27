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
class ChildrenNode implements Node {
  /// Creates a node of [children] with [priorityNode] (empty when null) and [indexMap].
  factory ChildrenNode(
    SortedMap<ChildKey, Node> children,
    Node? priorityNode,
    IndexMap indexMap,
  ) {
    if (priorityNode != null) {
      validatePriorityNode(priorityNode);
    }
    if (children.isEmpty && priorityNode != null && !priorityNode.isEmpty) {
      throw StateError('An empty node cannot have a priority');
    }
    return ChildrenNode._(children, priorityNode, indexMap);
  }

  ChildrenNode._(this._children, this._priorityNode, this._indexMap);

  final SortedMap<ChildKey, Node> _children;

  /// Null only for the empty node (which cannot be its own priority) and the max node.
  final Node? _priorityNode;

  final IndexMap _indexMap;

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

  @override
  Node get priority => _priorityNode ?? _empty;

  @override
  Node updatePriority(Node newPriority) {
    if (_children.isEmpty) {
      // Don't allow priorities on empty nodes.
      return this;
    }
    return ChildrenNode(_children, newPriority, _indexMap);
  }

  @override
  Node getImmediateChild(ChildKey key) {
    if (key.isPriorityKey) {
      return priority;
    }
    return _children[key] ?? _empty;
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
    if (newChild.isEmpty) {
      newChildren = _children.remove(key);
      newIndexMap = _indexMap.removeFromIndexes(namedNode, _children);
    } else {
      newChildren = _children.insert(key, newChild);
      newIndexMap = _indexMap.addToIndexes(namedNode, _children);
    }
    final Node? newPriority = newChildren.isEmpty ? _empty : _priorityNode;
    return ChildrenNode(newChildren, newPriority, newIndexMap);
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
        // Growable: a transaction handler gets this list and may add to or remove from it.
        final List<Object?> array = List<Object?>.filled(
          arrayLength,
          null,
          growable: true,
        );
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

  @override
  String hash() {
    final String? cached = _lazyHash;
    if (cached != null) {
      return cached;
    }
    final StringBuffer toHash = StringBuffer();
    final Node p = priority;
    if (!p.isEmpty) {
      toHash
        ..write('priority:')
        ..write(priorityHashText(p.value!))
        ..write(':');
    }
    forEachChild(priorityIndex, (ChildKey key, Node child) {
      final String childHash = child.hash();
      if (childHash.isNotEmpty) {
        toHash
          ..write(':')
          ..write(key.name)
          ..write(':')
          ..write(childHash);
      }
      return false;
    });
    final String text = toHash.toString();
    return _lazyHash = text.isEmpty ? '' : sha1Base64(text);
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
