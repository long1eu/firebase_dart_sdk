// Owner P. Threat model T13 (backoff that a server can reset) for PersistentConnection: the delay
// resets only after a healthy connection answered a request `ok`, never after a hello alone.
// Virtual time (fake_async) and a deterministic jitter (random 1: every delay is its full bound),
// so the gaps between attempts are the backoff bounds exactly. The server holds the credential
// answers until a test sends them, except in the invalid-token test, where it refuses the token
// itself as the emulator does.
import 'package:fake_async/fake_async.dart';
import 'package:firebase_database_dart/src/testing/recording_server_actions_delegate.dart';
import 'package:test/test.dart';

import '../util/persistent_connection_harness.dart';

/// Advances virtual time in 1 ms steps until [condition] holds (at most [limit]).
void _elapseUntil(
  FakeAsync async,
  bool Function() condition, {
  Duration limit = const Duration(seconds: 30),
}) {
  final Duration end = async.elapsed + limit;
  while (!condition()) {
    if (async.elapsed > end) {
      fail('condition not met within $limit of virtual time');
    }
    async.elapse(const Duration(milliseconds: 1));
  }
}

PRig _rig(FakeAsync async, {bool holdCredentials = true}) => fakeTimeRig(
  async,
  timings: shrunkTimings(
    reconnectMin: const Duration(milliseconds: 100),
    reconnectMax: const Duration(seconds: 60),
    reconnectResetAfter: Duration.zero,
  ),
  holdCredentials: holdCredentials,
);

/// Waits for connection [number], optionally answers its credentials (two `ok` responses: a
/// healthy connection with an ok answer), then drops it from the server side.
void _connectAndDrop(
  FakeAsync async,
  PRig rig,
  int number, {
  bool answer = false,
}) {
  _elapseUntil(async, () => rig.connects == number);
  if (answer) {
    rig.answerCredentialsNow();
    async.flushMicrotasks();
    // The reset needs the connection to be older than resetAfter (zero here): strictly older, as
    // JS's `>` (rtdb_protocol.md 8.2); with no time passing it would not reset.
    async.elapse(const Duration(milliseconds: 1));
  }
  final int disconnects = rig.delegate.callsOf('disconnect').length;
  rig.server.connector.last.serverClose(1006);
  _elapseUntil(
    async,
    () => rig.delegate.callsOf('disconnect').length > disconnects,
  );
}

List<int> _gapsMs(PRig rig) => <int>[
  for (int i = 1; i < rig.attemptTimes.length; i++)
    (rig.attemptTimes[i] - rig.attemptTimes[i - 1]).inMilliseconds,
];

void main() {
  test(
    'hello-then-drop server: the delays grow (no reset without an ok answer)',
    () {
      fakeAsync((FakeAsync async) {
        final PRig rig = _rig(async);
        rig.connection.initialize();
        for (int n = 1; n <= 4; n++) {
          _connectAndDrop(async, rig, n);
        }
        _elapseUntil(async, () => rig.attemptTimes.length == 5);
        // Bounds 100, 200, 400, 800 ms (multiplier 2 in the shrunk timings).
        final List<int> gaps = _gapsMs(rig);
        expect(gaps.first, inInclusiveRange(95, 110));
        expect(gaps.last, inInclusiveRange(790, 810));
        shutDownOnFakeTime(async, rig);
      });
    },
  );

  test(
    'a healthy connection with an ok answer resets the delay to its minimum',
    () {
      fakeAsync((FakeAsync async) {
        final PRig rig = _rig(async);
        rig.connection.initialize();
        for (int n = 1; n <= 3; n++) {
          _connectAndDrop(async, rig, n);
        }
        _connectAndDrop(async, rig, 4, answer: true);
        _elapseUntil(async, () => rig.attemptTimes.length == 5);
        final List<int> gaps = _gapsMs(rig);
        expect(
          gaps[2],
          inInclusiveRange(390, 410),
        ); // The bound had grown to 400 ms.
        expect(gaps.last, inInclusiveRange(95, 110)); // Back to 100 ms.
        shutDownOnFakeTime(async, rig);
      });
    },
  );

  test(
    'hello and two pushes without an ok answer: the delays still grow (the ok half of T13)',
    () {
      fakeAsync((FakeAsync async) {
        final PRig rig = _rig(async);
        rig.connection.initialize();
        for (int n = 1; n <= 4; n++) {
          _elapseUntil(async, () => rig.connects == n);
          // Two data messages make the connection healthy by count; none is an ok answer.
          rig.server
            ..pushData('/a', n)
            ..pushData('/b', n);
          async
            ..flushMicrotasks()
            ..elapse(const Duration(milliseconds: 1));
          rig.server.connector.last.serverClose(1006);
          _elapseUntil(
            async,
            () => rig.delegate.callsOf('disconnect').length == n,
          );
        }
        _elapseUntil(async, () => rig.attemptTimes.length == 5);
        // Breaks if `!_okOnConnection` is removed from _markEstablishedWhenHealthy
        // (persistent_connection.dart): every gap would be the 100 ms minimum.
        expect(_gapsMs(rig).last, inInclusiveRange(790, 810));
        shutDownOnFakeTime(async, rig);
      });
    },
  );

  test(
    'three refused auth tokens raise the next delay to its cap (T14b wiring)',
    () {
      fakeAsync((FakeAsync async) {
        // The server answers by itself and refuses the token (no `sub`); no App Check token, so
        // no answer is ok and no connection is established.
        final PRig rig = _rig(async, holdCredentials: false);
        rig.tokens
          ..auth = authTokenWithoutSub
          ..appCheck = null;
        rig.connection.initialize();
        for (int n = 1; n <= 3; n++) {
          _elapseUntil(async, () => rig.connects == n);
          _elapseUntil(
            async,
            () => rig.delegate.callsOf('disconnect').length == n,
          );
        }
        expect(
          rig.delegate.callsOf('authStatus').map((DelegateCall c) => c.status),
          <String>['invalid_token', 'invalid_token', 'invalid_token'],
        );
        _elapseUntil(
          async,
          () => rig.attemptTimes.length == 4,
          limit: const Duration(seconds: 90),
        );
        final List<int> gaps = _gapsMs(rig);
        expect(gaps[0], inInclusiveRange(98, 102));
        expect(gaps[1], inInclusiveRange(198, 202));
        // Breaks if PersistentConnection._detach stops calling _backoff.setToMax() when
        // invalidTokenThresholdReached: the gap would be the 400 ms bound.
        expect(gaps[2], inInclusiveRange(59998, 60002));
        shutDownOnFakeTime(async, rig);
      });
    },
  );
}
