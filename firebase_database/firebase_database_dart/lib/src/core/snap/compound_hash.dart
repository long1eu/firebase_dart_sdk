/// Compound hash of a node, sent as `ch` with a listen. JS: none; Android:
/// `snapshot/CompoundHash.java`.
library;

import 'dart:math' as math;

import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/key_index.dart';
import 'package:firebase_database_dart/src/core/snap/leaf_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/util/hash.dart';
import 'package:firebase_database_dart/src/core/util/node_size_estimator.dart';
import 'package:firebase_database_dart/src/core/util/numbers.dart';

/// The state a [SplitStrategy] looks at while the hash is being built.
abstract interface class CompoundHashBuildState {
  /// Whether a range is open.
  bool get buildingRange;

  /// The length of the current range text.
  int get currentHashLength;

  /// The path of the current leaf.
  Path get currentPath;
}

/// Decides whether to close the current range at the current leaf.
typedef SplitStrategy = bool Function(CompoundHashBuildState state);

/// A node split into ranges: n [hashes] and the n-1 [posts] (last leaf paths) between them.
final class CompoundHash {
  /// Creates a hash; [posts] has one element fewer than [hashes].
  const CompoundHash(this.posts, this.hashes);

  /// Builds the hash of [node], splitting with [strategy] (by default ranges of
  /// `max(512, sqrt(size * 100))` characters).
  factory CompoundHash.fromNode(Node node, [SplitStrategy? strategy]) {
    if (node.isEmpty && !(node is ChildrenNode && node.holdsHiddenState)) {
      return const CompoundHash(<Path>[], <String>['']);
    }
    final _CompoundHashBuilder state = _CompoundHashBuilder(
      strategy ?? _simpleSizeSplitStrategy(node),
    );
    _processNode(node, state);
    state.finishHashing();
    return CompoundHash(
      List<Path>.unmodifiable(state.currentPaths),
      List<String>.unmodifiable(state.currentHashes),
    );
  }

  /// The range end paths.
  final List<Path> posts;

  /// The base64 SHA-1 of each range; the last is `''`.
  final List<String> hashes;
}

/// Splits for 1k -> 512 (2 parts), 5k -> 715 (7 parts), 100k -> 3.2k (32 parts), 500k -> 7k
/// (71 parts), 5M -> 23k (228 parts). Never splits on a priority.
SplitStrategy _simpleSizeSplitStrategy(Node node) {
  final int estimatedNodeSize = _estimateServerSize(node);
  final int splitThreshold = math.max(
    512,
    math.sqrt(estimatedNodeSize * 100).floor(),
  );
  return (CompoundHashBuildState state) {
    final Path path = state.currentPath;
    return state.currentHashLength > splitThreshold &&
        (path.isEmpty || path.back != ChildKey.priority);
  };
}

void _processNode(Node node, _CompoundHashBuilder state) {
  if (node.isLeafNode) {
    state.processLeaf(node as LeafNode);
    return;
  }
  final List<(ChildKey, Node)> children = _serverChildren(node);
  if (children.isEmpty && !(node is ChildrenNode && node.holdsHiddenState)) {
    throw ArgumentError("Can't calculate hash on empty node!");
  }
  void visit(ChildKey key, Node child) {
    state.startChild(key);
    _processNode(child, state);
    state.endChild();
  }

  // Android `forEachChild(visitor, includePriority: true)`: the priority is visited just before
  // the first key that sorts after `.priority` (and not at all if no key does). A node emptied
  // below it, with no child left, gives its kept priority as a `.priority` leaf: the form the
  // server hashes (production check 39 Q5: it answers `rm []` to that form only).
  final Node priority = _keptPriority(node);
  bool passedPriorityKey = priority.isEmpty;
  for (final (ChildKey key, Node child) in children) {
    if (!passedPriorityKey && key.compareTo(ChildKey.priority) > 0) {
      passedPriorityKey = true;
      visit(ChildKey.priority, priority);
    }
    visit(key, child);
  }
  if (!passedPriorityKey && children.isEmpty) {
    visit(ChildKey.priority, priority);
  }
}

/// The children the server holds under [node] in key order: the visible ones and the hidden ones
/// (nodes emptied below that keep a priority).
List<(ChildKey, Node)> _serverChildren(Node node) {
  final List<(ChildKey, Node)> children = <(ChildKey, Node)>[];
  node.forEachChild(keyIndex, (ChildKey key, Node child) {
    children.add((key, child));
    return false;
  });
  if (node is ChildrenNode) {
    final List<ChildKey> hidden = node.hiddenKeys.toList();
    if (hidden.isNotEmpty) {
      children
        ..addAll(<(ChildKey, Node)>[
          for (final ChildKey key in hidden) (key, node.getImmediateChild(key)),
        ])
        ..sort(
          ((ChildKey, Node) a, (ChildKey, Node) b) => a.$1.compareTo(b.$1),
        );
    }
  }
  return children;
}

Node _keptPriority(Node node) =>
    node is ChildrenNode ? node.keptPriority : node.priority;

/// [estimateSerializedNodeSize] of the node the server holds: hidden children and kept
/// priorities count (the split threshold of the server's ranges).
int _estimateServerSize(Node node) {
  if (node.isLeafNode) {
    return estimateSerializedNodeSize(node);
  }
  final List<(ChildKey, Node)> children = _serverChildren(node);
  final Node priority = _keptPriority(node);
  if (children.isEmpty && priority.isEmpty) {
    return 4; // null
  }
  int sum = 1; // opening bracket
  for (final (ChildKey key, Node child) in children) {
    sum += key.name.length + 4 + _estimateServerSize(child);
  }
  if (!priority.isEmpty) {
    sum += 12 + estimateSerializedNodeSize(priority);
  }
  return sum;
}

/// The V2 hash text of a leaf (Android `getHashRepresentation(HashVersion.V2)`): as V1, except
/// strings are quoted with only `\` and `"` escaped.
String _leafHashV2(LeafNode leaf) {
  final Node priority = leaf.priority;
  final String prefix = priority.isEmpty
      ? ''
      : 'priority:${_leafHashV2(priority as LeafNode)}:';
  final Object value = leaf.value;
  return switch (leaf.leafType) {
    LeafType.string =>
      '${prefix}string:${stringHashV2Representation(value as String)}',
    LeafType.number =>
      '${prefix}number:${doubleToIeee754String((value as num).toDouble())}',
    LeafType.boolean => '${prefix}boolean:$value',
    LeafType.deferredValue => leaf.hashText(),
  };
}

final class _CompoundHashBuilder implements CompoundHashBuildState {
  _CompoundHashBuilder(this.splitStrategy);

  final SplitStrategy splitStrategy;

  /// Non-null while a range is open (a leaf was met since the last split).
  StringBuffer? _hashValueBuilder;

  /// The current path as a stack; with [_currentPathDepth] it also keeps the last leaf path.
  final List<ChildKey> _currentPathStack = <ChildKey>[];

  int _lastLeafDepth = -1;
  int _currentPathDepth = 0;
  bool _needsComma = true;

  final List<Path> currentPaths = <Path>[];
  final List<String> currentHashes = <String>[];

  @override
  bool get buildingRange => _hashValueBuilder != null;

  @override
  int get currentHashLength => _hashValueBuilder!.length;

  @override
  Path get currentPath => _pathAtDepth(_currentPathDepth);

  Path _pathAtDepth(int depth) =>
      Path.fromKeys(List<ChildKey>.unmodifiable(_currentPathStack.take(depth)));

  void _ensureRange() {
    if (!buildingRange) {
      final StringBuffer builder = StringBuffer('(');
      for (final ChildKey key in _currentPathStack.take(_currentPathDepth)) {
        builder
          ..write(stringHashV2Representation(key.name))
          ..write(':(');
      }
      _hashValueBuilder = builder;
      _needsComma = false;
    }
  }

  void processLeaf(LeafNode node) {
    _ensureRange();
    _lastLeafDepth = _currentPathDepth;
    _hashValueBuilder!.write(_leafHashV2(node));
    _needsComma = true;
    if (splitStrategy(this)) {
      _endRange();
    }
  }

  void startChild(ChildKey key) {
    _ensureRange();
    final StringBuffer builder = _hashValueBuilder!;
    if (_needsComma) {
      builder.write(',');
    }
    builder
      ..write(stringHashV2Representation(key.name))
      ..write(':(');
    if (_currentPathDepth == _currentPathStack.length) {
      _currentPathStack.add(key);
    } else {
      _currentPathStack[_currentPathDepth] = key;
    }
    _currentPathDepth++;
    _needsComma = false;
  }

  void endChild() {
    _currentPathDepth--;
    if (buildingRange) {
      _hashValueBuilder!.write(')');
    }
    _needsComma = true;
  }

  void finishHashing() {
    assert(
      _currentPathDepth == 0,
      "Can't finish hashing in the middle of processing a child",
    );
    if (buildingRange) {
      _endRange();
    }
    // Always close with the empty hash for the remaining range to allow simple appending.
    currentHashes.add('');
  }

  void _endRange() {
    final StringBuffer builder = _hashValueBuilder!;
    for (int i = 0; i < _currentPathDepth; i++) {
      builder.write(')');
    }
    builder.write(')');
    currentHashes.add(sha1Base64(builder.toString()));
    currentPaths.add(_pathAtDepth(_lastLeafDepth));
    _hashValueBuilder = null;
  }
}
