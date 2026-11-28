@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'support/abt_kit.dart';
import 'support/fakes.dart';
import 'support/missing_backoff_harness.dart';
import 'support/rc_fetch_harness.dart';
import 'support/rc_realtime_fakes.dart';
import 'support/review198_rig.dart';

const Duration _zero = Duration.zero;
const Duration _second = Duration(seconds: 1);
const Duration _twoHours = Duration(hours: 2);
const Duration _milli = Duration(milliseconds: 1);

Duration _s(num seconds) => secondsAfterEpoch(seconds);

Future<http.StreamedResponse> _refuse503(RealtimeConnection connection) =>
    connection.refuse(503);

/// True for a missing meta record or one without the state of a successful fetch.
Matcher get _noFetchState => predicate<Map<String, Object?>?>(
  (Map<String, Object?>? meta) =>
      meta == null ||
      (!meta.containsKey('lastSuccessfulFetchTime') &&
          !meta.containsKey('fid')),
  'no lastSuccessfulFetchTime and no fid',
);

/// Holds the read of the `realtime` record until [gate] opens (a slow store during the load).
FutureOr<void> Function(StoreOp op, String key) _holdRealtimeRead(Gate gate) =>
    (StoreOp op, String key) =>
        op == StoreOp.read && key.endsWith('/realtime') ? gate.future : null;

/// Turns the network off, then on again: a regain (A11, A20).
void _regainNetwork(BackoffHarness h) {
  h.app.onNetworkConnected.add(false);
  h.async.flushMicrotasks();
  h.app.onNetworkConnected.add(true);
  h.async.flushMicrotasks();
}

void main() {
  group('A38 reset and activate', () {
    rigTest(
      'A38 B1 reset() not awaited, then activate(): activate returns false, nothing is active '
      'in the store or in memory, and onActivated does not emit',
      (Review198Rig rig) {
        final FirebaseRemoteConfig rc = rig.instance(
          defaults: <String, Object>{'a': 'default'},
        );
        final ActivatedCount activated = ActivatedCount(rc.onActivated);
        rig.fetch(rc, version: 5);

        final Future<void> reset = rc.reset();
        final Future<bool> activate = rc.activate();
        rig.settle(reset);
        expect(rig.settle(activate), isFalse);
        rig.pump();

        expect(rig.raw('active'), isNull);
        expect(rig.raw('fetched'), isNull);
        expect(rc.info.activeTemplateVersion, isNull);
        expect(rc.info.fetchedTemplateVersion, isNull);
        expect(rc.getString('a'), 'default');
        expect(rc.getValue('a').source, ValueSource.valueDefault);
        expect(activated.count, 0);
      },
    );

    rigTest(
      'A38 B1 reset() not awaited, then activate() with a newer fetched record over an active '
      'one: neither comes back',
      (Review198Rig rig) {
        final FirebaseRemoteConfig rc = rig.instance(
          defaults: <String, Object>{'a': 'default'},
        );
        final ActivatedCount activated = ActivatedCount(rc.onActivated);
        rig.fetch(rc, version: 1, entries: <String, String>{'a': 'one'});
        expect(rig.settle(rc.activate()), isTrue);
        rig.fetch(rc, version: 2, entries: <String, String>{'a': 'two'});
        rig.pump();
        expect(activated.count, 1);

        final Future<void> reset = rc.reset();
        final Future<bool> activate = rc.activate();
        rig.settle(reset);
        expect(rig.settle(activate), isFalse);
        rig.pump();

        expect(rig.raw('active'), isNull);
        expect(rig.raw('fetched'), isNull);
        expect(rc.info.activeTemplateVersion, isNull);
        expect(rc.getString('a'), 'default');
        expect(activated.count, 1);
      },
    );

    rigTest(
      'A38 M1 two resets not awaited, then a fetch: the resets run one at a time, both '
      'complete, and the request goes out only after both finished',
      (Review198Rig rig) {
        final FirebaseRemoteConfig rc = rig.instance();
        rig.settle(rc.ensureInitialized());
        final String fetchedKey = rig.key('fetched');
        final String experimentsKey = rig.key('experiments');
        final StorePause first = rig.store.pauseBefore(
          StoreOp.update,
          fetchedKey,
        );
        final StorePause second = rig.store.pauseBefore(
          StoreOp.update,
          fetchedKey,
          skip: 1,
        );
        int? resetsFinishedAtRequest;
        final FakeAnswer answer = rig.template(version: 1);
        rig.backend.enqueue(
          FakeRoute.fetch,
          FakeAnswer((RecordedRequest request) {
            // Each reset removes the experiments record as its last store call.
            resetsFinishedAtRequest = rig.store.count(
              StoreOp.write,
              experimentsKey,
            );
            return answer.respond(request);
          }),
        );

        final Pending<void> reset1 = Pending<void>(rc.reset());
        final Pending<void> reset2 = Pending<void>(rc.reset());
        final Pending<FetchResult> fetch = Pending<FetchResult>(rc.fetch());
        rig.pump();
        rig.async.elapse(_second);

        expect(first.reached, isTrue);
        expect(second.reached, isFalse);
        expect(
          rig.store.count(StoreOp.update, fetchedKey),
          1,
          reason: 'the second reset waits for the first',
        );
        expect(rig.backend.requestsTo(FakeRoute.fetch), isEmpty);

        first.open();
        rig.pump();
        expect(reset1.done, isTrue);
        expect(reset1.error, isNull);
        expect(second.reached, isTrue);
        expect(reset2.done, isFalse);
        expect(
          rig.backend.requestsTo(FakeRoute.fetch),
          isEmpty,
          reason: 'the fetch waits for the second reset too',
        );

        second.open();
        expect(rig.settle(fetch.future), FetchResult.updated);
        expect(reset2.done, isTrue);
        expect(reset2.error, isNull);
        expect(rig.backend.requestsTo(FakeRoute.fetch), hasLength(1));
        expect(resetsFinishedAtRequest, 2);
        expect(rc.info.fetchedTemplateVersion, 1);
      },
    );

    rigTest(
      'A38 M2 setCustomSignals while reset clears the records (held at the throttle update): '
      'the stored meta has no lastSuccessfulFetchTime and no fid',
      (Review198Rig rig) {
        final FirebaseRemoteConfig rc = rig.instance();
        rig.fetch(rc, version: 1);
        expect(rig.record('meta'), isNot(_noFetchState));
        final StorePause held = rig.store.pauseBefore(
          StoreOp.update,
          rig.key('throttle'),
        );

        final Pending<void> reset = Pending<void>(rc.reset());
        rig.pump();
        expect(held.reached, isTrue);
        expect(rig.raw('meta'), isNull, reason: 'the reset removed it');
        final int metaUpdates = rig.store.count(
          StoreOp.update,
          rig.key('meta'),
        );
        final Pending<void> signals = Pending<void>(
          rc.setCustomSignals(<String, Object?>{'tier': 'gold'}),
        );
        rig.pump();
        expect(signals.done, isFalse);
        expect(
          rig.store.count(StoreOp.update, rig.key('meta')),
          metaUpdates,
          reason: 'the meta update waits for the reset',
        );

        held.open();
        rig.settle(reset.future);
        rig.settle(signals.future);

        expect(rig.record('meta'), _noFetchState);
        expect(rc.info.lastSuccessfulFetchTime, isNull);
        expect(rc.customSignals, <String, String>{'tier': 'gold'});
      },
    );

    rigTest(
      'A38 M2 an ID change to another FID while reset clears the records: the stored meta has '
      'no lastSuccessfulFetchTime and no fid',
      (Review198Rig rig) {
        final FirebaseRemoteConfig rc = rig.instance();
        rig.fetch(rc, version: 1);
        expect(rig.record('meta')?['fid'], rcFirstFid);
        final StorePause held = rig.store.pauseBefore(
          StoreOp.update,
          rig.key('throttle'),
        );

        final Pending<void> reset = Pending<void>(rc.reset());
        rig.pump();
        expect(held.reached, isTrue);
        final int metaUpdates = rig.store.count(
          StoreOp.update,
          rig.key('meta'),
        );
        rig.installations.changeId(rcSecondFid);
        rig.pump();
        expect(
          rig.store.count(StoreOp.update, rig.key('meta')),
          metaUpdates,
          reason: 'the meta update waits for the reset',
        );

        held.open();
        rig.settle(reset.future);
        rig.pump();

        expect(rig.record('meta'), _noFetchState);
        expect(rc.info.lastSuccessfulFetchTime, isNull);
      },
    );

    rigTest(
      'A38 M2 setCustomSignals while reset waits for a hanging analytics connector: the stored '
      'meta has no lastSuccessfulFetchTime and no fid',
      (Review198Rig rig) {
        final FakeAnalytics analytics = FakeAnalytics();
        final FirebaseRemoteConfig rc = rig.instance(analytics: analytics);
        rig.fetch(rc, version: 1, experiments: <String, String>{'1': 'A'});
        expect(rig.settle(rc.activate()), isTrue);
        analytics.onSet = (Map<String, String?> _) => Completer<void>().future;

        final Pending<void> reset = Pending<void>(rc.reset());
        rig.pump();
        expect(
          analytics.sets,
          hasLength(2),
          reason: 'the reset is at the hook',
        );
        expect(rig.raw('meta'), isNull, reason: 'the reset removed it');
        final Pending<void> signals = Pending<void>(
          rc.setCustomSignals(<String, Object?>{'tier': 'gold'}),
        );
        rig.async.elapse(_second);
        expect(signals.done, isFalse);

        rig.async.elapse(const Duration(seconds: 60));
        expect(reset.done, isTrue);
        expect(reset.error, isNull);
        rig.settle(signals.future);

        expect(rig.record('meta'), _noFetchState);
        expect(rc.info.lastSuccessfulFetchTime, isNull);
      },
    );

    rigTest(
      'A38 / A42 M3 a reset during the A/B hand-off of an activate: activate returns false, '
      'onActivated does not emit, nothing stays active',
      (Review198Rig rig) {
        final Gate connector = Gate();
        final FakeAnalytics analytics = FakeAnalytics();
        final FirebaseRemoteConfig rc = rig.instance(
          analytics: analytics,
          defaults: <String, Object>{'a': 'default'},
        );
        final ActivatedCount activated = ActivatedCount(rc.onActivated);
        rig.fetch(rc, version: 5, experiments: <String, String>{'1': 'A'});
        analytics.onSet = (Map<String, String?> _) => connector.future;

        final Pending<bool> activate = Pending<bool>(rc.activate());
        rig.pump();
        expect(analytics.sets, hasLength(1));
        final Pending<void> reset = Pending<void>(rc.reset());
        rig.pump();
        expect(reset.done, isFalse);

        analytics.onSet = null;
        connector.open();
        rig.settle(reset.future);
        expect(rig.settle(activate.future), isFalse);
        rig.pump();

        expect(activated.count, 0);
        expect(rig.raw('active'), isNull);
        expect(rig.raw('experiments'), isNull);
        expect(rc.info.activeTemplateVersion, isNull);
        expect(rc.getString('a'), 'default');
      },
    );

    rigTest(
      'A38 M3 a reset that fails removing the fetched record after the activate wrote active: '
      'activate returns true, memory holds the record, onActivated emits once',
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
        rig.store.failOnce(StoreOp.update, rig.key('fetched'));

        final Pending<bool> activate = Pending<bool>(rc.activate());
        rig.pump();
        expect(wrote.reached, isTrue);
        expect(rig.raw('active'), isNotNull);

        expect(rig.rcError(rc.reset()).code, 'storage-error');
        wrote.open();
        expect(rig.settle(activate.future), isTrue);
        rig.pump();

        expect(activated.count, 1);
        expect(rc.getString('a'), 'remote');
        expect(rc.getValue('a').source, ValueSource.valueRemote);
        expect(rc.info.activeTemplateVersion, 5);
        expect(rig.raw('active'), isNotNull);
      },
    );

    rigTest('A38 m-close close() during reset: no store call afterwards', (
      Review198Rig rig,
    ) {
      final FirebaseRemoteConfig rc = rig.instance();
      rig.fetch(rc, version: 1);
      expect(rig.settle(rc.activate()), isTrue);
      final StorePause held = rig.store.pauseBefore(
        StoreOp.update,
        rig.key('active'),
      );
      final Pending<void> reset = Pending<void>(rc.reset());
      rig.pump();
      expect(held.reached, isTrue);

      unawaited(rc.close());
      rig.pump();
      final int callsAtClose = rig.store.calls.length;
      held.open();
      expect(rig.rcError(reset.future).code, 'remote-config-closed');
      rig.async.elapse(_second);

      expect(rig.store.calls.length, callsAtClose);
      expect(rig.raw('meta'), isNotNull, reason: 'never removed');
    });

    rigTest(
      'A38 / A42 m-close close() while reset waits for a hanging connector: no store call '
      'afterwards, the experiments record stays',
      (Review198Rig rig) {
        final FakeAnalytics analytics = FakeAnalytics();
        final FirebaseRemoteConfig rc = rig.instance(analytics: analytics);
        rig.fetch(rc, version: 1, experiments: <String, String>{'1': 'A'});
        expect(rig.settle(rc.activate()), isTrue);
        analytics.onSet = (Map<String, String?> _) => Completer<void>().future;
        final Pending<void> reset = Pending<void>(rc.reset());
        rig.pump();
        expect(analytics.sets, hasLength(2));

        unawaited(rc.close());
        rig.pump();
        final int callsAtClose = rig.store.calls.length;
        expect(rig.rcError(reset.future).code, 'remote-config-closed');
        rig.async.elapse(const Duration(seconds: 61));

        expect(rig.store.calls.length, callsAtClose);
        expect(jsonDecode(rig.raw('experiments')!), <String, Object?>{
          'v': 1,
          'ids': <String>['1'],
        });
      },
    );
  });

  group('A39 restored backoff and the first connect', () {
    test(
      'A39 M4 a listen during the load on a fast store: a restored serverUntil 2 h ahead holds '
      'the first request until 2 h',
      () {
        fakeAsync((FakeAsync async) {
          final BackoffHarness h = BackoffHarness(
            async,
            records: <String, String>{
              'realtime': backoffText(
                serverFailures: 1,
                serverUntil: _twoHours,
              ),
            },
          );
          unawaited(h.remoteConfig.close());
          async.flushMicrotasks();
          final FirebaseRemoteConfig rc = review198BackoffInstance(h);
          h.remoteConfig = rc;
          // Listened before any microtask runs: the reconnect timer is set before the restore.
          UpdateLog().listen(rc.onConfigUpdated);
          expect(rc.isInitialized, isFalse);

          h.elapseTo(_twoHours - _milli);
          expect(rc.isInitialized, isTrue);
          expect(h.server.connections, isEmpty);
          h.elapseTo(_twoHours);
          expect(h.server.connections, hasLength(1));
          h.dispose();
        });
      },
    );

    test(
      'A39 M4 a connect already waiting on a slow store: a restored serverUntil 2 h ahead '
      'holds the request until 2 h, and no failure is counted',
      () {
        fakeAsync((FakeAsync async) {
          final Gate gate = Gate();
          final String stored = backoffText(
            serverFailures: 1,
            serverUntil: _twoHours,
          );
          final BackoffHarness h = BackoffHarness(
            async,
            records: <String, String>{'realtime': stored},
            before: _holdRealtimeRead(gate),
          );
          h.listen();
          h.elapseTo(_s(10));
          expect(h.remoteConfig.isInitialized, isFalse);
          expect(h.server.connections, isEmpty);

          gate.open();
          h.elapseTo(_twoHours - _milli);
          expect(h.server.connections, isEmpty);
          expect(h.record('realtime'), jsonDecode(stored));
          h.elapseTo(_twoHours);
          expect(h.server.connections, hasLength(1));
          h.dispose();
        });
      },
    );

    for (final String field in <String>[
      'serverUntil',
      'transportUntil',
      'retryUntil',
    ]) {
      test(
        'A39 m-past a stored realtime record holding only a past $field is removed at load',
        () {
          fakeAsync((FakeAsync async) {
            final BackoffHarness h = BackoffHarness(
              async,
              records: <String, String>{
                'realtime': backoffText(
                  serverUntil: field == 'serverUntil' ? -_s(10) : null,
                  transportUntil: field == 'transportUntil' ? -_s(10) : null,
                  retryUntil: field == 'retryUntil' ? -_s(10) : null,
                ),
              },
            );
            async.elapse(_zero);
            expect(h.remoteConfig.isInitialized, isTrue);
            expect(h.record('realtime'), isNull);
            h.dispose();
          });
        },
      );
    }

    test(
      'A39 m-past a stored record with counts and past waits stays at load (not empty)',
      () {
        fakeAsync((FakeAsync async) {
          final String stored = backoffText(
            serverFailures: 2,
            serverUntil: -_s(10),
          );
          final BackoffHarness h = BackoffHarness(
            async,
            records: <String, String>{'realtime': stored},
          );
          async.elapse(_zero);
          expect(h.record('realtime'), jsonDecode(stored));
          h.dispose();
        });
      },
    );

    test(
      'A39 m-success after a 60 s connection, with the restored retryUntil passed, the record '
      'is removed',
      () {
        fakeAsync((FakeAsync async) {
          final String stored = backoffText(
            serverFailures: 2,
            transportFailures: 1,
            retryUntil: _s(30),
          );
          final BackoffHarness h = BackoffHarness(
            async,
            records: <String, String>{'realtime': stored},
          );
          h.listen();
          h.elapseTo(_s(30));
          expect(h.server.connections, hasLength(1));
          h.elapseTo(_s(89.999));
          expect(h.record('realtime'), jsonDecode(stored));

          h.elapseTo(_s(90));
          expect(h.record('realtime'), isNull);
          h.dispose();
        });
      },
    );

    for (final String field in <String>['serverUntil', 'transportUntil']) {
      test(
        'A39 m-regain a network regain during the load connects within the 1 s floor despite '
        'a restored $field 2 h ahead',
        () {
          fakeAsync((FakeAsync async) {
            final Gate gate = Gate();
            final bool server = field == 'serverUntil';
            final BackoffHarness h = BackoffHarness(
              async,
              records: <String, String>{
                'realtime': backoffText(
                  serverFailures: server ? 1 : 0,
                  transportFailures: server ? 0 : 1,
                  serverUntil: server ? _twoHours : null,
                  transportUntil: server ? null : _twoHours,
                ),
              },
              before: _holdRealtimeRead(gate),
            );
            h.listen();
            _regainNetwork(h);
            expect(h.remoteConfig.isInitialized, isFalse);

            gate.open();
            h.elapseTo(_s(1));
            expect(h.server.connections, hasLength(1));
            // The regain clears the failure waits and the transport count; the server count stays.
            expect(
              h.record('realtime'),
              server ? backoffJson(serverFailures: 1) : isNull,
            );
            h.dispose();
          });
        },
      );
    }

    test(
      'A39 m-regain a network regain during the load leaves a restored retryUntil 2 h ahead in '
      'place: no request before 2 h',
      () {
        fakeAsync((FakeAsync async) {
          final Gate gate = Gate();
          final BackoffHarness h = BackoffHarness(
            async,
            records: <String, String>{
              'realtime': backoffText(
                serverFailures: 1,
                serverUntil: _twoHours,
                retryUntil: _twoHours,
              ),
            },
            before: _holdRealtimeRead(gate),
          );
          h.listen();
          _regainNetwork(h);

          gate.open();
          h.elapseTo(_twoHours - _milli);
          expect(h.server.connections, isEmpty);
          expect(
            h.record('realtime'),
            backoffJson(serverFailures: 1, retryUntil: _twoHours),
          );
          h.elapseTo(_twoHours);
          expect(h.server.connections, hasLength(1));
          h.dispose();
        });
      },
    );
  });

  group('A39 backoff writes', () {
    test(
      'A39 m-close a backoff write held in the store plus close(): the change queued behind it '
      'is never written',
      () {
        fakeAsync((FakeAsync async) {
          final Gate gate = Gate();
          int writes = 0;
          final BackoffHarness h = BackoffHarness(
            async,
            before: (StoreOp op, String key) {
              if (op == StoreOp.write && key.endsWith('/realtime')) {
                writes++;
                if (writes == 1) {
                  return gate.future;
                }
              }
              return null;
            },
          );
          h.server.realtimeAnswer = _refuse503;
          h.listen();
          async.elapse(const Duration(milliseconds: 10));
          expect(h.server.connections, hasLength(1));
          expect(
            writes,
            1,
            reason: 'the first server failure is being written',
          );

          // A second change: the regain clears the server wait.
          _regainNetwork(h);
          unawaited(h.remoteConfig.close());
          async.flushMicrotasks();
          gate.open();
          async.elapse(const Duration(seconds: 5));

          expect(writes, 1);
          expect(
            h.record('realtime'),
            backoffJson(serverFailures: 1, serverUntil: _s(120)),
          );
          h.dispose();
        });
      },
    );

    test(
      'A39 m-retry a failed backoff write is handed over again when the same state comes back',
      () {
        fakeAsync((FakeAsync async) {
          int writes = 0;
          final BackoffHarness h = BackoffHarness(
            async,
            before: (StoreOp op, String key) {
              if (op == StoreOp.write && key.endsWith('/realtime')) {
                writes++;
                if (writes == 1) {
                  throw StateError('fake disk full');
                }
              }
            },
          );
          h.listen();
          expect(h.server.connections, hasLength(1));
          h.server.last.send('{"retryIntervalSeconds": 600}');
          h.elapseTo(_s(1));
          expect(writes, 1);
          expect(h.record('realtime'), isNull, reason: 'the write failed');

          // The 60 s success leaves the state as it was: counts 0, the retry wait.
          h.elapseTo(_s(60));
          expect(writes, 2);
          expect(h.record('realtime'), backoffJson(retryUntil: _s(600)));
          h.dispose();
        });
      },
    );
  });

  group('A42 hand-off queue and repair', () {
    rigTest(
      'A42 m-queue a hung connector and two queued activates: each returns within fetchTimeout '
      'of its own call',
      (Review198Rig rig) {
        final FakeAnalytics analytics = FakeAnalytics()
          ..onSet = (Map<String, String?> _) => Completer<void>().future;
        final FirebaseRemoteConfig rc = rig.instance(analytics: analytics);
        rig.fetch(rc, version: 1, experiments: <String, String>{'1': 'A'});
        final DateTime first = rig.now();
        final Pending<bool> activate1 = Pending<bool>(rc.activate());
        rig.pump();
        expect(analytics.sets, hasLength(1));

        rig.async.elapse(const Duration(seconds: 29));
        rig.fetch(rc, version: 2, experiments: <String, String>{'2': 'B'});
        final DateTime second = rig.now();
        expect(second.difference(first), const Duration(seconds: 30));
        final Pending<bool> activate2 = Pending<bool>(rc.activate());
        rig.pump();
        expect(analytics.sets, hasLength(1), reason: 'queued behind the first');

        rig.elapseTo(first.add(const Duration(seconds: 59)));
        expect(activate1.done, isFalse);
        rig.elapseTo(first.add(const Duration(seconds: 61)));
        expect(activate1.done, isTrue);
        expect(activate1.value, isTrue);
        expect(activate2.done, isFalse);

        rig.elapseTo(second.add(const Duration(seconds: 59)));
        expect(activate2.done, isFalse);
        rig.elapseTo(second.add(const Duration(seconds: 61)));
        expect(activate2.done, isTrue);
        expect(activate2.value, isTrue);
      },
    );

    rigTest(
      'A42 m-queue a hand-off whose deadline passed while it waited sends nothing; activate '
      'still returns true and the ids are kept for the next one',
      (Review198Rig rig) {
        final FakeAnalytics analytics = FakeAnalytics();
        final FirebaseRemoteConfig rc = rig.instance(analytics: analytics);
        rig.fetch(rc, version: 1, experiments: <String, String>{'1': 'A'});
        // The first hand-off waits for a slow store read past both deadlines.
        final StorePause slowRead = rig.store.pauseBefore(
          StoreOp.read,
          rig.key('experiments'),
        );
        final Pending<bool> activate1 = Pending<bool>(rc.activate());
        rig.pump();
        expect(slowRead.reached, isTrue);
        rig.fetch(rc, version: 2, experiments: <String, String>{'2': 'B'});
        final Pending<bool> activate2 = Pending<bool>(rc.activate());
        rig.pump();
        rig.async.elapse(const Duration(seconds: 70));
        expect(activate1.done, isFalse);

        slowRead.open();
        expect(rig.settle(activate1.future), isTrue);
        expect(rig.settle(activate2.future), isTrue);

        expect(analytics.calls, isEmpty);
        expect(
          rig.warnings.where(
            (String warning) => warning.contains('past its deadline'),
          ),
          hasLength(1),
        );
        final Map<String, Object?> stored = rig.record('experiments')!;
        expect(stored['ids'], unorderedEquals(<String>['1', '2']));
      },
    );

    for (final MapEntry<String, String> corrupt in <String, String>{
      'not JSON': 'not json',
      'an empty id': jsonEncode(<String, Object?>{
        'v': 1,
        'ids': <String>[''],
      }),
    }.entries) {
      rigTest(
        'A42 m-repair a corrupt experiments record (${corrupt.key}) and an activate with no '
        'experiments: the record is removed',
        (Review198Rig rig) {
          final FakeAnalytics analytics = FakeAnalytics();
          final FirebaseRemoteConfig rc = rig.instance(analytics: analytics);
          rig.settle(rc.ensureInitialized());
          rig.settle(
            rig.store.inner.write(rig.key('experiments'), corrupt.value),
          );
          rig.fetch(rc, version: 1);

          expect(rig.settle(rc.activate()), isTrue);

          expect(rig.raw('experiments'), isNull);
          expect(analytics.calls, isEmpty);
        },
      );
    }
  });
}
