@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';

import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';
import 'package:test/test.dart';

import 'support/abt_kit.dart';
import 'support/fakes.dart';
import 'support/rc_fetch_harness.dart';

const Duration _second = Duration(seconds: 1);

/// Holds the first read of the experiments record until [gate] opens; [reached] turns true when it
/// is held.
final class _ReadGate {
  _ReadGate(AbtKit kit) {
    final String key = kit.experimentsKey;
    kit.store.before = (StoreOp op, String storeKey) {
      if (_armed && op == StoreOp.read && storeKey == key) {
        _armed = false;
        reached = true;
        return gate.future;
      }
      return Future<void>.value();
    };
  }

  final Gate gate = Gate();
  bool reached = false;
  bool _armed = true;
}

void main() {
  group('A42 hand-off on activate', () {
    abtTest(
      'A42 activate with {1:A, 2:B} makes one setUserProperties call, then the event, '
      'and stores {1, 2}',
      (AbtKit k) {
        final FakeAnalytics analytics = FakeAnalytics();
        final FirebaseRemoteConfig rc = k.instance(analytics: analytics);

        expect(k.cycle(rc, <String, String>{'1': 'A', '2': 'B'}), isTrue);

        expect(analytics.calls, hasLength(2));
        expect(analytics.calls[0].properties, <String, String?>{
          'firebase1': 'A',
          'firebase2': 'B',
        });
        expect(analytics.calls[1].event, abtEvent);
        expect(k.storedIds(), <String>{'1', '2'});
        final Map<String, Object?> record =
            jsonDecode(k.h.settle(k.env.store.read(k.experimentsKey))!)
                as Map<String, Object?>;
        expect(record['v'], 1);
        expect(record['ids'], unorderedEquals(<String>['1', '2']));
      },
    );

    abtTest('A42 the last description of an experiment id wins', (AbtKit k) {
      final FakeAnalytics analytics = FakeAnalytics();
      final FirebaseRemoteConfig rc = k.instance(analytics: analytics);
      k.fetchDescriptions(rc, <Map<String, Object?>>[
        <String, Object?>{'experimentId': '1', 'variantId': 'A'},
        <String, Object?>{'experimentId': '1', 'variantId': 'B'},
      ]);

      expect(k.h.settle(rc.activate()), isTrue);

      expect(analytics.sets, <Map<String, String?>>[
        <String, String?>{'firebase1': 'B'},
      ]);
    });

    abtTest('A42 activate returns only after both connector calls completed', (
      AbtKit k,
    ) {
      final FakeAnalytics analytics = FakeAnalytics()
        ..onSet = (Map<String, String?> _) =>
            Future<void>.delayed(const Duration(seconds: 5));
      final FirebaseRemoteConfig rc = k.instance(analytics: analytics);
      k.fetch(rc, <String, String>{'1': 'A'});

      final Tracked<bool> activated = k.track(rc.activate());
      k.async.elapse(const Duration(seconds: 4));
      expect(activated.done, isFalse);
      expect(analytics.events, isEmpty);

      k.async.elapse(const Duration(seconds: 2));
      expect(activated.done, isTrue);
      expect(activated.value, isTrue);
      expect(analytics.events, <String>[abtEvent]);
    });

    abtTest(
      'A42 the next activate with only {2:C} sends {firebase2: C, firebase1: null} and stores {2}',
      (AbtKit k) {
        final FakeAnalytics analytics = FakeAnalytics();
        final FirebaseRemoteConfig rc = k.instance(analytics: analytics);
        expect(k.cycle(rc, <String, String>{'1': 'A', '2': 'B'}), isTrue);
        analytics.calls.clear();

        expect(k.cycle(rc, <String, String>{'2': 'C'}), isTrue);

        expect(analytics.sets, <Map<String, String?>>[
          <String, String?>{'firebase2': 'C', 'firebase1': null},
        ]);
        expect(analytics.events, <String>[abtEvent]);
        expect(k.storedIds(), <String>{'2'});
      },
    );

    abtTest(
      'A42 removals survive a restart: a new instance on the same store sends firebase1: null',
      (AbtKit k) {
        final FakeAnalytics first = FakeAnalytics();
        final FirebaseRemoteConfig before = k.instance(analytics: first);
        expect(k.cycle(before, <String, String>{'1': 'A', '2': 'B'}), isTrue);
        k.h.settle(before.close());

        final FakeAnalytics second = FakeAnalytics();
        final FirebaseRemoteConfig after = k.instance(analytics: second);
        k.h.settle(after.ensureInitialized());
        expect(k.cycle(after, <String, String>{'2': 'C'}), isTrue);

        expect(second.sets, <Map<String, String?>>[
          <String, String?>{'firebase2': 'C', 'firebase1': null},
        ]);
        expect(second.events, <String>[abtEvent]);
        expect(k.storedIds(), <String>{'2'});
      },
    );

    abtTest(
      'A42 nothing is sent when the template has no experiments and none were stored',
      (AbtKit k) {
        final FakeAnalytics analytics = FakeAnalytics();
        final FirebaseRemoteConfig rc = k.instance(analytics: analytics);

        expect(k.cycle(rc, const <String, String>{}), isTrue);

        expect(analytics.calls, isEmpty);
        expect(k.storedIds(), isNull);
        expect(k.analyticsWarnings, isEmpty);
      },
    );

    abtTest('A42 nothing is sent when activate returns false', (AbtKit k) {
      final FakeAnalytics analytics = FakeAnalytics();
      final FirebaseRemoteConfig rc = k.instance(analytics: analytics);
      expect(k.cycle(rc, <String, String>{'1': 'A'}), isTrue);
      analytics.calls.clear();

      expect(k.h.settle(rc.activate()), isFalse);

      expect(analytics.calls, isEmpty);
      expect(k.storedIds(), <String>{'1'});
    });

    abtTest(
      'A42 a template without experiments after {1} clears firebase1 and removes the record',
      (AbtKit k) {
        final FakeAnalytics analytics = FakeAnalytics();
        final FirebaseRemoteConfig rc = k.instance(analytics: analytics);
        expect(k.cycle(rc, <String, String>{'1': 'A'}), isTrue);
        analytics.calls.clear();

        expect(k.cycle(rc, const <String, String>{}), isTrue);

        expect(analytics.sets, <Map<String, String?>>[
          <String, String?>{'firebase1': null},
        ]);
        expect(analytics.events, <String>[abtEvent]);
        expect(k.storedIds(), isNull);
      },
    );
  });

  group('A42 without a connector', () {
    abtTest(
      'A42 no connector: one warning in total, the set is still stored, activate returns true',
      (AbtKit k) {
        final FirebaseRemoteConfig rc = k.instance();

        expect(k.cycle(rc, <String, String>{'1': 'A'}), isTrue);
        expect(k.storedIds(), <String>{'1'});
        expect(k.cycle(rc, <String, String>{'2': 'B'}), isTrue);
        expect(k.storedIds(), <String>{'2'});
        expect(k.cycle(rc, <String, String>{'2': 'C', '3': 'D'}), isTrue);
        expect(k.storedIds(), <String>{'2', '3'});

        expect(k.analyticsWarnings, hasLength(1));
      },
    );
  });

  group('A42 connector failures', () {
    abtTest(
      'A42 a connector that always throws: three activates give three calls and one log line',
      (AbtKit k) {
        final FakeAnalytics analytics = FakeAnalytics()
          ..failWith(() => StateError('secret-variant-value'));
        final FirebaseRemoteConfig rc = k.instance(analytics: analytics);

        for (int i = 0; i < 3; i++) {
          expect(k.cycle(rc, <String, String>{'1': 'A$i'}), isTrue);
        }

        expect(analytics.sets, hasLength(3));
        expect(analytics.events, isEmpty);
        expect(k.analyticsWarnings, hasLength(1));
        for (final String warning in k.warnings) {
          expect(warning, isNot(contains('secret-variant-value')));
        }
      },
    );

    abtTest('A42 two different error types are logged once each', (AbtKit k) {
      int calls = 0;
      final FakeAnalytics analytics = FakeAnalytics()
        ..onSet = (Map<String, String?> _) async {
          calls++;
          if (calls <= 2) {
            throw StateError('first kind');
          }
          throw const FormatException('second kind');
        };
      final FirebaseRemoteConfig rc = k.instance(analytics: analytics);

      for (int i = 0; i < 4; i++) {
        expect(k.cycle(rc, <String, String>{'1': 'A$i'}), isTrue);
      }

      expect(analytics.sets, hasLength(4));
      expect(k.analyticsWarnings, hasLength(2));
    });

    abtTest('A42 a failing logEvent counts as a failed hand-off', (AbtKit k) {
      final FakeAnalytics analytics = FakeAnalytics()
        ..onEvent = (String _) async => throw StateError('event refused');
      final FirebaseRemoteConfig rc = k.instance(analytics: analytics);
      k.storeIds(<String>['1']);

      expect(k.cycle(rc, <String, String>{'2': 'B'}), isTrue);

      expect(analytics.calls, hasLength(2));
      expect(k.storedIds(), <String>{'2', '1'});
      expect(k.analyticsWarnings, hasLength(1));
    });

    abtTest(
      'A42 stored {1}, a failing activate with {2} stores {2, 1}; the next working one sends '
      'firebase3 and clears 2 and 1, then stores {3}',
      (AbtKit k) {
        final FakeAnalytics analytics = FakeAnalytics();
        final FirebaseRemoteConfig rc = k.instance(analytics: analytics);
        expect(k.cycle(rc, <String, String>{'1': 'A'}), isTrue);
        expect(k.storedIds(), <String>{'1'});

        analytics.failWith(() => StateError('refused'));
        expect(k.cycle(rc, <String, String>{'2': 'B'}), isTrue);
        expect(k.storedIds(), <String>{'2', '1'});

        analytics
          ..onSet = null
          ..onEvent = null
          ..calls.clear();
        expect(k.cycle(rc, <String, String>{'3': 'v'}), isTrue);

        expect(analytics.sets, <Map<String, String?>>[
          <String, String?>{
            'firebase3': 'v',
            'firebase2': null,
            'firebase1': null,
          },
        ]);
        expect(analytics.events, <String>[abtEvent]);
        expect(k.storedIds(), <String>{'3'});
      },
    );
  });

  group('A42 limits and bad records', () {
    abtTest(
      'A42 the stored union is capped at 1000 ids and keeps every current id first',
      (AbtKit k) {
        final List<String> previous = <String>[
          for (int i = 0; i < 1000; i++) 'p$i',
        ];
        k.storeIds(previous);
        final FakeAnalytics analytics = FakeAnalytics()
          ..failWith(() => StateError('refused'));
        final FirebaseRemoteConfig rc = k.instance(analytics: analytics);

        expect(k.cycle(rc, <String, String>{'n1': 'A', 'n2': 'B'}), isTrue);

        final Set<String> stored = k.storedIds()!;
        expect(stored, hasLength(1000));
        expect(stored, containsAll(<String>['n1', 'n2']));
        expect(
          stored.difference(<String>{'n1', 'n2'}).every(previous.contains),
          isTrue,
        );
      },
    );

    abtTest(
      'A42 experiment ids that are empty or over 256 characters are not handed over or stored',
      (AbtKit k) {
        final String longest = 'x' * 256;
        final String tooLong = 'y' * 257;
        final FakeAnalytics analytics = FakeAnalytics();
        final FirebaseRemoteConfig rc = k.instance(analytics: analytics);

        expect(
          k.cycle(rc, <String, String>{
            '': 'a',
            tooLong: 'b',
            longest: 'c',
            '7': 'd',
          }),
          isTrue,
        );

        expect(analytics.sets, <Map<String, String?>>[
          <String, String?>{'firebase$longest': 'c', 'firebase7': 'd'},
        ]);
        expect(k.storedIds(), <String>{longest, '7'});
      },
    );

    abtTest(
      'A42 a template with 1001 experiments hands over and stores the first 1000',
      (AbtKit k) {
        final FakeAnalytics analytics = FakeAnalytics();
        final FirebaseRemoteConfig rc = k.instance(analytics: analytics);

        expect(
          k.cycle(rc, <String, String>{
            for (int i = 0; i <= 1000; i++) 'e$i': 'v',
          }),
          isTrue,
        );

        final Map<String, String?> sent = analytics.sets.single;
        expect(sent, hasLength(1000));
        expect(sent.containsKey('firebasee0'), isTrue);
        expect(sent.containsKey('firebasee999'), isTrue);
        expect(sent.containsKey('firebasee1000'), isFalse);
        final Set<String> stored = k.storedIds()!;
        expect(stored, hasLength(1000));
        expect(stored.contains('e1000'), isFalse);
      },
    );

    abtTest('A42 a corrupt stored record counts as empty', (AbtKit k) {
      final FakeAnalytics analytics = FakeAnalytics();
      final FirebaseRemoteConfig rc = k.instance(analytics: analytics);
      final List<String> corrupt = <String>[
        '{not json',
        '[]',
        jsonEncode(<String, Object?>{'v': 1}),
        jsonEncode(<String, Object?>{
          'v': 1,
          'ids': <String>[for (int i = 0; i < 1001; i++) 'c$i'],
        }),
        jsonEncode(<String, Object?>{
          'v': 1,
          'ids': <String>['9', ''],
        }),
        jsonEncode(<String, Object?>{
          'v': 1,
          'ids': <String>['9', 'z' * 257],
        }),
        jsonEncode(<String, Object?>{
          'v': 1,
          'ids': <Object?>['9', 5],
        }),
      ];

      for (int i = 0; i < corrupt.length; i++) {
        k.writeRaw(corrupt[i]);
        analytics.calls.clear();

        expect(k.cycle(rc, <String, String>{'1': 'A$i'}), isTrue);

        expect(analytics.sets, <Map<String, String?>>[
          <String, String?>{'firebase1': 'A$i'},
        ], reason: 'stored record: ${corrupt[i]}');
        expect(k.storedIds(), <String>{'1'});
      }
    });
  });

  group('A42 deadline', () {
    abtTest(
      'A42 setUserProperties never completes: activate returns true once fetchTimeout passed, '
      'the union is stored, one warning; a late completion changes nothing',
      (AbtKit k) {
        final Completer<void> hang = Completer<void>();
        final FakeAnalytics analytics = FakeAnalytics()
          ..onSet = (Map<String, String?> _) => hang.future;
        final FirebaseRemoteConfig rc = k.instance(analytics: analytics);
        k.storeIds(<String>['9']);
        k.fetch(rc, <String, String>{'1': 'A'});

        final Tracked<bool> activated = k.track(rc.activate());
        k.async.elapse(const Duration(seconds: 59));
        expect(activated.done, isFalse);

        k.async.elapse(const Duration(seconds: 2));
        expect(activated.done, isTrue);
        expect(activated.value, isTrue);
        expect(analytics.events, isEmpty);
        expect(k.storedIds(), <String>{'1', '9'});
        expect(k.analyticsWarnings, hasLength(1));

        hang.complete();
        k.async
          ..flushMicrotasks()
          ..elapse(_second);
        expect(analytics.calls, hasLength(1));
        expect(k.storedIds(), <String>{'1', '9'});
        expect(k.analyticsWarnings, hasLength(1));
      },
    );

    abtTest(
      'A42 the two calls share one deadline: 40 s setUserProperties and a hanging logEvent '
      'fail at 60 s, not 100 s',
      (AbtKit k) {
        final FakeAnalytics analytics = FakeAnalytics()
          ..onSet = ((Map<String, String?> _) =>
              Future<void>.delayed(const Duration(seconds: 40)))
          ..onEvent = ((String _) => Completer<void>().future);
        final FirebaseRemoteConfig rc = k.instance(analytics: analytics);
        k.fetch(rc, <String, String>{'1': 'A'});

        final Tracked<bool> activated = k.track(rc.activate());
        k.async.elapse(const Duration(seconds: 39));
        expect(analytics.events, isEmpty);

        k.async.elapse(const Duration(seconds: 2));
        expect(analytics.events, <String>[abtEvent]);
        expect(activated.done, isFalse);

        k.async.elapse(const Duration(seconds: 18));
        expect(activated.done, isFalse);

        k.async.elapse(const Duration(seconds: 2));
        expect(activated.done, isTrue);
        expect(activated.value, isTrue);
        expect(k.analyticsWarnings, hasLength(1));
      },
    );

    abtTest('A42 the deadline follows a custom fetchTimeout', (AbtKit k) {
      final FakeAnalytics analytics = FakeAnalytics()
        ..onSet = (Map<String, String?> _) => Completer<void>().future;
      final FirebaseRemoteConfig rc = k.instance(
        analytics: analytics,
        fetchTimeout: const Duration(seconds: 10),
      );
      k.fetch(rc, <String, String>{'1': 'A'});

      final Tracked<bool> activated = k.track(rc.activate());
      k.async.elapse(const Duration(seconds: 9));
      expect(activated.done, isFalse);

      k.async.elapse(const Duration(seconds: 2));
      expect(activated.done, isTrue);
      expect(activated.value, isTrue);
    });
  });

  group('A42 reset', () {
    abtTest(
      'A42 reset sends null for every stored id, then the event, then removes the record',
      (AbtKit k) {
        final FakeAnalytics analytics = FakeAnalytics();
        final FirebaseRemoteConfig rc = k.instance(analytics: analytics);
        expect(k.cycle(rc, <String, String>{'1': 'A', '2': 'B'}), isTrue);
        analytics.calls.clear();

        k.h.settle(rc.reset());

        expect(analytics.calls, hasLength(2));
        expect(analytics.calls[0].properties, <String, String?>{
          'firebase1': null,
          'firebase2': null,
        });
        expect(analytics.calls[1].event, abtEvent);
        expect(k.storedIds(), isNull);
      },
    );

    abtTest('A42 reset with nothing stored sends nothing', (AbtKit k) {
      final FakeAnalytics analytics = FakeAnalytics();
      final FirebaseRemoteConfig rc = k.instance(analytics: analytics);
      k.h.settle(rc.ensureInitialized());

      k.h.settle(rc.reset());

      expect(analytics.calls, isEmpty);
      expect(k.storedIds(), isNull);
    });

    abtTest(
      'A42 reset with a hanging connector completes after fetchTimeout and keeps the record; '
      'the next activate clears what is gone',
      (AbtKit k) {
        final FakeAnalytics analytics = FakeAnalytics();
        final FirebaseRemoteConfig rc = k.instance(analytics: analytics);
        expect(k.cycle(rc, <String, String>{'1': 'A', '2': 'B'}), isTrue);
        analytics.onSet = (Map<String, String?> _) => Completer<void>().future;

        final Tracked<void> reset = k.track(rc.reset());
        k.async.elapse(const Duration(seconds: 59));
        expect(reset.done, isFalse);

        k.async.elapse(const Duration(seconds: 2));
        expect(reset.done, isTrue);
        expect(reset.error, isNull);
        expect(k.storedIds(), <String>{'1', '2'});

        analytics
          ..onSet = null
          ..calls.clear();
        expect(k.cycle(rc, <String, String>{'3': 'C'}), isTrue);
        expect(analytics.sets, <Map<String, String?>>[
          <String, String?>{
            'firebase3': 'C',
            'firebase1': null,
            'firebase2': null,
          },
        ]);
        expect(k.storedIds(), <String>{'3'});
      },
    );

    abtTest(
      'A42 reset with a failing connector completes and keeps the record',
      (AbtKit k) {
        final FakeAnalytics analytics = FakeAnalytics();
        final FirebaseRemoteConfig rc = k.instance(analytics: analytics);
        expect(k.cycle(rc, <String, String>{'1': 'A', '2': 'B'}), isTrue);
        analytics.failWith(() => StateError('refused'));

        k.h.settle(rc.reset());

        expect(k.storedIds(), <String>{'1', '2'});
        expect(k.analyticsWarnings, hasLength(1));
      },
    );
  });

  group('A42 reset and close during a hand-off', () {
    abtTest(
      'A42 a reset that starts before the hand-off reaches the connector: that hand-off sends '
      'and stores nothing',
      (AbtKit k) {
        final FakeAnalytics analytics = FakeAnalytics();
        final FirebaseRemoteConfig rc = k.instance(analytics: analytics);
        k.storeIds(<String>['9']);
        k.fetch(rc, <String, String>{'1': 'A'});
        final _ReadGate held = _ReadGate(k);

        final Future<bool> activating = rc.activate();
        k.async
          ..flushMicrotasks()
          ..elapse(Duration.zero);
        expect(held.reached, isTrue);
        expect(analytics.calls, isEmpty);

        final Future<void> resetting = rc.reset();
        k.async
          ..flushMicrotasks()
          ..elapse(Duration.zero);
        held.gate.open();
        k.h.settle(resetting);
        final Tracked<bool> activated = k.track(activating);
        k.async.flushMicrotasks();
        expect(activated.done, isTrue);

        expect(analytics.sets, <Map<String, String?>>[
          <String, String?>{'firebase9': null},
        ]);
        expect(analytics.events, <String>[abtEvent]);
        expect(k.storedIds(), isNull);
      },
    );

    abtTest(
      'A42 a reset during a hand-off at the connector waits for it, then clears its ids',
      (AbtKit k) {
        final Gate connector = Gate();
        final FakeAnalytics analytics = FakeAnalytics();
        final FirebaseRemoteConfig rc = k.instance(analytics: analytics);
        k.fetch(rc, <String, String>{'1': 'A'});
        analytics.onSet = (Map<String, String?> _) => connector.future;

        final Future<bool> activating = rc.activate();
        k.async
          ..flushMicrotasks()
          ..elapse(Duration.zero);
        expect(analytics.sets, hasLength(1));

        final Future<void> resetting = rc.reset();
        k.async
          ..flushMicrotasks()
          ..elapse(Duration.zero);
        expect(analytics.calls, hasLength(1));

        analytics.onSet = null;
        connector.open();
        k.h.settle(resetting);
        k.h.settle(activating);

        expect(analytics.calls.map((AbtCall c) => c.toString()), <String>[
          'setUserProperties({firebase1: A})',
          'logEvent($abtEvent)',
          'setUserProperties({firebase1: null})',
          'logEvent($abtEvent)',
        ]);
        expect(k.storedIds(), isNull);
      },
    );

    abtTest(
      'A42 close() before the hand-off reaches the connector: nothing is sent or stored',
      (AbtKit k) {
        final FakeAnalytics analytics = FakeAnalytics();
        final FirebaseRemoteConfig rc = k.instance(analytics: analytics);
        k.storeIds(<String>['9']);
        k.fetch(rc, <String, String>{'1': 'A'});
        final _ReadGate held = _ReadGate(k);

        final Tracked<bool> activated = k.track(rc.activate());
        k.async
          ..flushMicrotasks()
          ..elapse(Duration.zero);
        expect(held.reached, isTrue);

        final Future<void> closing = rc.close();
        held.gate.open();
        k.h.settle(closing);
        k.async
          ..flushMicrotasks()
          ..elapse(_second);

        expect(activated.done, isTrue);
        expect(analytics.calls, isEmpty);
        expect(k.storedIds(), <String>{'9'});
      },
    );

    abtTest(
      'A42 close() while the connector hangs abandons it: activate completes at once',
      (AbtKit k) {
        final FakeAnalytics analytics = FakeAnalytics()
          ..onSet = (Map<String, String?> _) => Completer<void>().future;
        final FirebaseRemoteConfig rc = k.instance(analytics: analytics);
        k.fetch(rc, <String, String>{'1': 'A'});

        final Tracked<bool> activated = k.track(rc.activate());
        k.async
          ..flushMicrotasks()
          ..elapse(Duration.zero);
        expect(analytics.sets, hasLength(1));
        expect(activated.done, isFalse);

        k.h.settle(rc.close());
        k.async.flushMicrotasks();

        expect(activated.done, isTrue);
        expect(k.analyticsWarnings, isEmpty);
      },
    );
  });
}
