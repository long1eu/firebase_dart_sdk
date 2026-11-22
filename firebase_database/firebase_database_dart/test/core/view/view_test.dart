// View (Android `core/view/View.java`, JS `core/view/View.ts`) without operations, and the
// registrations (Android `EventRegistration.java`, `ValueEventRegistration.java`,
// `ChildEventRegistration.java`). Operations are in view_processor_test.dart.
import 'package:firebase_database_dart/src/core/callback_event_registration.dart';
import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/core/event_registration.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/value_index.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/view/cache_node.dart';
import 'package:firebase_database_dart/src/core/view/change.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';
import 'package:firebase_database_dart/src/core/view/query_params.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:firebase_database_dart/src/core/view/view.dart';
import 'package:firebase_database_dart/src/core/view/view_cache.dart';
import 'package:test/test.dart';

import 'view_helpers.dart';

const Set<EventType> childTypes = <EventType>{
  EventType.childAdded,
  EventType.childRemoved,
  EventType.childChanged,
  EventType.childMoved,
};

final QuerySpec defaultQuery = QuerySpec(Path('q'), QueryParams.defaultParams);

final QuerySpec limitQuery = QuerySpec(
  Path('q'),
  QueryParams.defaultParams.orderBy(valueIndex).limitToFirst(1),
);

const DatabaseError denied = DatabaseError(
  DatabaseErrorCode.permissionDenied,
  'denied',
);

ViewCache caches(Node node, {required bool complete}) {
  final CacheNode c = CacheNode(
    node,
    fullyInitialized: complete,
    filtered: false,
  );
  return ViewCache(c, c);
}

CallbackEventRegistration reg(
  Set<EventType> types, {
  QuerySpec? query,
  void Function(DataEvent)? onEvent,
  List<String>? log,
}) => CallbackEventRegistration(
  query ?? defaultQuery,
  types,
  onEvent:
      onEvent ??
      (DataEvent e) => log?.add('${e.eventType.name} ${e.snapshotPath}'),
  onCancel: (DatabaseError e) => log?.add('cancel ${e.code.code}'),
);

void main() {
  final Node data = n(<String, Object?>{'a': 1, 'b': 2});

  group('View', () {
    test('the event cache is filtered, the server cache only indexed', () {
      final View view = View(limitQuery, caches(data, complete: true));
      expect(view.eventCache, n(<String, Object?>{'a': 1}));
      expect(view.viewCache.eventCache.filtered, isTrue);
      expect(view.viewCache.eventCache.fullyInitialized, isTrue);
      expect(view.eventCache.isIndexed(valueIndex), isTrue);
      expect(view.serverCache, data);
      expect(view.viewCache.serverCache.filtered, isFalse);
      expect(view.serverCache.isIndexed(valueIndex), isTrue);
      expect(view.completeNode, n(<String, Object?>{'a': 1}));
      expect(identical(view.query, limitQuery), isTrue);
    });

    test('initial events: children, then the value of a complete cache', () {
      final View view = View(defaultQuery, caches(data, complete: true));
      final List<String> log = <String>[];
      final CallbackEventRegistration r = reg(<EventType>{
        ...childTypes,
        EventType.value,
      }, log: log);
      final List<DataEvent> events = view.initialEvents(r);
      expect(
        events
            .map(
              (DataEvent e) =>
                  '${e.eventType.name} ${e.snapshotPath} ${e.previousName}',
            )
            .toList(),
        <String>['childAdded /q/a null', 'childAdded /q/b a', 'value /q null'],
      );
    });

    test('initial events of a partial cache have no value event (rule 7)', () {
      final View view = View(defaultQuery, caches(data, complete: false));
      final List<DataEvent> events = view.initialEvents(
        reg(<EventType>{...childTypes, EventType.value}),
      );
      expect(events.map((DataEvent e) => e.eventType).toList(), <EventType>[
        EventType.childAdded,
        EventType.childAdded,
      ]);
      expect(view.completeNode, isNull);
    });

    test('initial events of a leaf: the value only', () {
      final View view = View(defaultQuery, caches(n(5), complete: true));
      final List<DataEvent> events = view.initialEvents(
        reg(<EventType>{...childTypes, EventType.value}),
      );
      expect(events.single.eventType, EventType.value);
      expect(events.single.snapshot, n(5));
    });

    test('completeServerCache of a view that loads all data', () {
      final View view = View(defaultQuery, caches(data, complete: true));
      expect(view.completeServerCache(Path.empty), data);
      expect(view.completeServerCache(Path('a')), n(1));
      expect(view.completeServerCache(Path('z')), ChildrenNode.empty);
      expect(
        View(
          defaultQuery,
          caches(data, complete: false),
        ).completeServerCache(Path.empty),
        isNull,
      );
    });

    test('completeServerCache of a filtered view: only children it has', () {
      final View view = View(limitQuery, caches(data, complete: true));
      expect(view.completeServerCache(Path.empty), isNull);
      expect(view.completeServerCache(Path('b')), n(2));
      expect(view.completeServerCache(Path('z')), isNull);
    });

    group('registrations', () {
      test('add keeps the order; remove by listener zombifies that one', () {
        final View view = View(defaultQuery, caches(data, complete: true));
        expect(view.isEmpty, isTrue);
        final CallbackEventRegistration r1 = reg(<EventType>{EventType.value});
        final CallbackEventRegistration r2 = reg(<EventType>{EventType.value});
        view
          ..addEventRegistration(r1)
          ..addEventRegistration(r2);
        expect(view.eventRegistrations, <EventRegistration>[r1, r2]);
        final List<Event> events = view.removeEventRegistration(
          r1.clone(defaultQuery),
          null,
        );
        expect(events, isEmpty);
        expect(view.eventRegistrations, <EventRegistration>[r2]);
        expect(r1.isZombied, isTrue);
        expect(r2.isZombied, isFalse);
      });

      test('remove all zombifies all', () {
        final View view = View(defaultQuery, caches(data, complete: true));
        final CallbackEventRegistration r1 = reg(<EventType>{EventType.value});
        final CallbackEventRegistration r2 = reg(childTypes);
        view
          ..addEventRegistration(r1)
          ..addEventRegistration(r2);
        expect(view.removeEventRegistration(null, null), isEmpty);
        expect(view.isEmpty, isTrue);
        expect(r1.isZombied && r2.isZombied, isTrue);
      });

      test(
        'cancel returns a cancel event per registration, delivered once',
        () {
          final View view = View(defaultQuery, caches(data, complete: true));
          final List<String> log = <String>[];
          final CallbackEventRegistration r1 = reg(<EventType>{
            EventType.value,
          }, log: log);
          final CallbackEventRegistration r2 = reg(childTypes, log: log);
          view
            ..addEventRegistration(r1)
            ..addEventRegistration(r2);
          final List<Event> events = view.removeEventRegistration(null, denied);
          expect(view.isEmpty, isTrue);
          expect(events, hasLength(2));
          expect(events.every((Event e) => e is CancelEvent), isTrue);
          expect(events.first.path, Path('q'));
          expect((events.first as CancelEvent).eventRegistration, r1);
          expect(events.first.toString(), '/q:CANCEL');
          for (final Event e in events) {
            e.fire();
          }
          for (final Event e in events) {
            e.fire();
          }
          expect(log, <String>[
            'cancel permission-denied',
            'cancel permission-denied',
          ]);
          expect(r1.isZombied && r2.isZombied, isTrue);
        },
      );
    });
  });

  group('CallbackEventRegistration', () {
    test('respondsTo its types', () {
      final CallbackEventRegistration r = reg(<EventType>{EventType.value});
      expect(r.respondsTo(EventType.value), isTrue);
      expect(r.respondsTo(EventType.childAdded), isFalse);
    });

    test('createEvent: value at the query path, child at the child path', () {
      final CallbackEventRegistration r = reg(<EventType>{
        ...childTypes,
        EventType.value,
      });
      final DataEvent value = r.createEvent(Change.value(data), defaultQuery);
      expect(value.eventType, EventType.value);
      expect(value.snapshotPath, Path('q'));
      expect(value.path, Path('q'));
      expect(value.snapshot, data);
      expect(value.previousName, isNull);

      final DataEvent child = r.createEvent(
        Change.childAdded(k('b'), n(2)).withPrevName(k('a')),
        defaultQuery,
      );
      expect(child.eventType, EventType.childAdded);
      expect(child.snapshotPath, Path('q/b'));
      expect(child.path, Path('q'));
      expect(child.previousName, k('a'));
      expect(identical(child.eventRegistration, r), isTrue);
    });

    test('fire delivers until zombied; the zombie listener runs once', () {
      final List<String> log = <String>[];
      final CallbackEventRegistration r = reg(<EventType>{
        EventType.value,
      }, log: log);
      int zombieCalls = 0;
      r.onZombied = (EventRegistration z) {
        expect(identical(z, r), isTrue);
        zombieCalls++;
      };
      final DataEvent event = r.createEvent(Change.value(data), defaultQuery);
      event.fire();
      r
        ..zombify()
        ..zombify();
      event.fire();
      r.fireCancelEvent(denied);
      expect(log, <String>['value /q']);
      expect(zombieCalls, 1);
    });

    test('clone keeps the callbacks and types; isSameListener by onEvent', () {
      void onEvent(DataEvent _) {}
      final CallbackEventRegistration r = reg(<EventType>{
        EventType.value,
      }, onEvent: onEvent);
      final QuerySpec other = QuerySpec(Path('x'), QueryParams.defaultParams);
      final EventRegistration clone = r.clone(other);
      expect(clone.querySpec, other);
      expect(clone.respondsTo(EventType.value), isTrue);
      expect(clone.isSameListener(r), isTrue);
      expect(r.isSameListener(reg(<EventType>{EventType.value})), isFalse);
    });

    test('isUserInitiated defaults to false', () {
      final CallbackEventRegistration r = reg(<EventType>{EventType.value});
      expect(r.isUserInitiated, isFalse);
      r.isUserInitiated = true;
      expect(r.isUserInitiated, isTrue);
    });
  });
}
