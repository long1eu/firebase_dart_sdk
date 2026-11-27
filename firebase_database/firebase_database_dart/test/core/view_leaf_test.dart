// Leaves above a write: the server turns a listened map into a leaf, or a write lands below a
// server leaf. Found by the transaction and write model tests.
import 'package:test/test.dart';

import 'repo_harness.dart';

void main() {
  test('server leaf over a pending child write survives the ack', () async {
    final RepoHarness h = RepoHarness();
    h.listen('S', 'a');
    h.answer('a', <String, Object?>{'x': 0});
    await settle();
    h.set('a/x', 10, name: 'W');
    await settle();
    h.server.deliverDataUpdate('a', 10);
    await settle();
    h.server.respond(h.server.callsOf('put').single);
    await settle();
    expect(h.log, <String>['S:V({"x":0})', 'S:V({"x":10})', 'S:V(10)', 'W:ok']);
  });

  test('a write and its removal below a server leaf end with the server '
      'data', () async {
    final RepoHarness h = RepoHarness();
    h.listen('S', 'a');
    h.answer('a', 38);
    await settle();
    h.set('a/b/c', 35, name: 'W1');
    h.set('a/b/c', null, name: 'W2');
    await settle();
    // The server sends a again (a listen replayed on reconnect).
    h.server.deliverDataUpdate('a', 38);
    await settle();
    h.server.ackWrite(h.server.callsOf('put').first);
    await settle();
    h.server.ackWrite(h.server.callsOf('put').last);
    await settle();
    expect(h.server.dataAt('a'), isNull);
    // The fourth event shows the leaf again: the write tree keeps only the later write at a/b/c,
    // and removing a child of a leaf keeps the leaf (as in JS and Android). The last event is
    // the server's data.
    expect(h.log, <String>[
      'S:V(38)',
      'S:V({"b":{"c":35}})',
      'S:V(null)',
      'S:V(38)',
      'W1:ok',
      'S:V(null)',
      'W2:ok',
    ]);
  });
}
