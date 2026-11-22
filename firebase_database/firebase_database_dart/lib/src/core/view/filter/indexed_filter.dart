/// Does not filter; keeps the node indexed by its index. JS: `core/view/filter/IndexedFilter.ts`; Android: `core/view/filter/IndexedFilter.java`.
library;

import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/index.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/priority_index.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/view/change.dart';
import 'package:firebase_database_dart/src/core/view/complete_child_source.dart';
import 'package:firebase_database_dart/src/core/view/filter/child_change_accumulator.dart';
import 'package:firebase_database_dart/src/core/view/filter/node_filter.dart';

/// Does not filter; keeps the node indexed by its index.
final class IndexedFilter implements NodeFilter {
  /// Creates the filter.
  factory IndexedFilter(Index index) => IndexedFilter._(index);

  const IndexedFilter._(this._index);

  final Index _index;

  /// JS `IndexedFilter.updateChild`: reports the child change and keeps the result indexed.
  @override
  Node updateChild(
    Node snap,
    ChildKey key,
    Node newChild,
    Path affectedPath,
    CompleteChildSource source,
    ChildChangeAccumulator? accumulator,
  ) {
    assert(
      snap.isIndexed(_index),
      'A node must be indexed if only a child is updated',
    );
    final Node oldChild = snap.getImmediateChild(key);
    // Check if anything actually changed.
    if (oldChild.getChild(affectedPath) == newChild.getChild(affectedPath)) {
      // A child can enter or leave the view because affectedPath was set to null; then the
      // affected path is empty in both, which is not "nothing changed".
      if (oldChild.isEmpty == newChild.isEmpty) {
        return snap;
      }
    }
    if (accumulator != null) {
      if (newChild.isEmpty) {
        if (snap.hasChild(key)) {
          accumulator.trackChildChange(Change.childRemoved(key, oldChild));
        } else {
          assert(
            snap.isLeafNode,
            'A child remove without an old child only makes sense on a leaf node',
          );
        }
      } else if (oldChild.isEmpty) {
        accumulator.trackChildChange(Change.childAdded(key, newChild));
      } else {
        accumulator.trackChildChange(
          Change.childChanged(key, newChild, oldChild),
        );
      }
    }
    if (snap.isLeafNode && newChild.isEmpty) {
      return snap;
    }
    // Make sure the node is indexed.
    return snap.updateImmediateChild(key, newChild).withIndex(_index);
  }

  /// JS `IndexedFilter.updateFullNode`: reports removed, changed and added children.
  @override
  Node updateFullNode(
    Node oldSnap,
    Node newSnap,
    ChildChangeAccumulator? accumulator,
  ) {
    if (accumulator != null) {
      if (!oldSnap.isLeafNode) {
        oldSnap.forEachChild(priorityIndex, (ChildKey key, Node childNode) {
          if (!newSnap.hasChild(key)) {
            accumulator.trackChildChange(Change.childRemoved(key, childNode));
          }
          return false;
        });
      }
      if (!newSnap.isLeafNode) {
        newSnap.forEachChild(priorityIndex, (ChildKey key, Node childNode) {
          if (oldSnap.hasChild(key)) {
            final Node oldChild = oldSnap.getImmediateChild(key);
            if (oldChild != childNode) {
              accumulator.trackChildChange(
                Change.childChanged(key, childNode, oldChild),
              );
            }
          } else {
            accumulator.trackChildChange(Change.childAdded(key, childNode));
          }
          return false;
        });
      }
    }
    return newSnap.withIndex(_index);
  }

  /// [oldSnap] with [newPriority]; an empty node keeps no priority (Android
  /// `IndexedFilter.updatePriority`: returns [oldSnap] itself, so its index stays built).
  @override
  Node updatePriority(Node oldSnap, Node newPriority) {
    if (oldSnap.isEmpty) {
      return oldSnap;
    }
    return oldSnap.updatePriority(newPriority);
  }

  /// False (JS `IndexedFilter.filtersNodes`).
  @override
  bool get filtersNodes => false;

  /// This filter (JS `IndexedFilter.getIndexedFilter`).
  @override
  NodeFilter get indexedFilter => this;

  /// The index (JS `IndexedFilter.getIndex`).
  @override
  Index get index => _index;
}
