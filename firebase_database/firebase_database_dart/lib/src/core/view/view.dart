/// One query's view at a sync point. JS: `core/view/View.ts`; Android: `core/view/View.java`.
library;

import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/core/event_registration.dart';
import 'package:firebase_database_dart/src/core/operation/operation.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/view/change.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:firebase_database_dart/src/core/view/view_cache.dart';
import 'package:firebase_database_dart/src/core/write_tree_ref.dart';

/// The events and changes of one operation on a view.
final class ViewOperationResult {
  /// Creates a result.
  const ViewOperationResult(this.events, this.changes);

  /// The events to raise.
  final List<DataEvent> events;

  /// The changes (the sync point tracks child keys of filtered queries from them).
  final List<Change> changes;
}

/// The caches, registrations and processor of one query.
final class View {
  /// Creates a view of [query] starting from [initialViewCache].
  factory View(QuerySpec query, ViewCache initialViewCache) =>
      throw UnimplementedError();

  /// The query.
  QuerySpec get query => throw UnimplementedError();

  /// The current caches.
  ViewCache get viewCache => throw UnimplementedError();

  /// The registrations.
  List<EventRegistration> get eventRegistrations => throw UnimplementedError();

  /// The complete event cache, or null.
  Node? get completeNode => throw UnimplementedError();

  /// The server cache node.
  Node get serverCache => throw UnimplementedError();

  /// The event cache node.
  Node get eventCache => throw UnimplementedError();

  /// The complete server data at [path] below the view, or null.
  Node? completeServerCache(Path path) => throw UnimplementedError();

  /// Whether no registration is left.
  bool get isEmpty => throw UnimplementedError();

  /// Adds [registration].
  void addEventRegistration(EventRegistration registration) =>
      throw UnimplementedError();

  /// Removes [registration] (all when null); with [cancelError] removes all and returns their
  /// cancel events.
  List<Event> removeEventRegistration(
    EventRegistration? registration,
    DatabaseError? cancelError,
  ) => throw UnimplementedError();

  /// Applies [operation].
  ViewOperationResult applyOperation(
    Operation operation,
    WriteTreeRef writesCache,
    Node? optCompleteServerCache,
  ) => throw UnimplementedError();

  /// The events a new [registration] gets for the current data.
  List<DataEvent> initialEvents(EventRegistration registration) =>
      throw UnimplementedError();
}
