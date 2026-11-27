/// A query whose data is kept in the cache. JS: none; Android:
/// `core/persistence/TrackedQuery.java`.
library;

import 'package:firebase_database_dart/src/core/view/query_spec.dart';

/// A persisted record of a query: [id], [querySpec], [lastUse] (ms), [complete], [active].
final class TrackedQuery {
  /// Creates a record.
  const TrackedQuery({
    required this.id,
    required this.querySpec,
    required this.lastUse,
    required this.complete,
    required this.active,
  });

  /// The id.
  final int id;

  /// The query.
  final QuerySpec querySpec;

  /// The last time (ms since the epoch) the query was active.
  final int lastUse;

  /// Whether the server sent its complete data.
  final bool complete;

  /// Whether a listen is active.
  final bool active;

  /// With [lastUse].
  TrackedQuery withLastUse(int lastUse) => TrackedQuery(
    id: id,
    querySpec: querySpec,
    lastUse: lastUse,
    complete: complete,
    active: active,
  );

  /// Marked complete.
  TrackedQuery withComplete() => TrackedQuery(
    id: id,
    querySpec: querySpec,
    lastUse: lastUse,
    complete: true,
    active: active,
  );

  /// With [active].
  TrackedQuery withActiveState(bool active) => TrackedQuery(
    id: id,
    querySpec: querySpec,
    lastUse: lastUse,
    complete: complete,
    active: active,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrackedQuery &&
          other.id == id &&
          other.querySpec == querySpec &&
          other.lastUse == lastUse &&
          other.complete == complete &&
          other.active == active;

  @override
  int get hashCode => Object.hash(id, querySpec, lastUse, complete, active);

  @override
  String toString() =>
      'TrackedQuery{id=$id, querySpec=$querySpec, lastUse=$lastUse, '
      'complete=$complete, active=$active}';
}
