/// Collects child changes, merging several for one child. JS: `core/view/ChildChangeAccumulator.ts`;
/// Android: `core/view/filter/ChildChangeAccumulator.java`.
library;

import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/view/change.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';

/// Accumulates child changes; a remove after an add cancels out, and so on.
final class ChildChangeAccumulator {
  /// Creates an empty accumulator.
  ChildChangeAccumulator();

  // Insertion ordered, as the JS `Map`; the event generator sorts each type anyway.
  final Map<ChildKey, Change> _changeMap = <ChildKey, Change>{};

  /// Records [change] (a child added, changed or removed change), merged with an earlier change
  /// of the same child as JS `ChildChangeAccumulator.trackChildChange`:
  ///
  /// - removed then added: changed (old node from the remove);
  /// - added then removed: nothing;
  /// - changed then removed: removed (with the old node of the change);
  /// - added then changed: added (with the new node);
  /// - changed then changed: changed (new node of the second, old node of the first);
  /// - any other pair throws a [StateError].
  void trackChildChange(Change change) {
    final EventType type = change.eventType;
    final ChildKey? childKey = change.childKey;
    if (type != EventType.childAdded &&
        type != EventType.childChanged &&
        type != EventType.childRemoved) {
      throw StateError('Only child changes supported for tracking');
    }
    if (childKey == null || childKey.isPriorityKey) {
      throw StateError('Only non-priority child changes can be tracked.');
    }
    final Change? oldChange = _changeMap[childKey];
    if (oldChange == null) {
      _changeMap[childKey] = change;
      return;
    }
    final EventType oldType = oldChange.eventType;
    if (type == EventType.childAdded && oldType == EventType.childRemoved) {
      _changeMap[childKey] = Change.childChanged(
        childKey,
        change.node,
        oldChange.node,
      );
    } else if (type == EventType.childRemoved &&
        oldType == EventType.childAdded) {
      _changeMap.remove(childKey);
    } else if (type == EventType.childRemoved &&
        oldType == EventType.childChanged) {
      _changeMap[childKey] = Change.childRemoved(childKey, oldChange.oldNode!);
    } else if (type == EventType.childChanged &&
        oldType == EventType.childAdded) {
      _changeMap[childKey] = Change.childAdded(childKey, change.node);
    } else if (type == EventType.childChanged &&
        oldType == EventType.childChanged) {
      _changeMap[childKey] = Change.childChanged(
        childKey,
        change.node,
        oldChange.oldNode!,
      );
    } else {
      throw StateError(
        'Illegal combination of changes: $change occurred after $oldChange',
      );
    }
  }

  /// The accumulated changes, in the order their children were first tracked (JS
  /// `ChildChangeAccumulator.getChanges`).
  List<Change> get changes => List<Change>.of(_changeMap.values);
}
