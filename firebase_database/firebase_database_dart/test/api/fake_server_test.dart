// FakeDatabaseServer behaviour the shim's tests rely on (coordinator rulings a to d) and the auth tokens it
// records.

import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:test/test.dart';

import 'support/fake_time.dart';
import 'support/harness.dart';

void main() {
  void scenario(String name, void Function(Harness h) body) {
    test(name, () {
      fakeTime((FakeTime time) => body(Harness(time)));
    });
  }

  group('(a) path forms', () {
    scenario('answerListen, push and cancelListen take a/b and /a/b', (
      Harness h,
    ) {
      h.listen('S1', h.ref('a/b').onValue);
      h.settle();
      h.server.answerListen('/a/b', 1);
      h.settle();
      h.server.push('a/b', 2);
      h.settle();
      h.server.push('/a/b', 3);
      h.settle();
      h.server.cancelListen('/a/b', 'permission_denied');
      h.settle();
      expect(h.log, <String>[
        'S1:V(1)',
        'S1:V(2)',
        'S1:V(3)',
        'S1:E(permission-denied)',
        'S1:done',
      ]);
      expect(h.server.requests, contains('q /a/b'));
    });

    scenario('failListen takes /a', (Harness h) {
      h.listen('S1', h.ref('a').onValue);
      h.settle();
      h.server.failListen('/a', 'permission_denied');
      h.settle();
      expect(h.log, <String>['S1:E(permission-denied)', 'S1:done']);
    });

    scenario('answerGet and failGet take both forms', (Harness h) {
      h.trackValue('G1', h.ref('a').get());
      h.trackValue('G2', h.ref('b').get());
      h.settle();
      h.server.answerGet('/a', 1);
      h.server.failGet('b', 'permission_denied');
      h.settle();
      expect(
        h.log,
        unorderedEquals(<String>['G1:=1', 'G2:E(permission-denied)']),
      );
      expect(h.server.requests, containsAll(<String>['g /a', 'g /b']));
    });

    scenario('requests always print the leading slash', (Harness h) {
      h.listen('S1', h.ref('x/y').onValue);
      h.ref('w').set(1);
      h.listen('S2', h.db.ref().onValue);
      h.settle();
      expect(h.server.requests, everyElement(matches(RegExp(r'^[a-z]+ /'))));
      expect(h.server.requests, containsAll(<String>['q /x/y', 'p /w', 'q /']));
    });
  });

  group('(b) queries that load all data', () {
    for (final String order in <String>['child', 'value', 'key', 'priority']) {
      scenario('orderBy$order with no range or limit uses the default listen', (
        Harness h,
      ) {
        final DatabaseReference r = h.ref('a');
        final Query q = switch (order) {
          'child' => r.orderByChild('n'),
          'value' => r.orderByValue(),
          'key' => r.orderByKey(),
          _ => r.orderByPriority(),
        };
        h.listen('S1', q.onValue);
        h.settle();
        expect(
          h.server.requests.where((String r) => r.startsWith('q ')),
          <String>['q /a'],
        );
        h.server.answerListen('/a', <String, Object?>{'x': 1});
        h.settle();
        expect(h.log, <String>['S1:V({x:1})']);
      });
    }
  });

  group('(c) keepSynced', () {
    scenario('true twice sends one listen; false once stops it', (Harness h) {
      h.ref('a').keepSynced(true);
      h.ref('a').keepSynced(true);
      h.settle();
      expect(h.server.requests.where((String r) => r == 'q /a'), hasLength(1));
      h.ref('a').keepSynced(false);
      h.settle();
      expect(h.server.requests.last, 'n /a');
    });
  });

  group('(d) filtered listens', () {
    scenario('requests print the wire query object', (Harness h) {
      h.listen('S1', h.ref('a').limitToFirst(2).onValue);
      h.settle();
      expect(h.server.requests, contains('q /a {"l":2,"vf":"l"}'));
    });

    scenario('query addresses a filtered listen', (Harness h) {
      h.listen('S1', h.ref('a').limitToFirst(2).onValue);
      h.settle();
      h.server.answerListen(
        'a',
        <String, Object?>{'x': 1},
        query: <String, Object?>{'l': 2, 'vf': 'l'},
      );
      h.settle();
      expect(h.log, <String>['S1:V({x:1})']);
    });

    scenario('without query the default listen at the path is addressed', (
      Harness h,
    ) {
      h.listen('S1', h.ref('a').limitToFirst(2).onValue);
      h.listen('S2', h.ref('a').limitToLast(1).onValue);
      h.listen('S3', h.ref('a').onValue);
      h.settle();
      // The default listen covers the filtered queries, so the client listens to it alone.
      h.server.answerListen('a', <String, Object?>{'x': 1, 'y': 2});
      h.settle();
      expect(h.named('S3'), <String>['S3:V({x:1,y:2})']);
    });

    scenario('the single open listen is addressed without query', (Harness h) {
      h.listen('S1', h.ref('a').limitToLast(1).onValue);
      h.settle();
      h.server.answerListen('a', <String, Object?>{'x': 1});
      h.settle();
      expect(h.log, <String>['S1:V({x:1})']);
    });

    scenario('two filtered listens and no query is ambiguous', (Harness h) {
      h.listen('S1', h.ref('a').limitToFirst(1).onValue);
      h.listen('S2', h.ref('a').limitToLast(1).onValue);
      h.settle();
      expect(() => h.server.answerListen('a', 1), throwsStateError);
      expect(
        () => h.server.failListen('a', 'permission_denied'),
        throwsStateError,
      );
      h.server.failListen(
        'a',
        'permission_denied',
        query: <String, Object?>{'l': 1, 'vf': 'r'},
      );
      h.settle();
      expect(h.log, <String>['S2:E(permission-denied)', 'S2:done']);
    });
  });

  group('fidelity', () {
    scenario('ackLastWrite resolves the timestamp from serverTime', (
      Harness h,
    ) {
      h.server.serverTime = DateTime.fromMillisecondsSinceEpoch(1000);
      h.listenAnswered('S1', h.ref('t').onValue, 't', null);
      h.log.clear();
      h.ref('t').set(ServerValue.timestamp);
      h.settle();
      h.log.clear();
      h.server.ackLastWrite();
      h.settle();
      expect(h.log, <String>['S1:V(1000)']);
    });

    scenario('ackLastWrite resolves an increment against the server value', (
      Harness h,
    ) {
      h.listenAnswered('S1', h.ref('n').onValue, 'n', 10);
      h.ref('n').set(ServerValue.increment(1));
      h.settle();
      h.log.clear();
      h.server.push('n', 20);
      h.settle();
      h.server.ackLastWrite();
      h.settle();
      expect(h.log.last, 'S1:V(21)');
    });
  });

  group('receivedAuthTokens', () {
    scenario('one null per connection without a user', (Harness h) {
      expect(h.server.receivedAuthTokens, <String?>[null]);
      h.goDown();
      h.reconnect();
      expect(h.server.receivedAuthTokens, <String?>[null, null]);
      expect(
        () => h.server.receivedAuthTokens.add('x'),
        throwsUnsupportedError,
      );
    });

    scenario('revokeAuth reconnects and sends a token again', (Harness h) {
      h.server.revokeAuth();
      h.reconnect();
      expect(h.server.receivedAuthTokens, hasLength(2));
    });
  });
}
