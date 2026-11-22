/// Turns changes into events. JS: `core/view/EventGenerator.ts`; Android:
/// `core/view/EventGenerator.java`.
library;

import 'package:firebase_database_dart/src/core/event_registration.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/index.dart';
import 'package:firebase_database_dart/src/core/snap/named_node.dart';
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

  /// The events for [changes] on [eventCache] for each of [registrations] (JS
  /// `eventGeneratorGenerateEventsForChanges`): child removed, child added, child moved (a child
  /// changed whose indexed value changed), child changed, then value; within a type in index
  /// order; per change, the registrations in their order.
  List<DataEvent> generateEventsForChanges(
    List<Change> changes,
    Node eventCache,
    List<EventRegistration> registrations,
  ) {
    final Index index = query.index;
    final List<DataEvent> events = <DataEvent>[];
    final List<Change> moves = <Change>[
      for (final Change change in changes)
        if (change.eventType == EventType.childChanged &&
            index.indexedValueChanged(change.oldNode!, change.node))
          Change.childMoved(change.childKey!, change.node),
    ];
    _generateEventsForType(
      events,
      EventType.childRemoved,
      changes,
      registrations,
      eventCache,
    );
    _generateEventsForType(
      events,
      EventType.childAdded,
      changes,
      registrations,
      eventCache,
    );
    _generateEventsForType(
      events,
      EventType.childMoved,
      moves,
      registrations,
      eventCache,
    );
    _generateEventsForType(
      events,
      EventType.childChanged,
      changes,
      registrations,
      eventCache,
    );
    _generateEventsForType(
      events,
      EventType.value,
      changes,
      registrations,
      eventCache,
    );
    return events;
  }

  void _generateEventsForType(
    List<DataEvent> events,
    EventType eventType,
    List<Change> changes,
    List<EventRegistration> registrations,
    Node eventCache,
  ) {
    final List<Change> filteredChanges = <Change>[
      for (final Change change in changes)
        if (change.eventType == eventType) change,
    ];
    if (eventType != EventType.value) {
      final Index index = query.index;
      filteredChanges.sort(
        (Change a, Change b) => index.compare(
          NamedNode(a.childKey!, a.node),
          NamedNode(b.childKey!, b.node),
        ),
      );
    }
    for (final Change change in filteredChanges) {
      final Change materialized = _materializeSingleChange(change, eventCache);
      for (final EventRegistration registration in registrations) {
        if (registration.respondsTo(eventType)) {
          events.add(registration.createEvent(materialized, query));
        }
      }
    }
  }

  Change _materializeSingleChange(Change change, Node eventCache) {
    if (change.eventType == EventType.value ||
        change.eventType == EventType.childRemoved) {
      return change;
    }
    return change.withPrevName(
      eventCache.getPredecessorChildKey(
        change.childKey!,
        change.node,
        query.index,
      ),
    );
  }
}
