/// Turns changes into events. JS: `core/view/EventGenerator.ts`; Android:
/// `core/view/EventGenerator.java`.
library;

import 'package:firebase_database_dart/src/core/event_registration.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/view/change.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';

/// Generates the events of one query in the order child removed, added, moved, changed, value.
final class EventGenerator {
  /// Creates a generator for [query].
  const EventGenerator(this.query);

  /// The query.
  final QuerySpec query;

  /// The events for [changes] on [eventCache] for each of [registrations].
  List<DataEvent> generateEventsForChanges(
    List<Change> changes,
    Node eventCache,
    List<EventRegistration> registrations,
  ) => throw UnimplementedError();
}
