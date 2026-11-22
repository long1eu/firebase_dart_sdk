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
  TrackedQuery withLastUse(int lastUse) => throw UnimplementedError();

  /// Marked complete.
  TrackedQuery withComplete() => throw UnimplementedError();

  /// With [active].
  TrackedQuery withActiveState(bool active) => throw UnimplementedError();

  @override
  bool operator ==(Object other) => throw UnimplementedError();

  @override
  int get hashCode => throw UnimplementedError();

  @override
  String toString() => throw UnimplementedError();
}
