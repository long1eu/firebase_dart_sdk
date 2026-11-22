// Owner C. RealtimeConnection over the fake connector (test plan S3 rows of owner C).

import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_database_dart/src/core/util/logger.dart';
import 'package:firebase_database_dart/src/realtime/connection.dart';
import 'package:firebase_database_dart/src/realtime/transport/ws_channel.dart';
import 'package:test/test.dart';

import '../util/connection_test_rig.dart';
import '../util/fake_ws.dart';

const Duration _connectTimeout = Duration(seconds: 30);

void main() {
  group('hello (B-3.2a)', () {
    test('reports ts and session once and becomes connected', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        final RealtimeConnection connection = rig.open();
        expect(connection.isConnected, isFalse);

        rig.fake.last.serverHello(
          ts: 1795370969604,
          h: configuredHost,
          s: 'abc',
        );
        rig.flush();

        expect(connection.isConnected, isTrue);
        expect(rig.delegate.readies, hasLength(1));
        expect(rig.delegate.readies.single.ts, 1795370969604);
        expect(rig.delegate.readies.single.sessionId, 'abc');
      });
    });

    test('a second hello is ignored', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        final RealtimeConnection connection = rig.openReady();
        rig.fake.last.serverHello(ts: 2, h: configuredHost, s: 'other');
        rig.flush();

        expect(connection.isConnected, isTrue);
        expect(rig.delegate.readies, hasLength(1));
        expect(rig.delegate.disconnects, isEmpty);
      });
    });

    test(
      'send before the hello throws, after it wraps the request in a data envelope',
      () {
        fakeAsync((FakeAsync async) {
          final ConnectionRig rig = ConnectionRig(async);
          final RealtimeConnection connection = rig.open();
          expect(
            () => connection.send(<String, Object?>{'r': 1}),
            throwsStateError,
          );

          rig.fake.last.serverHello(ts: 1, h: configuredHost);
          rig.flush();
          connection.send(<String, Object?>{
            'r': 1,
            'a': 'q',
            'b': <String, Object?>{'p': '/a', 'h': ''},
          });

          expect(rig.fake.last.sentMessages.last, <String, Object?>{
            't': 'd',
            'd': <String, Object?>{
              'r': 1,
              'a': 'q',
              'b': <String, Object?>{'p': '/a', 'h': ''},
            },
          });
        });
      },
    );

    test('a large request is sent as a count frame and pieces', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        final RealtimeConnection connection = rig.openReady();
        final String big = 'x' * 40000;
        connection.send(<String, Object?>{'r': 1, 'a': 'p', 'b': big});

        final List<SentFrame> frames = rig.fake.last.sentFrames;
        expect(frames.first.text, '3');
        expect(
          frames.skip(1).every((SentFrame f) => f.text.length <= 16384),
          isTrue,
        );
        expect(
          (rig.fake.last.sentMessages.last['d']! as Map<String, Object?>)['b'],
          big,
        );
      });
    });

    test('the last session id goes into the URL as ls (B-3.2f)', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(
          async,
          lastSessionId: 'prev-session',
        );
        rig.open();

        expect(
          rig.fake.attempts.single.url.queryParameters['ls'],
          'prev-session',
        );
      });
    });
  });

  group('malformed hello (B-3.2b)', () {
    final Map<String, Object?> cases = <String, Object?>{
      'not an object': 'hello',
      'ts a string': <String, Object?>{
        'ts': '1',
        's': 'a',
        'h': configuredHost,
      },
      'ts a double': <String, Object?>{
        'ts': 1.5,
        's': 'a',
        'h': configuredHost,
      },
      'ts missing': <String, Object?>{'s': 'a', 'h': configuredHost},
      's a number': <String, Object?>{'ts': 1, 's': 2, 'h': configuredHost},
      'h a number': <String, Object?>{'ts': 1, 's': 'a', 'h': 3},
      'h null': <String, Object?>{'ts': 1, 's': 'a', 'h': null},
    };
    for (final MapEntry<String, Object?> entry in cases.entries) {
      test(
        '${entry.key}: closes as a failure and keeps the configured host',
        () {
          fakeAsync((FakeAsync async) {
            final ConnectionRig rig = ConnectionRig(async);
            rig.target.acceptServerHost('s-cached.firebaseio.com');
            final RealtimeConnection connection = rig.open();
            rig.fake.last.serverControl('h', entry.value);
            rig.flush();

            expect(rig.delegate.readies, isEmpty);
            expect(
              rig.delegate.disconnects.single.reason,
              DisconnectReason.other,
            );
            expect(connection.isConnected, isFalse);
            expect(rig.fake.last.isClosed, isTrue);
            expect(rig.target.internalHost, configuredHost);
          });
        },
      );
    }

    test('an invalid h string is ignored and the hello still succeeds', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        final RealtimeConnection connection = rig.openReady(
          host: 'evil.example',
        );

        expect(connection.isConnected, isTrue);
        expect(rig.target.internalHost, configuredHost);
        expect(rig.lines, contains('ignored server host (invalid)'));
        expect(rig.lines.join('\n'), isNot(contains('evil.example')));
      });
    });
  });

  group('hello host (B-3.2c)', () {
    test('a new h is the host of the next attempt, with ns', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        rig.openReady(host: 's-usc1.firebaseio.com').close();
        rig.open();

        final Uri url = rig.fake.attempts.last.url;
        expect(url.host, 's-usc1.firebaseio.com');
        expect(url.queryParameters['ns'], 'demo-ns');
      });
    });

    test('the emulator keeps the host the user gave', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async, repoInfo: emulatorRepo);
        rig.openReady(host: '127.0.0.1:9100').close();
        rig.open();

        final Uri url = rig.fake.attempts.last.url;
        expect(url.host, '127.0.0.1');
        expect(url.port, 9000);
        expect(rig.lines, isNot(contains('ignored server host (invalid)')));
      });
    });
  });

  test('a version other than 5 only warns (B-3.2d)', () {
    fakeAsync((FakeAsync async) {
      final ConnectionRig rig = ConnectionRig(async);
      final RealtimeConnection connection = rig.open();
      rig.fake.last.serverHello(ts: 1, v: '6', h: configuredHost);
      rig.flush();

      expect(connection.isConnected, isTrue);
      expect(
        rig.logs.where(
          ((DatabaseLogLevel, String) l) =>
              l.$1 == DatabaseLogLevel.warning &&
              l.$2.contains('protocol version mismatch'),
        ),
        hasLength(1),
      );
    });
  });

  group('shutdown (B-3.3a)', () {
    test('reports onKill, never onDisconnect, and closes the socket', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        final RealtimeConnection connection = rig.openReady();
        rig.fake.last.serverControl('s', 'database disabled');
        rig.flush();

        expect(rig.delegate.kills.single.reason, contains('database disabled'));
        expect(rig.delegate.disconnects, isEmpty);
        expect(connection.isConnected, isFalse);
        expect(rig.fake.last.isClosed, isTrue);

        connection.close();
        async.elapse(const Duration(minutes: 5));
        expect(rig.delegate.disconnects, isEmpty);
        expect(rig.fake.attempts, hasLength(1));
      });
    });

    test('a close from inside onKill reports nothing', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        final RealtimeConnection connection = rig.openReady();
        rig.delegate.whenKill = connection.close;
        rig.fake.last.serverControl('s', 'bye');
        rig.flush();

        expect(rig.delegate.kills, hasLength(1));
        expect(rig.delegate.disconnects, isEmpty);
      });
    });

    test(
      'a shutdown without a string reason is a protocol error, not a kill',
      () {
        fakeAsync((FakeAsync async) {
          final ConnectionRig rig = ConnectionRig(async);
          rig.openReady();
          rig.fake.last.serverControl('s', <String, Object?>{'x': 1});
          rig.flush();

          expect(rig.delegate.kills, isEmpty);
          expect(
            rig.delegate.disconnects.single.reason,
            DisconnectReason.other,
          );
        });
      },
    );
  });

  group('reset (B-3.3b, B-3.3c)', () {
    test('while connecting: reopens at once at the new host', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        final RealtimeConnection connection = rig.open();
        final FakeWsChannel first = rig.fake.last;
        first.serverControl('r', 's-reset.firebaseio.com');
        rig.flush();

        expect(rig.fake.attempts, hasLength(2));
        expect(rig.fake.attempts.last.url.host, 's-reset.firebaseio.com');
        expect(rig.fake.attempts.last.at, rig.fake.attempts.first.at);
        expect(first.isClosed, isTrue);
        expect(rig.delegate.disconnects, isEmpty);

        rig.fake.last.serverHello(ts: 1, h: 's-reset.firebaseio.com');
        rig.flush();
        expect(connection.isConnected, isTrue);
        expect(rig.delegate.readies, hasLength(1));
      });
    });

    test('frames of the old socket are ignored after a reset', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        final RealtimeConnection connection = rig.open();
        final FakeWsChannel first = rig.fake.last;
        first.serverControl('r', 's-reset.firebaseio.com');
        rig.flush();
        first.serverHello(ts: 1, h: configuredHost);
        rig.flush();

        expect(connection.isConnected, isFalse);
        expect(rig.delegate.events, isEmpty);
      });
    });

    test('while connected: closes as serverReset and keeps the new host', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        rig.openReady();
        rig.fake.last.serverControl('r', 's-reset.firebaseio.com');
        rig.flush();

        expect(
          rig.delegate.disconnects.single.reason,
          DisconnectReason.serverReset,
        );
        expect(rig.fake.attempts, hasLength(1));
        expect(rig.target.internalHost, 's-reset.firebaseio.com');
      });
    });

    final Map<String, Object?> invalid = <String, Object?>{
      'foreign host': 'evil.example',
      'host with port': 's-x.firebaseio.com:444',
      'number': 7,
      'null': null,
      'empty': '',
    };
    for (final MapEntry<String, Object?> entry in invalid.entries) {
      for (final bool connected in <bool>[false, true]) {
        test(
          '${entry.key} ${connected ? 'after' : 'before'} the hello restores the configured '
          'host and fails into the backoff',
          () {
            fakeAsync((FakeAsync async) {
              final ConnectionRig rig = ConnectionRig(async);
              rig.target.acceptServerHost('s-cached.firebaseio.com');
              if (connected) {
                rig.openReady(host: 's-cached.firebaseio.com');
              } else {
                rig.open();
              }
              rig.fake.last.serverControl('r', entry.value);
              rig.flush();

              expect(
                rig.delegate.disconnects.single.reason,
                DisconnectReason.other,
              );
              expect(rig.fake.attempts, hasLength(1));
              expect(rig.target.internalHost, configuredHost);
            });
          },
        );
      }
    }

    test(
      'at most maxResetsPerAttempt resets are followed, then the attempt fails',
      () {
        fakeAsync((FakeAsync async) {
          final ConnectionRig rig = ConnectionRig(async);
          rig.open();
          for (int i = 0; i < 10 && rig.delegate.disconnects.isEmpty; i++) {
            rig.fake.last.serverControl('r', 's-loop$i.firebaseio.com');
            rig.flush();
          }

          expect(
            rig.fake.attempts,
            hasLength(1 + rig.timings.maxResetsPerAttempt),
          );
          expect(
            rig.delegate.disconnects.single.reason,
            DisconnectReason.other,
          );
          expect(rig.target.internalHost, configuredHost);
          expect(async.pendingTimers, isEmpty);
        });
      },
    );

    test('the emulator never follows a reset', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async, repoInfo: emulatorRepo);
        rig.open();
        rig.fake.last.serverControl('r', '127.0.0.1:9100');
        rig.flush();

        expect(rig.fake.attempts, hasLength(1));
        expect(rig.delegate.disconnects.single.reason, DisconnectReason.other);
        expect(rig.target.internalHost, '127.0.0.1:9000');
      });
    });
  });

  group('other control messages (B-3.3d)', () {
    test('e is logged cleaned and changes nothing', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        final RealtimeConnection connection = rig.openReady();
        rig.fake.last.serverControl(
          'e',
          'ClientId[1]:ErrorId[2]: Error on incoming message\n',
        );
        rig.flush();

        expect(connection.isConnected, isTrue);
        final String line = rig.lines.singleWhere(
          (String l) => l.startsWith('server error'),
        );
        expect(line, contains('Error on incoming message'));
        expect(line, isNot(contains('\n')));
      });
    });

    test('a, n and unknown types are ignored; unknown ones are logged', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        final RealtimeConnection connection = rig.openReady();
        rig.fake.last
          ..serverControl('a', <String, Object?>{})
          ..serverControl('n', <String, Object?>{})
          ..serverControl('zz', <String, Object?>{});
        rig.flush();

        expect(connection.isConnected, isTrue);
        expect(rig.delegate.disconnects, isEmpty);
        expect(
          rig.lines.where((String l) => l.startsWith('unknown control')),
          hasLength(1),
        );
      });
    });

    test('a pong before the hello is accepted (probe: pong at any time)', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        final RealtimeConnection connection = rig.open();
        rig.fake.last.serverControl('o');
        rig.fake.last.serverHello(ts: 1, h: configuredHost);
        rig.flush();

        expect(connection.isConnected, isTrue);
        expect(rig.delegate.disconnects, isEmpty);
      });
    });
  });

  group('malformed messages (B-3.1g)', () {
    final Map<String, String> frames = <String, String>{
      'array': '[1]',
      'no type': '{"d":{}}',
      'no data': '{"t":"d"}',
      'data not an object': '{"t":"d","d":"x"}',
      'unknown layer': '{"t":"x","d":{}}',
      'control not an object': '{"t":"c","d":"x"}',
      'control type a number': '{"t":"c","d":{"t":5,"d":{}}}',
      'not json': '{"t":',
    };
    for (final MapEntry<String, String> entry in frames.entries) {
      test('${entry.key} closes as a failure without throwing', () {
        fakeAsync((FakeAsync async) {
          final ConnectionRig rig = ConnectionRig(async);
          final List<Object> errors = <Object>[];
          runZonedGuarded(() {
            rig.openReady();
            rig.fake.last.serverText(entry.value);
            rig.flush();
          }, (Object error, StackTrace _) => errors.add(error));

          expect(errors, isEmpty);
          expect(rig.delegate.data, isEmpty);
          expect(
            rig.delegate.disconnects.single.reason,
            DisconnectReason.other,
          );
        });
      });
    }

    test('a data message before the hello is a protocol error', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        rig.open();
        rig.fake.last.serverPush('d', <String, Object?>{'p': 'a', 'd': 1});
        rig.flush();

        expect(rig.delegate.data, isEmpty);
        expect(rig.delegate.disconnects.single.reason, DisconnectReason.other);
      });
    });

    test('binary frames, empty or not, are ignored (B-3.1f)', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        final RealtimeConnection connection = rig.openReady();
        rig.fake.last
          ..serverBinary(<int>[])
          ..serverBinary(<int>[1, 2, 3]);
        rig.flush();

        expect(connection.isConnected, isTrue);
        expect(rig.delegate.data, isEmpty);
        expect(rig.delegate.disconnects, isEmpty);
      });
    });

    test('data messages reach the delegate whole', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        rig.openReady();
        rig.fake.last.serverResponse(3, data: 'x' * 50000);
        rig.flush();

        expect(rig.delegate.data.single.message, <String, Object?>{
          'r': 3,
          'b': <String, Object?>{'s': 'ok', 'd': 'x' * 50000},
        });
      });
    });
  });

  group('connect timeout (B-3.4c)', () {
    test('a hanging connector is reported at the timeout, once', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        rig.fake.script(<AttemptBehavior>[const AttemptBehavior.hang()]);
        final RealtimeConnection connection = rig.open();

        async.elapse(_connectTimeout - const Duration(milliseconds: 1));
        expect(rig.delegate.disconnects, isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        expect(
          rig.delegate.disconnects.single.reason,
          DisconnectReason.connectTimeout,
        );

        connection.close();
        async.elapse(const Duration(minutes: 2));
        expect(rig.delegate.disconnects, hasLength(1));
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('an accepted socket without a hello is abandoned at the timeout', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        rig.fake.script(<AttemptBehavior>[
          const AttemptBehavior.acceptThenSilent(),
        ]);
        rig.open();

        async.elapse(_connectTimeout);
        expect(
          rig.delegate.disconnects.single.reason,
          DisconnectReason.connectTimeout,
        );
        expect(rig.fake.last.abandoned, isTrue);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test(
      'a channel that arrives after the timeout is abandoned and reports nothing',
      () {
        fakeAsync((FakeAsync async) {
          final Completer<WsChannel> late = Completer<WsChannel>();
          final ConnectionRig rig = ConnectionRig(
            async,
            connector:
                (
                  Uri url, {
                  Map<String, String> headers = const <String, String>{},
                  Future<void>? abort,
                }) => late.future,
          );
          rig.open();
          async.elapse(_connectTimeout);
          final FakeWsChannel channel = FakeWsChannel(
            elapsed: () => async.elapsed,
          );
          late.complete(channel);
          rig.flush();
          channel.serverHello(ts: 1, h: configuredHost);
          rig.flush();

          expect(channel.abandoned, isTrue);
          expect(rig.delegate.readies, isEmpty);
          expect(rig.delegate.disconnects, hasLength(1));
        });
      },
    );

    test('a close before the timeout leaves no timer and reports once', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        rig.fake.script(<AttemptBehavior>[const AttemptBehavior.hang()]);
        rig.open().close();
        expect(async.pendingTimers, isEmpty);

        async.elapse(_connectTimeout * 2);
        expect(rig.delegate.disconnects.single.reason, DisconnectReason.other);
      });
    });

    test('the hello cancels the timeout', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        final RealtimeConnection connection = rig.openReady();
        // Keep the link busy so neither the health check nor the probe ends it.
        for (int i = 0; i < 4; i++) {
          rig.fake.last.serverControl('o');
          rig.flush();
          async.elapse(const Duration(seconds: 10));
        }
        expect(connection.isConnected, isTrue);
        expect(rig.delegate.disconnects, isEmpty);
      });
    });

    test('a timeout forgets a server-chosen host', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        rig.target.acceptServerHost('s-cached.firebaseio.com');
        rig.fake.script(<AttemptBehavior>[const AttemptBehavior.hang()]);
        rig.open();
        async.elapse(_connectTimeout);

        expect(rig.target.internalHost, configuredHost);
      });
    });
  });

  group('close (B-3.5a)', () {
    test('close before open reports once and open then does nothing', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        final RealtimeConnection connection = rig.create()..close();
        connection.open();
        rig.flush();

        expect(rig.delegate.disconnects.single.reason, DisconnectReason.other);
        expect(rig.fake.attempts, isEmpty);
      });
    });

    test('open twice throws', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        final RealtimeConnection connection = rig.open();
        expect(connection.open, throwsStateError);
      });
    });

    test('close twice reports once and closes the socket', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        final RealtimeConnection connection = rig.openReady()
          ..close()
          ..close(DisconnectReason.deadLink);
        rig.flush();

        expect(rig.delegate.disconnects.single.reason, DisconnectReason.other);
        expect(rig.fake.last.isClosed, isTrue);
        expect(rig.fake.last.abandoned, isFalse);
        expect(connection.isConnected, isFalse);
        expect(() => connection.send(<String, Object?>{}), throwsStateError);
        expect(async.pendingTimers, isEmpty);
      });
    });

    for (final (String name, AttemptBehavior behavior)
        in <(String, AttemptBehavior)>[
          ('refused', const AttemptBehavior.refuse()),
          ('dns failure', const AttemptBehavior.dnsFailure()),
        ]) {
      test('a $name attempt is reported as a failure, once', () {
        fakeAsync((FakeAsync async) {
          final ConnectionRig rig = ConnectionRig(async);
          rig.target.acceptServerHost('s-cached.firebaseio.com');
          rig.fake.script(<AttemptBehavior>[behavior]);
          rig.open();
          async.elapse(_connectTimeout * 2);

          expect(
            rig.delegate.disconnects.single.reason,
            DisconnectReason.other,
          );
          expect(rig.target.internalHost, configuredHost);
          expect(async.pendingTimers, isEmpty);
        });
      });
    }

    test('a connector that throws synchronously is a failed attempt', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(
          async,
          connector:
              (
                Uri url, {
                Map<String, String> headers = const <String, String>{},
                Future<void>? abort,
              }) => throw const WsConnectException(
                WsConnectFailure.badScheme,
                'bad scheme',
              ),
        );
        rig.open();

        expect(rig.delegate.disconnects.single.reason, DisconnectReason.other);
        expect(rig.lines, contains('connect failed (badScheme)'));
      });
    });
  });

  group('re-entrancy (B-3.5b)', () {
    test('close inside onReady', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        final RealtimeConnection connection = rig.open();
        rig.delegate.whenReady = connection.close;
        rig.fake.last
          ..serverHello(ts: 1, h: configuredHost)
          ..serverResponse(1);
        rig.flush();

        expect(rig.delegate.readies, hasLength(1));
        expect(rig.delegate.data, isEmpty);
        expect(rig.delegate.disconnects, hasLength(1));
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('close inside onDataMessage stops later messages', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        final RealtimeConnection connection = rig.openReady();
        rig.delegate.whenData = connection.close;
        rig.fake.last
          ..serverResponse(1)
          ..serverResponse(2);
        rig.flush();

        expect(rig.delegate.data, hasLength(1));
        expect(rig.delegate.disconnects, hasLength(1));
      });
    });

    test('close and a new connection inside onDisconnect', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        final RealtimeConnection first = rig.openReady();
        RealtimeConnection? second;
        rig.delegate.whenDisconnect = () {
          rig.delegate.whenDisconnect = null;
          first.close();
          second = rig.create()..open();
        };
        rig.fake.last.serverClose(1000);
        rig.flush();
        rig.fake.last.serverHello(ts: 1, h: configuredHost);
        rig.flush();

        expect(rig.delegate.disconnects, hasLength(1));
        expect(second!.isConnected, isTrue);
        expect(first.isConnected, isFalse);
      });
    });
  });

  test('500 open/close races leave no timer and no open socket (B-3.5c)', () {
    fakeAsync((FakeAsync async) {
      final ConnectionRig rig = ConnectionRig(async);
      for (int i = 0; i < 500; i++) {
        final RealtimeConnection connection = rig.create()..open();
        switch (i % 4) {
          case 0:
            connection.close();
            rig.flush();
          case 1:
            rig.flush();
            connection.close();
          case 2:
            rig.flush();
            rig.fake.last.serverHello(ts: i, h: configuredHost);
            rig.flush();
            connection.close();
          case 3:
            rig.flush();
            rig.fake.last.serverHello(ts: i, h: configuredHost);
            rig.fake.last.serverClose(1006);
            rig.flush();
            connection.close();
        }
      }

      expect(rig.delegate.disconnects, hasLength(500));
      expect(async.pendingTimers, isEmpty);
      for (final ConnectAttempt attempt in rig.fake.attempts) {
        final FakeWsChannel? channel = attempt.channel;
        expect(
          channel == null || channel.isClosed || channel.abandoned,
          isTrue,
        );
      }
    });
  });

  group('server close (B-3.5d)', () {
    for (final int? code in <int?>[1000, 1001, 1011, 1006, null]) {
      test('close $code after the hello ends as other, once', () {
        fakeAsync((FakeAsync async) {
          final ConnectionRig rig = ConnectionRig(async);
          final RealtimeConnection connection = rig.openReady();
          rig.fake.last.serverClose(code);
          rig.flush();

          expect(
            rig.delegate.disconnects.single.reason,
            DisconnectReason.other,
          );
          expect(connection.isConnected, isFalse);
          expect(async.pendingTimers, isEmpty);
        });
      });
    }

    test('a socket error ends as other, once', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        rig.openReady();
        rig.fake.last.serverError(StateError('reset by peer'));
        rig.flush();

        expect(rig.delegate.disconnects.single.reason, DisconnectReason.other);
      });
    });

    test('a server close before the hello forgets a server host', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        rig.target.acceptServerHost('s-cached.firebaseio.com');
        rig.open();
        rig.fake.last.serverClose(1006);
        rig.flush();

        expect(rig.target.internalHost, configuredHost);
      });
    });

    test('a close after the hello keeps a server host', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        rig.openReady(host: 's-kept.firebaseio.com');
        rig.fake.last.serverClose(1006);
        rig.flush();

        expect(rig.target.internalHost, 's-kept.firebaseio.com');
      });
    });
  });

  group('abort signal to the connector (review M2)', () {
    /// A connector that never completes and records the abort signal it was given.
    (WsConnector, List<bool>) hangingConnector() {
      final List<bool> aborted = <bool>[];
      Future<WsChannel> connect(
        Uri url, {
        Map<String, String> headers = const <String, String>{},
        Future<void>? abort,
      }) {
        final int index = aborted.length;
        aborted.add(false);
        unawaited(abort?.then((_) => aborted[index] = true));
        return Completer<WsChannel>().future;
      }

      return (connect, aborted);
    }

    test('fires when the connect timeout elapses', () {
      fakeAsync((FakeAsync async) {
        final (WsConnector connector, List<bool> aborted) = hangingConnector();
        final ConnectionRig rig = ConnectionRig(async, connector: connector);
        rig.open();
        async.elapse(_connectTimeout - const Duration(milliseconds: 1));
        expect(aborted, <bool>[false]);
        async.elapse(const Duration(milliseconds: 1));

        expect(aborted, <bool>[true]);
        expect(
          rig.delegate.disconnects.single.reason,
          DisconnectReason.connectTimeout,
        );
      });
    });

    test('fires when the connection is closed during the upgrade', () {
      fakeAsync((FakeAsync async) {
        final (WsConnector connector, List<bool> aborted) = hangingConnector();
        final ConnectionRig rig = ConnectionRig(async, connector: connector);
        rig.open().close();
        rig.flush();

        expect(aborted, <bool>[true]);
      });
    });

    test('does not fire once the connector returned a channel', () {
      fakeAsync((FakeAsync async) {
        final List<Future<void>> signals = <Future<void>>[];
        bool fired = false;
        late final ConnectionRig rig;
        Future<WsChannel> connect(
          Uri url, {
          Map<String, String> headers = const <String, String>{},
          Future<void>? abort,
        }) {
          signals.add(abort!);
          unawaited(abort.then((_) => fired = true));
          return rig.fake.connect(url, headers: headers);
        }

        rig = ConnectionRig(async, connector: connect);
        rig.openReady().close();
        async.elapse(const Duration(minutes: 1));

        expect(signals, hasLength(1));
        expect(fired, isFalse);
        expect(rig.fake.last.isClosed, isTrue);
      });
    });
  });

  group('inbound frame signal (rulings H1)', () {
    test('fires once per frame, pieces of a buffered message included', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        final RealtimeConnection connection = rig.openReady();
        int signals = 0;
        connection.onInboundFrame = () {
          signals++;
          expect(rig.delegate.data, isEmpty);
        };
        final Map<String, Object?> envelope = <String, Object?>{
          't': 'd',
          'd': <String, Object?>{
            'r': 1,
            'b': <String, Object?>{'s': 'ok', 'd': 'abcdefghij'},
          },
        };
        rig.fake.last.serverMessage(envelope, frameSize: 5);
        rig.flush();

        final int pieces = (jsonEncode(envelope).length / 5).ceil();
        expect(signals, 1 + pieces);
        expect(rig.delegate.data, hasLength(1));
      });
    });

    test('a close from the signal stops the frame', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        final RealtimeConnection connection = rig.openReady();
        connection.onInboundFrame = connection.close;
        rig.fake.last.serverResponse(1);
        rig.flush();

        expect(rig.delegate.data, isEmpty);
        expect(rig.delegate.disconnects, hasLength(1));
      });
    });

    test('binary frames do not signal', () {
      fakeAsync((FakeAsync async) {
        final ConnectionRig rig = ConnectionRig(async);
        int signals = 0;
        rig.openReady().onInboundFrame = () => signals++;
        rig.fake.last.serverBinary(<int>[1]);
        rig.flush();

        expect(signals, 0);
      });
    });
  });

  test(
    'credentialActions is the one list of credential actions (review L6)',
    () {
      expect(credentialActions, <String>{
        'auth',
        'gauth',
        'unauth',
        'appcheck',
        'unappcheck',
        'unappeck',
      });
    },
  );

  test('toString shows no session, host query or token', () {
    fakeAsync((FakeAsync async) {
      final ConnectionRig rig = ConnectionRig(
        async,
        appCheckToken: 'AC-MARKER',
      );
      final RealtimeConnection connection = rig.openReady(
        session: 'SESSION-MARKER',
      );

      expect(connection.toString(), 'RealtimeConnection');
      expect(jsonEncode(rig.lines), isNot(contains('MARKER')));
    });
  });
}
