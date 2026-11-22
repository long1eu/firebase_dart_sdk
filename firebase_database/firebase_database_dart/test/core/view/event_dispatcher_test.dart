// EventDispatcher: delivery on a later turn, FIFO order, whole changes, the macrotask yield,
// zombied registrations, cancel events, throwing listeners (contract rules 4.4, 4.5, 4.11,
// 4.12; 13_engine_rules.md event delivery 2 to 6).
import 'dart:async';

import 'package:firebase_database_dart/src/core/callback_event_registration.dart';
import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';
import 'package:firebase_database_dart/src/core/view/event_dispatcher.dart';
import 'package:firebase_database_dart/src/core/view/macrotask_web.dart'
    if (dart.library.io) 'package:firebase_database_dart/src/core/view/macrotask_io.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:test/test.dart';

final List<String> log = <String>[];

CallbackEventRegistration registration(
  String name, {
  void Function(DataEvent event)? after,
}) => CallbackEventRegistration(
  QuerySpec.defaultAt(Path('a')),
  <EventType>{EventType.value},
  onEvent: (DataEvent event) {
    log.add('$name:${event.snapshot.value}');
    after?.call(event);
  },
  onCancel: (DatabaseError error) => log.add('$name:E(${error.code.code})'),
);

DataEvent value(CallbackEventRegistration r, Object v) =>
    DataEvent(EventType.value, r, Path('a'), nodeFromJson(v));

CancelEvent cancel(CallbackEventRegistration r) =>
    CancelEvent(r, DatabaseError.fromStatus('permission_denied'), Path('a'));

void main() {
  setUp(log.clear);

  test('delivers on a later turn, never inside enqueue', () async {
    final EventDispatcher dispatcher = EventDispatcher();
    final CallbackEventRegistration r = registration('R');
    dispatcher.enqueue(<Event>[value(r, 1)]);
    log.add('returned');
    await pumpEventQueue();
    expect(log, <String>['returned', 'R:1']);
  });

  test('changes in FIFO order; a listener enqueue goes to the tail', () async {
    final EventDispatcher dispatcher = EventDispatcher();
    late CallbackEventRegistration a;
    final CallbackEventRegistration b = registration('B');
    a = registration(
      'A',
      after: (DataEvent event) {
        if (event.snapshot.value == 1) {
          dispatcher.enqueue(<Event>[value(a, 3)]);
          log.add('enqueued');
        }
      },
    );
    dispatcher
      ..enqueue(<Event>[value(a, 1), value(b, 1)])
      ..enqueue(<Event>[value(b, 2)]);
    await pumpEventQueue();
    expect(log, <String>['A:1', 'enqueued', 'B:1', 'B:2', 'A:3']);
  });

  test('yields to the injected macrotask only between changes', () async {
    final List<void Function()> tasks = <void Function()>[];
    final EventDispatcher dispatcher = EventDispatcher(
      yieldEvery: 2,
      macrotask: tasks.add,
    );
    final CallbackEventRegistration r = registration('R');
    dispatcher
      ..enqueue(<Event>[value(r, 1), value(r, 2), value(r, 3)])
      ..enqueue(<Event>[value(r, 4)]);
    // Timers and microtasks run; the rest waits for the injected macrotask, not for Timer.run.
    await pumpEventQueue();
    expect(log, <String>['R:1', 'R:2', 'R:3']);
    expect(tasks, hasLength(1));
    log.add('T');
    tasks.removeAt(0)();
    expect(log, <String>['R:1', 'R:2', 'R:3', 'T', 'R:4']);
    expect(tasks, isEmpty);
  });

  test('events enqueued during a yield follow it, none is lost', () async {
    final List<void Function()> tasks = <void Function()>[];
    final EventDispatcher dispatcher = EventDispatcher(
      yieldEvery: 1,
      macrotask: tasks.add,
    );
    final CallbackEventRegistration r = registration('R');
    dispatcher
      ..enqueue(<Event>[value(r, 1)])
      ..enqueue(<Event>[value(r, 2)]);
    await pumpEventQueue();
    // A change that arrives while the yield is pending goes behind it; no second drain starts.
    dispatcher.enqueue(<Event>[value(r, 3)]);
    await pumpEventQueue();
    expect(log, <String>['R:1']);
    expect(tasks, hasLength(1));
    tasks.removeAt(0)();
    expect(log, <String>['R:1', 'R:2']);
    tasks.removeAt(0)();
    expect(log, <String>['R:1', 'R:2', 'R:3']);
    expect(tasks, isEmpty);
  });

  test('a close during a yield delivers nothing more', () async {
    final List<void Function()> tasks = <void Function()>[];
    final EventDispatcher dispatcher = EventDispatcher(
      yieldEvery: 1,
      macrotask: tasks.add,
    );
    final CallbackEventRegistration r = registration('R');
    dispatcher
      ..enqueue(<Event>[value(r, 1)])
      ..enqueue(<Event>[value(r, 2)]);
    await pumpEventQueue();
    expect(log, <String>['R:1']);
    // Repo.close fires the cancel and zombifies every registration synchronously.
    r.zombify();
    tasks.removeAt(0)();
    await pumpEventQueue();
    expect(log, <String>['R:1']);
    expect(tasks, isEmpty);
  });

  test(
    'the default yield is a macrotask: microtasks and earlier tasks run first',
    () async {
      final EventDispatcher dispatcher = EventDispatcher(yieldEvery: 1);
      final CallbackEventRegistration r = registration(
        'R',
        after: (DataEvent event) {
          if (event.snapshot.value == 1) {
            scheduleMacrotask(() => log.add('M'));
            scheduleMicrotask(() => log.add('m'));
          }
        },
      );
      dispatcher
        ..enqueue(<Event>[value(r, 1)])
        ..enqueue(<Event>[value(r, 2)]);
      await pumpEventQueue();
      expect(log, <String>['R:1', 'm', 'M', 'R:2']);
    },
  );

  test('a yield pending keeps later changes behind it', () async {
    final EventDispatcher dispatcher = EventDispatcher(yieldEvery: 1);
    late final CallbackEventRegistration r;
    r = registration(
      'R',
      after: (DataEvent event) {
        if (event.snapshot.value == 1) {
          // Enqueued while the drain runs; delivered after the yield, in order.
          dispatcher.enqueue(<Event>[value(r, 3)]);
        }
      },
    );
    dispatcher
      ..enqueue(<Event>[value(r, 1)])
      ..enqueue(<Event>[value(r, 2)]);
    await pumpEventQueue();
    expect(log, <String>['R:1', 'R:2', 'R:3']);
  });

  test(
    'skips data events of zombied registrations, also queued ones',
    () async {
      final EventDispatcher dispatcher = EventDispatcher();
      final CallbackEventRegistration b = registration('B');
      final CallbackEventRegistration a = registration(
        'A',
        after: (_) => b.zombify(),
      );
      dispatcher.enqueue(<Event>[value(a, 1), value(b, 1)]);
      dispatcher.enqueue(<Event>[value(b, 2)]);
      await pumpEventQueue();
      expect(log, <String>['A:1']);
    },
  );

  test('a cancel is delivered once, and nothing after it', () async {
    final EventDispatcher dispatcher = EventDispatcher();
    final CallbackEventRegistration r = registration('R');
    dispatcher
      ..enqueue(<Event>[value(r, 1)])
      ..enqueue(<Event>[cancel(r)])
      ..enqueue(<Event>[value(r, 2), cancel(r)]);
    await pumpEventQueue();
    expect(log, <String>['R:1', 'R:E(permission-denied)']);
    expect(r.isZombied, isTrue);
  });

  test('a throwing listener does not stop the drain', () async {
    final List<Object> errors = <Object>[];
    final EventDispatcher dispatcher = EventDispatcher();
    final CallbackEventRegistration a = registration(
      'A',
      after: (_) => throw StateError('x'),
    );
    final CallbackEventRegistration b = registration('B');
    runZonedGuarded(
      () => dispatcher.enqueue(<Event>[value(a, 1), value(b, 1)]),
      (Object e, StackTrace s) => errors.add(e),
    );
    await pumpEventQueue();
    expect(log, <String>['A:1', 'B:1']);
    expect(errors.single, isA<StateError>());
  });

  test('an empty change schedules nothing', () async {
    int scheduled = 0;
    final EventDispatcher dispatcher = EventDispatcher(
      schedule: (void Function() f) {
        scheduled++;
        scheduleMicrotask(f);
      },
    );
    dispatcher.enqueue(const <Event>[]);
    await pumpEventQueue();
    expect(scheduled, 0);
  });

  test('one drain is scheduled for many changes', () async {
    int scheduled = 0;
    final EventDispatcher dispatcher = EventDispatcher(
      schedule: (void Function() f) {
        scheduled++;
        scheduleMicrotask(f);
      },
    );
    final CallbackEventRegistration r = registration('R');
    dispatcher
      ..enqueue(<Event>[value(r, 1)])
      ..enqueue(<Event>[value(r, 2)]);
    await pumpEventQueue();
    expect(scheduled, 1);
    expect(log, <String>['R:1', 'R:2']);
  });
}
