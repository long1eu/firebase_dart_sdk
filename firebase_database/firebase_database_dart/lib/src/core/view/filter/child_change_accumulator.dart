/// Collects child changes, merging several for one child. JS: `core/view/ChildChangeAccumulator.ts`;
/// Android: `core/view/filter/ChildChangeAccumulator.java`.
library;

import 'package:firebase_database_dart/src/core/view/change.dart';

/// Accumulates child changes; a remove after an add cancels out, and so on.
final class ChildChangeAccumulator {
  /// Creates an empty accumulator.
  ChildChangeAccumulator();

  /// Records [change] (a child change).
  void trackChildChange(Change change) => throw UnimplementedError();

  /// The accumulated changes.
  List<Change> get changes => throw UnimplementedError();
}
