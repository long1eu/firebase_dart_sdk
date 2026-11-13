// The built-in connectivity detector under a network that is gone long enough
// for the backoff of the listen stream to grow: without a hint the client
// waits for the rest of its backoff after the network is back, with a hint it
// reconnects at once. The interface list is simulated: the test cannot unplug
// the machine.

import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/connectivity_change_detector.dart';
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
  Future<Duration> recoveryTime({required bool hint}) async {
    final Set<String> addresses = <String>{};
    int signals = 0;
    final ConnectivityChangeDetector detector = ConnectivityChangeDetector(
      listAddresses: () async => Set<String>.of(addresses),
      pollInterval: const Duration(milliseconds: 100),
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

      await env.proxy.unplug();
      await Future<void>.delayed(outage);
      expect(
        detector.isRunning,
        isTrue,
        reason: 'the stream is failing, the detector looks for changes',
      );
      expect(signals, 0);

      // The backend moved on while the client was away.
      await serverDoc.set(<String, Object?>{'n': 1});

      final Stopwatch stopwatch = Stopwatch()..start();
      await env.proxy.plug();
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
      final Duration withoutHint = await recoveryTime(hint: false);
      // ignore: avoid_print
      print(
        'Recovery after a ${outage.inSeconds}s outage: '
        '${withHint.inMilliseconds} ms with a connectivity hint, '
        '${withoutHint.inMilliseconds} ms without',
      );

      // The poll takes up to 100 ms, then the stream is opened and the listen is
      // answered.
      expect(withHint, lessThan(const Duration(seconds: 2)));
      // Without a hint the client waits for the rest of a backoff of several
      // seconds; how much is left when the network comes back is random.
      expect(withHint, lessThan(withoutHint));
    },
    skip:
        chaosSkipReason ??
        webTransportSkipReason(
          'the backoff of the WebChannel transport is not the one measured here',
        ),
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
