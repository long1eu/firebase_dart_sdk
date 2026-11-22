// Owner P. Unit tests of PersistentConnection over FakeRtdbServer (test plan section 3, rows with
// P). Real time, shrunk timings (no fake_async in the package).
import 'dart:async';

import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/core/connection/wire_range_merge.dart';
import 'package:firebase_database_dart/src/testing/recording_server_actions_delegate.dart';
import 'package:test/test.dart';

import '../util/fake_rtdb_server.dart';
import '../util/persistent_connection_harness.dart';

void main() {
  late PRig rig;

  tearDown(() => rig.connection.shutdown());

  group('requests (4)', () {
    test(
      'B-4.0 request numbers start at 1 and are never reset by a reconnect',
      () async {
        rig = PRig();
        await rig.start();
        final List<int> first = rig.server.log
            .map((ServerSeen s) => s.r!)
            .toList();
        expect(first.first, 1);
        await rig.drop();
        await until(() => rig.connects == 2);
        final List<int> second = rig.server.log
            .where((ServerSeen s) => s.connection == 2)
            .map((ServerSeen s) => s.r!)
            .toList();
        expect(second.first, greaterThan(first.last));
      },
    );

    test(
      'B-4.0a a response for an unknown r is ignored; a non-object body fails the request',
      () async {
        rig = PRig();
        await rig.start();
        final List<String> statuses = <String>[];
        rig.connection.put(
          '/a',
          1,
          onComplete: (String s, _) => statuses.add(s),
        );
        await rig.settle();
        rig.server.connector.last.serverResponse(9999);
        await rig.settle();
        expect(statuses, isEmpty);
        final int r = rig.sent('p').single.r!;
        rig.server.connector.last.serverMessage(<String, Object?>{
          't': 'd',
          'd': <String, Object?>{'r': r, 'b': 'not an object'},
        });
        await rig.settle();
        // The core's operationFailed wire status (K's decoder; the stub's 'failed' was wrong).
        expect(statuses, <String>['failure']);
      },
    );

    test(
      'B-4.1a a default listen sends p and h only, h empty for an empty cache',
      () async {
        rig = PRig();
        await rig.start();
        rig.connection.listen(
          defaultListen('/users/ada'),
          hashProvider: CountingHash(''),
          onComplete: (_, _) {},
        );
        await rig.settle();
        expect(rig.sent('q').single.body, <String, Object?>{
          'p': '/users/ada',
          'h': '',
        });
      },
    );

    test(
      'B-4.1b a tagged listen sends the query object as given, t and h',
      () async {
        rig = PRig();
        await rig.start();
        rig.connection.listen(
          taggedListen('/users'),
          hashProvider: CountingHash('abc'),
          tag: 7,
          onComplete: (_, _) {},
        );
        await rig.settle();
        expect(rig.sent('q').single.body, <String, Object?>{
          'p': '/users',
          'h': 'abc',
          'q': <String, Object?>{'i': 'age', 'l': 10, 'vf': 'l'},
          't': 7,
        });
      },
    );

    test(
      'a non-default listen without a tag is refused (it takes the emulator down)',
      () {
        rig = PRig();
        expect(
          () => rig.connection.listen(
            taggedListen('/users'),
            hashProvider: CountingHash(''),
            onComplete: (_, _) {},
          ),
          throwsArgumentError,
        );
      },
    );

    test(
      'B-4.1c an ok listen stays and warns about no_index; a failed one is removed',
      () async {
        rig = PRig();
        await rig.start();
        final List<String> statuses = <String>[];
        rig.connection.listen(
          taggedListen('/users'),
          hashProvider: CountingHash(''),
          tag: 1,
          onComplete: (String s, _) => statuses.add('tagged $s'),
        );
        rig.connection.listen(
          defaultListen('/secret'),
          hashProvider: CountingHash(''),
          onComplete: (String s, _) => statuses.add('secret $s'),
        );
        await rig.settle();
        final List<ServerSeen> listens = rig.sent('q');
        rig.server.connector.last.serverResponse(
          listens[0].r!,
          data: <String, Object?>{
            'w': <Object?>['no_index'],
          },
        );
        rig.server.connector.last.serverResponse(
          listens[1].r!,
          status: 'permission_denied',
          data: 'denied',
        );
        await rig.settle();
        expect(statuses, <String>['tagged ok', 'secret permission_denied']);
        expect(
          rig.logs.where((String l) => l.contains('.indexOn": "age"')),
          hasLength(1),
        );
        await rig.drop();
        await until(() => rig.connects == 2);
        expect(
          rig.sent('q', onConnection: 2).map((ServerSeen s) => s.body['p']),
          <Object?>['/users'],
        );
      },
    );

    test('B-4.1d listening twice to the same path and query is an error', () {
      rig = PRig();
      rig.connection.listen(
        defaultListen('/a'),
        hashProvider: CountingHash(''),
        onComplete: (_, _) {},
      );
      expect(
        () => rig.connection.listen(
          defaultListen('/a'),
          hashProvider: CountingHash(''),
          onComplete: (_, _) {},
        ),
        throwsStateError,
      );
    });

    test(
      'B-4.2 unlisten sends p (q and t only when tagged), never offline or unknown',
      () async {
        rig = PRig();
        rig.connection.listen(
          defaultListen('/offline'),
          hashProvider: CountingHash(''),
          onComplete: (_, _) {},
        );
        rig.connection.unlisten(defaultListen('/offline'));
        await rig.start();
        expect(rig.sent('q'), isEmpty);
        rig.connection.listen(
          defaultListen('/a'),
          hashProvider: CountingHash(''),
          onComplete: (_, _) {},
        );
        rig.connection.listen(
          taggedListen('/b'),
          hashProvider: CountingHash(''),
          tag: 2,
          onComplete: (_, _) {},
        );
        rig.connection.unlisten(defaultListen('/a'));
        rig.connection.unlisten(taggedListen('/b'), tag: 2);
        rig.connection.unlisten(defaultListen('/never'));
        await rig.settle();
        expect(rig.sent('n').map((ServerSeen s) => s.body), <Object?>[
          <String, Object?>{'p': '/a'},
          <String, Object?>{
            'p': '/b',
            'q': <String, Object?>{'i': 'age', 'l': 10, 'vf': 'l'},
            't': 2,
          },
        ]);
      },
    );

    test(
      'B-4.3a a get sends p and q, never t or h; offline it waits for the connection',
      () async {
        rig = PRig();
        final Future<Object?> result = rig.connection.get(
          taggedListen('/users'),
        );
        await rig.settle();
        expect(rig.server.log, isEmpty);
        await rig.start();
        expect(rig.sent('g').single.body, <String, Object?>{
          'p': '/users',
          'q': <String, Object?>{'i': 'age', 'l': 10, 'vf': 'l'},
        });
        await rig.answer('g', data: <String, Object?>{'ada': 1});
        expect(await result, <String, Object?>{'ada': 1});
      },
    );

    test('B-4.4a put shapes and completions with status and reason', () async {
      rig = PRig();
      await rig.start();
      final List<String> results = <String>[];
      rig.connection.put('/a', <String, Object?>{'.value': 1, '.priority': 2});
      rig.connection.put('/b', null);
      rig.connection.put(
        '/c/.priority',
        5,
        onComplete: (String s, Object? d) => results.add('$s $d'),
      );
      await rig.settle();
      expect(rig.sent('p').map((ServerSeen s) => s.body), <Object?>[
        <String, Object?>{
          'p': '/a',
          'd': <String, Object?>{'.value': 1, '.priority': 2},
        },
        <String, Object?>{'p': '/b', 'd': null},
        <String, Object?>{'p': '/c/.priority', 'd': 5},
      ]);
      await rig.answer('p', status: 'permission_denied', data: 'no write');
      expect(results, <String>['permission_denied no write']);
    });

    test(
      'B-4.4b a merge keeps relative-path keys and server values unresolved',
      () async {
        rig = PRig();
        await rig.start();
        rig.connection.merge('/u', <String, Object?>{
          'a/b': 1,
          'n': <String, Object?>{
            '.sv': <String, Object?>{'increment': 1},
          },
        });
        await rig.settle();
        expect(rig.sent('m').single.body, <String, Object?>{
          'p': '/u',
          'd': <String, Object?>{
            'a/b': 1,
            'n': <String, Object?>{
              '.sv': <String, Object?>{'increment': 1},
            },
          },
        });
      },
    );

    test(
      'B-4.5a onDisconnect shapes; oc carries d: null; the callback is never synchronous',
      () async {
        rig = PRig();
        await rig.start();
        final List<String> statuses = <String>[];
        rig.connection.onDisconnectPut(
          '/p',
          false,
          onComplete: (String s, _) => statuses.add(s),
        );
        rig.connection.onDisconnectMerge('/p', <String, Object?>{'a': 1});
        rig.connection.onDisconnectCancel('/p');
        await rig.settle();
        expect(
          rig.server.log
              .where((ServerSeen s) => s.action.startsWith('o'))
              .map((s) => s.body),
          <Object?>[
            <String, Object?>{'p': '/p', 'd': false},
            <String, Object?>{
              'p': '/p',
              'd': <String, Object?>{'a': 1},
            },
            <String, Object?>{'p': '/p', 'd': null},
          ],
        );
        final ServerSeen o = rig.sent('o').single;
        rig.server.connector.last.serverResponse(o.r!);
        expect(statuses, isEmpty);
        await rig.settle();
        expect(statuses, <String>['ok']);
      },
    );

    test('B-4.9 no stats request is ever sent', () async {
      rig = PRig();
      await rig.start();
      await rig.drop();
      await until(() => rig.connects == 2);
      expect(rig.sent('s'), isEmpty);
    });
  });

  group('pushes (5)', () {
    test(
      'B-5.1 d and m pushes reach the delegate at /a/b with their tag; tag 0 is untagged',
      () async {
        rig = PRig();
        await rig.start();
        rig.server.pushData('/a/b', 1);
        rig.server.pushMerge('/a', <String, Object?>{'b/c': 2}, tag: 4);
        rig.server.pushData('/', 'root', tag: 0);
        await rig.settle();
        final List<DelegateCall> updates = rig.delegate.callsOf('dataUpdate');
        expect(
          updates.map((DelegateCall c) => '${c.path} ${c.isMerge} ${c.tag}'),
          <String>['/a/b false null', '/a true 4', '/ false null'],
        );
      },
    );

    test(
      'B-5.1 an rm push reaches the delegate as range merges at /a/b',
      () async {
        rig = PRig();
        await rig.start();
        rig.server.pushRangeMerge('/ch', <Map<String, Object?>>[
          <String, Object?>{
            'e': 'ch/c4',
            'm': <String, Object?>{'c1': 1},
          },
          <String, Object?>{
            's': 'ch/c4',
            'm': <String, Object?>{'c5': 5},
          },
        ]);
        await rig.settle();
        final DelegateCall call = rig.delegate
            .callsOf('rangeMergeUpdate')
            .single;
        expect(call.path, '/ch');
        expect(
          call.merges!.map((WireRangeMerge m) => m.inclusiveEnd),
          <String?>['/ch/c4', null],
        );
      },
    );

    test(
      'B-5.2 a c push cancels every listen at its path with permission_denied',
      () async {
        rig = PRig();
        await rig.start();
        final List<String> statuses = <String>[];
        for (final (String name, int? tag) in <(String, int?)>[
          ('default', null),
          ('tagged', 3),
        ]) {
          rig.connection.listen(
            tag == null ? defaultListen('/users') : taggedListen('/users'),
            hashProvider: CountingHash(''),
            tag: tag,
            onComplete: (String s, _) => statuses.add('$name $s'),
          );
        }
        rig.connection.listen(
          defaultListen('/other'),
          hashProvider: CountingHash(''),
          onComplete: (String s, _) => statuses.add('other $s'),
        );
        await rig.settle();
        rig.server.pushListenCancel('/users', <Map<String, Object?>>[
          <String, Object?>{'l': 10},
        ]);
        await rig.settle();
        expect(statuses, <String>[
          'default permission_denied',
          'tagged permission_denied',
        ]);
      },
    );

    test(
      'B-5.6 a data push and the response after it reach Repo in order',
      () async {
        rig = PRig();
        await rig.start();
        final List<String> order = <String>[];
        rig.onCall = order.add;
        rig.connection.listen(
          defaultListen('/a'),
          hashProvider: CountingHash(''),
          onComplete: (String s, _) => order.add('complete $s'),
        );
        await rig.settle();
        order.clear();
        rig.server.pushData('/a', 1);
        rig.server.connector.last.serverResponse(rig.sent('q').single.r!);
        await rig.settle();
        expect(order, <String>['dataUpdate', 'complete ok']);
      },
    );
  });

  group('connection management (8)', () {
    test(
      'B-8.1a nothing connects before initialize; initialize connects at once',
      () async {
        rig = PRig();
        await rig.settle();
        expect(rig.attemptTimes, isEmpty);
        await rig.start();
        expect(rig.attemptTimes, hasLength(1));
      },
    );

    test(
      'B-8.1b tokens are fetched without forcing; a failed fetch backs off and retries',
      () async {
        rig = PRig();
        rig.tokens.error = Exception('provider down');
        rig.connection.initialize();
        await until(() => rig.tokens.authCalls.length >= 2);
        expect(rig.attemptTimes, isEmpty);
        expect(rig.tokens.authCalls.first, isFalse);
        expect(
          rig.logs.any((String l) => l.contains('provider down')),
          isFalse,
        );
        rig.tokens.error = null;
        await until(() => rig.connects == 1);
      },
    );

    test(
      'B-8.6b an interrupt while the tokens are fetched drops the fetch',
      () async {
        rig = PRig();
        rig.tokens.gate = Completer<void>();
        rig.connection.initialize();
        await until(() => rig.tokens.authCalls.isNotEmpty);
        rig.connection.interrupt('repo_interrupt');
        rig.tokens.gate!.complete();
        await rig.settle();
        await rig.settle();
        expect(rig.attemptTimes, isEmpty);
        rig.connection.resume('repo_interrupt');
        await until(() => rig.connects == 1);
      },
    );

    test(
      'B-8.6a interrupt closes without reconnecting; resume reconnects at once',
      () async {
        rig = PRig(
          timings: shrunkTimings(
            reconnectMin: const Duration(hours: 1),
            reconnectMax: const Duration(hours: 1),
          ),
        );
        await rig.start();
        rig.connection.interrupt('repo_interrupt');
        await until(() => rig.delegate.callsOf('disconnect').length == 1);
        expect(rig.connection.isInterrupted('repo_interrupt'), isTrue);
        await rig.settle();
        expect(rig.attemptTimes, hasLength(1));
        rig.connection.resume('repo_interrupt');
        await until(() => rig.connects == 2);
      },
    );

    test(
      'B-8.6a a server shutdown reports the reason and is never followed by a reconnect',
      () async {
        rig = PRig();
        await rig.start();
        rig.server.pushShutdown('maintenance');
        await until(() => rig.delegate.callsOf('serverShutdown').isNotEmpty);
        expect(rig.connection.isInterrupted('server_kill'), isTrue);
        rig.connection.resume('server_kill');
        rig.connection.interrupt('repo_interrupt');
        rig.connection.resume('repo_interrupt');
        await rig.settle();
        await rig.settle();
        expect(rig.attemptTimes, hasLength(1));
      },
    );

    test(
      'B-8.2c a connectivity hint starts a waiting attempt at once',
      () async {
        rig = PRig(
          timings: shrunkTimings(
            reconnectMin: const Duration(hours: 1),
            reconnectMax: const Duration(hours: 1),
          ),
        );
        await rig.start();
        await rig.drop();
        await rig.settle();
        expect(rig.attemptTimes, hasLength(1));
        rig.hints.add(null);
        await until(() => rig.connects == 2);
      },
    );

    test(
      'an admin credential (the emulator owner) goes out as gauth',
      () async {
        rig = PRig()..tokens.auth = 'owner';
        await rig.start();
        expect(rig.actionsOn(1).first, 'gauth');
        expect(rig.sent('gauth').single.body, <String, Object?>{
          'cred': 'owner',
        });
        expect(rig.sent('auth'), isEmpty);
      },
    );

    test(
      'B-8.3a every connection sends auth, then appcheck, before its listens',
      () async {
        rig = PRig();
        rig.connection.listen(
          defaultListen('/a'),
          hashProvider: CountingHash(''),
          onComplete: (_, _) {},
        );
        await rig.start();
        await rig.drop();
        await until(() => rig.connects == 2);
        for (final int n in <int>[1, 2]) {
          expect(rig.actionsOn(n).take(3), <String>['auth', 'appcheck', 'q']);
        }
      },
    );

    test('B-8.4a the replay recomputes every listen hash', () async {
      rig = PRig();
      final CountingHash hash = CountingHash('one');
      rig.connection.listen(
        defaultListen('/a'),
        hashProvider: hash,
        onComplete: (_, _) {},
      );
      await rig.start();
      hash.hash = 'two';
      await rig.drop();
      await until(() => rig.connects == 2);
      expect(rig.sent('q').map((ServerSeen s) => s.body['h']), <Object?>[
        'one',
        'two',
      ]);
    });

    test('B-8.4c onConnect comes only after the replay was sent', () async {
      // MERGE: T: relies on FakeRtdbServer.log being appended when the client's frame is sent
      // (synchronously in FakeWsChannel.sendText), before any microtask of the client runs.
      rig = PRig();
      rig.connection.put('/a', 1);
      rig.connection.listen(
        defaultListen('/a'),
        hashProvider: CountingHash(''),
        onComplete: (_, _) {},
      );
      final List<String> seenAtConnect = <String>[];
      rig.onCall = (String method) {
        if (method == 'connect') {
          seenAtConnect.addAll(rig.server.log.map((ServerSeen s) => s.action));
        }
      };
      await rig.start();
      expect(seenAtConnect, <String>['auth', 'appcheck', 'q', 'p']);
    });

    test(
      'the hello publishes serverTimeOffset and its session id becomes ls',
      () async {
        rig = PRig();
        await rig.start();
        final Map<String, Object?> info =
            rig.delegate.callsOf('serverInfoUpdate').single.data!
                as Map<String, Object?>;
        final int offset = info['serverTimeOffset']! as int;
        expect(
          (PRig.serverTimeMs - DateTime.now().millisecondsSinceEpoch - offset)
              .abs(),
          lessThan(5000),
        );
        await rig.drop();
        await until(() => rig.connects == 2);
        expect(rig.lastSessionIds, <String?>[null, 'sess-1']);
      },
    );

    test(
      'B-8.5 an unsent transaction put survives a drop and is sent at the reconnect',
      () async {
        rig = PRig(
          timings: shrunkTimings(
            reconnectMin: const Duration(hours: 1),
            reconnectMax: const Duration(hours: 1),
          ),
        );
        await rig.start();
        await rig.drop();
        final List<String> statuses = <String>[];
        rig.connection.put(
          '/tx',
          1,
          hash: 'h',
          onComplete: (String s, _) => statuses.add(s),
        );
        rig.hints.add(null);
        await until(() => rig.connects == 2);
        expect(rig.sent('p', onConnection: 2).single.body, <String, Object?>{
          'p': '/tx',
          'd': 1,
          'h': 'h',
        });
        expect(statuses, isEmpty);
      },
    );

    test(
      'purgeOutstandingWrites completes every write with write_canceled, asynchronously',
      () async {
        rig = PRig();
        await rig.start();
        final List<String> statuses = <String>[];
        rig.connection.put(
          '/a',
          1,
          onComplete: (String s, _) => statuses.add('a $s'),
        );
        rig.connection.merge('/b', <String, Object?>{
          'c': 1,
        }, onComplete: (String s, _) => statuses.add('b $s'));
        await rig.settle();
        rig.connection.purgeOutstandingWrites();
        expect(statuses, isEmpty);
        await rig.settle();
        expect(statuses, <String>['a write_canceled', 'b write_canceled']);
        await rig.answer('p');
        expect(statuses, hasLength(2));
      },
    );

    test(
      'shutdown drops every callback; later calls are ignored and a get fails',
      () async {
        rig = PRig();
        await rig.start();
        final List<String> statuses = <String>[];
        rig.connection.put(
          '/a',
          1,
          onComplete: (String s, _) => statuses.add(s),
        );
        await rig.settle();
        await rig.connection.shutdown();
        rig.connection.put(
          '/b',
          1,
          onComplete: (String s, _) => statuses.add(s),
        );
        await expectLater(
          rig.connection.get(defaultListen('/a')),
          throwsA(isA<ServerActionsException>()),
        );
        await rig.settle();
        expect(statuses, isEmpty);
        expect(rig.sent('p'), hasLength(1));
      },
    );
  });

  group('request timeouts', () {
    test(
      'a request waiting offline is not timed: only the time on a live socket counts',
      () async {
        rig = PRig(
          timings: shrunkTimings(
            requestTimeout: const Duration(milliseconds: 40),
          ),
        );
        final List<String> statuses = <String>[];
        rig.connection.put(
          '/a',
          1,
          onComplete: (String s, _) => statuses.add(s),
        );
        rig.connection.interrupt('repo_interrupt');
        rig.connection.initialize();
        await Future<void>.delayed(const Duration(milliseconds: 120));
        expect(statuses, isEmpty);
        rig.connection.resume('repo_interrupt');
        await until(() => rig.connects == 1);
        await rig.answerCredentials();
        expect(rig.sent('p'), hasLength(1));
        expect(statuses, isEmpty);
      },
    );

    test(
      'the first timeout reconnects and replays; the second fails with network_error',
      () async {
        rig = PRig(
          timings: shrunkTimings(
            requestTimeout: const Duration(milliseconds: 40),
          ),
        );
        await rig.start();
        await rig.answerCredentials();
        final List<String> statuses = <String>[];
        final Future<Object?> get = rig.connection.get(defaultListen('/g'));
        // The expectation listens before the failure, or the error would be unhandled.
        final Future<void> getFailed = expectLater(
          get,
          throwsA(
            isA<ServerActionsException>().having(
              (ServerActionsException e) => e.status,
              'status',
              'network_error',
            ),
          ),
        );
        rig.connection.put(
          '/a',
          1,
          onComplete: (String s, _) => statuses.add(s),
        );
        // First timeout: both the get and the put were waiting, both count one; reconnect.
        await until(() => rig.connects == 2);
        await rig.answerCredentials();
        expect(rig.sent('p', onConnection: 2), hasLength(1));
        expect(rig.sent('g', onConnection: 2), hasLength(1));
        expect(statuses, isEmpty);
        // Second timeout: both fail; nothing is left waiting, so the connection stays.
        await until(() => statuses.isNotEmpty);
        expect(statuses, <String>['network_error']);
        await getFailed;
        expect(rig.connects, 2);
        await rig.drop();
        await until(() => rig.connects == 3);
        expect(rig.sent('p', onConnection: 3), isEmpty);
        expect(rig.sent('g', onConnection: 3), isEmpty);
      },
    );
  });
}
