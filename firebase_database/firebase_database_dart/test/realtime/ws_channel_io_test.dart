// Owner T. The dart:io channel and connector against in-process loopback servers (test plan 2.1;
// B-3.1f, B-3.5a, B-3.5d at channel level; threat model T4, T5, T9). Real time, no network.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:firebase_database_dart/src/realtime/transport/ws_channel.dart';
import 'package:firebase_database_dart/src/realtime/transport/ws_channel_io.dart';
import 'package:firebase_database_dart/src/realtime/transport/ws_connector.dart';
import 'package:test/test.dart';

/// A loopback WebSocket server; [onSocket] gets every upgraded socket, [requests] every request.
final class _WsServer {
  _WsServer._(this._server, this.onSocket);

  static Future<_WsServer> start(
    void Function(WebSocket socket) onSocket,
  ) async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final _WsServer ws = _WsServer._(server, onSocket);
    server.listen((HttpRequest request) async {
      ws.requests.add(request.headers);
      ws.onSocket(await WebSocketTransformer.upgrade(request));
    });
    return ws;
  }

  final HttpServer _server;
  final void Function(WebSocket socket) onSocket;
  final List<HttpHeaders> requests = <HttpHeaders>[];

  Uri get url =>
      Uri(scheme: 'ws', host: '127.0.0.1', port: _server.port, path: '/.ws');

  Future<void> close() => _server.close(force: true);
}

/// A loopback server that answers the upgrade by hand: [status] and [extraHeaders], with a
/// correct `Sec-WebSocket-Accept` unless [accept] is given.
Future<HttpServer> _rawUpgradeServer({
  int status = 101,
  String? accept,
  String extraHeaders = '',
  void Function(Socket socket)? afterUpgrade,
}) async {
  final HttpServer server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  server.listen((HttpRequest request) async {
    final String key = request.headers.value('Sec-WebSocket-Key') ?? '';
    final String expected = base64Encode(
      sha1
          .convert(ascii.encode('${key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11'))
          .bytes,
    );
    final Socket socket = await request.response.detachSocket(
      writeHeaders: false,
    );
    socket.write(
      'HTTP/1.1 $status Switching Protocols\r\n'
      'Upgrade: websocket\r\n'
      'Connection: Upgrade\r\n'
      'Sec-WebSocket-Accept: ${accept ?? expected}\r\n'
      '$extraHeaders'
      '\r\n',
    );
    await socket.flush();
    afterUpgrade?.call(socket);
  });
  return server;
}

Future<List<WsEvent>> _drain(WsChannel channel) =>
    channel.events.toList().timeout(const Duration(seconds: 10));

void main() {
  final WsConnector connect = ioWsConnector(maxMessageBytes: 1 << 20);

  test('opens, sends a text frame and receives the echo', () async {
    final _WsServer server = await _WsServer.start((WebSocket socket) {
      socket.listen((Object? message) => socket.add('echo:$message'));
    });
    addTearDown(server.close);
    final WsChannel channel = await connect(server.url);
    final StreamIterator<WsEvent> events = StreamIterator<WsEvent>(
      channel.events,
    );
    channel.sendText('{"t":"d"}');
    expect(await events.moveNext(), isTrue);
    expect((events.current as WsText).data, 'echo:{"t":"d"}');
    await channel.close();
    await events.cancel();
  });

  test('passes the upgrade headers (B-2.3a)', () async {
    final _WsServer server = await _WsServer.start(
      (WebSocket socket) => socket.close(),
    );
    addTearDown(server.close);
    final WsChannel channel = await connect(
      server.url,
      headers: <String, String>{
        'X-Firebase-AppCheck': 'ac-token',
        'X-Firebase-GMPID': '1:2',
      },
    );
    await _drain(channel);
    expect(server.requests.single.value('X-Firebase-AppCheck'), 'ac-token');
    expect(server.requests.single.value('X-Firebase-GMPID'), '1:2');
    expect(platformSendsHeaders, isTrue);
    expect(wsConnectorSendsHeaders, isTrue);
  });

  test('a binary frame becomes WsBinary, an empty one too (B-3.1f)', () async {
    final _WsServer server = await _WsServer.start((WebSocket socket) {
      socket
        ..add(<int>[1, 2, 3])
        ..add(<int>[])
        ..close();
    });
    addTearDown(server.close);
    final List<WsEvent> events = await _drain(await connect(server.url));
    expect(
      events.whereType<WsBinary>().map((WsBinary b) => b.data),
      <List<int>>[
        <int>[1, 2, 3],
        <int>[],
      ],
    );
    expect(events.last, isA<WsClosed>());
  });

  test(
    'a server close gives its code and reason as the last event (B-3.5d)',
    () async {
      for (final int code in <int>[1000, 1001, 1011, 4001]) {
        final _WsServer server = await _WsServer.start((WebSocket socket) {
          socket
            ..add('last')
            ..close(code, 'bye');
        });
        final List<WsEvent> events = await _drain(await connect(server.url));
        await server.close();
        expect((events.first as WsText).data, 'last');
        final WsClosed closed = events.last as WsClosed;
        expect(closed.code, code);
        expect(closed.reason, 'bye');
      }
    },
  );

  test('a TCP cut ends the stream with a WsClosed (B-3.5d)', () async {
    final HttpServer server = await _rawUpgradeServer(
      afterUpgrade: (Socket socket) =>
          Timer(const Duration(milliseconds: 50), socket.destroy),
    );
    addTearDown(() => server.close(force: true));
    final WsChannel channel = await connect(
      Uri.parse('ws://127.0.0.1:${server.port}/.ws'),
    );
    expect((await _drain(channel)).last, isA<WsClosed>());
  });

  test('a local close is idempotent and ends the stream', () async {
    final Completer<int?> serverSaw = Completer<int?>();
    final _WsServer server = await _WsServer.start((WebSocket socket) {
      socket.listen((_) {}, onDone: () => serverSaw.complete(socket.closeCode));
    });
    addTearDown(server.close);
    final WsChannel channel = await connect(server.url);
    final Future<List<WsEvent>> events = _drain(channel);
    final Future<void> first = channel.close(4000, 'done');
    expect(identical(first, channel.close()), isTrue);
    await first;
    expect((await events).last, isA<WsClosed>());
    expect(await serverSaw.future, 4000);
    expect(() => channel.sendText('x'), throwsStateError);
  });

  test('abandon ends the stream at once with WsClosed(null)', () async {
    final _WsServer server = await _WsServer.start((WebSocket socket) {});
    addTearDown(server.close);
    final WsChannel channel = await connect(server.url);
    final Future<List<WsEvent>> events = _drain(channel);
    channel.abandon();
    channel.abandon();
    final List<WsEvent> seen = await events;
    expect(seen, hasLength(1));
    expect((seen.single as WsClosed).code, isNull);
    expect(() => channel.sendText('x'), throwsStateError);
  });

  group('the upgrade is checked (T4, T5)', () {
    test('a wrong Sec-WebSocket-Accept is refused', () async {
      final HttpServer server = await _rawUpgradeServer(accept: 'AAAA');
      addTearDown(() => server.close(force: true));
      await expectLater(
        connect(Uri.parse('ws://127.0.0.1:${server.port}/.ws')),
        throwsA(
          isA<WsConnectException>()
              .having(
                (WsConnectException e) => e.kind,
                'kind',
                WsConnectFailure.upgradeRejected,
              )
              .having((WsConnectException e) => e.httpStatus, 'status', 101),
        ),
      );
    });

    test('an answer that selects compression is refused', () async {
      final HttpServer server = await _rawUpgradeServer(
        extraHeaders: 'Sec-WebSocket-Extensions: permessage-deflate\r\n',
      );
      addTearDown(() => server.close(force: true));
      await expectLater(
        connect(Uri.parse('ws://127.0.0.1:${server.port}/.ws')),
        throwsA(
          isA<WsConnectException>().having(
            (WsConnectException e) => e.kind,
            'kind',
            WsConnectFailure.upgradeRejected,
          ),
        ),
      );
    });

    test(
      'a status other than 101 is upgradeRejected with the status',
      () async {
        final HttpServer server = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(() => server.close(force: true));
        server.listen((HttpRequest request) {
          request.response
            ..statusCode = HttpStatus.forbidden
            ..write('no')
            ..close();
        });
        await expectLater(
          connect(Uri.parse('ws://127.0.0.1:${server.port}/.ws')),
          throwsA(
            isA<WsConnectException>()
                .having(
                  (WsConnectException e) => e.kind,
                  'kind',
                  WsConnectFailure.upgradeRejected,
                )
                .having((WsConnectException e) => e.httpStatus, 'status', 403),
          ),
        );
      },
    );
  });

  group('refused before any socket', () {
    late ServerSocket listener;
    late int connections;

    setUp(() async {
      connections = 0;
      listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      listener.listen((Socket socket) {
        connections++;
        socket.destroy();
      });
    });

    tearDown(() => listener.close());

    for (final String scheme in <String>['http', 'https', 'ftp', 'file']) {
      test('a $scheme URL fails with badScheme (U-C20)', () async {
        await expectLater(
          connect(Uri.parse('$scheme://127.0.0.1:${listener.port}/.ws')),
          throwsA(
            isA<WsConnectException>().having(
              (WsConnectException e) => e.kind,
              'kind',
              WsConnectFailure.badScheme,
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(connections, 0);
      });
    }

    test(
      'a URL with user info is refused (it would become Authorization)',
      () async {
        await expectLater(
          connect(Uri.parse('ws://user:pass@127.0.0.1:${listener.port}/.ws')),
          throwsA(isA<WsConnectException>()),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(connections, 0);
      },
    );
  });

  test(
    'a closed port fails with refused, and the message has no URL (B-3.5a, T8)',
    () async {
      final ServerSocket probe = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final int port = probe.port;
      await probe.close();
      try {
        await connect(Uri.parse('ws://127.0.0.1:$port/.ws?ac=secret-ac'));
        fail('connected to a closed port');
      } on WsConnectException catch (e) {
        expect(e.kind, WsConnectFailure.refused);
        expect('$e', isNot(contains('secret-ac')));
        expect('$e', isNot(contains('$port')));
      }
    },
  );

  group('the size of one inbound message is bounded (T9)', () {
    test(
      'a message over the limit closes with 1009 before it is delivered',
      () async {
        final _WsServer server = await _WsServer.start((WebSocket socket) {
          socket.add('x' * 5000);
        });
        addTearDown(server.close);
        final WsChannel channel = await ioWsConnector(maxMessageBytes: 1000)(
          server.url,
        );
        final List<WsEvent> events = await _drain(channel);
        expect(events.whereType<WsText>(), isEmpty);
        expect(events.whereType<WsError>(), isNotEmpty);
        expect((events.last as WsClosed).code, 1009);
      },
    );

    test(
      'many messages under the limit pass: the count restarts per message',
      () async {
        final _WsServer server = await _WsServer.start((WebSocket socket) {
          for (int i = 0; i < 20; i++) {
            socket.add('${'y' * 599}$i'.substring(0, 600));
          }
          socket.add(<int>[for (int i = 0; i < 1000; i++) 7]);
          socket.close();
        });
        addTearDown(server.close);
        final WsChannel channel = await ioWsConnector(maxMessageBytes: 1000)(
          server.url,
        );
        final List<WsEvent> events = await _drain(channel);
        expect(events.whereType<WsText>(), hasLength(20));
        expect(events.whereType<WsBinary>().single.data, hasLength(1000));
        expect(events.whereType<WsError>(), isEmpty);
      },
    );

    test(
      'a channel over a WebSocket opened elsewhere checks each message',
      () async {
        final _WsServer server = await _WsServer.start((WebSocket socket) {
          socket
            ..add('small')
            ..add('z' * 200);
        });
        addTearDown(server.close);
        final WebSocket socket = await WebSocket.connect(server.url.toString());
        final List<WsEvent> events = await _drain(
          IoWsChannel(socket, maxMessageBytes: 100),
        );
        expect((events.first as WsText).data, 'small');
        expect(events.whereType<WsText>(), hasLength(1));
        expect((events.last as WsClosed).code, 1009);
      },
    );
  });

  test('platformWsConnector is the io connector on the VM', () async {
    final _WsServer server = await _WsServer.start(
      (WebSocket socket) => socket.close(4005),
    );
    addTearDown(server.close);
    final WsChannel channel = await platformWsConnector(maxMessageBytes: 100)(
      server.url,
    );
    expect(channel, isA<IoWsChannel>());
    expect(((await _drain(channel)).last as WsClosed).code, 4005);
  });

  group(
    'a server that accepts and stays silent leaves nothing open (review M2)',
    () {
      late ServerSocket listener;
      late int accepted;
      late Set<Socket> open;

      setUp(() async {
        accepted = 0;
        open = <Socket>{};
        listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        listener.listen((Socket socket) {
          accepted++;
          open.add(socket);
          socket.listen(
            (_) {},
            onError: (Object _) {},
            onDone: () {
              open.remove(socket);
              socket.destroy();
            },
          );
        });
      });

      tearDown(() async {
        // A copy: a destroyed socket removes itself from `open` in its onDone.
        for (final Socket socket in List<Socket>.of(open)) {
          socket.destroy();
        }
        await listener.close();
      });

      Future<void> allClosed() async {
        // The server side sees the closes a little later: poll for up to 1 s.
        for (int i = 0; i < 50 && open.isNotEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }

      Matcher failsAs(String message) => throwsA(
        isA<WsConnectException>()
            .having(
              (WsConnectException e) => e.kind,
              'kind',
              WsConnectFailure.other,
            )
            .having((WsConnectException e) => e.message, 'message', message),
      );

      for (final String scheme in <String>['ws', 'wss']) {
        test(
          '20 $scheme attempts time out and close their sockets',
          () async {
            final WsConnector bounded = ioWsConnector(
              maxMessageBytes: 1000,
              upgradeTimeout: const Duration(milliseconds: 100),
            );
            final Uri url = Uri.parse(
              '$scheme://127.0.0.1:${listener.port}/.ws',
            );
            await Future.wait(<Future<void>>[
              for (int i = 0; i < 20; i++)
                expectLater(
                  bounded(url),
                  failsAs('the WebSocket upgrade timed out'),
                ),
            ]);
            await allClosed();
            expect(accepted, 20);
            expect(open, isEmpty);
          },
          skip: scheme == 'wss'
              ? 'dart:io limit: a socket inside a pending TLS handshake has no handle to close '
                    '(SecureSocket.secure detaches it); see the late-handshake test'
              : false,
        );
      }

      test(
        '20 aborted attempts fail at once and close their sockets',
        () async {
          final WsConnector slow = ioWsConnector(maxMessageBytes: 1000);
          final Uri url = Uri.parse('ws://127.0.0.1:${listener.port}/.ws');
          final Stopwatch watch = Stopwatch()..start();
          await Future.wait(<Future<void>>[
            for (int i = 0; i < 20; i++)
              expectLater(
                slow(
                  url,
                  abort: Future<void>.delayed(
                    const Duration(milliseconds: 100),
                  ),
                ),
                failsAs('the connect attempt was aborted'),
              ),
          ]);
          expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
          await allClosed();
          expect(accepted, 20);
          expect(open, isEmpty);
        },
      );

      test(
        'an abort with a shared client drops the request, not the client',
        () async {
          final HttpClient shared = HttpClient();
          addTearDown(() => shared.close(force: true));
          final WsConnector viaShared = ioWsConnector(
            httpClient: shared,
            maxMessageBytes: 1000,
          );
          final Uri url = Uri.parse('ws://127.0.0.1:${listener.port}/.ws');
          final Completer<void> abort = Completer<void>();
          final Future<WsChannel> attempt = viaShared(url, abort: abort.future);
          await Future<void>.delayed(const Duration(milliseconds: 100));
          abort.complete();
          await expectLater(
            attempt,
            failsAs('the connect attempt was aborted'),
          );
          await allClosed();
          expect(accepted, 1);
          expect(open, isEmpty);
        },
      );
    },
  );

  test('an abort after the channel opened does not touch it', () async {
    final _WsServer server = await _WsServer.start((WebSocket socket) {
      socket.listen((Object? message) => socket.add('echo:$message'));
    });
    addTearDown(server.close);
    final Completer<void> abort = Completer<void>();
    final WsChannel channel = await connect(server.url, abort: abort.future);
    abort.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final StreamIterator<WsEvent> events = StreamIterator<WsEvent>(
      channel.events,
    );
    channel.sendText('still');
    expect(await events.moveNext(), isTrue);
    expect((events.current as WsText).data, 'echo:still');
    await channel.close();
    await events.cancel();
  });

  test(
    'wss: a handshake that ends after the timeout frees its socket at once (review M2)',
    () async {
      final Directory directory = Directory.systemTemp.createTempSync(
        'rtdb_tls_',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final String certificate = '${directory.path}/cert.pem';
      final String key = '${directory.path}/key.pem';
      final ProcessResult made = Process.runSync('openssl', <String>[
        'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '2', //
        '-keyout', key, '-out', certificate, '-subj', '/CN=127.0.0.1',
        '-addext', 'subjectAltName=IP:127.0.0.1',
        '-addext', 'extendedKeyUsage=serverAuth',
      ]);
      expect(made.exitCode, 0, reason: '${made.stderr}');
      final SecurityContext context = SecurityContext()
        ..useCertificateChain(certificate)
        ..usePrivateKey(key);

      // The server takes the TCP connection, stays silent past the client's timeout, then answers
      // the TLS handshake. The client cannot trust the self-signed certificate, so its late
      // handshake fails; either way the socket must be gone as soon as the handshake ends.
      final Completer<void> serverSawEnd = Completer<void>();
      final Stopwatch sinceAnswer = Stopwatch();
      final ServerSocket listener = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(listener.close);
      listener.listen((Socket socket) {
        Timer(const Duration(milliseconds: 400), () {
          sinceAnswer.start();
          SecureSocket.secureServer(socket, context).then(
            (SecureSocket secured) => secured.listen(
              (_) {},
              onError: (Object _) {},
              onDone: () {
                secured.destroy();
                serverSawEnd.complete();
              },
            ),
            onError: (Object _) => serverSawEnd.complete(),
          );
        });
      });

      final WsConnector bounded = ioWsConnector(
        maxMessageBytes: 1000,
        upgradeTimeout: const Duration(milliseconds: 100),
      );
      await expectLater(
        bounded(Uri.parse('wss://127.0.0.1:${listener.port}/.ws')),
        throwsA(isA<WsConnectException>()),
      );
      await serverSawEnd.future.timeout(const Duration(seconds: 2));
      expect(sinceAnswer.elapsed, lessThan(const Duration(seconds: 1)));
    },
    skip: Process.runSync('which', <String>['openssl']).exitCode == 0
        ? false
        : 'needs openssl to make a certificate',
  );
}
