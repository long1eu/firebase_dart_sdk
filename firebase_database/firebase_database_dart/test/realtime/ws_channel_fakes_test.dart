// Owner T. The test doubles every other owner builds on (test plan 2.2, 2.3): FakeWsChannel,
// FakeWsConnector and FakeRtdbServer behave as documented, deterministically.

import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_database_dart/src/realtime/framing.dart';
import 'package:firebase_database_dart/src/realtime/transport/ws_channel.dart';
import 'package:test/test.dart';

import '../util/fake_rtdb_server.dart';
import '../util/fake_ws.dart';

/// Records the events of [channel]; read them after [pumpEventQueue].
List<WsEvent> _record(WsChannel channel) {
  final List<WsEvent> events = <WsEvent>[];
  channel.events.listen(events.add);
  return events;
}

/// The decoded text frames among [events], joined with the production assembler.
List<Map<String, Object?>> _messages(List<WsEvent> events) {
  final FrameAssembler assembler = FrameAssembler(
    maxMessageBytes: 1 << 24,
    maxDepth: 64,
  );
  return <Map<String, Object?>>[
    for (final WsEvent event in events)
      if (event is WsText) ?assembler.add(event.data),
  ];
}

/// Sends [message] from the client side as JSON, split into frames of [frameUnits].
void _clientSend(
  WsChannel channel,
  Map<String, Object?> message, {
  int frameUnits = 16384,
}) {
  FrameSplitter(
    maxFrameUnits: frameUnits,
  ).framesFor(jsonEncode(message)).forEach(channel.sendText);
}

Map<String, Object?> _request(
  int r,
  String action,
  Map<String, Object?> body,
) => <String, Object?>{
  't': 'd',
  'd': <String, Object?>{'r': r, 'a': action, 'b': body},
};

void main() {
  group('FakeWsChannel', () {
    test('sentMessages joins counted frames and skips the keep-alive', () {
      final FakeWsChannel channel = FakeWsChannel();
      channel.sendText('0');
      _clientSend(
        channel,
        _request(1, 'p', <String, Object?>{'p': '/a', 'd': 'x' * 40}),
        frameUnits: 16,
      );
      _clientSend(channel, _request(2, 'q', <String, Object?>{'p': '/b'}));
      expect(channel.sentFrames.first.text, '0');
      expect(channel.sentMessages, hasLength(2));
      expect(channel.sentRequests('p').single['r'], 1);
      expect(channel.lastRequest('q')!['b'], <String, Object?>{'p': '/b'});
      expect(channel.lastRequest('g'), isNull);
      expect(channel.sentRequests(), hasLength(2));
    });

    test('SentFrame.at is the virtual time; toString hides the text', () {
      Duration now = Duration.zero;
      final FakeWsChannel channel = FakeWsChannel(elapsed: () => now);
      now = const Duration(seconds: 45);
      channel.sendText('secret-token');
      expect(channel.sentFrames.single.at, const Duration(seconds: 45));
      expect('${channel.sentFrames.single}', isNot(contains('secret')));
    });

    test(
      'serverMessage with frameSize sends a count and pieces that join back',
      () async {
        final FakeWsChannel channel = FakeWsChannel();
        final List<WsEvent> events = _record(channel);
        final Map<String, Object?> envelope = <String, Object?>{
          't': 'd',
          'd': <String, Object?>{
            'a': 'd',
            'b': <String, Object?>{'p': 'a', 'd': 'y' * 30},
          },
        };
        channel.serverMessage(envelope, frameSize: 5);
        await pumpEventQueue();
        final List<String> frames = <String>[
          for (final WsEvent e in events) (e as WsText).data,
        ];
        expect(int.parse(frames.first), frames.length - 1);
        expect(frames.skip(1).every((String f) => f.length <= 5), isTrue);
        expect(_messages(events), <Map<String, Object?>>[envelope]);
      },
    );

    test('the shaped helpers deliver the documented envelopes', () async {
      final FakeWsChannel channel = FakeWsChannel();
      final List<WsEvent> events = _record(channel);
      channel
        ..serverHello(ts: 5, h: 'h.example')
        ..serverResponse(3, data: <String, Object?>{})
        ..serverPush('d', <String, Object?>{'p': 'a', 'd': 1})
        ..serverControl('o');
      await pumpEventQueue();
      expect(_messages(events), <Map<String, Object?>>[
        <String, Object?>{
          't': 'c',
          'd': <String, Object?>{
            't': 'h',
            'd': <String, Object?>{
              'ts': 5,
              'v': '5',
              'h': 'h.example',
              's': 'sess-1',
            },
          },
        },
        <String, Object?>{
          't': 'd',
          'd': <String, Object?>{
            'r': 3,
            'b': <String, Object?>{'s': 'ok', 'd': <String, Object?>{}},
          },
        },
        <String, Object?>{
          't': 'd',
          'd': <String, Object?>{
            'a': 'd',
            'b': <String, Object?>{'p': 'a', 'd': 1},
          },
        },
        <String, Object?>{
          't': 'c',
          'd': <String, Object?>{'t': 'o', 'd': null},
        },
      ]);
    });

    test(
      'nothing is delivered synchronously: the client is never re-entered',
      () {
        final FakeWsChannel channel = FakeWsChannel();
        final List<WsEvent> events = _record(channel);
        channel.serverText('{}');
        expect(events, isEmpty);
      },
    );

    test('a binary frame, also an empty one', () async {
      final FakeWsChannel channel = FakeWsChannel();
      final List<WsEvent> events = _record(channel);
      channel
        ..serverBinary(<int>[1, 2])
        ..serverBinary(<int>[]);
      await pumpEventQueue();
      expect(events.map((WsEvent e) => (e as WsBinary).data.length), <int>[
        2,
        0,
      ]);
    });

    test(
      'serverClose ends the stream with the code; sendText then throws',
      () async {
        final FakeWsChannel channel = FakeWsChannel();
        final List<WsEvent> events = _record(channel);
        channel
          ..serverClose(1011, 'boom')
          ..serverText('{}');
        await pumpEventQueue();
        expect(events, hasLength(1));
        expect((events.single as WsClosed).code, 1011);
        expect((events.single as WsClosed).reason, 'boom');
        expect(channel.isClosed, isTrue);
        expect(channel.localCloseCode, isNull);
        expect(() => channel.sendText('x'), throwsStateError);
      },
    );

    test('serverError gives WsError then WsClosed(1006)', () async {
      final FakeWsChannel channel = FakeWsChannel();
      final List<WsEvent> events = _record(channel);
      channel.serverError(StateError('cut'));
      await pumpEventQueue();
      expect(events.first, isA<WsError>());
      expect((events.last as WsClosed).code, 1006);
    });

    test('close records the code, is idempotent and ends the stream', () async {
      final FakeWsChannel channel = FakeWsChannel();
      final List<WsEvent> events = _record(channel);
      await channel.close(4000);
      await channel.close(1000);
      await pumpEventQueue();
      expect(channel.localCloseCode, 4000);
      expect((events.single as WsClosed).code, 4000);
      expect(channel.abandoned, isFalse);
    });

    test('abandon ends the stream with WsClosed(null)', () async {
      final FakeWsChannel channel = FakeWsChannel();
      final List<WsEvent> events = _record(channel);
      channel.abandon();
      await pumpEventQueue();
      expect(channel.abandoned, isTrue);
      expect(channel.isClosed, isTrue);
      expect((events.single as WsClosed).code, isNull);
    });

    test(
      'half-open: nothing is delivered either way, then resume delivers in order',
      () async {
        final FakeWsChannel channel = FakeWsChannel();
        final List<String> serverGot = <String>[];
        channel.onClientFrame = serverGot.add;
        final List<WsEvent> events = _record(channel);
        channel.goSilent(dropOutbound: false);
        channel
          ..serverText('{"n":1}')
          ..serverText('{"n":2}')
          ..sendText('{"p":1}');
        await pumpEventQueue();
        expect(events, isEmpty);
        expect(serverGot, isEmpty);
        expect(channel.sentFrames, hasLength(1));
        channel.resume();
        await pumpEventQueue();
        expect(serverGot, <String>['{"p":1}']);
        expect(_messages(events), <Map<String, Object?>>[
          <String, Object?>{'n': 1},
          <String, Object?>{'n': 2},
        ]);
      },
    );

    test(
      'half-open with dropOutbound loses the frames sent meanwhile',
      () async {
        final FakeWsChannel channel = FakeWsChannel();
        final List<String> serverGot = <String>[];
        channel.onClientFrame = serverGot.add;
        channel
          ..goSilent()
          ..sendText('{"lost":1}')
          ..resume()
          ..sendText('{"kept":1}');
        expect(serverGot, <String>['{"kept":1}']);
      },
    );

    test(
      'a close while silent is held too: the client sees nothing until resume',
      () async {
        final FakeWsChannel channel = FakeWsChannel();
        final List<WsEvent> events = _record(channel);
        channel
          ..goSilent()
          ..serverClose(1006);
        await pumpEventQueue();
        expect(events, isEmpty);
        expect(channel.isClosed, isFalse);
        channel.resume();
        await pumpEventQueue();
        expect((events.single as WsClosed).code, 1006);
      },
    );
  });

  group('FakeWsConnector', () {
    test('follows the script, then accepts; records every attempt', () async {
      final FakeWsConnector connector = FakeWsConnector();
      connector.script(const <AttemptBehavior>[
        AttemptBehavior.refuse(),
        AttemptBehavior.dnsFailure(),
      ]);
      final Uri url = Uri.parse('wss://h.example/.ws?v=5');
      await expectLater(
        connector.connect(url),
        throwsA(
          isA<WsConnectException>().having(
            (WsConnectException e) => e.kind,
            'kind',
            WsConnectFailure.refused,
          ),
        ),
      );
      await expectLater(
        connector.connect(
          url,
          headers: <String, String>{'X-Firebase-AppCheck': 'ac'},
        ),
        throwsA(
          isA<WsConnectException>().having(
            (WsConnectException e) => e.kind,
            'kind',
            WsConnectFailure.dns,
          ),
        ),
      );
      final WsChannel channel = await connector.connect(url);
      expect(connector.attempts, hasLength(3));
      expect(connector.attempts[1].headers, <String, String>{
        'X-Firebase-AppCheck': 'ac',
      });
      expect(connector.attempts[0].channel, isNull);
      expect(identical(connector.attempts[2].channel, channel), isTrue);
      expect(identical(connector.last, channel), isTrue);
      expect('${connector.attempts[1]}', isNot(contains('ac')));
    });

    test(
      'a non-ws scheme fails with badScheme and uses no scripted behaviour',
      () async {
        final FakeWsConnector connector = FakeWsConnector();
        connector.script(const <AttemptBehavior>[AttemptBehavior.refuse()]);
        await expectLater(
          connector.connect(Uri.parse('https://h.example/.ws')),
          throwsA(
            isA<WsConnectException>().having(
              (WsConnectException e) => e.kind,
              'kind',
              WsConnectFailure.badScheme,
            ),
          ),
        );
        await expectLater(
          connector.connect(Uri.parse('wss://h.example/.ws')),
          throwsA(isA<WsConnectException>()),
        );
      },
    );

    test('hang never completes', () async {
      final FakeWsConnector connector = FakeWsConnector();
      connector.script(const <AttemptBehavior>[AttemptBehavior.hang()]);
      bool completed = false;
      unawaited(
        connector
            .connect(Uri.parse('wss://h/.ws'))
            .then((_) => completed = true),
      );
      await pumpEventQueue();
      expect(completed, isFalse);
      expect(connector.attempts.single.channel, isNull);
    });

    test(
      'acceptThenSilent holds everything; acceptThenClose closes with the code',
      () async {
        final FakeWsConnector connector = FakeWsConnector(autoHello: true);
        connector.script(const <AttemptBehavior>[
          AttemptBehavior.acceptThenSilent(),
          AttemptBehavior.acceptThenClose(1011),
        ]);
        final FakeWsChannel silent =
            await connector.connect(Uri.parse('wss://h/.ws')) as FakeWsChannel;
        final List<WsEvent> silentEvents = _record(silent);
        final List<WsEvent> closedEvents = _record(
          await connector.connect(Uri.parse('wss://h/.ws')),
        );
        await pumpEventQueue();
        expect(silent.isSilent, isTrue);
        expect(silentEvents, isEmpty);
        expect((closedEvents.single as WsClosed).code, 1011);
        silent.resume();
        await pumpEventQueue();
        expect(_messages(silentEvents).single['t'], 'c');
      },
    );

    test('autoHello and nextChannel', () async {
      Duration now = const Duration(seconds: 2);
      final FakeWsConnector connector = FakeWsConnector(
        autoHello: true,
        elapsed: () => now,
      );
      final Future<FakeWsChannel> next = connector.nextChannel;
      final List<WsEvent> events = _record(
        await connector.connect(Uri.parse('wss://s-1.example/.ws')),
      );
      expect(identical(await next, connector.last), isTrue);
      await pumpEventQueue();
      expect(_messages(events).single['d'], <String, Object?>{
        't': 'h',
        'd': <String, Object?>{
          'ts': FakeWsConnector.helloEpochMs + 2000,
          'v': '5',
          'h': 's-1.example',
          's': 'sess-1',
        },
      });
      expect(connector.attempts.single.at, const Duration(seconds: 2));
    });

    test('an aborted hang fails with other (review M2)', () async {
      final FakeWsConnector connector = FakeWsConnector();
      connector.script(const <AttemptBehavior>[AttemptBehavior.hang()]);
      final Completer<void> abort = Completer<void>();
      final Future<WsChannel> attempt = connector.connect(
        Uri.parse('wss://h/.ws'),
        abort: abort.future,
      );
      expect(identical(connector.attempts.single.abort, abort.future), isTrue);
      abort.complete();
      await expectLater(
        attempt,
        throwsA(
          isA<WsConnectException>().having(
            (WsConnectException e) => e.kind,
            'kind',
            WsConnectFailure.other,
          ),
        ),
      );
    });

    test('last before any accepted attempt throws', () {
      expect(() => FakeWsConnector().last, throwsStateError);
    });
  });

  group('FakeRtdbServer', () {
    late FakeRtdbServer server;
    late WsChannel channel;
    late List<WsEvent> events;

    Future<void> open() async {
      channel = await server.connect(Uri.parse('wss://h.example/.ws?v=5'));
      events = _record(channel);
      await pumpEventQueue();
    }

    Future<List<Map<String, Object?>>> send(
      Map<String, Object?> message,
    ) async {
      final int before = _messages(events).length;
      _clientSend(channel, message);
      await pumpEventQueue();
      return _messages(events).sublist(before);
    }

    setUp(() async {
      server = FakeRtdbServer(host: 's-1.example', clock: () => 42);
      await open();
    });

    // Review M8: each test below failed against the fake before it modelled the measurement.
    group('as measured on the emulator (review M8)', () {
      Map<String, Object?> inner(Map<String, Object?> message) =>
          message['d']! as Map<String, Object?>;

      Map<String, Object?> answerOf(List<Map<String, Object?>> messages) =>
          inner(messages.last)['b']! as Map<String, Object?>;

      List<Map<String, Object?>> pushes(List<Map<String, Object?>> messages) =>
          <Map<String, Object?>>[
            for (final Map<String, Object?> m in messages)
              if (m['t'] == 'd' && inner(m)['a'] != null) inner(m),
          ];

      test(
        'a write is pushed once per overlapping listen, with its tag',
        () async {
          await send(_request(1, 'q', <String, Object?>{'p': '/', 'h': ''}));
          await send(
            _request(2, 'q', <String, Object?>{
              'p': '/people',
              'q': <String, Object?>{'l': 1, 'vf': 'l'},
              't': 1,
              'h': '',
            }),
          );
          await send(
            _request(3, 'q', <String, Object?>{
              'p': '/people',
              'q': <String, Object?>{'l': 2, 'vf': 'r'},
              't': 2,
              'h': '',
            }),
          );
          final List<Map<String, Object?>> got = await send(
            _request(4, 'p', <String, Object?>{'p': '/people/0', 'd': 1}),
          );
          expect(pushes(got).map((Map<String, Object?> p) => p['b']), <Object?>[
            <String, Object?>{'p': 'people/0', 'd': 1},
            <String, Object?>{'p': 'people/0', 'd': 1, 't': 1},
            <String, Object?>{'p': 'people/0', 'd': 1, 't': 2},
          ]);
        },
      );

      test(
        'a listen whose hash matches gets no push; a wrong hash gets the data',
        () async {
          server.data['v'] = 5;
          // The hash the emulator accepted for the leaf 5 (probe addendum 4, measured).
          const String hashOf5 = 'w28swksk9+tXf5jEdS9R5oSFAv8=';
          final List<Map<String, Object?>> matched = await send(
            _request(1, 'q', <String, Object?>{'p': '/v', 'h': hashOf5}),
          );
          expect(pushes(matched), isEmpty);
          expect(answerOf(matched), <String, Object?>{
            's': 'ok',
            'd': <String, Object?>{},
          });
          final List<Map<String, Object?>> stale = await send(
            _request(2, 'q', <String, Object?>{'p': '/v', 'h': 'AAAA'}),
          );
          expect(pushes(stale).single['b'], <String, Object?>{
            'p': 'v',
            'd': 5,
          });
        },
      );

      test(
        'a hashed put: datastale on a mismatch, the new value on a match',
        () async {
          server.data['v'] = 5;
          final List<Map<String, Object?>> stale = await send(
            _request(1, 'p', <String, Object?>{'p': '/v', 'd': 7, 'h': 'AAAA'}),
          );
          expect(answerOf(stale), <String, Object?>{
            's': 'datastale',
            'd': 'Transaction ETag does not match',
          });
          expect(server.data['v'], 5);
          final List<Map<String, Object?>> written = await send(
            _request(2, 'p', <String, Object?>{
              'p': '/v',
              'd': 7,
              'h': 'w28swksk9+tXf5jEdS9R5oSFAv8=',
            }),
          );
          expect(answerOf(written), <String, Object?>{'s': 'ok', 'd': 7});
          expect(server.data['v'], 7);
        },
      );

      test('server values are resolved in what is stored and pushed', () async {
        await send(_request(1, 'q', <String, Object?>{'p': '/', 'h': ''}));
        final Map<String, Object?> increment = <String, Object?>{
          '.sv': <String, Object?>{'increment': 3},
        };
        final List<Map<String, Object?>> first = await send(
          _request(2, 'p', <String, Object?>{'p': '/n', 'd': increment}),
        );
        final List<Map<String, Object?>> second = await send(
          _request(3, 'p', <String, Object?>{'p': '/n', 'd': increment}),
        );
        final List<Map<String, Object?>> stamped = await send(
          _request(4, 'm', <String, Object?>{
            'p': '/',
            'd': <String, Object?>{
              'ts': <String, Object?>{'.sv': 'timestamp'},
            },
          }),
        );
        expect(pushes(first).single['b'], <String, Object?>{'p': 'n', 'd': 3});
        expect(pushes(second).single['b'], <String, Object?>{'p': 'n', 'd': 6});
        expect(pushes(stamped).single['b'], <String, Object?>{
          'p': '',
          'd': <String, Object?>{'ts': 42},
        });
        expect(answerOf(second), <String, Object?>{'s': 'ok', 'd': ''});
        expect(server.data, <String, Object?>{'n': 6, 'ts': 42});
      });

      test(
        'malformed requests: a control error and no answer, as measured',
        () async {
          for (final Map<String, Object?> bad in <Map<String, Object?>>[
            _request(1, 'zz', <String, Object?>{}),
            _request(2, 'p', <String, Object?>{
              'p': '/a',
              'd': <String, Object?>{'a.b': 1},
            }),
            _request(3, 'p', <String, Object?>{
              'p': '/a',
              'd': <String, Object?>{'.sv': 'bogus'},
            }),
          ]) {
            final List<Map<String, Object?>> got = await send(bad);
            expect(got, hasLength(1));
            expect(got.single['t'], 'c');
            expect(inner(got.single)['t'], 'e');
          }
          expect(server.data, isEmpty);
        },
      );

      test('a path with . or \$ is answered invalid_parameters', () async {
        for (final String path in <String>['/a.b', r'/a/$b']) {
          final List<Map<String, Object?>> got = await send(
            _request(1, 'q', <String, Object?>{'p': path, 'h': ''}),
          );
          expect(answerOf(got), <String, Object?>{
            's': 'invalid_parameters',
            'd': 'Invalid token in path',
          });
        }
        final List<Map<String, Object?>> priority = await send(
          _request(2, 'p', <String, Object?>{'p': '/c/.priority', 'd': 5}),
        );
        expect(answerOf(priority)['s'], 'ok');
      });

      test(
        'a q without p closes the socket with 1006 and no message',
        () async {
          _clientSend(channel, _request(1, 'q', <String, Object?>{'h': ''}));
          await pumpEventQueue();
          expect((events.last as WsClosed).code, 1006);
          expect(server.log.single.action, 'q');
        },
      );

      test(
        'a query listen without a tag: internal_error, a reset, a close',
        () async {
          _clientSend(
            channel,
            _request(1, 'q', <String, Object?>{
              'p': '/people',
              'q': <String, Object?>{'l': 2, 'vf': 'l'},
              'h': '',
            }),
          );
          await pumpEventQueue();
          final List<Map<String, Object?>> got = _messages(
            events,
          ).skip(1).toList();
          expect(
            answerOf(<Map<String, Object?>>[got.first])['s'],
            'internal_error',
          );
          expect(inner(got.last), <String, Object?>{
            't': 'r',
            'd': 's-1.example',
          });
          expect((events.last as WsClosed).code, 1006);
        },
      );

      test(
        'a frame over 65536 bytes closes with 1002; 65536 bytes pass',
        () async {
          String frameOfBytes(int bytes) {
            const String head =
                '{"t":"d","d":{"r":1,"a":"p","b":{"p":"/a","d":"';
            const String tail = '"}}}';
            return '$head${'x' * (bytes - head.length - tail.length)}$tail';
          }

          channel.sendText(frameOfBytes(65536));
          await pumpEventQueue();
          expect(server.log, hasLength(1));
          channel.sendText(frameOfBytes(65537));
          await pumpEventQueue();
          expect(server.log, hasLength(1));
          expect((events.last as WsClosed).code, 1002);
        },
      );

      test('the flags give the simple form back', () async {
        server = FakeRtdbServer(
          checkHashes: false,
          resolveServerValues: false,
          validateRequests: false,
        );
        await open();
        final List<Map<String, Object?>> hashed = await send(
          _request(1, 'p', <String, Object?>{'p': '/v', 'd': 7, 'h': 'AAAA'}),
        );
        expect(answerOf(hashed), <String, Object?>{'s': 'ok', 'd': ''});
        final List<Map<String, Object?>> unknown = await send(
          _request(2, 'zz', <String, Object?>{}),
        );
        expect(answerOf(unknown)['s'], 'ok');
        final Map<String, Object?> sv = <String, Object?>{'.sv': 'timestamp'};
        await send(_request(3, 'p', <String, Object?>{'p': '/t', 'd': sv}));
        expect(server.data['t'], sv);
      });

      test('idleClose: 120 s without a client frame closes with 1006', () {
        fakeAsync((FakeAsync async) {
          final FakeRtdbServer idle = FakeRtdbServer(
            idleClose: FakeRtdbServer.measuredIdleClose,
            elapsed: () => async.elapsed,
          );
          late WsChannel ws;
          idle.connect(Uri.parse('wss://h/.ws')).then((WsChannel c) => ws = c);
          async.flushMicrotasks();
          final List<WsEvent> seen = _record(ws);
          async.elapse(const Duration(seconds: 100));
          ws.sendText('0');
          async.elapse(const Duration(seconds: 119));
          expect(seen.whereType<WsClosed>(), isEmpty);
          async.elapse(const Duration(seconds: 1));
          expect((seen.last as WsClosed).code, 1006);
          expect(async.pendingTimers, isEmpty);
        });
      });
    });

    test(
      'says hello on every connection; later sessions get a suffix',
      () async {
        expect(_messages(events).single['d'], <String, Object?>{
          't': 'h',
          'd': <String, Object?>{
            'ts': 42,
            'v': '5',
            'h': 's-1.example',
            's': 'sess-1',
          },
        });
        await open();
        final Map<String, Object?> hello =
            _messages(events).single['d']! as Map<String, Object?>;
        expect((hello['d']! as Map<String, Object?>)['s'], 'sess-1-2');
        expect(server.connections, 2);
      },
    );

    test(
      'answers a ping with a pong at any time; a keep-alive gets nothing',
      () async {
        channel.sendText('0');
        final List<Map<String, Object?>> answers = await send(<String, Object?>{
          't': 'c',
          'd': <String, Object?>{'t': 'p', 'd': <String, Object?>{}},
        });
        expect(answers, <Map<String, Object?>>[
          <String, Object?>{
            't': 'c',
            'd': <String, Object?>{'t': 'o', 'd': null},
          },
        ]);
      },
    );

    test(
      'a listen pushes the data at a path without leading slash, then ok {}',
      () async {
        server.data['a'] = <String, Object?>{'b': 1};
        final List<Map<String, Object?>> answers = await send(
          _request(1, 'q', <String, Object?>{'p': '/a', 'h': ''}),
        );
        expect(answers, <Map<String, Object?>>[
          <String, Object?>{
            't': 'd',
            'd': <String, Object?>{
              'a': 'd',
              'b': <String, Object?>{
                'p': 'a',
                'd': <String, Object?>{'b': 1},
              },
            },
          },
          <String, Object?>{
            't': 'd',
            'd': <String, Object?>{
              'r': 1,
              'b': <String, Object?>{'s': 'ok', 'd': <String, Object?>{}},
            },
          },
        ]);
      },
    );

    test(
      'a put is stored, echoed to the listen first, then acked; get reads it',
      () async {
        await send(_request(1, 'q', <String, Object?>{'p': '/', 'h': ''}));
        final List<Map<String, Object?>> answers = await send(
          _request(2, 'p', <String, Object?>{'p': '/x/y', 'd': 5}),
        );
        expect(
          (answers.first['d']! as Map<String, Object?>)['b'],
          <String, Object?>{'p': 'x/y', 'd': 5},
        );
        expect((answers.last['d']! as Map<String, Object?>)['r'], 2);
        expect(server.data, <String, Object?>{
          'x': <String, Object?>{'y': 5},
        });
        final List<Map<String, Object?>> got = await send(
          _request(3, 'g', <String, Object?>{'p': '/x'}),
        );
        expect(
          (got.single['d']! as Map<String, Object?>)['b'],
          <String, Object?>{
            's': 'ok',
            'd': <String, Object?>{'y': 5},
          },
        );
      },
    );

    test('failNext answers the next request of the action only', () async {
      server.failNext('p', 'permission_denied', 'no');
      final List<Map<String, Object?>> first = await send(
        _request(1, 'p', <String, Object?>{'p': '/a', 'd': 1}),
      );
      final List<Map<String, Object?>> second = await send(
        _request(2, 'p', <String, Object?>{'p': '/a', 'd': 1}),
      );
      expect(
        (first.single['d']! as Map<String, Object?>)['b'],
        <String, Object?>{'s': 'permission_denied', 'd': 'no'},
      );
      expect(
        ((second.single['d']! as Map<String, Object?>)['b']!
            as Map<String, Object?>)['s'],
        'ok',
      );
    });

    test('respondTo answers with the handler result', () async {
      server.respondTo(
        'auth',
        (Map<String, Object?> body) => <String, Object?>{'auth': body['cred']},
      );
      final List<Map<String, Object?>> answers = await send(
        _request(1, 'auth', <String, Object?>{'cred': 'c'}),
      );
      expect(
        (answers.single['d']! as Map<String, Object?>)['b'],
        <String, Object?>{
          's': 'ok',
          'd': <String, Object?>{'auth': 'c'},
        },
      );
      expect('${server.log.single}', isNot(contains('cred')));
    });

    test(
      'held responses are released in order, dropped when the connection closed',
      () async {
        server.holdResponses();
        expect(
          await send(_request(1, 'p', <String, Object?>{'p': '/a', 'd': 1})),
          isEmpty,
        );
        expect(
          await send(
            _request(2, 'm', <String, Object?>{
              'p': '/a',
              'd': <String, Object?>{},
            }),
          ),
          isEmpty,
        );
        server.releaseResponses();
        await pumpEventQueue();
        expect(
          _messages(events)
              .skip(1)
              .map(
                (Map<String, Object?> m) =>
                    (m['d']! as Map<String, Object?>)['r'],
              ),
          <int>[1, 2],
        );
        server.holdResponses();
        await send(_request(3, 'p', <String, Object?>{'p': '/a', 'd': 2}));
        await channel.close();
        server.releaseResponses();
        await pumpEventQueue();
        expect(server.log.map((ServerSeen s) => s.r), <int>[1, 2, 3]);
      },
    );

    test(
      'pushes strip the leading slash, carry the tag, rm strips s and e',
      () async {
        server
          ..pushData('/', 1)
          ..pushMerge('/a/b', <String, Object?>{'c': null}, tag: 3)
          ..pushRangeMerge('/ch', <Map<String, Object?>>[
            <String, Object?>{'e': '/ch/c4', 'm': <String, Object?>{}},
            <String, Object?>{'s': '/ch/c4', 'm': 1},
          ], tag: 1)
          ..pushListenCancel('/a')
          ..pushAuthRevoked('expired_token', 'gone')
          ..pushAppCheckRevoked('invalid_token', 'bad');
        await pumpEventQueue();
        final List<Object?> bodies = <Object?>[
          for (final Map<String, Object?> m in _messages(events).skip(1))
            m['d'],
        ];
        expect(bodies, <Object?>[
          <String, Object?>{
            'a': 'd',
            'b': <String, Object?>{'p': '', 'd': 1},
          },
          <String, Object?>{
            'a': 'm',
            'b': <String, Object?>{
              'p': 'a/b',
              'd': <String, Object?>{'c': null},
              't': 3,
            },
          },
          <String, Object?>{
            'a': 'rm',
            'b': <String, Object?>{
              'p': 'ch',
              'd': <Object?>[
                <String, Object?>{'e': 'ch/c4', 'm': <String, Object?>{}},
                <String, Object?>{'s': 'ch/c4', 'm': 1},
              ],
              't': 1,
            },
          },
          <String, Object?>{
            'a': 'c',
            'b': <String, Object?>{'p': 'a', 'q': null},
          },
          <String, Object?>{
            'a': 'ac',
            'b': <String, Object?>{'s': 'expired_token', 'd': 'gone'},
          },
          <String, Object?>{
            'a': 'apc',
            'b': <String, Object?>{'s': 'invalid_token', 'd': 'bad'},
          },
        ]);
      },
    );

    test('shutdown and reset are control messages', () async {
      server
        ..pushShutdown('bye')
        ..pushReset('s-2.example');
      await pumpEventQueue();
      expect(
        _messages(events).skip(1).map((Map<String, Object?> m) => m['d']),
        <Object?>[
          <String, Object?>{'t': 's', 'd': 'bye'},
          <String, Object?>{'t': 'r', 'd': 's-2.example'},
        ],
      );
    });

    test(
      'an unparseable frame gets the control error e and no answer, as measured',
      () async {
        channel.sendText('not json');
        await pumpEventQueue();
        final Map<String, Object?> error = _messages(events).last;
        expect(error['t'], 'c');
        expect((error['d']! as Map<String, Object?>)['t'], 'e');
        expect(server.log, isEmpty);
      },
    );

    test(
      'a chunked request is understood; the log has the connection number',
      () async {
        _clientSend(
          channel,
          _request(7, 'p', <String, Object?>{'p': '/big', 'd': 'z' * 100}),
          frameUnits: 9,
        );
        await pumpEventQueue();
        expect(server.log.single.connection, 1);
        expect(server.log.single.r, 7);
        expect(server.seen('p'), hasLength(1));
        expect(server.data['big'], 'z' * 100);
      },
    );

    test('pushing with no open connection is a StateError', () async {
      await channel.close();
      expect(() => server.pushData('/a', 1), throwsStateError);
    });

    test('helloDelay holds the hello back', () async {
      // Wide margins: in a browser the open alone can take tens of milliseconds.
      server = FakeRtdbServer(helloDelay: const Duration(milliseconds: 400));
      await open();
      expect(_messages(events), isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(_messages(events), hasLength(1));
    });
  });

  test(
    'under fakeAsync: helloDelay, virtual times and silence are driven by elapse',
    () {
      fakeAsync((FakeAsync async) {
        final FakeRtdbServer server = FakeRtdbServer(
          helloDelay: const Duration(seconds: 1),
          elapsed: () => async.elapsed,
        );
        server.connector.script(const <AttemptBehavior>[
          AttemptBehavior.accept(),
        ]);
        late WsChannel channel;
        server
            .connect(Uri.parse('wss://h/.ws'))
            .then((WsChannel c) => channel = c);
        async.flushMicrotasks();
        final List<WsEvent> events = _record(channel);
        async.elapse(const Duration(milliseconds: 999));
        expect(events, isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        final Map<String, Object?> hello = _messages(events).single;
        expect(
          ((hello['d']! as Map<String, Object?>)['d']!
              as Map<String, Object?>)['ts'],
          FakeWsConnector.helloEpochMs + 1000,
        );
        async.elapse(const Duration(seconds: 44));
        server.connector.last.goSilent();
        channel.sendText('{"t":"c","d":{"t":"p","d":{}}}');
        async.elapse(const Duration(seconds: 30));
        expect(_messages(events), hasLength(1));
        expect(
          server.connector.last.sentFrames.single.at,
          const Duration(seconds: 45),
        );
        expect(server.connector.attempts.single.at, Duration.zero);
        expect(async.pendingTimers, isEmpty);
      });
    },
  );
}
