// JS: core/view/Event.ts (DataEvent); Android: core/view/DataEvent.java.
part of 'event.dart';

/// A data change for one registration. JS: `core/view/Event.ts` (`DataEvent`); Android:
/// `core/view/DataEvent.java`.
final class DataEvent extends Event {
  /// Creates an event; [snapshotPath] is the path of [snapshot].
  const DataEvent(
    this.eventType,
    this.eventRegistration,
    this.snapshotPath,
    this.snapshot, {
    this.previousName,
  });

  /// The kind.
  final EventType eventType;

  /// The receiver.
  final EventRegistration eventRegistration;

  /// The path of [snapshot] (the child for child events).
  final Path snapshotPath;

  /// The data (indexed with the query's index).
  final Node snapshot;

  /// The key of the previous sibling for child added, changed and moved events.
  final ChildKey? previousName;

  /// The snapshot path for value events, its parent for child events.
  @override
  Path get path => throw UnimplementedError();

  @override
  void fire() => throw UnimplementedError();

  @override
  String toString() => throw UnimplementedError();
}
