// Owner C. Threat model T1 through RealtimeConnection: a server host from the hello `h` or a
// reset `r` decides the next URL only when it passes RealtimeTarget.acceptServerHost.

import 'package:fake_async/fake_async.dart';
import 'package:firebase_database_dart/src/realtime/connection.dart';
import 'package:test/test.dart';

import '../util/connection_test_rig.dart';
import '../util/fake_ws.dart';

/// Hosts a hostile server may name; none may become the host of the next attempt.
const List<String> _refused = <String>[
  'evil.example',
  's-x.firebaseio.com@evil.example',
  's-x.firebaseio.com:444',
  's-x.firebaseio.com/x',
  's-x.firebaseio.com#',
  's-x.firebaseio.com?ac=x',
  's-x.firebaseio.com.evil.example',
  'xfirebaseio.com',
  'firebaseio.com.',
  '',
];

void _expectConfiguredUrl(ConnectionRig rig) {
  final Uri url = rig.fake.attempts.last.url;
  expect(url.host, configuredHost);
  expect(url.hasPort, isFalse);
  expect(url.userInfo, isEmpty);
  expect(url.scheme, 'wss');
}

void main() {
  group('server host from the hello (T1)', () {
    for (final String host in _refused) {
      test('"$host" is ignored', () {
        fakeAsync((FakeAsync async) {
          final ConnectionRig rig = ConnectionRig(
            async,
            appCheckToken: 'AC-MARKER',
          );
          rig.openReady(host: host).close();
          rig.open();

          _expectConfiguredUrl(rig);
          for (final ConnectAttempt attempt in rig.fake.attempts) {
            expect(attempt.url.host, configuredHost);
          }
        });
      });
    }

    test('an upper-case Google host is lowercased and used', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        rig.openReady(host: 'S-X.FIREBASEIO.COM').close();
        rig.open();

        expect(rig.fake.attempts.last.url.host, 's-x.firebaseio.com');
      });
    });

    test('a regional host is used', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        rig
            .openReady(host: 'demo-ns.europe-west1.firebasedatabase.app')
            .close();
        rig.open();

        expect(
          rig.fake.attempts.last.url.host,
          'demo-ns.europe-west1.firebasedatabase.app',
        );
      });
    });
  });

  group('server host from a reset (T1)', () {
    for (final String host in _refused) {
      test('"$host" while connecting is not followed', () {
        fakeAsync((FakeAsync async) {
          final ConnectionRig rig = ConnectionRig(async);
          rig.open();
          rig.fake.last.serverControl('r', host);
          rig.flush();

          expect(rig.fake.attempts, hasLength(1));
          expect(
            rig.delegate.disconnects.single.reason,
            DisconnectReason.other,
          );
          rig.open();
          _expectConfiguredUrl(rig);
        });
      });
    }
  });

  test('the emulator ignores h and r', () {
    fakeAsync((FakeAsync async) {
      final ConnectionRig rig = ConnectionRig(async, repoInfo: emulatorRepo);
      rig.openReady(host: 's-x.firebaseio.com').close();
      rig.open();
      rig.fake.last.serverControl('r', 's-y.firebaseio.com');
      rig.flush();
      rig.open();

      for (final ConnectAttempt attempt in rig.fake.attempts) {
        expect(attempt.url.host, '127.0.0.1');
        expect(attempt.url.port, 9000);
        expect(attempt.url.scheme, 'ws');
      }
    });
  });
}
