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
    'reset loop: at most 1 + maxResetsPerAttempt socket opens, then a failure (T2)',
    () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        rig.open();
        for (int i = 0; i < 20 && rig.delegate.disconnects.isEmpty; i++) {
          rig.fake.last.serverControl('r', 's-storm.firebaseio.com');
          rig.flush();
        }

        expect(
          rig.fake.attempts,
          hasLength(1 + const ConnectionTimings().maxResetsPerAttempt),
        );
        expect(rig.delegate.disconnects.single.reason, DisconnectReason.other);
        expect(rig.delegate.readies, isEmpty);
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
