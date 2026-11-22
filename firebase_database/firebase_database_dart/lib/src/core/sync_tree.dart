/// The tree of sync points and pending writes. JS: `core/SyncTree.ts`; Android:
/// `core/SyncTree.java` (including its inner `KeepSyncedEventRegistration` and `ListenContainer`).
library;

import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/core/event_registration.dart';
import 'package:firebase_database_dart/src/core/listen_provider.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_manager.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/range_merge.dart';
import 'package:firebase_database_dart/src/core/sync_point.dart';
import 'package:firebase_database_dart/src/core/sync_tree_api.dart';
import 'package:firebase_database_dart/src/core/tag.dart';
import 'package:firebase_database_dart/src/core/util/clock.dart';
import 'package:firebase_database_dart/src/core/util/immutable_tree.dart';
import 'package:firebase_database_dart/src/core/view/cache_node.dart';
import 'package:firebase_database_dart/src/core/view/change.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:firebase_database_dart/src/core/write_id.dart';
import 'package:firebase_database_dart/src/core/write_tree.dart';

/// Cached server data larger than this (estimated JSON bytes) makes a listen send a compound
/// hash.
const int sizeThresholdForCompoundHash = 1024;

/// The sync tree: sync points by path, the pending write tree, tags (from a counter of this
/// instance, starting at 1), keep-synced queries, with every entry point wrapped in a
/// [PersistenceManager.runInTransaction].
final class SyncTree implements SyncTreeApi {
  /// Creates a tree listening through [listenProvider] and persisting through
  /// [persistenceManager] (a no-op one by default).
  factory SyncTree({
    required ListenProvider listenProvider,
    PersistenceManager? persistenceManager,
  }) => throw UnimplementedError();

  /// The sync points (for tests).
  ImmutableTree<SyncPoint> get syncPointTree => throw UnimplementedError();

  /// The pending writes (for tests).
  WriteTree get pendingWriteTree => throw UnimplementedError();

  @override
  bool get isEmpty => throw UnimplementedError();

  @override
  List<Event> applyUserOverwrite(
    Path path,
    Node newDataUnresolved,
    Node newData,
    WriteId writeId, {
    required bool visible,
    required bool persist,
  }) => throw UnimplementedError();

  @override
  List<Event> applyUserMerge(
    Path path,
    CompoundWrite unresolvedChildren,
    CompoundWrite children,
    WriteId writeId, {
    required bool persist,
  }) => throw UnimplementedError();

  @override
  List<Event> ackUserWrite(
    WriteId writeId, {
    required bool revert,
    required bool persist,
    required ServerClock serverClock,
  }) => throw UnimplementedError();

  @override
  List<Event> removeAllWrites() => throw UnimplementedError();

  @override
  List<Event> applyServerOverwrite(Path path, Node newData) =>
      throw UnimplementedError();

  @override
  List<Event> applyServerMerge(Path path, Map<Path, Node> changedChildren) =>
      throw UnimplementedError();

  @override
  List<Event> applyServerRangeMerges(Path path, List<RangeMerge> rangeMerges) =>
      throw UnimplementedError();

  @override
  List<Event> applyListenComplete(Path path) => throw UnimplementedError();

  @override
  List<Event> applyTaggedListenComplete(Tag tag) => throw UnimplementedError();

  @override
  List<Event> applyTaggedQueryOverwrite(Path path, Node snap, Tag tag) =>
      throw UnimplementedError();

  @override
  List<Event> applyTaggedQueryMerge(
    Path path,
    Map<Path, Node> changedChildren,
    Tag tag,
  ) => throw UnimplementedError();

  @override
  List<Event> applyTaggedRangeMerges(
    Path path,
    List<RangeMerge> rangeMerges,
    Tag tag,
  ) => throw UnimplementedError();

  @override
  List<Event> addEventRegistration(
    EventRegistration registration, {
    bool skipListenerSetup = false,
    CacheNode? preloadedServerCache,
  }) => throw UnimplementedError();

  @override
  List<Event> removeEventRegistration(
    EventRegistration registration, {
    bool skipDedup = false,
  }) => throw UnimplementedError();

  @override
  List<Event> removeAllEventRegistrations(
    QuerySpec query,
    DatabaseError error,
  ) => throw UnimplementedError();

  @override
  void keepSynced(
    QuerySpec query, {
    required bool keep,
    bool skipDedup = false,
  }) => throw UnimplementedError();

  @override
  Node? getServerValue(QuerySpec query) => throw UnimplementedError();

  @override
  Node? persistenceServerCache(QuerySpec query) => throw UnimplementedError();

  @override
  void setQueryActive(QuerySpec query) => throw UnimplementedError();

  @override
  void setQueryInactive(QuerySpec query) => throw UnimplementedError();

  @override
  Node? calcCompleteEventCache(
    Path path, {
    List<WriteId> writeIdsToExclude = const <WriteId>[],
  }) => throw UnimplementedError();

  @override
  Node? calcCompleteEventCacheFromRoot(
    Path path, {
    List<WriteId> writeIdsToExclude = const <WriteId>[],
  }) => throw UnimplementedError();

  @override
  Tag? tagForQuery(QuerySpec query) => throw UnimplementedError();
}

/// A registration that raises nothing and only keeps a query listened to and cached
/// (`keepSynced`, and Repo's `get` bracket). Equal to any other one on the same query.
final class KeepSyncedEventRegistration extends EventRegistration {
  /// Creates the registration for [querySpec].
  KeepSyncedEventRegistration(this.querySpec);

  @override
  final QuerySpec querySpec;

  @override
  bool respondsTo(EventType type) => throw UnimplementedError();

  @override
  DataEvent createEvent(Change change, QuerySpec query) =>
      throw UnimplementedError();

  @override
  void fireEvent(DataEvent event) => throw UnimplementedError();

  @override
  void fireCancelEvent(DatabaseError error) => throw UnimplementedError();

  @override
  EventRegistration clone(QuerySpec newQuery) => throw UnimplementedError();

  @override
  bool isSameListener(EventRegistration other) => throw UnimplementedError();

  @override
  bool operator ==(Object other) => throw UnimplementedError();

  @override
  int get hashCode => throw UnimplementedError();
}
