/// The views at one path. JS: `core/SyncPoint.ts`; Android: `core/SyncPoint.java`.
library;

import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/core/event_registration.dart';
import 'package:firebase_database_dart/src/core/operation/operation.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_manager.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/view/cache_node.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';
import 'package:firebase_database_dart/src/core/view/query_params.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:firebase_database_dart/src/core/view/view.dart';
import 'package:firebase_database_dart/src/core/write_tree_ref.dart';

/// The queries removed by a removal and the cancel events it produced.
typedef SyncPointRemoval = ({
  List<QuerySpec> removed,
  List<Event> cancelEvents,
});

/// The views of every query registered at one path; tracks the child keys of filtered queries
/// through [persistenceManager].
final class SyncPoint {
  /// Creates an empty sync point.
  factory SyncPoint(PersistenceManager persistenceManager) =>
      throw UnimplementedError();

  /// The persistence hooks.
  PersistenceManager get persistenceManager => throw UnimplementedError();

  /// Whether no view is left.
  bool get isEmpty => throw UnimplementedError();

  /// Applies [operation] to the view it targets (tagged) or to every view.
  List<DataEvent> applyOperation(
    Operation operation,
    WriteTreeRef writesCache,
    Node? optCompleteServerCache,
  ) => throw UnimplementedError();

  /// The view of [query], creating one from [serverCache] and the writes when missing.
  View getView(
    QuerySpec query,
    WriteTreeRef writesCache,
    CacheNode serverCache,
  ) => throw UnimplementedError();

  /// Adds [registration] (creating its view) and returns its initial events.
  List<DataEvent> addEventRegistration(
    EventRegistration registration,
    WriteTreeRef writesCache,
    CacheNode serverCache,
  ) => throw UnimplementedError();

  /// Removes [registration] (all when null) from the views of [query] (all views for the default
  /// query); with [cancelError] returns cancel events.
  SyncPointRemoval removeEventRegistration(
    QuerySpec query,
    EventRegistration? registration,
    DatabaseError? cancelError,
  ) => throw UnimplementedError();

  /// The views of queries that do not load all data.
  List<View> get queryViews => throw UnimplementedError();

  /// The complete server data at [path] below this point, or null.
  Node? completeServerCache(Path path) => throw UnimplementedError();

  /// The view of [query], or null.
  View? viewForQuery(QuerySpec query) => throw UnimplementedError();

  /// Whether a view for [query] exists.
  bool viewExistsForQuery(QuerySpec query) => throw UnimplementedError();

  /// Whether a view loading all data exists.
  bool get hasCompleteView => throw UnimplementedError();

  /// The view loading all data, or null.
  View? get completeView => throw UnimplementedError();

  /// The views by query parameters.
  Map<QueryParams, View> get views => throw UnimplementedError();
}
