// Two writes at one path below a server leaf, then the server's answers in the order the
// emulator sent them (rtdb/from_helper/reports/leaf_write_js_vs_dart.md). The JS SDK 13.4.0
// keeps a wrong value in both forms until the listener is attached again: `1` where the server
// holds null (offline form) and null where the server holds `1` (refused form). Here the view
// ends with the server's value: ViewProcessor rebuilds the event cache when a server change
// lands below a leaf it holds (decisions section 25, row 26), and applies the server leaf when a
// write below it is acknowledged (row 25).
import 'package:test/test.dart';

import 'repo_harness.dart';

void main() {
  test('offline: a child written below a server leaf and then deleted ends '
      'with the server null', () async {
    final RepoHarness h = RepoHarness(connected: false);
    h.repo.interrupt();
    h.listen('W', 'r');
    h.set('r/c', <String, Object?>{'v': 1}, name: 'P1');
    h.set('r/c', null, name: 'P2');
    await settle();
    expect(h.log, isEmpty);
    h.repo.resume();
    h.server.connect();
    await settle();
    // The frames after goOnline: d r 1, the listen's ok, then each put pushed back at r/c
    // before its ok.
    h.server.deliverDataUpdate('r', 1);
    h.server.respond(h.server.callsOf('listen').single);
    await settle();
    h.server.ackWrite(h.server.callsOf('put').first);
    await settle();
    h.server.ackWrite(h.server.callsOf('put').last);
    await settle();
    expect(h.server.dataAt('r'), isNull);
    // JS: only W:V(1), and the view keeps 1.
    expect(h.log, <String>['W:V(1)', 'P1:ok', 'W:V(null)', 'P2:ok']);
  });

  test('refused: a child written below a server leaf, refused, and then '
      'deleted ends with the server leaf', () async {
    final RepoHarness h = RepoHarness();
    h.listen('W', 'r');
    h.answer('r', 1);
    await settle();
    h.set('r/b', 1, name: 'P1');
    h.set('r/b', null, name: 'P2');
    await settle();
    // The frames: the first put refused, then the second pushed back at r/b before its ok.
    h.server.respond(
      h.server.callsOf('put').first,
      status: 'permission_denied',
      data: 'Permission denied',
    );
    await settle();
    h.server.ackWrite(h.server.callsOf('put').last);
    await settle();
    expect(h.server.dataAt('r'), 1);
    // JS: no event after W:V(null), and the view keeps null.
    expect(h.log, <String>[
      'W:V(1)',
      'W:V({"b":1})',
      'W:V(null)',
      'P1:E(permission-denied)',
      'W:V(1)',
      'P2:ok',
    ]);
  });
}
