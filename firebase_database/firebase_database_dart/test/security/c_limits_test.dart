// Owner C. Threat model T2 (reset storm) and T9-T11 as RealtimeConnection sees them: a violation
// closes the connection as an ordinary failure and never throws into the application's zone.

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_database_dart/src/realtime/connection.dart';
import 'package:firebase_database_dart/src/realtime/connection_timings.dart';
import 'package:test/test.dart';

import '../util/connection_test_rig.dart';

void main() {
  test(
    'a reset storm ends the attempt after maxResetsPerAttempt resets, however slow (T2)',
    () {
      // connection_test.dart has the storm in one turn; here each reset comes just before the
      // socket's connect timeout, the slowest storm that still keeps the attempt connecting.
      fakeAsync((FakeAsync async) {
        const ConnectionTimings timings = ConnectionTimings(
          healthyTimeout: Duration(hours: 1),
        );
        final ConnectionRig rig = ConnectionRig(async, timings: timings);
        final Duration justBefore =
            timings.connectTimeout - const Duration(seconds: 1);
        rig.open();
        for (int i = 0; i < 20 && rig.delegate.disconnects.isEmpty; i++) {
          async.elapse(justBefore);
          rig.fake.last.serverControl('r', 's-storm$i.firebaseio.com');
          rig.flush();
        }

        expect(rig.fake.attempts, hasLength(1 + timings.maxResetsPerAttempt));
        expect(rig.delegate.disconnects.single.reason, DisconnectReason.other);
        expect(async.elapsed, justBefore * (1 + timings.maxResetsPerAttempt));
        expect(rig.delegate.readies, isEmpty);
        expect(rig.target.internalHost, configuredHost);
        expect(async.pendingTimers, isEmpty);
      });
    },
  );

  test(
    'a message over maxMessageBytes closes the connection without an error in the zone (T9)',
    () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(
          async,
          timings: const ConnectionTimings(maxMessageBytes: 1000),
        );
        final List<Object> errors = <Object>[];
        runZonedGuarded(() {
          rig.openReady();
          rig.fake.last.serverResponse(1, data: 'x' * 5000);
          rig.flush();
        }, (Object error, StackTrace _) => errors.add(error));

        expect(errors, isEmpty);
        expect(rig.delegate.data, isEmpty);
        expect(rig.delegate.disconnects.single.reason, DisconnectReason.other);
      });
    },
  );

  test(
    '100 000 nested arrays close the connection without an error in the zone (T10)',
    () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        final List<Object> errors = <Object>[];
        runZonedGuarded(() {
          rig.openReady();
          rig.fake.last.serverText(
            '{"t":"d","d":${'[' * 100000}${']' * 100000}}',
          );
          rig.flush();
        }, (Object error, StackTrace _) => errors.add(error));

        expect(errors, isEmpty);
        expect(rig.delegate.data, isEmpty);
        expect(rig.delegate.disconnects.single.reason, DisconnectReason.other);
      });
    },
  );

  test('a hello with a non-integer ts is a protocol error (T11)', () {
    fakeAsync((FakeAsync async) {
      final ConnectionRig rig = ConnectionRig(async);
      rig.open();
      rig.fake.last.serverText(
        '{"t":"c","d":{"t":"h","d":{"ts":1e400,"v":"5","h":"x","s":"s"}}}',
      );
      rig.flush();

      expect(rig.delegate.readies, isEmpty);
      expect(rig.delegate.disconnects.single.reason, DisconnectReason.other);
    });
  });
}
