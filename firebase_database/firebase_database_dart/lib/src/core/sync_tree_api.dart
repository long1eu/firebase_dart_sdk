/// The surface Repo uses on the sync tree. JS: the exported `syncTree*` functions of
/// `core/SyncTree.ts`; Android: the public methods of `core/SyncTree.java`.
///
/// Seam between the Repo team and the sync-tree team; `SyncTree` implements it.
library;

import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/core/event_registration.dart';
import 'package:firebase_database_dart/src/core/listen_provider.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_manager.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/range_merge.dart';
import 'package:firebase_database_dart/src/core/tag.dart';
import 'package:firebase_database_dart/src/core/view/cache_node.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:firebase_database_dart/src/core/write_id.dart';

/// Repo's view of the sync tree. Every method is synchronous, runs in one
/// [PersistenceManager.runInTransaction], and returns the events to raise (Repo raises them
/// by appending them to its `EventDispatcher`); none raises events itself.
abstract interface class SyncTreeApi {
  /// Whether no query is registered.
  bool get isEmpty;

  /// A user `set` or transaction write of [newData] (resolved) at [path]. [newDataUnresolved] is
  /// what is persisted when [persist]; [visible] is false for transactions with
  /// `applyLocally: false` (never persisted).
  List<Event> applyUserOverwrite(
    Path path,
    Node newDataUnresolved,
    Node newData,
    WriteId writeId, {
    required bool visible,
    required bool persist,
  });

  /// A user `update` of [children] (resolved) at [path]; [unresolvedChildren] is persisted when
  /// [persist].
  List<Event> applyUserMerge(
    Path path,
    CompoundWrite unresolvedChildren,
    CompoundWrite children,
    WriteId writeId, {
    required bool persist,
  });

  /// The server acknowledged ([revert] false) or rejected ([revert] true) write [writeId].
  /// When [persist], the write leaves the persisted log and an acknowledged write moves into the
  /// persisted server cache, with server values resolved against [serverValues] (Repo passes
  /// `generateServerValues()`; the sync tree reads no clock).
  List<Event> ackUserWrite(
    WriteId writeId, {
    required bool revert,
    required bool persist,
    required Map<String, Object?> serverValues,
  });

  /// Removes every pending write (purgeOutstandingWrites) and returns the revert events.
  List<Event> removeAllWrites();

  /// Server data [newData] at [path] for untagged listens.
  List<Event> applyServerOverwrite(Path path, Node newData);

  /// Server merge of [changedChildren] (relative paths) at [path] for untagged listens.
  List<Event> applyServerMerge(Path path, Map<Path, Node> changedChildren);

  /// Server range merges at [path] for untagged listens.
  List<Event> applyServerRangeMerges(Path path, List<RangeMerge> rangeMerges);

  /// The untagged listen at [path] completed.
  List<Event> applyListenComplete(Path path);

  /// The tagged listen [tag] completed; no events when the tag is unknown.
  List<Event> applyTaggedListenComplete(Tag tag);

  /// Server data for the tagged query [tag]; no events when the tag is unknown.
  List<Event> applyTaggedQueryOverwrite(Path path, Node snap, Tag tag);

  /// Server merge for the tagged query [tag].
  List<Event> applyTaggedQueryMerge(
    Path path,
    Map<Path, Node> changedChildren,
    Tag tag,
  );

  /// Server range merges for the tagged query [tag].
  List<Event> applyTaggedRangeMerges(
    Path path,
    List<RangeMerge> rangeMerges,
    Tag tag,
  );

  /// Registers [registration] and returns its initial events. Starts a server listen unless
  /// [skipListenerSetup] or a covering listen exists. [preloadedServerCache] is server data an
  /// asynchronous persistence engine loaded beforehand; when given it is used instead of asking
  /// the persistence manager. The events [ListenProvider.startListening] returns (the `.info`
  /// value) are part of the result.
  List<Event> addEventRegistration(
    EventRegistration registration, {
    bool skipListenerSetup = false,
    CacheNode? preloadedServerCache,
  });

  /// Removes [registration] (all registrations of its query when it matches none specifically)
  /// and stops listens no longer needed; [skipDedup] skips the check for a covering listen.
  List<Event> removeEventRegistration(
    EventRegistration registration, {
    bool skipDedup = false,
  });

  /// Removes every registration of [query] with [error] and returns their cancel events.
  List<Event> removeAllEventRegistrations(QuerySpec query, DatabaseError error);

  /// Keeps [query] listened to (and cached) without a user listener, or stops doing so.
  void keepSynced(
    QuerySpec query, {
    required bool keep,
    bool skipDedup = false,
  });

  /// The complete server data of [query] if the tree has it (for `get` without a round trip),
  /// else null.
  Node? getServerValue(QuerySpec query);

  /// The cached server data of [query] from persistence, filtered by the query, when persistence
  /// knows it complete (an empty node for a location known empty), else null (for `get` while
  /// offline).
  Node? persistenceServerCache(QuerySpec query);

  /// Marks [query] active in persistence (around `get`).
  void setQueryActive(QuerySpec query);

  /// Marks [query] inactive in persistence.
  void setQueryInactive(QuerySpec query);

  /// Marks [query] inactive in persistence unless a view of the tree serves it (the end of a
  /// `get` answered without a server overwrite).
  void releaseQuery(QuerySpec query);

  /// The complete event cache at [path] (server data with pending writes, including hidden
  /// ones) excluding [writeIdsToExclude], or null; used by transactions and server values.
  Node? calcCompleteEventCache(
    Path path, {
    List<WriteId> writeIdsToExclude = const <WriteId>[],
  });

  /// Like [calcCompleteEventCache] but starting from the root view's cache.
  Node? calcCompleteEventCacheFromRoot(
    Path path, {
    List<WriteId> writeIdsToExclude = const <WriteId>[],
  });

  /// The tag of [query], or null when untagged.
  Tag? tagForQuery(QuerySpec query);
}
