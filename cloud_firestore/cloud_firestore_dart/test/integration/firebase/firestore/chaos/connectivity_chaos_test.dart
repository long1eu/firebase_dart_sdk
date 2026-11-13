// The built-in connectivity detector under a network that is gone long enough
// for the backoff of the listen stream to grow: without a hint the client
// waits for the rest of its backoff after the network is back, with a hint it
// reconnects at once. The interface list is simulated: the test cannot unplug
// the machine.

import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart'
    show FirestoreInternal;
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/connectivity_change_detector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:test/test.dart';

import '../../../../util/integration_test_util.dart';
import 'chaos_util.dart';

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/chaos_connectivity';

  late ChaosEnv env;

  setUp(() async {
    if (chaosSkipReason == null) {
      env = await ChaosEnv.start();
    }
  });

  tearDown(() async {
    if (chaosSkipReason == null) {
      await env.close();
    }
  });

  /// How long the network is gone (connections to the proxy are refused). The stream is retried after about 1, 1.5,
  /// 2.3, 3.4, 5.1 and 7.6 seconds (each plus or minus half), so after this
  /// long the next attempt is seconds away.
  const Duration outage = Duration(seconds: 16);

  /// Cuts the network of a listening client for [outage], brings it back and
  /// returns how long the client then took to deliver a change made on the
  /// backend. With [hint] an address appears on the simulated interfaces at
  /// the moment the network is back.
  ///
  /// With [acceptAndClose] the proxy does not refuse the connections during the outage: it accepts every one and
  /// closes it at once. [connectionsDuringOutage] is then how often the client connected.
  int connectionsDuringOutage = 0;

  /// How much of the backoff of the listen stream was left when the network came back, in the last [recoveryTime]
  /// (zero if no attempt was scheduled).
  Duration backoffLeftAtRecovery = Duration.zero;
  Future<Duration> recoveryTime({
    required bool hint,
    bool acceptAndClose = false,
  }) async {
    final Set<String> addresses = <String>{};
    int signals = 0;
    // The clock of the detector advances by one poll interval per reading: under the load of a full suite a poll can
    // run more than 10 s late, which the detector takes for a wake-up from sleep and signals (a run without a hint then
    // saw one signal). This test is about the interface hint; the wake-up check has its own unit tests.
    const Duration pollInterval = Duration(milliseconds: 100);
    DateTime clock = DateTime.utc(2026);
    final ConnectivityChangeDetector detector = ConnectivityChangeDetector(
      listAddresses: () async => Set<String>.of(addresses),
      pollInterval: pollInterval,
      now: () => clock = clock.add(pollInterval),
    );
    final Firestore db = await env.newClient(connectivityDetector: detector);
    // The remote store installed its handler; count the signals on top of it.
    final void Function() restart = detector.onChange!;
    detector.onChange = () {
      signals++;
      restart();
    };

    final String name = uniqueName('connectivity');
    final DocumentReference<Map<String, Object?>> serverDoc = env.oracle
        .collection(name)
        .doc('doc');
    await serverDoc.set(<String, Object?>{'n': 0});

    final List<int> seen = <int>[];
    final Completer<void> first = Completer<void>();
    final Completer<void> recovered = Completer<void>();
    final StreamSubscription<DocumentSnapshot<Map<String, Object?>>>
    subscription = db.collection(name).doc('doc').snapshots.listen((
      DocumentSnapshot<Map<String, Object?>> snapshot,
    ) {
      final int? n = snapshot.data?['n'] as int?;
      if (n == null) {
        return;
      }
      seen.add(n);
      if (n == 0 && !first.isCompleted) {
        first.complete();
      }
      if (n == 1 && !recovered.isCompleted) {
        recovered.complete();
      }
    });
    try {
      await first.future.timeout(const Duration(seconds: 20));
      expect(
        detector.isRunning,
        isFalse,
        reason: 'a healthy client does not poll',
      );

      final int connectionsBefore = env.proxy.acceptedConnections;
      if (acceptAndClose) {
        env.proxy.disconnect();
      } else {
        await env.proxy.unplug();
      }
      await Future<void>.delayed(outage);
      connectionsDuringOutage =
          env.proxy.acceptedConnections - connectionsBefore;
      expect(
        detector.isRunning,
        isTrue,
        reason: 'the stream is failing, the detector looks for changes',
      );
      expect(signals, 0);

      // The backend moved on while the client was away.
      await serverDoc.set(<String, Object?>{'n': 1});

      final TimerTask? backoff = db.scheduler.getTask(
        TaskId.listenStreamConnectionBackoff,
      );
      final Duration left = backoff == null
          ? Duration.zero
          : backoff.targetTime.difference(DateTime.now());
      backoffLeftAtRecovery = left.isNegative ? Duration.zero : left;
      final Stopwatch stopwatch = Stopwatch()..start();
      if (acceptAndClose) {
        env.proxy.restore();
      } else {
        await env.proxy.plug();
      }
      if (hint) {
        addresses.add('en0/192.168.1.20');
      }
      await recovered.future.timeout(const Duration(seconds: 90));
      stopwatch.stop();

      expect(signals, hint ? 1 : 0);
      // Let the stream settle: once it works the detector stops.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(
        detector.isRunning,
        isFalse,
        reason: 'the stream works again, nothing is left to speed up',
      );
      return stopwatch.elapsed;
    } finally {
      await subscription.cancel();
    }
  }

  test(
    'a connectivity hint makes the client reconnect without its backoff',
    () async {
      final Duration withHint = await recoveryTime(hint: true);
      final Duration backoffLeftWithHint = backoffLeftAtRecovery;
      final Duration withoutHint = await recoveryTime(hint: false);
      final Duration backoffLeftWithoutHint = backoffLeftAtRecovery;
      // ignore: avoid_print
      print(
        'Recovery after a ${outage.inSeconds}s outage: '
        '${withHint.inMilliseconds} ms with a connectivity hint '
        '(${backoffLeftWithHint.inMilliseconds} ms of backoff left), '
        '${withoutHint.inMilliseconds} ms without '
        '(${backoffLeftWithoutHint.inMilliseconds} ms of backoff left)',
      );

      // The poll takes up to 100 ms, then the stream is opened and the listen is
      // answered.
      expect(withHint, lessThan(const Duration(seconds: 2)));
      // Without a hint the client waits for the rest of its backoff. How much is left when the network comes back is
      // random (it can be next to nothing), so the two runs are not compared with each other: each is compared with
      // the backoff that was left in it.
      expect(
        withoutHint,
        greaterThanOrEqualTo(
          backoffLeftWithoutHint - const Duration(milliseconds: 100),
        ),
        reason: 'without a hint the client waits for its backoff',
      );
      if (backoffLeftWithHint > const Duration(seconds: 2)) {
        expect(
          withHint,
          lessThan(backoffLeftWithHint),
          reason: 'with a hint the client does not wait for its backoff',
        );
      }
    },
    skip:
        chaosSkipReason ??
        webTransportSkipReason(
          'the backoff of the WebChannel transport is not the one measured here',
        ),
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'a network that accepts and closes connections is backed off from, and '
    'recovered from like a refused one',
    () async {
      // Before the fix of KeepAliveTransportConnector the client connected
      // about 43 times per second for the whole outage.
      final Duration withHint = await recoveryTime(
        hint: true,
        acceptAndClose: true,
      );
      final int connectionsWithHint = connectionsDuringOutage;
      final Duration withoutHint = await recoveryTime(
        hint: false,
        acceptAndClose: true,
      );
      final int connectionsWithoutHint = connectionsDuringOutage;
      // ignore: avoid_print
      print(
        'Accept-and-close outage of ${outage.inSeconds}s: '
        '$connectionsWithHint and $connectionsWithoutHint connections; '
        'recovery ${withHint.inMilliseconds} ms with a connectivity hint, '
        '${withoutHint.inMilliseconds} ms without',
      );

      // One stream is in use (the listen), whose backoff allows about seven
      // attempts in 16 seconds.
      expect(connectionsWithHint, lessThanOrEqualTo(12));
      expect(connectionsWithoutHint, lessThanOrEqualTo(12));
      expect(withHint, lessThan(const Duration(seconds: 2)));
      // Without a hint the client is back after the rest of its backoff.
      expect(withoutHint, lessThan(const Duration(seconds: 20)));
    },
    skip:
        chaosSkipReason ??
        webTransportSkipReason(
          'the backoff of the WebChannel transport is not the one measured here',
        ),
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
