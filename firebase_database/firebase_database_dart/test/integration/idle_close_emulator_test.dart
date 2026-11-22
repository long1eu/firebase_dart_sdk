// Owner U. A measurement (review L2): does the emulator's 120 s idle close count the server's own
// pushes? The probe measured only that a connection that sends nothing is closed after exactly
// 120 s ("Keep-alive and idle behaviour"); here the client sends nothing after its listen while
// REST writes to the listened path every 20 s. Prints the time of the close, or that none came
// within 150 s. Long: tagged emulator-slow, excluded by default.
@Tags(<String>['emulator', 'emulator-slow'])
@TestOn('vm')
library;

import 'dart:async';

import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/realtime/connection_timings.dart';
import 'package:test/test.dart';

import '../util/chaos_proxy.dart';
import '../util/ws_tap.dart';
import 'emulator_rig.dart';

void main() {
  group('idle close measurement', skip: emulatorSkipReason, () {
    test(
      'a receive-only client with a push every 20 s: closed at about 120 s?',
      () async {
        final EmulatorRig rig = EmulatorRig.create();
        final ChaosProxy proxy = await rig.proxy();
        final WsFrameTap tap = WsFrameTap(proxy);
        // Nothing of the client's own: no keep-alive, no probe ping, no extra ping.
        final RigClient client = await rig.open(
          proxy: proxy,
          timings: const ConnectionTimings(
            keepAlive: Duration(minutes: 10),
            idleProbeAfter: Duration(minutes: 10),
            extraPingDelay: Duration(minutes: 10),
            healthyTimeout: Duration(minutes: 10),
            reconnectMin: Duration(minutes: 10),
          ),
        );
        final Ack ack = await client.first(client.listen(defaultSpec('/l2')));
        expect(ack.status, statusOk);

        final Stopwatch sinceLastSend = Stopwatch()..start();
        int framesUp = 0;
        int framesDown = 0;
        final StreamSubscription<TapFrame> frames = tap.frames.listen((
          TapFrame f,
        ) {
          if (f.direction == ChaosDirection.up) {
            framesUp++;
          } else {
            framesDown++;
          }
        });
        addTearDown(frames.cancel);

        int writes = 0;
        final Timer writer = Timer.periodic(const Duration(seconds: 20), (_) {
          writes++;
          unawaited(rig.write('/l2/n', writes));
        });
        addTearDown(writer.cancel);

        Duration? closedAt;
        while (sinceLastSend.elapsed < const Duration(seconds: 150)) {
          if (client.delegate.callsOf('disconnect').isNotEmpty) {
            closedAt = sinceLastSend.elapsed;
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        writer.cancel();

        // ignore: avoid_print, the measurement is the output of this test.
        print(
          closedAt == null
              ? 'L2: no close within 150 s of the last client frame '
                    '($writes pushes, $framesDown frames down, $framesUp up): '
                    'the server counts its own pushes'
              : 'L2: closed ${closedAt.inMilliseconds} ms after the last client '
                    'frame ($writes pushes, $framesDown frames down, $framesUp '
                    'up, reason ${client.disconnectReasons}): pushes do not '
                    'count',
        );
        expect(framesUp, 0, reason: 'the client really sent nothing');
        expect(
          client.updatesAt('/l2/n'),
          isNotEmpty,
          reason: 'the pushes reached the client',
        );
      },
      timeout: const Timeout(Duration(seconds: 200)),
    );
  });
}
