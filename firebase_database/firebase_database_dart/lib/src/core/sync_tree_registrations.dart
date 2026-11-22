// Android: core/SyncTree.java (KeepSyncedEventRegistration).
part of 'sync_tree.dart';

/// A registration that raises nothing and only keeps a query listened to and cached
/// (`keepSynced`, and Repo's `get` bracket). Equal to any other one on the same query. Android
/// `SyncTree.KeepSyncedEventRegistration`.
final class KeepSyncedEventRegistration extends EventRegistration {
  /// Creates the registration for [querySpec] (Android `KeepSyncedEventRegistration(QuerySpec)`).
  KeepSyncedEventRegistration(this.querySpec);

  /// The query kept synced (Android `KeepSyncedEventRegistration.getQuerySpec`).
  @override
  final QuerySpec querySpec;

  /// Always false (Android `KeepSyncedEventRegistration.respondsTo`).
  @override
  bool respondsTo(EventType type) => false;

  /// Never called, as [respondsTo] is false (Android `KeepSyncedEventRegistration.createEvent`
  /// returns null).
  @override
  DataEvent createEvent(Change change, QuerySpec query) =>
      throw StateError('KeepSyncedEventRegistration raises no events');

  /// Does nothing (Android `KeepSyncedEventRegistration.fireEvent`).
  @override
  void fireEvent(DataEvent event) {}

  /// Does nothing (Android `KeepSyncedEventRegistration.fireCancelEvent`).
  @override
  void fireCancelEvent(DatabaseError error) {}

  /// The registration for [newQuery] (Android `KeepSyncedEventRegistration.clone`).
  @override
  EventRegistration clone(QuerySpec newQuery) =>
      KeepSyncedEventRegistration(newQuery);

  /// Any keep-synced registration (Android `KeepSyncedEventRegistration.isSameListener`).
  @override
  bool isSameListener(EventRegistration other) =>
      other is KeepSyncedEventRegistration;

  /// Equal for the same query (Android `KeepSyncedEventRegistration.equals`).
  @override
  bool operator ==(Object other) =>
      other is KeepSyncedEventRegistration && other.querySpec == querySpec;

  /// Android `KeepSyncedEventRegistration.hashCode`.
  @override
  int get hashCode => querySpec.hashCode;
}
