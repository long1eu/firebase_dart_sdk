// Owner C. Liveness on its own and through RealtimeConnection (test plan B-3.1h, B-3.1i, B-3.4a,
// B-3.4b).

import 'package:fake_async/fake_async.dart';
import 'package:firebase_database_dart/src/realtime/connection.dart';
import 'package:firebase_database_dart/src/realtime/connection_timings.dart';
import 'package:firebase_database_dart/src/realtime/liveness.dart';
import 'package:test/test.dart';

import '../util/connection_test_rig.dart';
import '../util/fake_ws.dart';

/// A Liveness with recorded callbacks. The keep-alive callback reports its frame back, as the
/// connection does.
final class _Probe {
  _Probe(this.async, {ConnectionTimings timings = const ConnectionTimings()}) {
    liveness = Liveness(
      timings: timings,
      sendKeepAlive: () {
        keepAlives.add(async.elapsed);
        liveness.onFrameSent(1);
      },
      sendPing: () {
        pings.add(async.elapsed);
        liveness.onFrameSent(30);
      },
      close: (DisconnectReason reason) {
        closes.add((reason, async.elapsed));
        liveness.stop();
      },
    );
  }

  final FakeAsync async;
  late final Liveness liveness;
  final List<Duration> keepAlives = <Duration>[];
  final List<Duration> pings = <Duration>[];
  final List<(DisconnectReason, Duration)> closes =
      <(DisconnectReason, Duration)>[];
}

const Duration _s = Duration(seconds: 1);

/// Timings where only the timer under test can fire within a few minutes.
const ConnectionTimings _keepAliveOnly = ConnectionTimings(
  healthyTimeout: Duration(hours: 1),
  idleProbeAfter: Duration(hours: 1),
);

void main() {
  group('keep-alive (B-3.1h)', () {
    test('sends 0 after 45 s of silence and re-arms', () {
      fakeAsync((FakeAsync async) {
        final _Probe probe = _Probe(async, timings: _keepAliveOnly)
          ..liveness.start();
        async.elapse(_s * 44);
        expect(probe.keepAlives, isEmpty);
        async.elapse(_s);
        async.elapse(_s * 45);

        expect(probe.keepAlives, <Duration>[_s * 45, _s * 90]);
      });
    });

    test('a sent frame postpones it', () {
      fakeAsync((FakeAsync async) {
        final _Probe probe = _Probe(async, timings: _keepAliveOnly)
          ..liveness.start();
        async.elapse(_s * 30);
        probe.liveness.onFrameSent(10);
        async.elapse(_s * 44);
        expect(probe.keepAlives, isEmpty);
        async.elapse(_s);

        expect(probe.keepAlives, <Duration>[_s * 75]);
      });
    });

    test('a received frame postpones it', () {
      fakeAsync((FakeAsync async) {
        final _Probe probe = _Probe(async, timings: _keepAliveOnly)
          ..liveness.start();
        async.elapse(_s * 30);
        probe.liveness.onFrameReceived(10);
        async.elapse(_s * 45);

        expect(probe.keepAlives, <Duration>[_s * 75]);
      });
    });

    test('re-arms even when the send could not report a frame', () {
      fakeAsync((FakeAsync async) {
        int sent = 0;
        final Liveness liveness = Liveness(
          timings: _keepAliveOnly,
          sendKeepAlive: () => sent++,
          sendPing: () {},
          close: (_) {},
        )..start();
        async.elapse(_s * 90);

        expect(sent, 2);
        liveness.stop();
      });
    });

    test('stop cancels it and nothing re-arms afterwards', () {
      fakeAsync((FakeAsync async) {
        final _Probe probe = _Probe(async, timings: _keepAliveOnly)
          ..liveness.start();
        probe.liveness.stop();
        probe.liveness
          ..onFrameSent(1)
          ..onFrameReceived(1)
          ..onHello()
          ..onResponse(isPong: true)
          ..start();
        async.elapse(const Duration(minutes: 10));

        expect(probe.keepAlives, isEmpty);
        expect(probe.pings, isEmpty);
        expect(probe.closes, isEmpty);
        expect(async.pendingTimers, isEmpty);
      });
    });
  });

  group('health (B-3.4a)', () {
    const ConnectionTimings noProbe = ConnectionTimings(
      idleProbeAfter: Duration(hours: 1),
    );

    test('closes as other when not healthy at 30 s', () {
      fakeAsync((FakeAsync async) {
        final _Probe probe = _Probe(async, timings: noProbe)..liveness.start();
        probe.liveness.onResponse();
        async.elapse(_s * 29);
        expect(probe.closes, isEmpty);
        async.elapse(_s);

        expect(probe.closes, <(DisconnectReason, Duration)>[
          (DisconnectReason.other, _s * 30),
        ]);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('two responses make it healthy', () {
      fakeAsync((FakeAsync async) {
        final _Probe probe = _Probe(async, timings: noProbe)..liveness.start();
        probe.liveness
          ..onResponse()
          ..onResponse(isPong: true);
        async.elapse(const Duration(minutes: 1));

        expect(probe.liveness.isHealthy, isTrue);
        expect(probe.closes, isEmpty);
      });
    });

    test('more than 100 KiB received counts as healthy', () {
      fakeAsync((FakeAsync async) {
        final _Probe probe = _Probe(async, timings: noProbe)..liveness.start();
        probe.liveness.onFrameReceived(100 * 1024 + 1);
        async.elapse(_s * 30);

        expect(probe.liveness.isHealthy, isTrue);
        expect(probe.closes, isEmpty);
      });
    });

    test('exactly 100 KiB received is not enough', () {
      fakeAsync((FakeAsync async) {
        final _Probe probe = _Probe(async, timings: noProbe)..liveness.start();
        probe.liveness.onFrameReceived(100 * 1024);
        async.elapse(_s * 30);

        expect(probe.closes.single.$1, DisconnectReason.other);
      });
    });

    test(
      'more than 10 KiB sent leaves it alone, unhealthy, never checked again',
      () {
        fakeAsync((FakeAsync async) {
          final _Probe probe = _Probe(async, timings: noProbe)
            ..liveness.start();
          probe.liveness.onFrameSent(10 * 1024 + 1);
          async.elapse(const Duration(minutes: 5));

          expect(probe.liveness.isHealthy, isFalse);
          expect(probe.closes, isEmpty);
        });
      },
    );
  });

  group('extra ping (B-3.4b)', () {
    const ConnectionTimings noProbe = ConnectionTimings(
      idleProbeAfter: Duration(hours: 1),
      healthyTimeout: Duration(hours: 1),
    );

    test(
      '5 s after the hello a ping goes out, and again on each pong until healthy',
      () {
        fakeAsync((FakeAsync async) {
          final _Probe probe = _Probe(async, timings: noProbe);
          probe.liveness
            ..start()
            ..onHello();
          async.elapse(_s * 4);
          expect(probe.pings, isEmpty);
          async.elapse(_s);
          expect(probe.pings, <Duration>[_s * 5]);

          probe.liveness.onResponse(isPong: true);
          expect(probe.pings, hasLength(2));
          probe.liveness.onResponse(isPong: true);
          expect(probe.liveness.isHealthy, isTrue);
          expect(probe.pings, hasLength(2));
          probe.liveness.onResponse(isPong: true);
          expect(probe.pings, hasLength(2));
        });
      },
    );

    test('a data response counts but does not ping', () {
      fakeAsync((FakeAsync async) {
        final _Probe probe = _Probe(async, timings: noProbe);
        probe.liveness
          ..start()
          ..onHello()
          ..onResponse();
        expect(probe.pings, isEmpty);
        async.elapse(_s * 5);
        expect(probe.pings, hasLength(1));
        probe.liveness.onResponse();
        expect(probe.liveness.isHealthy, isTrue);
        expect(probe.pings, hasLength(1));
      });
    });

    test('no ping when healthy before 5 s', () {
      fakeAsync((FakeAsync async) {
        final _Probe probe = _Probe(async, timings: noProbe);
        probe.liveness
          ..start()
          ..onHello()
          ..onResponse()
          ..onResponse();
        async.elapse(_s * 10);

        expect(probe.pings, isEmpty);
      });
    });

    test('a transport that needs no responses is healthy at the hello', () {
      fakeAsync((FakeAsync async) {
        final _Probe probe = _Probe(
          async,
          timings: const ConnectionTimings(
            responsesRequiredToBeHealthy: 0,
            idleProbeAfter: Duration(hours: 1),
          ),
        );
        probe.liveness
          ..start()
          ..onHello();
        async.elapse(_s * 40);

        expect(probe.liveness.isHealthy, isTrue);
        expect(probe.pings, isEmpty);
        expect(probe.closes, isEmpty);
      });
    });
  });

  group('dead-link probe (B-3.1i)', () {
    const ConnectionTimings healthy = ConnectionTimings(
      responsesRequiredToBeHealthy: 0,
    );

    test(
      'pings after 30 s without inbound and closes as deadLink 15 s later',
      () {
        fakeAsync((FakeAsync async) {
          final _Probe probe = _Probe(async, timings: healthy);
          probe.liveness
            ..start()
            ..onHello();
          async.elapse(_s * 30);
          expect(probe.pings, <Duration>[_s * 30]);
          async.elapse(_s * 14);
          expect(probe.closes, isEmpty);
          async.elapse(_s);

          expect(probe.closes, <(DisconnectReason, Duration)>[
            (DisconnectReason.deadLink, _s * 45),
          ]);
          expect(async.pendingTimers, isEmpty);
        });
      },
    );

    test('an inbound frame answers the probe and re-arms it', () {
      fakeAsync((FakeAsync async) {
        final _Probe probe = _Probe(async, timings: healthy);
        probe.liveness
          ..start()
          ..onHello();
        async.elapse(_s * 40);
        probe.liveness.onFrameReceived(30);
        async.elapse(_s * 29);
        expect(probe.pings, <Duration>[_s * 30]);
        async.elapse(_s);
        expect(probe.pings, <Duration>[_s * 30, _s * 70]);
        expect(probe.closes, isEmpty);
      });
    });

    test('outbound frames do not count as proof of life', () {
      fakeAsync((FakeAsync async) {
        final _Probe probe = _Probe(async, timings: healthy);
        probe.liveness
          ..start()
          ..onHello();
        for (int i = 0; i < 9; i++) {
          async.elapse(_s * 5);
          probe.liveness.onFrameSent(100);
        }

        expect(probe.closes.single.$1, DisconnectReason.deadLink);
      });
    });

    test('is not armed before the hello', () {
      fakeAsync((FakeAsync async) {
        final _Probe probe = _Probe(
          async,
          timings: const ConnectionTimings(healthyTimeout: Duration(hours: 1)),
        )..liveness.start();
        probe.liveness.onFrameReceived(5);
        async.elapse(const Duration(minutes: 2));

        expect(probe.pings, isEmpty);
        expect(probe.closes, isEmpty);
      });
    });
  });

  group('probeNow', () {
    const ConnectionTimings healthy = ConnectionTimings(
      responsesRequiredToBeHealthy: 0,
    );
    const String ping = '{"t":"c","d":{"t":"p","d":{}}}';

    int pings(FakeWsChannel channel) =>
        channel.sentFrames.where((SentFrame f) => f.text == ping).length;

    test('pings at once and closes as deadLink after the probe timeout', () {
      fakeAsync((FakeAsync async) {
        final _Probe probe = _Probe(async, timings: healthy);
        probe.liveness
          ..start()
          ..onHello();
        async.elapse(_s * 3);
        probe.liveness.probeNow();
        expect(probe.pings, <Duration>[_s * 3]);
        async.elapse(_s * 15);

        expect(probe.closes, <(DisconnectReason, Duration)>[
          (DisconnectReason.deadLink, _s * 18),
        ]);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('is a no-op before the hello', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async, timings: healthy);
        final RealtimeConnection connection = rig.open();
        connection.probeNow();
        async.elapse(_s * 20);

        expect(pings(rig.fake.last), 0);
        expect(rig.delegate.disconnects, isEmpty);

        final _Probe probe = _Probe(async, timings: healthy)..liveness.start();
        probe.liveness.probeNow();
        expect(probe.pings, isEmpty);
        probe.liveness.stop();
      });
    });

    test('is a no-op while a probe is outstanding and keeps its deadline', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async, timings: healthy);
        final RealtimeConnection connection = rig.openReady();
        connection.probeNow();
        async.elapse(_s * 10);
        connection.probeNow();
        expect(pings(rig.fake.last), 1);
        async.elapse(_s * 5);

        expect(
          rig.delegate.disconnects.single.reason,
          DisconnectReason.deadLink,
        );
      });
    });

    test(
      'after the close it starts nothing: one disconnect, no ping, no timer',
      () {
        fakeAsync((FakeAsync async) {
          final ConnectionRig rig = ConnectionRig(async, timings: healthy);
          final RealtimeConnection connection = rig.openReady()..probeNow();
          async.elapse(_s * 15);
          expect(
            rig.delegate.disconnects.single.reason,
            DisconnectReason.deadLink,
          );

          connection.probeNow();
          async.elapse(const Duration(minutes: 2));

          expect(pings(rig.fake.last), 1);
          expect(rig.delegate.disconnects, hasLength(1));
          expect(rig.fake.attempts, hasLength(1));
          expect(async.pendingTimers, isEmpty);
        });
      },
    );

    test('a pong after probeNow keeps the connection', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async, timings: healthy);
        final RealtimeConnection connection = rig.openReady()..probeNow();
        async.elapse(_s * 2);
        rig.fake.last.serverControl('o');
        rig.flush();
        async.elapse(_s * 20);

        expect(connection.isConnected, isTrue);
        expect(rig.delegate.disconnects, isEmpty);
        // The next routine probe comes idleProbeAfter after the pong.
        expect(pings(rig.fake.last), 1);
        async.elapse(_s * 10);
        expect(pings(rig.fake.last), 2);
      });
    });
  });

  group('through RealtimeConnection', () {
    test(
      'keep-alive 0 is re-armed by every send and receive and stops at close',
      () {
        fakeAsync((FakeAsync async) {
          final ConnectionRig rig = ConnectionRig(async);
          final RealtimeConnection connection = rig.openReady();
          final FakeWsChannel channel = rig.fake.last;
          // Healthy, so the extra ping stays quiet; inbound every 20 s keeps the probe quiet.
          channel
            ..serverResponse(1)
            ..serverResponse(2);
          rig.flush();
          async.elapse(_s * 20);
          connection.send(<String, Object?>{
            'r': 3,
            'a': 'n',
            'b': <String, Object?>{'p': '/'},
          });
          async.elapse(_s * 20);
          channel.serverResponse(3);
          rig.flush();
          async.elapse(_s * 44);
          // Sent at 20 s, received at 40 s, probe ping sent at 70 s: never 45 s of silence.
          expect(
            channel.sentFrames.where((SentFrame f) => f.text == '0'),
            isEmpty,
          );
          connection.close();
          async.elapse(const Duration(minutes: 5));

          expect(
            channel.sentFrames.where((SentFrame f) => f.text == '0'),
            isEmpty,
          );
          expect(async.pendingTimers, isEmpty);
        });
      },
    );

    test('keep-alive 0 is sent on a quiet socket before the hello', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(
          async,
          timings: const ConnectionTimings(
            connectTimeout: Duration(minutes: 5),
            healthyTimeout: Duration(minutes: 5),
          ),
        );
        rig.open();
        async.elapse(_s * 91);

        expect(
          rig.fake.last.sentFrames
              .where((SentFrame f) => f.text == '0')
              .map((SentFrame f) => f.at),
          <Duration>[_s * 45, _s * 90],
        );
      });
    });

    test('a silent link is closed as deadLink after the probe', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        rig.openReady();
        final FakeWsChannel channel = rig.fake.last
          ..serverResponse(1)
          ..serverResponse(2);
        rig.flush();
        // The fake server says nothing unless told to: the link is silent from here on.
        async.elapse(_s * 30);
        expect(channel.sentFrames.last.text, '{"t":"c","d":{"t":"p","d":{}}}');
        expect(rig.delegate.disconnects, isEmpty);
        async.elapse(_s * 15);

        expect(
          rig.delegate.disconnects.single.reason,
          DisconnectReason.deadLink,
        );
        expect(channel.isClosed || channel.abandoned, isTrue);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('a pong answers the probe', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        final RealtimeConnection connection = rig.openReady();
        final FakeWsChannel channel = rig.fake.last
          ..serverResponse(1)
          ..serverResponse(2);
        rig.flush();
        for (int i = 0; i < 6; i++) {
          async.elapse(_s * 31);
          channel.serverControl('o');
          rig.flush();
        }

        expect(connection.isConnected, isTrue);
        expect(rig.delegate.disconnects, isEmpty);
      });
    });

    test('an unhealthy connection pings at 5 s and closes at 30 s', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        rig.open();
        async.elapse(_s);
        rig.fake.last.serverHello(ts: 1, h: configuredHost);
        rig.flush();
        async.elapse(_s * 5);
        expect(
          rig.fake.last.sentFrames.where(
            (SentFrame f) => f.text.contains('"t":"p"'),
          ),
          hasLength(1),
        );
        async.elapse(_s * 24);

        expect(rig.delegate.disconnects.single.reason, DisconnectReason.other);
        expect(async.pendingTimers, isEmpty);
      });
    });
  });
}
