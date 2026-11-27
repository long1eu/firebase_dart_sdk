/// How the sync tree starts and stops server listens. JS: `core/SyncTree.ts` (`ListenProvider`);
/// Android: `core/SyncTree.java` (`ListenProvider`, `CompletionListener`).
///
/// Internal seam between the sync tree and Repo: Repo implements it over `ServerActions`
/// (converting [QuerySpec] to a `ListenSpec` and [Tag] to an int); the info tree's provider
/// answers from `.info` data.
library;

import 'package:firebase_database_dart/src/core/connection/listen_hash_provider.dart';
import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/core/tag.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';

/// Called once when a listen completes: [error] null on success. Returns the events the sync
/// tree raised in response (listen complete, or the cancel events of the failed query), which
/// the caller (Repo) raises.
typedef ListenCompletion = List<Event> Function(DatabaseError? error);

/// Starts and stops server listens for the sync tree.
abstract interface class ListenProvider {
  /// Starts listening to [query]. [query] is already in its listen form (a query that loads all
  /// data arrives as the default query); [tag] is non-null exactly for queries that do not load
  /// all data. [hash] gives the simple hash (always sent), and the compound hash when
  /// [ListenHashProvider.shouldIncludeCompoundHash]. [onComplete] is called once, asynchronously,
  /// when the server answers; on a later revoke it is called with the error (a listen is
  /// completed at most once with an error).
  ///
  /// Returns the events raised at once (JS `SyncTree.ts:91-96`): the `.info` provider applies the
  /// current `.info` value to its tree and returns those events, so they stay inside
  /// `addEventRegistration`'s result. The server provider returns an empty list.
  ///
  /// Called from inside sync tree operations: apart from that synchronous `.info` overwrite,
  /// implementations must not call back into the sync tree synchronously.
  List<Event> startListening(
    QuerySpec query,
    Tag? tag,
    ListenHashProvider hash,
    ListenCompletion onComplete,
  );

  /// Stops listening to [query] with [tag] (the same values given to [startListening]).
  void stopListening(QuerySpec query, Tag? tag);
}
