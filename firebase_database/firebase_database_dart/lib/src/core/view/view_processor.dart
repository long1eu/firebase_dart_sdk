/// Applies operations to a view cache. JS: `core/view/ViewProcessor.ts`; Android:
/// `core/view/ViewProcessor.java`.
library;

import 'package:firebase_database_dart/src/core/operation/operation.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/view/change.dart';
import 'package:firebase_database_dart/src/core/view/filter/child_change_accumulator.dart';
import 'package:firebase_database_dart/src/core/view/filter/node_filter.dart';
import 'package:firebase_database_dart/src/core/view/view_cache.dart';
import 'package:firebase_database_dart/src/core/write_tree_ref.dart';

/// The new view cache and the changes that led to it.
final class ProcessorResult {
  /// Creates a result.
  const ProcessorResult(this.viewCache, this.changes);

  /// The new cache.
  final ViewCache viewCache;

  /// The child and value changes.
  final List<Change> changes;
}

/// Computes view caches and changes from operations, using [filter] for the query.
final class ViewProcessor {
  /// Creates a processor.
  const ViewProcessor(this.filter);

  /// The query's filter.
  final NodeFilter filter;

  /// Applies [operation] to [oldViewCache] with the pending [writesCache]; [optCompleteCache] is a
  /// complete server cache from a parent view, if any.
  ProcessorResult applyOperation(
    ViewCache oldViewCache,
    Operation operation,
    WriteTreeRef writesCache,
    Node? optCompleteCache,
  ) => throw UnimplementedError();

  /// Reverts a rejected user write at [path].
  ViewCache revertUserWrite(
    ViewCache viewCache,
    Path path,
    WriteTreeRef writesCache,
    Node? optCompleteServerCache,
    ChildChangeAccumulator accumulator,
  ) => throw UnimplementedError();
}
