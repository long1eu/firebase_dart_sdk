// The scenario table of the API contract (14_api_contract.md, section 4.4), rows D1 to D58, run through
// databaseWithFakeServer inside a fake clock. Every setup starts connected and ends settled with an empty
// log; every action block ends with settle().

import 'dart:async';

import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:firebase_database_dart/src/core/view/event_dispatcher.dart';
import 'package:test/test.dart';

import 'support/fake_time.dart';
import 'support/harness.dart';

void main() {
  void scenario(
    String name,
    void Function(Harness h) body, {
    Map<String, Object?>? persisted,
    bool acceptConnections = true,
    bool settled = true,
  }) {
    test(name, () {
      fakeTime((FakeTime time) {
        body(
          Harness(
            time,
            persisted: persisted,
            acceptConnections: acceptConnections,
            settled: settled,
          ),
        );
      });
    });
  }

  group('4.4 delivery', () {
    scenario('D1 no listener runs inside the call', (Harness h) {
      h.listenAnswered('S1', h.ref('a').onValue, 'a', 1);
      h.log.clear();

      h.ref('a').set(2);
      h.log.add('returned');
      h.settle();
      expect(h.log, <String>['returned', 'S1:V(2)']);
    });

    scenario('D2 initial events come after listen returns', (Harness h) {
      h.listenAnswered('S1', h.ref('a').onValue, 'a', 1);
      h.log.clear();

      h.listen('S2', h.ref('a').onValue);
      h.log.add('returned');
      h.settle();
      expect(h.log, <String>['returned', 'S2:V(1)']);
      expect(h.server.requests.where((String r) => r == 'q /a'), hasLength(1));
    });

    scenario('D3 one stream listened twice', (Harness h) {
      final Stream<DatabaseEvent> st = h.ref('a').onValue;
      h.listenAnswered('S1', st, 'a', 1);
      h.log.clear();

      h.listen('S2', st);
      h.settle();
      h.server.push('a', 2);
      h.settle();
      expect(h.log, <String>['S2:V(1)', 'S1:V(2)', 'S2:V(2)']);
      expect(h.server.requests.where((String r) => r == 'q /a'), hasLength(1));
    });

    scenario('D4 order inside a change', (Harness h) {
      final Query q = h.ref('l').orderByValue();
      h.listen('S1', q.onChildEvents);
      h.listen('S2', q.onValue);
      h.settle();
      h.server.answerListen('l', <String, Object?>{'a': 1, 'b': 2});
      h.settle();
      h.log.clear();

      h.ref('l').update(<String, Object?>{'a': null, 'b': 5, 'c': 0});
      h.settle();
      expect(h.log, <String>[
        'S1:R(a)',
        'S1:A(c,null)',
        'S1:M(b,c)',
        'S1:C(b,c)',
        'S2:V({b:5,c:0})',
      ]);
    });

    scenario('D5 two registrations on one query', (Harness h) {
      h.listen('S1', h.ref('l').onChildAdded);
      h.listen('S2', h.ref('l').onChildAdded);
      h.settle();
      h.log.clear();

      h.server.answerListen('l', <String, Object?>{'a': 1, 'b': 2});
      h.settle();
      expect(h.log, <String>[
        'S1:A(a,null)',
        'S2:A(a,null)',
        'S1:A(b,a)',
        'S2:A(b,a)',
      ]);
    });

    scenario('D6 type order before registration order', (Harness h) {
      h.listen('S1', h.ref('l').onValue);
      h.listen('S2', h.ref('l').onChildAdded);
      h.settle();
      h.log.clear();

      h.server.answerListen('l', <String, Object?>{'a': 1});
      h.settle();
      expect(h.log, <String>['S2:A(a,null)', 'S1:V({a:1})']);
    });

    scenario('D7 deeper location first', (Harness h) {
      h.listenAnswered('S1', h.ref('a').onValue, 'a', <String, Object?>{
        'b': 1,
      });
      h.listen('S2', h.ref('a/b').onValue);
      h.settle();
      h.log.clear();

      h.ref('a').set(<String, Object?>{'b': 2});
      h.settle();
      expect(h.log, <String>['S2:V(2)', 'S1:V({b:2})']);
    });

    void setUpD8(Harness h) {
      h.listenAnswered('S1', h.ref('a').onValue, 'a', null);
      h.listenAnswered('S2', h.ref('b').onValue, 'b', null);
    }

    scenario('D8 between changes, no pause', (Harness h) {
      setUpD8(h);
      h.log.clear();

      h.ref('a').set(1);
      h.ref('b').set(1);
      h.ref('a').set(2);
      h.settle();
      expect(h.log, <String>['S1:V(1)', 'S2:V(1)', 'S1:V(2)']);
    });

    scenario('D9 with pause', (Harness h) {
      final StreamSubscription<DatabaseEvent> s1 = h.listenAnswered(
        'S1',
        h.ref('a').onValue,
        'a',
        null,
      );
      h.listenAnswered('S2', h.ref('b').onValue, 'b', null);
      s1.pause();
      h.log.clear();

      h.ref('a').set(1);
      h.ref('b').set(1);
      h.ref('a').set(2);
      h.settle();
      h.log.add('resume');
      s1.resume();
      h.settle();
      expect(h.log, <String>['S2:V(1)', 'resume', 'S1:V(1)', 'S1:V(2)']);
    });

    void awaitForScenario(String name, {required bool withAwait}) {
      scenario(name, (Harness h) {
        Future<void> loop() async {
          await for (final DatabaseEvent e in h.ref('a').onValue) {
            h.log.add('X:${eventText(e)}');
            if (withAwait) {
              await Future<void>.value();
            }
          }
        }

        unawaited(loop().catchError((Object _) {}));
        h.settle();
        h.server.answerListen('a', null);
        h.settle();
        h.listenAnswered('Y', h.ref('b').onValue, 'b', null);
        h.log.clear();

        h.ref('a').set(1);
        h.ref('a').set(2);
        h.ref('b').set(1);
        h.settle();
        // Contract rule 4.9: each stream keeps its own order; the order across X and Y is not pinned.
        // (The row's literal log `Y:V(1), X:V(1), X:V(2)` assumes the loop body runs after the drain;
        // in Dart the body of `await for` starts synchronously inside the delivery of its event.)
        expect(h.named('X'), <String>['X:V(1)', 'X:V(2)']);
        expect(h.named('Y'), <String>['Y:V(1)']);
      });
    }

    awaitForScenario('D10 await for with an await', withAwait: true);
    awaitForScenario('D11 await for without an await', withAwait: false);

    scenario('D12 onChildEvents under await for', (Harness h) {
      Future<void> loop() async {
        await for (final DatabaseEvent e in h.ref('l').onChildEvents) {
          h.log.add('X:${eventText(e)}');
          await Future<void>.value();
        }
      }

      unawaited(loop().catchError((Object _) {}));
      h.settle();
      h.server.answerListen('l', null);
      h.settle();
      h.listenAnswered('Y', h.ref('m').onValue, 'm', null);
      h.log.clear();

      h.ref('l/a').set(1);
      h.ref('m').set(1);
      h.ref('l/a').remove();
      h.ref('l/b').set(2);
      h.settle();
      expect(h.named('X'), <String>['X:A(a,null)', 'X:R(a)', 'X:A(b,null)']);
      expect(h.named('Y'), <String>['Y:V(1)']);
    });

    scenario("D13 a listener's own write", (Harness h) {
      h.listenAnswered(
        'S1',
        h.ref('a').onValue,
        'a',
        0,
        then: (DatabaseEvent e) {
          h.log.add('in');
          if (e.snapshot.value == 1) {
            h.ref('a').set(2);
          }
          h.log.add('out');
        },
      );
      h.log.clear();

      h.ref('a').set(1);
      h.settle();
      expect(h.log, <String>['S1:V(1)', 'in', 'out', 'S1:V(2)', 'in', 'out']);
    });

    scenario('D14 listener added during delivery', (Harness h) {
      bool armed = false;
      bool added = false;
      h.listenAnswered(
        'S1',
        h.ref('a').onValue,
        'a',
        null,
        then: (DatabaseEvent _) {
          if (armed && !added) {
            added = true;
            h.listen('S2', h.ref('a').onValue);
          }
        },
      );
      h.log.clear();
      armed = true;

      h.ref('a').set(1);
      h.ref('a').set(2);
      h.settle();
      expect(h.log, <String>['S1:V(1)', 'S1:V(2)', 'S2:V(2)']);
    });

    scenario('D15 cancel during delivery', (Harness h) {
      bool armed = false;
      late final StreamSubscription<DatabaseEvent> s2;
      h.listen(
        'S1',
        h.ref('l').onChildAdded,
        then: (DatabaseEvent _) {
          if (armed) {
            armed = false;
            unawaited(s2.cancel());
          }
        },
      );
      s2 = h.listen('S2', h.ref('l').onChildAdded);
      h.settle();
      h.server.answerListen('l', null);
      h.settle();
      h.log.clear();
      armed = true;

      h.ref('l').set(<String, Object?>{'a': 1, 'b': 2});
      h.settle();
      expect(h.log, <String>['S1:A(a,null)', 'S1:A(b,a)']);
    });

    scenario('D16 cancel does not wait', (Harness h) {
      final StreamSubscription<DatabaseEvent> s1 = h.listenAnswered(
        'S1',
        h.ref('a').onValue,
        'a',
        1,
      );
      h.log.clear();

      s1.cancel().then((_) => h.log.add('cancelled'));
      h.settle();
      h.server.push('a', 2);
      h.settle();
      expect(h.log, <String>['cancelled']);
      expect(h.server.requests.last, 'n /a');
    });

    scenario('D17 throwing listener', (Harness h) {
      final List<Object> errors = <Object>[];
      runZonedGuarded(() {
        h.listen(
          'S1',
          h.ref('a').onValue,
          then: (DatabaseEvent _) => throw StateError('x'),
        );
      }, (Object e, StackTrace _) => errors.add(e));
      h.listen('S2', h.ref('a').onValue);
      h.settle();
      h.server.answerListen('a', null);
      h.settle();
      h.log.clear();
      errors.clear();

      h.ref('a').set(1);
      h.settle();
      h.ref('a').set(2);
      h.settle();
      expect(h.log, <String>['S1:V(1)', 'S2:V(1)', 'S1:V(2)', 'S2:V(2)']);
      expect(errors, hasLength(2));
      expect(errors, everyElement(isA<StateError>()));
    });

    String k(int i) => 'k${i.toString().padLeft(5, '0')}';

    scenario('D18 no yield inside a change', (Harness h) {
      const int n = eventsPerDrainSlice;
      bool armed = false;
      h.listenAnswered(
        'S1',
        h.ref('l').onChildAdded,
        'l',
        null,
        then: (DatabaseEvent _) {
          if (armed) {
            armed = false;
            Timer.run(() => h.log.add('T'));
          }
        },
      );
      h.log.clear();
      armed = true;

      h.ref('l').set(<String, Object?>{
        for (int i = 0; i < 2 * n; i++) k(i): i,
      });
      h.settle();
      expect(h.log, hasLength(2 * n + 1));
      expect(h.log.first, 'S1:A(${k(0)},null)');
      expect(h.log[2 * n - 1], 'S1:A(${k(2 * n - 1)},${k(2 * n - 2)})');
      expect(h.log.last, 'T');
    });

    scenario('D19 yield between changes', (Harness h) {
      // In a browser the yield is a message task, which the fake clock of these scenarios does
      // not drive; test/core/repo_test.dart D19 covers the browsers with the real event loop.
      if (const bool.fromEnvironment('dart.library.js_interop')) {
        return;
      }
      const int n = eventsPerDrainSlice;
      bool armed = false;
      h.listenAnswered(
        'S1',
        h.ref('x').onChildAdded,
        'x',
        null,
        then: (DatabaseEvent _) {
          if (armed) {
            armed = false;
            Timer.run(() => h.log.add('T'));
          }
        },
      );
      h.listenAnswered('S2', h.ref('y').onChildAdded, 'y', null);
      h.log.clear();
      armed = true;

      h.ref('x').set(<String, Object?>{for (int i = 0; i < n; i++) k(i): i});
      h.ref('y').set(<String, Object?>{k(0): 0});
      h.settle();
      expect(h.log, hasLength(n + 2));
      expect(h.log[n - 1], startsWith('S1:A(${k(n - 1)},'));
      expect(h.log[n], 'T');
      expect(h.log[n + 1], 'S2:A(${k(0)},null)');
    });
  });

  group('4.4 writes', () {
    scenario('D20 local write then ack', (Harness h) {
      h.listenAnswered('S1', h.ref('a').onValue, 'a', 1);
      h.log.clear();

      h.track('F', h.ref('a').set(2));
      h.settle();
      h.server.ackLastWrite();
      h.settle();
      expect(h.log, <String>['S1:V(2)', 'F:ok']);
    });

    scenario('D21 paused subscription, write acked', (Harness h) {
      final StreamSubscription<DatabaseEvent> s1 = h.listenAnswered(
        'S1',
        h.ref('a').onValue,
        'a',
        1,
      );
      s1.pause();
      h.log.clear();

      h.track('F', h.ref('a').set(2));
      h.settle();
      h.server.ackLastWrite();
      h.settle();
      h.log.add('resume');
      s1.resume();
      h.settle();
      expect(h.log, <String>['F:ok', 'resume', 'S1:V(2)']);
    });

    scenario('D22 local write then rejection', (Harness h) {
      h.listenAnswered('S1', h.ref('a').onValue, 'a', 1);
      h.log.clear();

      h.track('F', h.ref('a').set(2));
      h.settle();
      h.server.failLastWrite('permission_denied');
      h.settle();
      expect(h.log, <String>['S1:V(2)', 'S1:V(1)', 'F:E(permission-denied)']);
    });

    scenario('D23 offline write, then reconnect', (Harness h) {
      h.listenAnswered('S1', h.ref('a').onValue, 'a', 1);
      h.goDown();
      h.log.clear();
      final int sentBefore = h.server.requests.length;

      h.track('F', h.ref('a').set(2));
      h.settle();
      h.elapse(const Duration(minutes: 1));
      expect(h.server.requests, hasLength(sentBefore));
      h.reconnect();
      h.server.answerListen('a', 1);
      h.settle();
      h.server.ackLastWrite();
      h.settle();
      expect(h.log, <String>['S1:V(2)', 'F:ok']);
      expect(h.server.requests.where((String r) => r == 'p /a'), hasLength(1));
      expect(
        h.server.requests.indexOf('p /a'),
        greaterThanOrEqualTo(sentBefore),
      );
    });

    scenario('D24 purgeOutstandingWrites', (Harness h) {
      h.listenAnswered('S1', h.ref('a').onValue, 'a', 1);
      h.listenAnswered('S2', h.ref('c').onValue, 'c', 0);
      h.log.clear();

      h.track('F', h.ref('a').set(2));
      h.trackTransaction(
        'T',
        h.ref('c').runTransaction((Object? v) => const Transaction.success(7)),
      );
      h.settle();
      h.track('P', h.db.purgeOutstandingWrites());
      h.settle();
      expect(h.named('S1'), <String>['S1:V(2)', 'S1:V(1)']);
      expect(h.named('S2'), <String>['S2:V(7)', 'S2:V(0)']);
      expect(h.named('F'), <String>['F:E(write-canceled)']);
      expect(h.named('T'), <String>['T:E(write-canceled)']);
      expect(h.named('P'), <String>['P:ok']);
    });

    scenario('D25 partial cache', (Harness h) {
      h.listenAnswered('P1', h.ref('f/a').onValue, 'f/a', 1);
      h.listenAnswered('P2', h.ref('f/b').onValue, 'f/b', 2);
      h.log.clear();

      h.listen('S1', h.ref('f').onChildEvents);
      h.listen('S2', h.ref('f').onValue);
      h.settle();
      h.log.add('answer');
      h.server.answerListen('f', <String, Object?>{'a': 1, 'b': 2, 'c': 3});
      h.settle();
      expect(h.log, <String>[
        'S1:A(a,null)',
        'S1:A(b,a)',
        'answer',
        'S1:A(c,b)',
        'S2:V({a:1,b:2,c:3})',
      ]);
    });

    scenario('D26 pending write as complete data', (Harness h) {
      h.track('F', h.ref('x').set(<String, Object?>{'k': 1}));
      h.settle();
      h.listen('S1', h.ref('x').onValue);
      h.settle();
      expect(h.log, <String>['S1:V({k:1})']);
    });
  });

  group('4.4 errors and connection', () {
    scenario('D27 server cancel', (Harness h) {
      h.listenAnswered('S1', h.ref('s').onValue, 's', 1);
      h.listenAnswered('S2', h.ref('t').onValue, 't', 2);
      h.log.clear();

      h.server.cancelListen('s', 'permission_denied');
      h.settle();
      expect(h.log, <String>['S1:E(permission-denied)', 'S1:done']);
    });

    scenario('D28 disconnect, reconnect', (Harness h) {
      h.db.onConnected.listen((bool c) => h.log.add('C:$c'));
      h.listenAnswered('S1', h.ref('a').onValue, 'a', 1);
      h.log.clear();
      final int sentBefore = h.server.requests.length;

      h.goDown();
      h.reconnect();
      h.server.answerListen('a', 1);
      h.settle();
      expect(h.log, <String>['C:false', 'C:true']);
      expect(h.server.requests.skip(sentBefore), contains('q /a'));
    });

    scenario('D29 auth revoke, re-listen accepted', (Harness h) {
      h.listenAnswered('S1', h.ref('s').onValue, 's', 1);
      h.log.clear();

      h.server.revokeAuth();
      h.settle();
      h.reconnect();
      h.server.answerListen('s', 1);
      h.settle();
      expect(h.log, isEmpty);
    });

    scenario('D30 auth revoke, re-listen refused', (Harness h) {
      h.listenAnswered('S1', h.ref('s').onValue, 's', 1);
      h.log.clear();

      h.server.revokeAuth();
      h.settle();
      h.reconnect();
      h.server.failListen('s', 'permission_denied');
      h.settle();
      expect(h.log, <String>['S1:E(permission-denied)', 'S1:done']);
    });

    scenario('D31 server kill', (Harness h) {
      h.db.onConnected.listen((bool c) => h.log.add('C:$c'));
      h.settle();
      h.log.clear();

      h.server.kill('test');
      h.settle();
      final int attempts = h.server.connectionAttempts;
      h.elapse(const Duration(minutes: 1));
      h.db.goOffline();
      h.db.goOnline();
      h.settle();
      h.elapse(const Duration(minutes: 1));
      expect(h.log, <String>['C:false']);
      expect(h.server.connectionAttempts, attempts);
    });

    scenario('D32 close()', (Harness h) {
      h.listenAnswered('S1', h.ref('a').onValue, 'a', 1);
      h.track('F', h.ref('b').set(1));
      h.settle();
      h.log.clear();

      h.db.close().then((_) => h.log.add('closed'));
      h.settle();
      expect(h.log, <String>[
        'S1:E(database-closed)',
        'S1:done',
        'F:E(database-closed)',
        'closed',
      ]);
      h.log.clear();

      h.listen('S2', h.ref('a').onValue);
      h.trackValue('G', h.ref('a').get());
      h.db.close().then((_) => h.log.add('closed2'));
      h.settle();
      // The streams and Futures made after close are independent: only their entries are pinned.
      expect(
        h.log,
        unorderedEquals(<String>[
          'S2:E(database-closed)',
          'S2:done',
          'G:E(database-closed)',
          'closed2',
        ]),
      );
      expect(h.named('S2'), <String>['S2:E(database-closed)', 'S2:done']);
    });

    scenario('D32 close() fails an outstanding get', (Harness h) {
      h.trackValue('G', h.ref('a').get());
      h.settle();
      expect(h.server.requests, contains('g /a'));

      h.db.close();
      h.settle();
      expect(h.log, <String>['G:E(database-closed)']);
    });

    scenario('D33 app deleted', (Harness h) {
      h.listenAnswered('S1', h.ref('a').onValue, 'a', 1);
      h.log.clear();

      h.app.delete();
      h.settle();
      expect(h.log, <String>['S1:E(database-closed)', 'S1:done']);
    });
  });

  group('4.4 transactions', () {
    void setUpD34(Harness h) {
      h.listenAnswered('S1', h.ref('c').onValue, 'c', 0);
      h.log.clear();
    }

    scenario('D34 transaction first run', (Harness h) {
      setUpD34(h);
      h.trackTransaction(
        'T',
        h
            .ref('c')
            .runTransaction(
              h.handler((Object? v) => Transaction.success((v! as int) + 1)),
            ),
      );
      h.log.add('returned');
      h.settle();
      h.server.ackLastWrite();
      h.settle();
      // The handler runs inside the call, as in JS and Android; its events wait for the queue.
      expect(h.log, <String>['H(0)', 'returned', 'S1:V(1)', 'T:committed(1)']);
    });

    scenario('D35 rerun after data-stale', (Harness h) {
      setUpD34(h);
      h.trackTransaction(
        'T',
        h
            .ref('c')
            .runTransaction(
              h.handler((Object? v) => Transaction.success((v! as int) + 1)),
            ),
      );
      h.settle();
      h.server.push('c', 5);
      h.server.failLastWrite('datastale');
      h.settle();
      h.server.ackLastWrite();
      h.settle();
      expect(h.log, <String>[
        'H(0)',
        'S1:V(1)',
        'H(5)',
        'S1:V(6)',
        'T:committed(6)',
      ]);
    });

    scenario('D35 a stale transaction put is answered datastale by the fake', (
      Harness h,
    ) {
      setUpD34(h);
      h.trackTransaction(
        'T',
        h
            .ref('c')
            .runTransaction(
              h.handler((Object? v) => Transaction.success((v! as int) + 1)),
            ),
      );
      h.settle();
      h.server.push('c', 5);
      h.server.ackLastWrite();
      h.settle();
      h.server.ackLastWrite();
      h.settle();
      expect(h.log, <String>[
        'H(0)',
        'S1:V(1)',
        'H(5)',
        'S1:V(6)',
        'T:committed(6)',
      ]);
    });

    scenario('D36 rerun aborts and reverts', (Harness h) {
      setUpD34(h);
      h.trackTransaction(
        'T',
        h
            .ref('c')
            .runTransaction(
              h.handler(
                (Object? v) => v == 5
                    ? const Transaction.abort()
                    : const Transaction.success(1),
              ),
            ),
      );
      h.settle();
      h.server.push('c', 5);
      h.server.failLastWrite('datastale');
      h.settle();
      expect(h.log, <String>[
        'H(0)',
        'S1:V(1)',
        'H(5)',
        'S1:V(5)',
        'T:aborted(5)',
      ]);
    });

    scenario('D37 abort on first run', (Harness h) {
      setUpD34(h);
      h.trackTransaction(
        'T',
        h
            .ref('c')
            .runTransaction(
              h.handler((Object? v) => const Transaction.abort()),
            ),
      );
      h.settle();
      expect(h.log, <String>['H(0)', 'T:aborted(0)']);
      expect(h.server.requests, isNot(contains('p /c')));
    });

    scenario('D38 handler throws', (Harness h) {
      setUpD34(h);
      final StateError e = StateError('boom');
      Object? failure;
      h.trackTransaction(
        'T',
        h.ref('c').runTransaction(h.handler((Object? v) => throw e)),
        onError: (Object error) => failure = error,
      );
      h.settle();
      expect(h.log, <String>['H(0)', 'T:E(Bad state: boom)']);
      expect(identical(failure, e), isTrue);
      expect(h.server.requests, isNot(contains('p /c')));
    });

    scenario('D39 applyLocally false', (Harness h) {
      setUpD34(h);
      h.trackTransaction(
        'T',
        h
            .ref('c')
            .runTransaction(
              h.handler((Object? v) => const Transaction.success(1)),
              applyLocally: false,
            ),
      );
      h.settle();
      expect(h.log, <String>['H(0)']);
      h.server.ackLastWrite();
      h.settle();
      expect(h.log, <String>['H(0)', 'S1:V(1)', 'T:committed(1)']);
    });

    scenario('D40 sent transaction, connection lost', (Harness h) {
      setUpD34(h);
      h.trackTransaction(
        'T',
        h
            .ref('c')
            .runTransaction(
              h.handler((Object? v) => const Transaction.success(1)),
            ),
      );
      h.settle();
      h.goDown();
      expect(h.log, <String>[
        'H(0)',
        'S1:V(1)',
        'S1:V(0)',
        'T:E(disconnected)',
      ]);
    });

    scenario('D41 handler gets a mutable copy', (Harness h) {
      h.listenAnswered('S1', h.ref('c').onValue, 'c', <String, Object?>{
        'n': 1,
      });
      h.log.clear();

      h.trackTransaction(
        'T',
        h
            .ref('c')
            .runTransaction(
              h.handler((Object? v) {
                (v! as Map<String, Object?>)['n'] = 2;
                return Transaction.success(v);
              }),
            ),
      );
      h.settle();
      h.server.ackLastWrite();
      h.settle();
      expect(h.log, <String>['H({n:1})', 'S1:V({n:2})', 'T:committed({n:2})']);
    });
  });

  group('4.4 onDisconnect, once, get', () {
    scenario('D42 onDisconnect applied locally', (Harness h) {
      h.db.onConnected.listen((bool c) => h.log.add('C:$c'));
      h.listenAnswered('S1', h.ref('p').onValue, 'p', 'on');
      h.track('F', h.ref('p').onDisconnect.set('off'));
      h.settle();
      h.server.ackLastOnDisconnect();
      h.settle();
      h.log.clear();

      h.goDown();
      h.reconnect();
      h.server.answerListen('p', 'off');
      h.settle();
      h.goDown();
      expect(h.log, <String>['C:false', 'S1:V(off)', 'C:true', 'C:false']);
    });

    scenario('D42 an onDisconnect request sent and then dropped fails', (
      Harness h,
    ) {
      h.track('F', h.ref('p').onDisconnect.set('off'));
      h.settle();
      expect(h.server.requests, contains('o /p'));

      h.goDown();
      expect(h.log, <String>['F:E(disconnected)']);
    });

    scenario('D43 once() with a pending write', (Harness h) {
      h.ref('a').set(5);
      h.settle();
      h.trackEvent('O', h.ref('a').once());
      h.settle();
      expect(h.log, <String>['O:V(5)']);
    });

    scenario('D44 once() from the server', (Harness h) {
      h.trackEvent('O', h.ref('a').once());
      h.settle();
      h.server.answerListen('a', 1);
      h.settle();
      expect(h.log, <String>['O:V(1)']);
      final List<String> requests = h.server.requests;
      expect(requests.sublist(requests.length - 2), <String>['q /a', 'n /a']);
    });

    scenario('D45 once(childAdded)', (Harness h) {
      h.listenAnswered('S1', h.ref('l').onValue, 'l', <String, Object?>{
        'x': 1,
        'y': 2,
      });
      h.log.clear();

      h.trackEvent('O', h.ref('l').once(DatabaseEventType.childAdded));
      h.settle();
      expect(h.log, <String>['O:A(x,null)']);
    });

    scenario('D46 get() from an active view', (Harness h) {
      h.listenAnswered('S1', h.ref('a').onValue, 'a', 1);
      h.log.clear();

      h.ref('a').set(2);
      h.trackValue('G', h.ref('a').get());
      h.settle();
      expect(h.log, <String>['S1:V(2)', 'G:=2']);
      expect(h.server.requests, isNot(contains('g /a')));
    });

    scenario('D47 get() has no timer while connected', (Harness h) {
      h.trackValue('G', h.ref('a').get());
      h.settle();
      h.elapse(const Duration(minutes: 1));
      expect(h.log, isEmpty);
      h.server.answerGet('a', 7);
      h.settle();
      expect(h.log, <String>['G:=7']);
    }, persisted: <String, Object?>{'a': 1});

    scenario('D48 get() answer raises events', (Harness h) {
      h.trackValue('G', h.ref('a').get());
      h.settle();
      h.listen('S1', h.ref('a/b').onValue);
      h.settle();
      h.server.answerGet('a', <String, Object?>{'b': 3});
      h.settle();
      expect(h.log, <String>['S1:V(3)', 'G:={b:3}']);
    });

    scenario('D49 get() offline, no cache', (Harness h) {
      h.goDown();
      h.trackValue('G', h.ref('a').get());
      h.settle();
      h.elapse(const Duration(milliseconds: 2999));
      h.log.add('t');
      h.elapse(const Duration(milliseconds: 1));
      expect(h.log, <String>['t', 'G:E(unavailable)']);
    });

    scenario('D50 get() offline, persisted', (Harness h) {
      h.goDown();
      h.trackValue('G', h.ref('a').get());
      h.settle();
      h.elapse(const Duration(seconds: 3));
      expect(h.log, <String>['G:=1']);
    }, persisted: <String, Object?>{'a': 1});

    scenario('D51 get() connection comes back', (Harness h) {
      h.goDown();
      h.trackValue('G', h.ref('a').get());
      h.settle();
      h.reconnect();
      h.server.answerGet('a', 4);
      h.settle();
      expect(h.log, <String>['G:=4']);
    });

    scenario('D52 get() connection drops', (Harness h) {
      h.trackValue('G', h.ref('a').get());
      h.settle();
      h.goDown();
      h.elapse(const Duration(milliseconds: 2999));
      h.log.add('t');
      h.elapse(const Duration(milliseconds: 1));
      expect(h.log, <String>['t', 'G:E(unavailable)']);
    });

    scenario('D52 variant: get() connection drops and comes back', (Harness h) {
      h.trackValue('G', h.ref('a').get());
      h.settle();
      h.goDown();
      h.reconnect();
      h.server.answerGet('a', 4);
      h.settle();
      expect(h.log, <String>['G:=4']);
      expect(h.server.requests.where((String r) => r == 'g /a'), hasLength(2));
    });

    scenario('D53 get() refused', (Harness h) {
      h.trackValue('G', h.ref('a').get());
      h.settle();
      h.server.failGet('a', 'permission_denied');
      h.settle();
      expect(h.log, <String>['G:E(permission-denied)']);
    }, persisted: <String, Object?>{'a': 1});

    scenario('D54 get() after goOffline()', (Harness h) {
      h.db.goOffline();
      h.settle();
      h.trackValue('G', h.ref('a').get());
      h.settle();
      expect(h.log, <String>['G:E(unavailable)']);
    });

    scenario(
      'D54 variant: get() after goOffline(), persisted',
      (Harness h) {
        h.db.goOffline();
        h.settle();
        h.trackValue('G', h.ref('a').get());
        h.settle();
        expect(h.log, <String>['G:=1']);
      },
      persisted: <String, Object?>{'a': 1},
    );

    void logKeys(Harness h, DataSnapshot s) =>
        h.log.add(s.children.map((DataSnapshot c) => c.key).join(','));

    scenario('get() of an ordered query asks for the default query', (
      Harness h,
    ) {
      h.trackValue(
        'G',
        h.ref('l').orderByChild('x').get(),
        then: (DataSnapshot s) => logKeys(h, s),
      );
      h.settle();
      expect(h.server.requests.last, 'g /l');
      h.server.answerGet('l', <String, Object?>{
        'a': <String, Object?>{'x': 3},
        'b': <String, Object?>{'x': 1},
        'c': <String, Object?>{'x': 2},
      });
      h.settle();
      expect(h.log.last, 'b,c,a');
    });

    scenario('get() of an orderByValue query asks for the default query', (
      Harness h,
    ) {
      h.trackValue(
        'G',
        h.ref('l').orderByValue().get(),
        then: (DataSnapshot s) => logKeys(h, s),
      );
      h.settle();
      expect(h.server.requests.last, 'g /l');
      h.server.answerGet('l', <String, Object?>{'a': 3, 'b': 1, 'c': 2});
      h.settle();
      expect(h.log.last, 'b,c,a');
    });

    scenario('get() of a limited ordered query sends its query', (Harness h) {
      h.trackValue('G', h.ref('l').orderByChild('x').limitToLast(2).get());
      h.settle();
      expect(h.server.requests.last, 'g /l {"i":"x","l":2,"vf":"r"}');
      h.server.failGet('l', 'no_index');
      h.settle();
      expect(h.log, <String>['G:E(index-not-defined)']);
    });
  });

  group('4.4 connection state and snapshots', () {
    scenario(
      'D55 onConnected, isConnected',
      (Harness h) {
        h.log.add('${h.db.isConnected}');
        h.db.onConnected.listen((bool c) => h.log.add('C:$c'));
        h.settle();
        h.reconnect();
        h.log.add('${h.db.isConnected}');
        expect(h.log, <String>['false', 'C:false', 'C:true', 'true']);
      },
      acceptConnections: false,
      settled: false,
    );

    scenario('D56 child event ref', (Harness h) {
      h.listenAnswered(
        'S1',
        h.ref('l').onChildAdded,
        'l',
        <String, Object?>{'a': 1},
        then: (DatabaseEvent e) => h.log.add(e.snapshot.ref.path),
      );
      expect(h.log, <String>['S1:A(a,null)', '/l/a']);
    });

    scenario('D57 child snapshot priority', (Harness h) {
      h.trackValue(
        'G',
        h.ref('l').get(),
        then: (DataSnapshot s) {
          h.log
            ..add('${s.child('a').priority}')
            ..add('${s.children.first.priority}');
        },
      );
      h.settle();
      h.server.answerGet('l', <String, Object?>{
        'a': <String, Object?>{'.value': 1, '.priority': 5},
      });
      h.settle();
      expect(h.log, <String>['G:={a:1}', '5', '5']);
    });

    scenario('D58 sign-out: the listen sent again without auth is refused', (
      Harness h,
    ) {
      h.listenAnswered('S1', h.ref('s').onValue, 's', 1);
      h.log.clear();

      h.server.revokeAuth();
      h.reconnect();
      expect(h.server.requests.where((String r) => r == 'q /s'), hasLength(2));
      h.server.failListen('s', 'permission_denied');
      h.settle();
      expect(h.log, <String>['S1:E(permission-denied)', 'S1:done']);
    });
  });
}
