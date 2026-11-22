// JS: core/view/Event.ts (CancelEvent); Android: core/view/CancelEvent.java.
part of 'event.dart';

/// A listen failed and its registration is cancelled. JS: `core/view/Event.ts` (`CancelEvent`);
/// Android: `core/view/CancelEvent.java`.
final class CancelEvent extends Event {
  /// Creates an event.
  const CancelEvent(this.eventRegistration, this.error, this.path);

  /// The receiver.
  final EventRegistration eventRegistration;

  /// Why.
  final DatabaseError error;

  @override
  final Path path;

  @override
  void fire() => throw UnimplementedError();

  @override
  String toString() => throw UnimplementedError();
}
