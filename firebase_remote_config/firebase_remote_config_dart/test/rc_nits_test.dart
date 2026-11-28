/// The nit fixes of the closing review (F1-F4 and close), each test named after its decision (A38,
/// A40, A42) and the finding it pins.
///
/// The F4 race sits in a gap of one microtask, so that test is repeated for each number of
/// microtasks in a range and checks the decision's rule in every case.
@TestOn('vm')
library;

import 'dart:async';

import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';
import 'package:test/test.dart';

import 'support/abt_kit.dart';
import 'support/fakes.dart';
import 'support/rc_fetch_harness.dart';
import 'support/rc_realtime_fakes.dart';
import 'support/review198_rig.dart';

const Duration _second = Duration(seconds: 1);

Matcher _rcCode(String code) => isA<FirebaseRemoteConfigException>().having(
  (FirebaseRemoteConfigException error) => error.code,
  'code',
  code,
);

/// Runs [action] after [count] microtasks; at once when [count] is 0.
void _afterMicrotasks(int count, void Function() action) {
  if (count == 0) {
    action();
    return;
  }
  scheduleMicrotask(() => _afterMicrotasks(count - 1, action));
}

/// An instance with defaults and a fetched template that has one rollout of the key `a`.
FirebaseRemoteConfig _rolloutRc(Review198Rig rig) {
  final FirebaseRemoteConfig rc = rig.instance(
    defaults: <String, Object>{'a': 'default'},
  );
  rig.backend.enqueue(
    FakeRoute.fetch,
    FakeAnswer.fetch(
      entries: <String, String>{'a': 'remote'},
      templateVersion: '5',
      extra: <String, Object?>{
        'rolloutMetadata': <Map<String, Object?>>[
          <String, Object?>{
            'rolloutId': 'r1',
            'variantId': 'v1',
            'affectedParameterKeys': <String>['a'],
          },
        ],
      },
    ),
  );
  rig.async.elapse(_second);
  expect(rig.settle(rc.fetch()), FetchResult.updated);
  return rc;
}

/// Listens to the rollouts and checks that the first set is the empty one.
List<Set<RolloutAssignment>> _listen(
  Review198Rig rig,
  FirebaseRemoteConfig rc,
) {
  final List<Set<RolloutAssignment>> events = <Set<RolloutAssignment>>[];
  rc.onRolloutsStateChanged.listen(events.add);
  rig.pump();
  expect(events, hasLength(1));
  expect(events.single, isEmpty);
  return events;
}

/// The end state after a reset that removed everything, and the sets the listeners saw: with the
/// record in memory when the reset started, the record's set then the empty one; without it, no
/// set of the record and activate returned false (A40).
void _expectResetOutcome(
  Review198Rig rig,
  FirebaseRemoteConfig rc,
  List<Set<RolloutAssignment>> events,
  Pending<bool> activate, {
  required bool inMemory,
}) {
  expect(activate.done, isTrue);
  expect(activate.error, isNull);
  expect(rig.raw('active'), isNull);
  expect(rc.info.activeTemplateVersion, isNull);
  expect(rc.getString('a'), 'default');
  if (inMemory) {
    expect(events, hasLength(3));
    expect(events[1].single.rolloutId, 'r1');
    expect(events[2], isEmpty);
  } else {
    expect(events, hasLength(1), reason: 'only the first, empty set');
    expect(activate.value, isFalse);
  }
}

void main() {
  group('A38 F1 meta updates waiting for a reset, then close()', () {
    rigTest(
      'A38 F1 setCustomSignals waiting for a reset that is clearing its last record, then '
      'close(): it fails with remote-config-closed and writes no meta',
      (Review198Rig rig) {
        final FirebaseRemoteConfig rc = rig.instance();
        rig.fetch(rc, version: 1);
        final String metaKey = rig.key('meta');
        expect(rig.record('meta'), isNotNull);
        final StorePause held = rig.store.pauseBefore(
          StoreOp.update,
          rig.key('throttle'),
        );
        final Pending<void> reset = Pending<void>(rc.reset());
        rig.pump();
        expect(held.reached, isTrue);
        expect(rig.raw('meta'), isNull, reason: 'the reset removed it already');
        final Pending<void> signals = Pending<void>(
          rc.setCustomSignals(<String, Object?>{'tier': 'gold'}),
        );
        rig.pump();
        expect(signals.done, isFalse, reason: 'its meta update waits');
        final int metaUpdates = rig.store.count(StoreOp.update, metaKey);

        unawaited(rc.close());
        rig.pump();
        held.open();
        expect(rig.rcError(reset.future).code, 'remote-config-closed');
        rig.async.elapse(_second);

        expect(signals.done, isTrue);
        expect(signals.error, _rcCode('remote-config-closed'));
        expect(rig.store.count(StoreOp.update, metaKey), metaUpdates);
        expect(rig.raw('meta'), isNull);
      },
    );

    rigTest(
      'A38 F1 an ID change waiting for a reset that is clearing its last record, then close(): '
      'no uncaught error and no meta write',
      (Review198Rig rig) {
        final FirebaseRemoteConfig rc = rig.instance();
        rig.fetch(rc, version: 1);
        final String metaKey = rig.key('meta');
        final StorePause held = rig.store.pauseBefore(
          StoreOp.update,
          rig.key('throttle'),
        );
        final Pending<void> reset = Pending<void>(rc.reset());
        rig.pump();
        expect(held.reached, isTrue);
        final int metaUpdates = rig.store.count(StoreOp.update, metaKey);
        rig.installations.changeId(rcSecondFid);
        rig.pump();
        expect(
          rig.store.count(StoreOp.update, metaKey),
          metaUpdates,
          reason: 'the meta update waits for the reset',
        );

        unawaited(rc.close());
        rig.pump();
        held.open();
        expect(rig.rcError(reset.future).code, 'remote-config-closed');
        // fake_async rethrows an error that no one handles.
        rig.async.elapse(_second);

        expect(rig.store.count(StoreOp.update, metaKey), metaUpdates);
        expect(rig.raw('meta'), isNull);
      },
    );
  });

  group('A42 F2 the hand-off and a failed reset', () {
    rigTest(
      'A42 F2 the hand-off completes, a reset starts and fails before its clear step, and the '
      'record survives: one setUserProperties call and one event, not a second hand-off',
      (Review198Rig rig) {
        final FakeAnalytics analytics = FakeAnalytics();
        final FirebaseRemoteConfig rc = rig.instance(analytics: analytics);
        final ActivatedCount activated = ActivatedCount(rc.onActivated);
        rig.fetch(rc, version: 5, experiments: <String, String>{'1': 'A'});
        final Gate connector = Gate();
        analytics.onSet = (Map<String, String?> _) => connector.future;
        rig.store.failOnce(StoreOp.update, rig.key('fetched'));

        final Pending<bool> activate = Pending<bool>(rc.activate());
        rig.pump();
        expect(
          analytics.sets,
          hasLength(1),
          reason: 'the hand-off is at the connector',
        );
        expect(rig.rcError(rc.reset()).code, 'storage-error');
        expect(rig.raw('active'), isNotNull);

        analytics.onSet = null;
        connector.open();
        expect(rig.settle(activate.future), isTrue);
        rig.pump();

        expect(analytics.sets, <Map<String, String?>>[
          <String, String?>{'firebase1': 'A'},
        ]);
        expect(analytics.events, <String>[abtEvent]);
        expect(activated.count, 1);
        expect(rc.info.activeTemplateVersion, 5);
      },
    );

    rigTest(
      "A42 F2 the hand-off completes, a reset's clear step sends nulls and its store write "
      'fails, and the record survives (another activate wrote it again): the first activate '
      'hands off again, so the connector gets the template\'s properties after the nulls',
      (Review198Rig rig) {
        final FakeAnalytics analytics = FakeAnalytics();
        final FirebaseRemoteConfig rc = rig.instance(analytics: analytics);
        final ActivatedCount activated = ActivatedCount(rc.onActivated);
        rig.fetch(rc, version: 5, experiments: <String, String>{'1': 'A'});
        final Gate connector = Gate();
        analytics.onSet = (Map<String, String?> _) => connector.future;
        // The writes of the experiments record: the hand-off's first, then the reset's removal.
        rig.store.failOnce(StoreOp.write, rig.key('experiments'), skip: 1);
        final StorePause check = rig.store.pauseBefore(
          StoreOp.read,
          rig.key('active'),
        );

        final Pending<bool> first = Pending<bool>(rc.activate());
        rig.pump();
        expect(
          analytics.sets,
          hasLength(1),
          reason: 'the hand-off is at the connector',
        );
        final Pending<void> reset = Pending<void>(rc.reset());
        rig.pump();
        analytics.onSet = null;
        connector.open();
        rig.pump();
        expect(rig.rcError(reset.future).code, 'storage-error');
        expect(
          check.reached,
          isTrue,
          reason: 'the first activate checks the record',
        );
        expect(
          analytics.sets.map((Map<String, String?> set) => set['firebase1']),
          <String?>['A', null],
          reason: 'the clear step sent nulls',
        );
        expect(rig.raw('active'), isNull);

        // The reset failed after memory kept the template: this activate writes the record again.
        expect(rig.settle(rc.activate()), isTrue);
        check.open();
        expect(rig.settle(first.future), isTrue);
        rig.pump();

        expect(
          analytics.sets.map((Map<String, String?> set) => set['firebase1']),
          <String?>['A', null, 'A', 'A'],
          reason:
              'hand-off, nulls, the second activate, the first activate again',
        );
        expect(analytics.events, everyElement(abtEvent));
        expect(analytics.events, hasLength(4));
        expect(activated.count, 2);
        expect(rc.info.activeTemplateVersion, 5);
      },
    );
  });

  group('A40 F4 a reset around the resume of an activate', () {
    for (int k = 0; k < 24; k++) {
      rigTest(
        'A40 F4 an activate resumes after its write, and a reset is called $k microtasks later '
        'and succeeds: rollouts listeners get {record} then {} only when memory held the record '
        'once the reset had started; otherwise they get no set of it and activate returns false',
        (Review198Rig rig) {
          final FirebaseRemoteConfig rc = _rolloutRc(rig);
          final List<Set<RolloutAssignment>> events = _listen(rig, rc);
          final StorePause wrote = rig.store.pauseAfter(
            StoreOp.update,
            rig.key('active'),
          );
          // The first store call of a reset: it has certainly started when it gets here.
          final StorePause started = rig.store.pauseBefore(
            StoreOp.update,
            rig.key('fetched'),
          );

          final Pending<bool> activate = Pending<bool>(rc.activate());
          rig.pump();
          expect(wrote.reached, isTrue);
          Pending<void>? reset;
          wrote.open();
          _afterMicrotasks(k, () => reset = Pending<void>(rc.reset()));
          rig.pump();
          expect(started.reached, isTrue);
          final bool inMemory = rc.info.activeTemplateVersion != null;
          started.open();
          rig.settle(reset!.future);
          rig.pump();

          _expectResetOutcome(rig, rc, events, activate, inMemory: inMemory);
          expect(reset!.error, isNull);
        },
      );
    }

    for (int k = 0; k < 24; k++) {
      rigTest(
        'A40 F4 an activate whose record survived a failed reset, and a second reset called $k '
        'microtasks after the first failed that succeeds: no set of the record is followed by '
        'the empty set unless memory held it when the second reset started',
        (Review198Rig rig) {
          final FirebaseRemoteConfig rc = _rolloutRc(rig);
          final List<Set<RolloutAssignment>> events = _listen(rig, rc);
          final String fetchedKey = rig.key('fetched');
          final StorePause wrote = rig.store.pauseAfter(
            StoreOp.update,
            rig.key('active'),
          );
          // The second reset's removal of the fetched record; the first reset's call is skipped.
          final StorePause started = rig.store.pauseBefore(
            StoreOp.update,
            fetchedKey,
            skip: 1,
          );
          rig.store.failOnce(StoreOp.update, fetchedKey);

          final Pending<bool> activate = Pending<bool>(rc.activate());
          rig.pump();
          expect(wrote.reached, isTrue);
          expect(rig.rcError(rc.reset()).code, 'storage-error');
          Pending<void>? second;
          wrote.open();
          _afterMicrotasks(k, () => second = Pending<void>(rc.reset()));
          rig.pump();
          expect(started.reached, isTrue);
          final bool inMemory = rc.info.activeTemplateVersion != null;
          started.open();
          rig.settle(second!.future);
          rig.pump();

          _expectResetOutcome(rig, rc, events, activate, inMemory: inMemory);
          expect(second!.error, isNull);
        },
      );
    }
  });

  group('A38 close during the hand-off', () {
    rigTest(
      'A38 close close() while the hand-off waits at the connector: activate fails with '
      'remote-config-closed and onActivated emits nothing',
      (Review198Rig rig) {
        final FakeAnalytics analytics = FakeAnalytics();
        final FirebaseRemoteConfig rc = rig.instance(analytics: analytics);
        final ActivatedCount activated = ActivatedCount(rc.onActivated);
        rig.fetch(rc, version: 5, experiments: <String, String>{'1': 'A'});
        analytics.onSet = (Map<String, String?> _) => Completer<void>().future;

        final Pending<bool> activate = Pending<bool>(rc.activate());
        rig.pump();
        expect(analytics.sets, hasLength(1));
        expect(activate.done, isFalse);

        unawaited(rc.close());
        rig.pump();

        expect(activate.done, isTrue);
        expect(activate.error, _rcCode('remote-config-closed'));
        expect(activated.count, 0);
      },
    );

    rigTest(
      'A38 close close() while the hand-off waits to read the stored set: activate fails with '
      'remote-config-closed, onActivated emits nothing and the connector is not called',
      (Review198Rig rig) {
        final FakeAnalytics analytics = FakeAnalytics();
        final FirebaseRemoteConfig rc = rig.instance(analytics: analytics);
        final ActivatedCount activated = ActivatedCount(rc.onActivated);
        rig.fetch(rc, version: 5, experiments: <String, String>{'1': 'A'});
        final StorePause held = rig.store.pauseBefore(
          StoreOp.read,
          rig.key('experiments'),
        );

        final Pending<bool> activate = Pending<bool>(rc.activate());
        rig.pump();
        expect(held.reached, isTrue);

        unawaited(rc.close());
        rig.pump();
        held.open();
        rig.pump();

        expect(activate.done, isTrue);
        expect(activate.error, _rcCode('remote-config-closed'));
        expect(activated.count, 0);
        expect(analytics.calls, isEmpty);
      },
    );
  });
}
