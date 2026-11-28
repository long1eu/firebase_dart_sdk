/// The follow-up fixes of the re-check of pull request #198 (findings N1-N6 and the realtime writes
/// after `close()`), each test named after its decision (A38, A39, A42) and finding.
///
/// Some races sit in a gap of one microtask. Those tests call the racing method after each number of
/// microtasks in a range, one test per number, and check the decision's rule in every case, so the
/// gap is hit without depending on the exact microtask count of the code.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';
import 'package:test/test.dart';

import 'support/abt_kit.dart';
import 'support/fakes.dart';
import 'support/missing_backoff_harness.dart';
import 'support/rc_fetch_harness.dart';
import 'support/rc_realtime_fakes.dart';
import 'support/review198_rig.dart';

const Duration _zero = Duration.zero;
const Duration _second = Duration(seconds: 1);

Duration _s(num seconds) => secondsAfterEpoch(seconds);

/// True for a missing meta record or one without the state of a successful fetch.
Matcher get _noFetchState => predicate<Map<String, Object?>?>(
  (Map<String, Object?>? meta) =>
      meta == null ||
      (!meta.containsKey('lastSuccessfulFetchTime') &&
          !meta.containsKey('fid')),
  'no lastSuccessfulFetchTime and no fid',
);

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

/// The number of microtasks that run, from now, before [reached] is true; it flushes the queue.
int _microtasksUntil(FakeAsync async, bool Function() reached) {
  const int limit = 500;
  int ticks = 0;
  int? at;
  void tick() {
    if (reached()) {
      at = ticks;
      return;
    }
    ticks++;
    if (ticks <= limit) {
      scheduleMicrotask(tick);
    }
  }

  scheduleMicrotask(tick);
  async.flushMicrotasks();
  final int? result = at;
  if (result == null) {
    fail('Not reached within $limit microtasks.');
  }
  return result;
}

/// Turns the network off, then on again: a regain (A11, A20).
void _regainNetwork(BackoffHarness h) {
  h.app.onNetworkConnected.add(false);
  h.async.flushMicrotasks();
  h.app.onNetworkConnected.add(true);
  h.async.flushMicrotasks();
}

/// A `before` hook of a [ScriptedStore] that counts the writes of the `realtime` record in [writes]
/// and runs [onWrite] with the number of each (from 1).
FutureOr<void> Function(StoreOp op, String key) _realtimeWrites(
  List<int> writes,
  FutureOr<void> Function(int number) onWrite,
) => (StoreOp op, String key) {
  if (op == StoreOp.write && key.endsWith('/realtime')) {
    writes[0]++;
    return onWrite(writes[0]);
  }
  return null;
};

void main() {
  group('A38 reset and activate', () {
    for (int k = 0; k < 40; k++) {
      rigTest(
        'A38 N1 an activate whose record survived a failed reset, and a second reset called $k '
        'microtasks after the activate resumes: activate returns true only when that reset had '
        "not started clearing, and the second reset's removal holds",
        (Review198Rig rig) {
          final FirebaseRemoteConfig rc = rig.instance(
            defaults: <String, Object>{'a': 'default'},
          );
          final ActivatedCount activated = ActivatedCount(rc.onActivated);
          rig.fetch(rc, version: 5);
          final String fetchedKey = rig.key('fetched');
          final StorePause wrote = rig.store.pauseAfter(
            StoreOp.update,
            rig.key('active'),
          );
          rig.store.failOnce(StoreOp.update, fetchedKey);

          final Future<bool> call = rc.activate();
          final Pending<bool> activate = Pending<bool>(call);
          rig.pump();
          expect(wrote.reached, isTrue);
          expect(rig.rcError(rc.reset()).code, 'storage-error');
          final int fetchedUpdates = rig.store.count(
            StoreOp.update,
            fetchedKey,
          );
          int? fetchedUpdatesAtReturn;
          unawaited(
            call.then<void>(
              (bool _) => fetchedUpdatesAtReturn = rig.store.count(
                StoreOp.update,
                fetchedKey,
              ),
              onError: (Object _) {},
            ),
          );

          Pending<void>? second;
          wrote.open();
          _afterMicrotasks(k, () => second = Pending<void>(rc.reset()));
          rig.pump();
          rig.settle(second!.future);
          rig.pump();

          expect(activate.done, isTrue);
          expect(activate.error, isNull);
          expect(second!.error, isNull);
          expect(rig.raw('active'), isNull);
          expect(rig.raw('fetched'), isNull);
          expect(rc.info.activeTemplateVersion, isNull);
          expect(rc.getString('a'), 'default');
          if (activate.value!) {
            expect(
              fetchedUpdatesAtReturn,
              fetchedUpdates,
              reason:
                  'activate returned true after the second reset had begun removing the records',
            );
            expect(activated.count, 1);
          } else {
            expect(activated.count, 0);
          }
        },
      );
    }

    rigTest(
      'A38 N6 an activate whose record survived a failed reset, and the read that checks it '
      'fails: activate returns false, memory takes nothing, onActivated does not emit; the '
      'stored record is active after a restart',
      (Review198Rig rig) {
        final FirebaseRemoteConfig rc = rig.instance(
          defaults: <String, Object>{'a': 'default'},
        );
        final ActivatedCount activated = ActivatedCount(rc.onActivated);
        rig.fetch(rc, version: 5);
        final StorePause wrote = rig.store.pauseAfter(
          StoreOp.update,
          rig.key('active'),
        );
        rig.store
          ..failOnce(StoreOp.update, rig.key('fetched'))
          ..failOnce(StoreOp.read, rig.key('active'));

        final Pending<bool> activate = Pending<bool>(rc.activate());
        rig.pump();
        expect(wrote.reached, isTrue);
        expect(rig.rcError(rc.reset()).code, 'storage-error');
        wrote.open();
        expect(rig.settle(activate.future), isFalse);
        rig.pump();

        expect(activated.count, 0);
        expect(rc.info.activeTemplateVersion, isNull);
        expect(rc.getString('a'), 'default');
        expect(rig.raw('active'), isNotNull);

        unawaited(rc.close());
        rig.pump();
        final FirebaseRemoteConfig restarted = rig.instance();
        rig.settle(restarted.ensureInitialized());
        expect(restarted.info.activeTemplateVersion, 5);
        expect(restarted.getString('a'), 'remote');
      },
    );
  });

  group('A38 meta updates and a reset', () {
    rigTest(
      'A38 N3 setCustomSignals waiting for a reset that clears the records, then close(): no '
      'meta write after close, and no store call at all',
      (Review198Rig rig) {
        final FirebaseRemoteConfig rc = rig.instance();
        rig.fetch(rc, version: 1);
        expect(rig.settle(rc.activate()), isTrue);
        final String metaKey = rig.key('meta');
        final Map<String, Object?>? metaBefore = rig.record('meta');
        expect(metaBefore, isNot(_noFetchState));
        final StorePause held = rig.store.pauseBefore(
          StoreOp.update,
          rig.key('active'),
        );
        final Pending<void> reset = Pending<void>(rc.reset());
        rig.pump();
        expect(held.reached, isTrue);
        final Pending<void> signals = Pending<void>(
          rc.setCustomSignals(<String, Object?>{'tier': 'gold'}),
        );
        rig.pump();
        expect(signals.done, isFalse, reason: 'its meta update waits');
        final int metaUpdates = rig.store.count(StoreOp.update, metaKey);

        unawaited(rc.close());
        rig.pump();
        final int callsAtClose = rig.store.calls.length;
        held.open();
        expect(rig.rcError(reset.future).code, 'remote-config-closed');
        rig.async.elapse(_second);

        expect(signals.done, isTrue);
        expect(rig.store.count(StoreOp.update, metaKey), metaUpdates);
        expect(rig.store.calls.length, callsAtClose);
        expect(rig.record('meta'), metaBefore);
      },
    );

    rigTest(
      'A38 N3 an ID change to another FID waiting for a reset that clears the records, then '
      'close(): no meta write after close, and no store call at all',
      (Review198Rig rig) {
        final FirebaseRemoteConfig rc = rig.instance();
        rig.fetch(rc, version: 1);
        expect(rig.settle(rc.activate()), isTrue);
        final String metaKey = rig.key('meta');
        final Map<String, Object?>? metaBefore = rig.record('meta');
        expect(metaBefore?['fid'], rcFirstFid);
        final StorePause held = rig.store.pauseBefore(
          StoreOp.update,
          rig.key('active'),
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
        final int callsAtClose = rig.store.calls.length;
        held.open();
        expect(rig.rcError(reset.future).code, 'remote-config-closed');
        rig.async.elapse(_second);

        expect(rig.store.count(StoreOp.update, metaKey), metaUpdates);
        expect(rig.store.calls.length, callsAtClose);
        expect(rig.record('meta'), metaBefore);
      },
    );

    for (int k = 0; k < 24; k++) {
      rigTest(
        'A38 N4 setCustomSignals waiting for a reset that fails part-way, and a second reset '
        'called $k microtasks after the first is let go: once the second reset completes, the '
        'stored meta has no fetch state',
        (Review198Rig rig) {
          final FirebaseRemoteConfig rc = rig.instance();
          rig.fetch(rc, version: 1);
          final String throttleKey = rig.key('throttle');
          final StorePause held = rig.store.pauseBefore(
            StoreOp.update,
            throttleKey,
          );
          rig.store.failOnce(StoreOp.update, throttleKey);

          final Pending<void> first = Pending<void>(rc.reset());
          rig.pump();
          expect(held.reached, isTrue);
          expect(rig.raw('meta'), isNull, reason: 'the first reset removed it');
          final Pending<void> signals = Pending<void>(
            rc.setCustomSignals(<String, Object?>{'tier': 'gold'}),
          );
          rig.pump();
          expect(signals.done, isFalse, reason: 'its meta update waits');

          Pending<void>? second;
          held.open();
          _afterMicrotasks(k, () => second = Pending<void>(rc.reset()));
          rig.pump();
          rig.settle(second!.future);
          rig.settle(signals.future);
          rig.pump();

          expect(first.error, _rcCode('storage-error'));
          expect(second!.error, isNull);
          expect(signals.error, isNull);
          expect(rig.record('meta'), _noFetchState);
          expect(rc.info.lastSuccessfulFetchTime, isNull);
          expect(rc.customSignals, <String, String>{'tier': 'gold'});
        },
      );
    }

    rigTest(
      'A38 N4 outside a reset setCustomSignals issues its meta update after as many microtasks '
      'as before any reset ran',
      (Review198Rig rig) {
        final FirebaseRemoteConfig rc = rig.instance();
        rig.settle(rc.ensureInitialized());
        final String metaKey = rig.key('meta');

        int metaUpdates = rig.store.count(StoreOp.update, metaKey);
        final Pending<void> gold = Pending<void>(
          rc.setCustomSignals(<String, Object?>{'tier': 'gold'}),
        );
        final int beforeAnyReset = _microtasksUntil(
          rig.async,
          () => rig.store.count(StoreOp.update, metaKey) > metaUpdates,
        );
        rig.settle(gold.future);

        rig.settle(rc.reset());
        expect(rig.raw('meta'), isNull);
        metaUpdates = rig.store.count(StoreOp.update, metaKey);
        final Pending<void> silver = Pending<void>(
          rc.setCustomSignals(<String, Object?>{'tier': 'silver'}),
        );
        final int afterReset = _microtasksUntil(
          rig.async,
          () => rig.store.count(StoreOp.update, metaKey) > metaUpdates,
        );
        rig.settle(silver.future);

        expect(afterReset, beforeAnyReset);
        expect(rig.raw('meta'), isNotNull);
        expect(rc.customSignals, <String, String>{'tier': 'silver'});
      },
    );
  });

  group('A42 hand-off after a failed reset', () {
    rigTest(
      'A42 N2 a reset that starts during the hand-off of an activate and fails removing the '
      "fetched record: the connector gets the template's experiments before activate returns "
      'true, and the stored set matches',
      (Review198Rig rig) {
        final FakeAnalytics analytics = FakeAnalytics();
        final FirebaseRemoteConfig rc = rig.instance(
          analytics: analytics,
          defaults: <String, Object>{'a': 'default'},
        );
        final ActivatedCount activated = ActivatedCount(rc.onActivated);
        rig.fetch(rc, version: 5, experiments: <String, String>{'1': 'A'});
        final StorePause handOff = rig.store.pauseBefore(
          StoreOp.read,
          rig.key('experiments'),
        );
        rig.store.failOnce(StoreOp.update, rig.key('fetched'));

        final Future<bool> call = rc.activate();
        final Pending<bool> activate = Pending<bool>(call);
        int? setsAtReturn;
        unawaited(
          call.then<void>(
            (bool _) => setsAtReturn = analytics.sets.length,
            onError: (Object _) {},
          ),
        );
        rig.pump();
        expect(handOff.reached, isTrue);
        expect(rig.raw('active'), isNotNull);
        expect(rig.rcError(rc.reset()).code, 'storage-error');
        expect(analytics.calls, isEmpty);

        handOff.open();
        expect(rig.settle(activate.future), isTrue);
        rig.pump();

        expect(setsAtReturn, 1);
        expect(analytics.sets, <Map<String, String?>>[
          <String, String?>{'firebase1': 'A'},
        ]);
        expect(analytics.events, <String>[abtEvent]);
        expect(jsonDecode(rig.raw('experiments')!), <String, Object?>{
          'v': 1,
          'ids': <String>['1'],
        });
        expect(activated.count, 1);
        expect(rc.info.activeTemplateVersion, 5);
        expect(rc.getString('a'), 'remote');
      },
    );
  });

  group('A39 realtime backoff writes', () {
    test(
      'A39 N5 the stored state S1, a different state S2 being written, then back to S1: S1 is '
      'written last',
      () {
        fakeAsync((FakeAsync async) {
          final Gate gate = Gate();
          final List<int> writes = <int>[0];
          final BackoffHarness h = BackoffHarness(
            async,
            before: _realtimeWrites(
              writes,
              (int number) => number == 2 ? gate.future : null,
            ),
          );
          h.listen();
          expect(h.server.connections, hasLength(1));
          h.server.last.send('{"retryIntervalSeconds": 3600}');
          h.elapseTo(_s(1));
          final Map<String, Object?> s1 = backoffJson(retryUntil: _s(3600));
          expect(writes.single, 1);
          expect(h.record('realtime'), s1);

          // S2: a transport failure adds a count and a wait.
          h.server.last.fail();
          async.flushMicrotasks();
          expect(writes.single, 2, reason: 'S2 is being written');
          expect(h.record('realtime'), s1);

          // Back to S1: the regain clears the transport count and wait; the retry wait stays.
          _regainNetwork(h);
          gate.open();
          async.elapse(_second);

          expect(writes.single, 3);
          expect(h.record('realtime'), s1);
          h.dispose();
        });
      },
    );

    test(
      'A39 N5 a failed removal of an empty record at load: the next change hands the state '
      'over again and the record is removed',
      () {
        fakeAsync((FakeAsync async) {
          final List<int> writes = <int>[0];
          final BackoffHarness h = BackoffHarness(
            async,
            records: <String, String>{
              'realtime': backoffText(serverUntil: -_s(10)),
            },
            before: _realtimeWrites(writes, (int number) {
              if (number == 1) {
                throw StateError('fake disk full');
              }
            }),
          );
          async.elapse(_zero);
          expect(h.remoteConfig.isInitialized, isTrue);
          expect(writes.single, 1);
          expect(h.record('realtime'), isNotNull, reason: 'the removal failed');

          // A change that leaves the state empty: nothing to clear.
          _regainNetwork(h);
          async.elapse(_zero);

          expect(writes.single, 2);
          expect(h.record('realtime'), isNull);
          h.dispose();
        });
      },
    );

    test(
      'A39 close close() while a realtime write is held: that write lands, and no later state '
      'is handed over or written',
      () {
        fakeAsync((FakeAsync async) {
          final Gate gate = Gate();
          final List<int> writes = <int>[0];
          final BackoffHarness h = BackoffHarness(
            async,
            before: _realtimeWrites(
              writes,
              (int number) => number == 1 ? gate.future : null,
            ),
          );
          h.listen();
          expect(h.server.connections, hasLength(1));
          h.server.last.send('{"retryIntervalSeconds": 600}');
          async.elapse(_zero);
          expect(writes.single, 1, reason: 'the retry wait is being written');
          expect(h.record('realtime'), isNull);

          unawaited(h.remoteConfig.close());
          async.flushMicrotasks();
          // Later changes: the end of the aborted connection, and a network regain.
          _regainNetwork(h);
          gate.open();
          async.elapse(const Duration(minutes: 15));

          expect(writes.single, 1);
          expect(h.record('realtime'), backoffJson(retryUntil: _s(600)));
          expect(h.server.connections, hasLength(1));
          h.dispose();
        });
      },
    );
  });
}
