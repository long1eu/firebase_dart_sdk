// Owner P. The wiring of PersistentConnection that the connection's unit tests left open
// (rtdb/reports/round2/test-audit-connection.md, mutations m02 to m06, m11, m12, m14, m16, m17):
// what resets or raises the reconnect delay, the attempt time subtracted from it, a token
// provider that fails, the App Check half of review H2, a late listen answer, callbacks after
// shutdown, a write whose send failed, and the T13 "ok answer" and "established" rules.
//
// Everything runs on fake time with a deterministic jitter (random 1: every delay is its full
// bound). The delay is measured from one attempt to the next: the backoff subtracts the time the
// attempt took, so that gap is the bound itself.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_database_dart/src/realtime/auth_session.dart';
import 'package:firebase_database_dart/src/realtime/connection_timings.dart';
import 'package:firebase_database_dart/src/testing/recording_server_actions_delegate.dart';
import 'package:test/test.dart';

import '../util/fake_rtdb_server.dart';
import '../util/fake_ws.dart';
import '../util/persistent_connection_harness.dart';

/// Bounds 100, 200, 400, 800 ms... (multiplier 2 in the shrunk timings), reset after
/// [resetAfter] of an established connection.
ConnectionTimings _growing({
  Duration resetAfter = const Duration(minutes: 1),
  Duration reconnectMin = const Duration(milliseconds: 100),
}) => shrunkTimings(
  reconnectMin: reconnectMin,
  reconnectMax: const Duration(seconds: 60),
  reconnectResetAfter: resetAfter,
);

/// Closes the current connection from the server side and waits for the disconnect.
void _drop(FakeAsync async, PRig rig) {
  final int before = rig.delegate.callsOf('disconnect').length;
  rig.server.connector.last.serverClose(1006);
  elapseUntil(async, () => rig.delegate.callsOf('disconnect').length > before);
}

/// Waits for connection [number], lets its answers arrive, then drops it.
void _connectAndDrop(FakeAsync async, PRig rig, int number) {
  elapseUntil(async, () => rig.connects == number);
  async.flushMicrotasks();
  _drop(async, rig);
}

/// The time from each attempt to the next, in ms.
List<int> _gapsMs(PRig rig) => <int>[
  for (int i = 1; i < rig.attemptTimes.length; i++)
    (rig.attemptTimes[i] - rig.attemptTimes[i - 1]).inMilliseconds,
];

/// Gaps that equal [expected] within 2 ms each.
Matcher _gaps(List<int> expected) => pairwiseCompare(
  expected,
  (int want, Object? got) => got is int && (got - want).abs() <= 2,
  'within 2 ms of',
);

/// A second App Check token the fake server accepts: claims {"sub":"app","v":2}.
const String _newerAppCheck =
    'eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJhcHAiLCJ2IjoyfQ.sig';

void main() {
  group('reconnect delay', () {
    test(
      'a connectivity hint while connected resets the next delay to its minimum (m03)',
      () {
        fakeAsync((FakeAsync async) {
          final PRig rig = fakeTimeRig(async, timings: _growing());
          rig.connection.initialize();
          for (int n = 1; n <= 3; n++) {
            _connectAndDrop(async, rig, n);
          }
          elapseUntil(async, () => rig.connects == 4);
          rig.hints.add(null);
          async.flushMicrotasks();
          _drop(async, rig);
          elapseUntil(async, () => rig.attemptTimes.length == 5);

          // Breaks if PersistentConnection._onConnectivityHint stops calling _backoff.reset(): the
          // last gap would be the 800 ms bound.
          expect(_gapsMs(rig), _gaps(<int>[100, 200, 400, 100]));
          shutDownOnFakeTime(async, rig);
        });
      },
    );

    test(
      'resume resets the delay: the attempt after it starts at the minimum (m04)',
      () {
        fakeAsync((FakeAsync async) {
          final PRig rig = fakeTimeRig(async, timings: _growing());
          rig.connection.initialize();
          for (int n = 1; n <= 3; n++) {
            _connectAndDrop(async, rig, n);
          }
          // Attempt 4 waits 400 ms; interrupt and resume replace it by an immediate one.
          rig.connection
            ..interrupt('test')
            ..resume('test');
          _connectAndDrop(async, rig, 4);
          elapseUntil(async, () => rig.attemptTimes.length == 5);

          // Breaks if PersistentConnection.resume stops calling _backoff.reset(): the last gap
          // would be the 800 ms bound.
          expect(_gapsMs(rig).last, closeTo(100, 2));
          shutDownOnFakeTime(async, rig);
        });
      },
    );

    test('the time a failed attempt took is subtracted from the delay (m06)', () {
      fakeAsync((FakeAsync async) {
        // An 8 s bound; the first socket never opens, so the attempt ends at connectTimeout (5 s).
        final PRig rig = fakeTimeRig(
          async,
          timings: _growing(reconnectMin: const Duration(seconds: 8)),
        );
        rig.server.connector.script(<AttemptBehavior>[
          const AttemptBehavior.hang(),
        ]);
        rig.connection.initialize();
        elapseUntil(async, () => rig.connects == 1);

        // Breaks if PersistentConnection._scheduleReconnect passes the time of the failure
        // instead of _attemptStartedAt: the second attempt would start at 13 s.
        expect(rig.attemptTimes.map((Duration t) => t.inMilliseconds), <int>[
          0,
          8000,
        ]);
        shutDownOnFakeTime(async, rig);
      });
    });

    test(
      'a token provider that fails is retried after the backoff, not at once (m16)',
      () {
        fakeAsync((FakeAsync async) {
          final PRig rig = fakeTimeRig(async, timings: _growing());
          final List<int> fetchesMs = <int>[];
          rig.tokens
            ..error = Exception('provider down')
            ..onAuthFetch = () {
              fetchesMs.add(async.elapsed.inMilliseconds);
              if (fetchesMs.length == 4) {
                rig.tokens.error = null;
              }
            };
          rig.connection.initialize();
          elapseUntil(async, () => rig.connects == 1);

          // Breaks if the failure branch of PersistentConnection._establish schedules the next
          // attempt with no delay: every fetch would be at 0 ms.
          expect(fetchesMs, <int>[0, 100, 300, 700]);
          expect(rig.attemptTimes.map((Duration t) => t.inMilliseconds), <int>[
            700,
          ]);
          shutDownOnFakeTime(async, rig);
        });
      },
    );
  });

  group('T13: who may reset the delay', () {
    test(
      'answers that are all errors never reset the delay, however many arrive (m14)',
      () {
        fakeAsync((FakeAsync async) {
          // Reset after zero: any established connection resets the delay at its drop.
          final PRig rig = fakeTimeRig(
            async,
            timings: _growing(resetAfter: Duration.zero),
          );
          rig.tokens
            ..auth = null
            ..appCheck = null;
          final List<String> statuses = <String>[];
          rig.connection.initialize();
          for (int n = 1; n <= 4; n++) {
            elapseUntil(async, () => rig.connects == n);
            // Two answers make the connection healthy by count; neither is ok.
            rig.server
              ..failNext('p', 'permission_denied')
              ..failNext('p', 'permission_denied');
            rig.connection
              ..put('/a', n, onComplete: (String s, _) => statuses.add(s))
              ..put('/b', n, onComplete: (String s, _) => statuses.add(s));
            async
              ..flushMicrotasks()
              ..elapse(const Duration(milliseconds: 1));
            expect(statuses, hasLength(2 * n));
            _drop(async, rig);
          }
          elapseUntil(async, () => rig.attemptTimes.length == 5);

          expect(statuses.toSet(), <String>{'permission_denied'});
          // Breaks if PersistentConnection._onDataMessage sets _okOnConnection for any answer:
          // every gap would be the 100 ms minimum.
          expect(_gapsMs(rig), _gaps(<int>[100, 200, 400, 800]));
          shutDownOnFakeTime(async, rig);
        });
      },
    );

    test('a connection is established once: a message just before its drop does not move the mark '
        '(m17)', () {
      fakeAsync((FakeAsync async) {
        final PRig rig = fakeTimeRig(
          async,
          timings: _growing(resetAfter: const Duration(seconds: 1)),
        );
        rig.connection.initialize();
        // Established (both credentials answered ok) but shorter than 1 s: no reset.
        for (int n = 1; n <= 3; n++) {
          _connectAndDrop(async, rig, n);
        }
        elapseUntil(async, () => rig.connects == 4);
        async.elapse(const Duration(seconds: 2));
        rig.server.pushData('/a', 1);
        async
          ..flushMicrotasks()
          ..elapse(const Duration(milliseconds: 1));
        _drop(
          async,
          rig,
        ); // Established 2 s ago: the bound goes back to 100 ms.
        _connectAndDrop(async, rig, 5);
        elapseUntil(async, () => rig.attemptTimes.length == 6);

        final List<int> gaps = _gapsMs(rig);
        expect(gaps.take(3), _gaps(<int>[100, 200, 400]));
        // Breaks if _markEstablishedWhenHealthy marks again on every message (the push 1 ms
        // before the drop): no reset, and this gap would be the 1600 ms bound.
        expect(gaps.last, closeTo(200, 2));
        shutDownOnFakeTime(async, rig);
      });
    });
  });

  test(
    'H2, App Check half: a change during the token fetch wins over the fetched token (m02)',
    () {
      fakeAsync((FakeAsync async) {
        final PRig rig = fakeTimeRig(async);
        rig.tokens.gate = Completer<void>();
        rig.connection.initialize();
        elapseUntil(async, () => rig.tokens.appCheckCalls.isNotEmpty);
        rig.tokens.emitAppCheck(_newerAppCheck);
        async.flushMicrotasks();
        rig.tokens.gate!.complete();
        elapseUntil(async, () => rig.connects == 1);
        async.flushMicrotasks();

        // Breaks if PersistentConnection._establish applies the fetched App Check token although
        // _appCheckVersion moved during the fetch.
        expect(
          rig.sent('appcheck').map((ServerSeen s) => s.body['token']),
          <Object?>[_newerAppCheck],
        );
        expect(
          rig.server.connector.attempts.single.headers[RealtimeProtocol
              .appCheckHeader],
          _newerAppCheck,
        );
        expect(
          rig.delegate
              .callsOf('appCheckStatus')
              .map((DelegateCall c) => c.status),
          <String>['ok'],
        );
        shutDownOnFakeTime(async, rig);
      });
    },
  );

  test(
    'a refused App Check token keeps the connection and forces both fetches of the next one',
    () {
      fakeAsync((FakeAsync async) {
        final PRig rig = fakeTimeRig(async);
        rig.tokens.appCheck = 'not-a-jwt';
        rig.connection.initialize();
        elapseUntil(async, () => rig.connects == 1);
        async.flushMicrotasks();
        expect(
          rig.delegate.callsOf('appCheckStatus').single.explanation,
          'Could not parse token.',
        );
        expect(rig.tokens.invalid, <TokenKind>[TokenKind.appCheck]);
        expect(rig.delegate.callsOf('disconnect'), isEmpty);

        _drop(async, rig);
        elapseUntil(async, () => rig.connects == 2);
        expect(rig.tokens.authCalls, <bool>[false, true]);
        expect(rig.tokens.appCheckCalls, <bool>[false, true]);
        shutDownOnFakeTime(async, rig);
      });
    },
  );

  test(
    'an answer to a listen replaced meanwhile is dropped and leaves the new listen alone (m05)',
    () {
      fakeAsync((FakeAsync async) {
        final PRig rig = fakeTimeRig(async, hold: true);
        rig.connection.initialize();
        elapseUntil(async, () => rig.connects == 1);
        final List<String> statuses = <String>[];
        rig.connection.listen(
          defaultListen('/l'),
          hashProvider: CountingHash(''),
          onComplete: (String s, _) => statuses.add('old $s'),
        );
        final int oldR = rig.sent('q').single.r!;
        rig.connection
          ..unlisten(defaultListen('/l'))
          ..listen(
            defaultListen('/l'),
            hashProvider: CountingHash(''),
            onComplete: (String s, _) => statuses.add('new $s'),
          );
        rig.server.connector.last.serverResponse(
          oldR,
          status: 'permission_denied',
          data: 'denied',
        );
        async.flushMicrotasks();

        // Breaks if PersistentConnection._onListenResponse drops the `hasListen` check: the old
        // callback would run and the new listen would be removed from the replay.
        expect(statuses, isEmpty);
        _drop(async, rig);
        elapseUntil(async, () => rig.connects == 2);
        expect(
          rig.sent('q', onConnection: 2).map((ServerSeen s) => s.body['p']),
          <Object?>['/l'],
        );
        shutDownOnFakeTime(async, rig);
      });
    },
  );

  test(
    'callbacks and delegate calls scheduled before shutdown never run after it (m11)',
    () {
      fakeAsync((FakeAsync async) {
        final PRig rig = fakeTimeRig(async, hold: true);
        rig.connection.initialize();
        elapseUntil(async, () => rig.connects == 1);
        async.flushMicrotasks();
        final int callsBefore = rig.delegate.calls.length;
        final List<String> statuses = <String>[];
        rig.connection
          ..put('/a', 1, onComplete: (String s, _) => statuses.add(s))
          // Schedules write_canceled for the put, then onDisconnect for Repo.
          ..purgeOutstandingWrites()
          ..interrupt('test');
        // Same turn: the two are still queued.
        shutDownOnFakeTime(async, rig);

        // Breaks if PersistentConnection._emit stops checking _shutdown when the action runs.
        expect(statuses, isEmpty);
        expect(rig.delegate.methods.skip(callsBefore), isEmpty);
      });
    },
  );

  test(
    'a transaction put whose own send failed is replayed, not completed with disconnect (m12)',
    () {
      fakeAsync((FakeAsync async) {
        // The first socket dies on its third frame: auth, appcheck, then the put. The next
        // attempt is refused, which ends a connection that never said hello.
        final PRig rig = fakeTimeRig(
          async,
          hold: true,
          wrapConnector: failFrameOfFirstChannel(3),
        );
        rig.server.connector.script(<AttemptBehavior>[
          const AttemptBehavior.accept(),
          const AttemptBehavior.refuse(),
        ]);
        final List<String> statuses = <String>[];
        rig.connection
          ..put(
            '/tx',
            1,
            hash: 'h',
            onComplete: (String s, _) => statuses.add(s),
          )
          ..initialize();
        elapseUntil(async, () => rig.connects == 1);
        async.flushMicrotasks();

        expect(rig.server.connector.attempts, hasLength(3));
        expect(rig.sent('p', onConnection: 1), isEmpty);
        // Breaks if PersistentConnection._sendWrite sets `write.sent = true` whatever _send
        // returned: the refused attempt would complete the put with `disconnect`.
        expect(statuses, isEmpty);
        expect(rig.sent('p', onConnection: 2).single.body, <String, Object?>{
          'p': '/tx',
          'd': 1,
          'h': 'h',
        });
        shutDownOnFakeTime(async, rig);
      });
    },
  );
}
