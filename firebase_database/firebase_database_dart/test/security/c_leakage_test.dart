// Owner C. Threat model T7 and T8 for RealtimeConnection: no token, credential body, URL query,
// session id or data in a log line or toString; server text cut and escaped.

import 'package:fake_async/fake_async.dart';
import 'package:firebase_database_dart/src/realtime/connection.dart';
import 'package:test/test.dart';

import '../util/connection_test_rig.dart';

const String _marker = 'MARKER';

void main() {
  test('a full session logs no marker', () {
    fakeAsync((FakeAsync async) {
      final ConnectionRig rig = ConnectionRig(
        async,
        appCheckToken: 'AC-$_marker',
        lastSessionId: 'LS-$_marker',
      );
      final RealtimeConnection connection = rig.openReady(
        session: 'SESSION-$_marker',
      );
      for (final String action in <String>[
        'auth',
        'gauth',
        'appcheck',
        'unauth',
        'unappcheck',
      ]) {
        connection.send(<String, Object?>{
          'r': 1,
          'a': action,
          'b': <String, Object?>{'cred': 'ID-$_marker'},
        });
      }
      connection.send(<String, Object?>{
        'r': 2,
        'a': 'p',
        'b': <String, Object?>{'p': '/a', 'd': 'DATA-$_marker'},
      });
      rig.fake.last
        ..serverResponse(2, data: 'DATA-$_marker')
        ..serverPush('d', <String, Object?>{'p': 'a', 'd': 'DATA-$_marker'})
        ..serverControl('r', 'evil-$_marker.example');
      rig.flush();

      expect(rig.lines, contains('auth (contents hidden)'));
      expect(rig.lines, contains('appcheck (contents hidden)'));
      for (final String line in rig.lines) {
        expect(line, isNot(contains(_marker)));
      }
      expect(connection.toString(), isNot(contains(_marker)));
    });
  });

  test('a shutdown reason is cut and has no control characters in the log', () {
    fakeAsync((FakeAsync async) {
      final ConnectionRig rig = ConnectionRig(async);
      rig.openReady();
      rig.fake.last.serverControl('s', 'line1\nline2\u0000${'y' * 5000}');
      rig.flush();

      final String line = rig.lines.singleWhere(
        (String l) => l.startsWith('server shutdown'),
      );
      expect(line, isNot(contains('\n')));
      expect(line, isNot(contains('\u0000')));
      expect(line.length, lessThan(1024 + 200));
      expect(rig.delegate.kills.single.reason, isNot(contains('\n')));
    });
  });

  test('an unknown control type is cleaned before it is logged', () {
    fakeAsync((FakeAsync async) {
      final ConnectionRig rig = ConnectionRig(async);
      rig.openReady();
      rig.fake.last.serverControl('zz\n${'q' * 5000}', <String, Object?>{});
      rig.flush();

      final String line = rig.lines.singleWhere(
        (String l) => l.startsWith('unknown control'),
      );
      expect(line, isNot(contains('\n')));
      expect(line.length, lessThan(1024 + 200));
    });
  });
}
