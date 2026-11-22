/// What the connection needs to know about one listen. JS: `QueryContext` as `ServerActions.listen`
/// reads it (`core/ServerActions.ts`, `core/PersistentConnection.ts` `listen`); Android: the
/// `path` and `queryParams` arguments of `connection/PersistentConnection.java` `listen`.
///
/// Cross-team seam: JSON only, no `Path`, `Node` or `QuerySpec`.
library;

import 'package:firebase_database_dart/src/core/connection/server_actions.dart';

/// One listen (or get) as the connection sees it: plain strings and decoded JSON.
///
/// Built by Repo from a `QuerySpec` (`QuerySpec.toListenSpec`). Two specs are the same listen
/// when [path] and [queryIdentifier] are equal; [ServerActions] keys its listen table by them.
final class ListenSpec {
  /// Creates a spec.
  const ListenSpec({
    required this.path,
    required this.queryObject,
    required this.queryIdentifier,
    required this.isDefault,
    required this.loadsAllData,
    required this.indexName,
    required this.restParams,
  });

  /// The path in wire form: `/a/b`, `/` for the root.
  final String path;

  /// The query wire object (`sp`, `sn`, `sin`, `ep`, `en`, `ein`, `l`, `vf`, `i`); `{}` for the
  /// default query. Sent as `q` of a listen only together with a tag; always sent as `q` of a get.
  /// Unmodifiable.
  final Map<String, Object?> queryObject;

  /// `default` for the default query, else the canonical JSON of [queryObject] (sorted keys, no
  /// spaces). Matches listen-cancel (`c`) pushes and keys the listen table.
  final String queryIdentifier;

  /// Whether this is the default query (priority index, no range, no limit).
  final bool isDefault;

  /// Whether the query loads all data at [path] (no range, no limit). A query that loads all data
  /// but is not the default (a plain `orderByChild`) is listened to as the default query, untagged.
  final bool loadsAllData;

  /// The index wire name (`.priority`, `.key`, `.value` or a child path), for the "Using an
  /// unspecified index" warning when the listen response carries `w: ['no_index']`.
  final String indexName;

  /// The REST query string parameters (`orderBy`, `startAt`, `limitToFirst`, ...), from
  /// `QueryParams.toRestQueryStringParameters()`; `{}` for the default query. Used by the REST
  /// client. Unmodifiable.
  final Map<String, String> restParams;

  // Identity is path + queryIdentifier, as JS `PersistentConnection.listens_` keys its table
  // (`pathString` -> `queryId`). Android's `PersistentConnectionImpl.QuerySpec` compares the path
  // and the query params map instead; queryIdentifier is the canonical JSON of that map.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ListenSpec &&
          other.path == path &&
          other.queryIdentifier == queryIdentifier;

  @override
  int get hashCode => Object.hash(path, queryIdentifier);

  @override
  String toString() => '$path (params: $queryIdentifier)';
}
