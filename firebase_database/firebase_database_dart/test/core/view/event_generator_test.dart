// Event order (rtdb/research/13_engine_rules.md, event delivery rule 6; JS
// `core/view/EventGenerator.ts`): child removed, added, moved, changed, value; index order within a
// type; per change, the registrations in the order they were added.
import 'package:firebase_database_dart/src/core/callback_event_registration.dart';
import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/core/event_registration.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/value_index.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/view/change.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';
import 'package:firebase_database_dart/src/core/view/event_generator.dart';
import 'package:firebase_database_dart/src/core/view/query_params.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:test/test.dart';

import 'view_helpers.dart';

const Set<EventType> childTypes = <EventType>{
  EventType.childAdded,
  EventType.childRemoved,
  EventType.childChanged,
  EventType.childMoved,
};

final QuerySpec query = QuerySpec(Path('q'), QueryParams.defaultParams);

CallbackEventRegistration registration(Set<EventType> types) =>
    CallbackEventRegistration(
      query,
      types,
      onEvent: (DataEvent _) {},
      onCancel: (DatabaseError _) {},
    );

String describeEvent(DataEvent e, Map<EventRegistration, String> names) =>
    '${names[e.eventRegistration]} ${e.eventType.name} ${e.snapshotPath} '
    'prev=${e.previousName}';

void main() {
  final CallbackEventRegistration childReg = registration(childTypes);
  final CallbackEventRegistration valueReg = registration(<EventType>{
    EventType.value,
  });
  final CallbackEventRegistration bothReg = registration(<EventType>{
    ...childTypes,
    EventType.value,
  });
  final Map<EventRegistration, String> names = <EventRegistration, String>{
    childReg: 'child',
    valueReg: 'value',
    bothReg: 'both',
  };

  test('types in order, index order within a type, registrations in order', () {
    // Priority index: b, c, d have no priority and sort by key before e (priority 1).
    final Node eventCache = n(<String, Object?>{
      'b': 2,
      'c': 3,
      'd': 4,
      'e': <String, Object?>{'.value': 5, '.priority': 1},
    });
    final List<Change> changes = <Change>[
      Change.value(eventCache),
      Change.childChanged(
        k('e'),
        n(<String, Object?>{'.value': 5, '.priority': 1}),
        n(5),
      ),
      Change.childChanged(k('d'), n(4), n(40)),
      Change.childAdded(k('c'), n(3)),
      Change.childAdded(k('b'), n(2)),
      Change.childRemoved(k('z'), n(9)),
      Change.childRemoved(k('a'), n(1)),
    ];
    final List<DataEvent> events =
        EventGenerator(
          QuerySpec(Path.empty, QueryParams.defaultParams),
        ).generateEventsForChanges(changes, eventCache, <EventRegistration>[
          childReg,
          valueReg,
          bothReg,
        ]);
    expect(
      events.map((DataEvent e) => describeEvent(e, names)).toList(),
      <String>[
        'child childRemoved /a prev=null',
        'both childRemoved /a prev=null',
        'child childRemoved /z prev=null',
        'both childRemoved /z prev=null',
        'child childAdded /b prev=null',
        'both childAdded /b prev=null',
        'child childAdded /c prev=b',
        'both childAdded /c prev=b',
        // e's priority changed: a move, before the changes.
        'child childMoved /e prev=d',
        'both childMoved /e prev=d',
        'child childChanged /d prev=c',
        'both childChanged /d prev=c',
        'child childChanged /e prev=d',
        'both childChanged /e prev=d',
        'value value / prev=null',
        'both value / prev=null',
      ],
    );
  });

  test('events carry the query path and the change node', () {
    final Node eventCache = n(<String, Object?>{'a': 1});
    final List<DataEvent> events = EventGenerator(query)
        .generateEventsForChanges(
          <Change>[Change.childAdded(k('a'), n(1)), Change.value(eventCache)],
          eventCache,
          <EventRegistration>[bothReg],
        );
    expect(events, hasLength(2));
    expect(events[0].snapshotPath, Path('q/a'));
    expect(events[0].path, Path('q'));
    expect(events[0].snapshot, n(1));
    expect(events[1].snapshotPath, Path('q'));
    expect(events[1].path, Path('q'));
    expect(events[1].snapshot, eventCache);
  });

  test('a value change on a value index is a move', () {
    final QuerySpec byValue = QuerySpec(
      Path.empty,
      QueryParams.defaultParams.orderBy(valueIndex),
    );
    final Node eventCache = n(<String, Object?>{
      'a': 1,
      'b': 5,
    }).withIndex(valueIndex);
    final List<DataEvent> events = EventGenerator(byValue)
        .generateEventsForChanges(
          <Change>[Change.childChanged(k('b'), n(5), n(0))],
          eventCache,
          <EventRegistration>[childReg],
        );
    expect(events.map((DataEvent e) => e.eventType).toList(), <EventType>[
      EventType.childMoved,
      EventType.childChanged,
    ]);
    expect(events.first.previousName, k('a'));
  });

  test('no registration, no events', () {
    expect(
      EventGenerator(query).generateEventsForChanges(
        <Change>[Change.value(n(1))],
        n(1),
        const <EventRegistration>[],
      ),
      isEmpty,
    );
  });
}
