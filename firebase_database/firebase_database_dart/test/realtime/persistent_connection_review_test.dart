// Owner P. The missing tests of the connection review (rtdb/reports/review-connection.md) for the
// persistent connection: H1 (the replaced timeout rule), H2, H3, M1 (b), M3, M4/M5, M6, M7, L3.
// Time-dependent cases run on fake time.
import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/core/repo_info.dart';
import 'package:firebase_database_dart/src/realtime/connection_timings.dart';
import 'package:firebase_database_dart/src/realtime/realtime_target.dart';
import 'package:test/test.dart';

import '../util/fake_ws.dart';
import '../util/persistent_connection_harness.dart';

const Duration _timeout = Duration(milliseconds: 200);

ConnectionTimings _timings() => shrunkTimings(requestTimeout: _timeout);

/// Initializes [rig] and waits (in fake time) for connection [number]; the server has answered
/// its credentials.
void _connect(FakeAsync async, PRig rig, int number) {
  if (number == 1) {
    rig.connection.initialize();
  }
  elapseUntil(async, () => rig.connects == number);
  async.flushMicrotasks();
}

void main() {
  group('H1: link silence, not request age', () {
    test(
      'a 500 ms push in 50 pieces with a 200 ms timeout: one connection, listen ok, put ok',
      () {
        fakeAsync((FakeAsync async) {
          final PRig rig = fakeTimeRig(async, timings: _timings(), hold: true);
          _connect(async, rig, 1);
          final List<String> results = <String>[];
          rig.connection.listen(
            defaultListen('/big'),
            hashProvider: CountingHash(''),
            onComplete: (String s, _) => results.add('listen $s'),
          );
          rig.connection.put(
            '/a',
            1,
            onComplete: (String s, _) => results.add('put $s'),
          );
          async.flushMicrotasks();
          final FakeWsChannel channel = rig.server.connector.last;
          final String push = jsonEncode(<String, Object?>{
            't': 'd',
            'd': <String, Object?>{
              'a': 'd',
              'b': <String, Object?>{'p': 'big', 'd': 'x' * 2000},
            },
          });
          final int size = (push.length / 50).ceil();
          channel.serverText('50');
          for (int i = 0; i < 50; i++) {
            final int end = (i + 1) * size;
            channel.serverText(
              push.substring(i * size, end > push.length ? push.length : end),
            );
            async.elapse(const Duration(milliseconds: 10));
          }
          channel
            ..serverResponse(rig.sent('q').single.r!)
            ..serverResponse(rig.sent('p').single.r!);
          async.elapse(const Duration(milliseconds: 10));
          expect(results, <String>['listen ok', 'put ok']);
          expect(rig.attemptTimes, hasLength(1));
          expect(rig.delegate.callsOf('dataUpdate').last.path, '/big');
          expect(rig.delegate.callsOf('dataUpdate').last.data, 'x' * 2000);
          shutDownOnFakeTime(async, rig);
        });
      },
    );

    test(
      'writes and listens are never failed by a timeout: they are re-sent on every connection',
      () {
        fakeAsync((FakeAsync async) {
          final PRig rig = fakeTimeRig(async, timings: _timings(), hold: true);
          _connect(async, rig, 1);
          final List<String> results = <String>[];
          rig.connection.put(
            '/a',
            1,
            onComplete: (String s, _) => results.add('put $s'),
          );
          rig.connection.listen(
            defaultListen('/l'),
            hashProvider: CountingHash(''),
            onComplete: (String s, _) => results.add('listen $s'),
          );
          for (int n = 2; n <= 4; n++) {
            _connect(
              async,
              rig,
              n,
            ); // Each previous connection ended in silence.
          }
          expect(results, isEmpty);
          for (int n = 1; n <= 4; n++) {
            expect(rig.sent('p', onConnection: n), hasLength(1));
            expect(rig.sent('q', onConnection: n), hasLength(1));
          }
          shutDownOnFakeTime(async, rig);
        });
      },
    );

    test(
      'a get fails with network_error after two silent connections, counted for that get alone',
      () {
        fakeAsync((FakeAsync async) {
          final PRig rig = fakeTimeRig(async, timings: _timings(), hold: true);
          _connect(async, rig, 1);
          final List<String> results = <String>[];
          rig.connection
              .get(defaultListen('/a'))
              .then(
                (Object? v) => results.add('a $v'),
                onError: (Object e) =>
                    results.add('a ${(e as ServerActionsException).status}'),
              );
          async.flushMicrotasks();
          _connect(
            async,
            rig,
            2,
          ); // Connection 1 was silent with A waiting: A counts 1.
          rig.connection
              .get(defaultListen('/b'))
              .then(
                (Object? v) => results.add('b $v'),
                onError: (Object e) =>
                    results.add('b ${(e as ServerActionsException).status}'),
              );
          async.flushMicrotasks();
          // Connection 2 is silent with A (second time) and B (first time) waiting.
          _connect(async, rig, 3);
          expect(results, <String>['a $statusNetworkError']);
          expect(rig.sent('g', onConnection: 3), hasLength(1));
          rig.server.connector.last.serverResponse(
            rig.sent('g', onConnection: 3).single.r!,
            data: 'B',
          );
          async.flushMicrotasks();
          expect(results, <String>['a $statusNetworkError', 'b B']);
          shutDownOnFakeTime(async, rig);
        });
      },
    );

    test('L3: a server that never answers the credentials is logged once', () {
      fakeAsync((FakeAsync async) {
        final PRig rig = fakeTimeRig(
          async,
          timings: _timings(),
          holdCredentials: true,
        );
        rig.connection.initialize();
        elapseUntil(async, () => rig.connects == 4);
        expect(
          rig.logs.where(
            (String l) => l.contains('does not answer the credentials'),
          ),
          hasLength(1),
        );
        shutDownOnFakeTime(async, rig);
      });
    });
  });

  test(
    'H2: a sign-out during the token fetch is not undone by the fetched token',
    () async {
      final PRig rig = PRig();
      rig.tokens.gate = Completer<void>();
      rig.connection.initialize();
      await until(() => rig.tokens.authCalls.isNotEmpty);
      rig.tokens.emitAuth(null);
      await rig.settle();
      rig.tokens.gate!.complete();
      await until(() => rig.connects == 1);
      expect(rig.sent('auth'), isEmpty);
      expect(rig.sent('gauth'), isEmpty);
      await rig.connection.shutdown();
    },
  );

  test(
    'H3: a sent onDisconnect whose connection drops completes once with disconnect, '
    'not replayed',
    () async {
      final PRig rig = PRig(hold: true);
      await rig.start();
      final List<String> statuses = <String>[];
      rig.connection.onDisconnectPut(
        '/p',
        'off',
        onComplete: (String s, _) => statuses.add(s),
      );
      await rig.settle();
      expect(rig.sent('o'), hasLength(1));
      await rig.drop();
      await until(() => rig.connects == 2);
      await rig.settle();
      expect(statuses, <String>[statusDisconnect]);
      expect(rig.sent('o', onConnection: 2), isEmpty);
      await rig.connection.shutdown();
    },
  );

  test(
    'M1: no token can reach a plain-text WebSocket: a non-emulator ws target is refused',
    () {
      // PersistentConnection also withholds the App Check token and the credential requests
      // when mayReceiveTokens(connectionUri()) is false; since RealtimeTarget refuses such a
      // RepoInfo (M1 a), that check is defence in depth that no valid target reaches.
      expect(
        () => RealtimeTarget(
          const RepoInfo(
            host: 'x.firebaseio.com',
            namespace: 'x',
            secure: false,
          ),
          useHeaders: true,
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'M3: a token provider that never answers does not keep the client offline',
    () {
      fakeAsync((FakeAsync async) {
        final PRig rig = fakeTimeRig(async);
        rig.tokens.gate = Completer<void>(); // Never completed.
        rig.connection.initialize();
        async.elapse(const Duration(seconds: 1));
        expect(rig.tokens.authCalls, hasLength(1));
        // The fetch is bounded by connectTimeout (5 s in the shrunk timings), then retried after
        // the backoff less the 5 s the attempt took: at once. Exactly two fetches by 7 s; a
        // retry loop with no bound would make more.
        async.elapse(const Duration(seconds: 6));
        expect(rig.tokens.authCalls, hasLength(2));
        final int before = rig.tokens.authCalls.length;
        // A connectivity hint during a fetch restarts it at once.
        rig.hints.add(null);
        async.elapse(const Duration(milliseconds: 10));
        expect(rig.tokens.authCalls.length, before + 1);
        rig.tokens.gate!.complete();
        elapseUntil(async, () => rig.connects == 1);
        shutDownOnFakeTime(async, rig);
      });
    },
  );

  test(
    'M4/M5: a send failure inside the replay reports no connect and marks nothing sent',
    () async {
      final PRig rig = PRig(
        hold: true,
        wrapConnector: failFrameOfFirstChannel(3),
      );
      rig.server.connector.script(<AttemptBehavior>[
        const AttemptBehavior.accept(),
        const AttemptBehavior.refuse(),
      ]);
      final List<String> statuses = <String>[];
      rig.connection.listen(
        defaultListen('/a'),
        hashProvider: CountingHash(''),
        onComplete: (_, _) {},
      );
      rig.connection.put(
        '/tx',
        1,
        hash: 'h',
        onComplete: (String s, _) => statuses.add(s),
      );
      rig.connection.initialize();
      // Attempt 1: auth, appcheck, then the listen frame throws. Attempt 2 is refused.
      await until(() => rig.connects == 1);
      expect(rig.server.connections, 2);
      expect(
        rig.delegate.methods.where((String m) => m == 'connect'),
        hasLength(1),
      );
      expect(rig.delegate.methods, isNot(contains('disconnect')));
      expect(statuses, isEmpty);
      expect(rig.sent('p', onConnection: 2).single.body['h'], 'h');
      await rig.connection.shutdown();
    },
  );

  test(
    'M6: a get answer with an invalid key fails with failure and closes the connection',
    () async {
      final PRig rig = PRig(hold: true);
      await rig.start();
      final Future<Object?> result = rig.connection.get(defaultListen('/a'));
      final Future<void> failed = expectLater(
        result,
        throwsA(
          isA<ServerActionsException>().having(
            (ServerActionsException e) => e.status,
            'status',
            'failure',
          ),
        ),
      );
      await rig.answer('g', data: <String, Object?>{'a.b': 1});
      await failed;
      await until(() => rig.attemptTimes.length == 2);
      // Closed for this reason, as a protocol error, not by a later drop.
      expect(
        rig.logs.where((String l) => l.contains('protocol error')),
        <String>[
          'warning: protocol error: invalid data in an answer; reconnecting',
        ],
      );
      await rig.connection.shutdown();
    },
  );

  test(
    'M7: shutdown fails every outstanding get with database_closed',
    () async {
      final PRig rig = PRig();
      final Future<Object?> offline = rig.connection.get(defaultListen('/a'));
      final Future<void> failed = expectLater(
        offline,
        throwsA(
          isA<ServerActionsException>().having(
            (ServerActionsException e) => e.status,
            'status',
            'database_closed',
          ),
        ),
      );
      await rig.connection.shutdown();
      await failed.timeout(const Duration(seconds: 1));
      await expectLater(
        rig.connection.get(defaultListen('/b')),
        throwsA(
          isA<ServerActionsException>().having(
            (ServerActionsException e) => e.status,
            'status',
            'database_closed',
          ),
        ),
      );
    },
  );

  group('addendum 6', () {
    test(
      'after a dropped onDisconnect, the same put registered again is sent as a new request',
      () async {
        final PRig rig = PRig(hold: true);
        await rig.start();
        final List<String> statuses = <String>[];
        rig.connection.onDisconnectPut(
          '/p',
          'off',
          onComplete: (String s, _) => statuses.add('first $s'),
        );
        await rig.settle();
        await rig.drop();
        await until(() => rig.connects == 2);
        await rig.settle();
        expect(statuses, <String>['first $statusDisconnect']);
        rig.connection.onDisconnectMerge('/p', <String, Object?>{
          'state': 'off',
        }, onComplete: (String s, _) => statuses.add('again $s'));
        await rig.settle();
        expect(rig.sent('om', onConnection: 2).single.body['p'], '/p');
        await rig.answer('om');
        expect(statuses.last, 'again ok');
        await rig.connection.shutdown();
      },
    );

    test(
      'after a dropped onDisconnect, a cancel of that path is still sent',
      () async {
        final PRig rig = PRig();
        await rig.start();
        rig.connection.onDisconnectPut('/p', 'off');
        await rig.settle();
        await rig.drop();
        await until(() => rig.connects == 2);
        rig.connection.onDisconnectCancel('/p');
        await rig.settle();
        expect(rig.sent('oc', onConnection: 2).single.body, <String, Object?>{
          'p': '/p',
          'd': null,
        });
        await rig.connection.shutdown();
      },
    );

    for (final bool byPush in <bool>[true, false]) {
      test(
        'a ${byPush ? 'revoked' : 'failed'} listen is never re-sent and its callback never '
        'runs again',
        () async {
          final PRig rig = PRig(hold: true);
          await rig.start();
          final List<String> statuses = <String>[];
          rig.connection.listen(
            defaultListen('/l'),
            hashProvider: CountingHash(''),
            onComplete: (String s, _) => statuses.add(s),
          );
          await rig.settle();
          if (byPush) {
            await rig.answer('q');
            rig.server.pushListenCancel('/l');
          } else {
            await rig.answer('q', status: 'permission_denied');
          }
          await rig.settle();
          await rig.drop();
          await until(() => rig.connects == 2);
          rig.server.pushData('/l', 1);
          rig.server.pushListenCancel('/l');
          await rig.settle();
          expect(
            statuses,
            byPush
                ? <String>['ok', 'permission_denied']
                : <String>['permission_denied'],
          );
          expect(rig.sent('q', onConnection: 2), isEmpty);
          await rig.connection.shutdown();
        },
      );
    }
  });

  test(
    'addendum 7: a hint while connected sends exactly one ping and starts no connection',
    () {
      // The connection must be healthy (the server answered both credentials), or the 3.4
      // health rule pings again on every pong (liveness.dart onResponse); and the link is held
      // silent, or a pong re-arms the idle probe and a second hint after it probes again (both
      // correct). One second of virtual time is well inside the probe's 15 s timeout.
      fakeAsync((FakeAsync async) {
        final PRig rig = fakeTimeRig(async);
        _connect(async, rig, 1);
        expect(rig.delegate.callsOf('authStatus'), hasLength(1));
        final FakeWsChannel channel = rig.server.connector.last;
        channel.goSilent();
        bool isPing(String frame) {
          final Object? decoded = jsonDecode(frame);
          if (decoded is! Map<String, Object?> || decoded['t'] != 'c') {
            return false;
          }
          final Object? control = decoded['d'];
          return control is Map<String, Object?> && control['t'] == 'p';
        }

        int pings() => channel.sentFrames
            .where((SentFrame f) => f.text != '0' && isPing(f.text))
            .length;
        expect(pings(), 0);
        rig.hints
          ..add(null)
          ..add(null);
        async.elapse(const Duration(seconds: 1));
        expect(pings(), 1);
        expect(rig.attemptTimes, hasLength(1));
        expect(rig.delegate.methods, isNot(contains('disconnect')));
        channel.resume();
        shutDownOnFakeTime(async, rig);
      });
    },
  );
}
