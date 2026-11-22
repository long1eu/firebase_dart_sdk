// Owner T. The browser channel against a loopback dart:io server started with spawnHybridCode
// (test plan 2.1; B-3.1f, B-3.5a, B-3.5d in the browser; threat model T25, T27). Run with
// `dart test -p chrome -c dart2js` and `-c dart2wasm`.
@TestOn('browser')
@Tags(<String>['browser'])
library;

import 'dart:async';

import 'package:firebase_database_dart/src/realtime/transport/ws_channel.dart';
import 'package:firebase_database_dart/src/realtime/transport/ws_channel_web.dart';
import 'package:firebase_database_dart/src/realtime/transport/ws_connector.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

/// A loopback WebSocket server: echoes text, answers `binary` with bytes, `close` with a 4002
/// close, and refuses the upgrade on `/refuse`. Sends its port, then the headers of every upgrade.
const String _serverCode = r'''
import 'dart:io';

import 'package:stream_channel/stream_channel.dart';

Future<void> hybridMain(StreamChannel<Object?> channel) async {
  final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((HttpRequest request) async {
    if (request.uri.path == '/refuse') {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }
    channel.sink.add(request.uri.query);
    final WebSocket socket = await WebSocketTransformer.upgrade(request);
    socket.listen((Object? message) {
      if (message == 'binary') {
        socket.add(<int>[1, 2, 3]);
      } else if (message == 'close') {
        socket.close(4002, 'bye');
      } else {
        socket.add('echo:$message');
      }
    });
  });
  channel.sink.add(server.port);
}
''';

/// The next value of [iterator].
Future<T> _next<T>(StreamIterator<T> iterator) async {
  if (!await iterator.moveNext()) {
    throw StateError('the stream ended');
  }
  return iterator.current;
}

void main() {
  late StreamIterator<Object?> server;
  late int port;

  setUpAll(() async {
    server = StreamIterator<Object?>(spawnHybridCode(_serverCode).stream);
    port = await _next(server) as int;
  });

  Uri url([String path = '/.ws', String query = 'v=5']) =>
      Uri.parse('ws://127.0.0.1:$port$path?$query');

  test(
    'text frames go both ways, the query reaches the server (T25)',
    () async {
      final WsChannel channel = await webWsConnector()(
        url('/.ws', 'v=5&ac=web-ac'),
      );
      expect(await _next(server), 'v=5&ac=web-ac');
      final StreamIterator<WsEvent> events = StreamIterator<WsEvent>(
        channel.events,
      );
      channel.sendText('{"t":"d"}');
      expect(((await _next(events)) as WsText).data, 'echo:{"t":"d"}');
      await channel.close();
      expect(await _next(events), isA<WsClosed>());
    },
  );

  test('a binary frame becomes WsBinary (B-3.1f)', () async {
    final WsChannel channel = await webWsConnector()(url());
    await _next(server);
    final StreamIterator<WsEvent> events = StreamIterator<WsEvent>(
      channel.events,
    );
    channel.sendText('binary');
    expect(((await _next(events)) as WsBinary).data, <int>[1, 2, 3]);
    channel.abandon();
  });

  test('a server close gives its code and reason (B-3.5d)', () async {
    final WsChannel channel = await webWsConnector()(url());
    await _next(server);
    final Future<List<WsEvent>> events = channel.events.toList();
    channel.sendText('close');
    final WsClosed closed = (await events).last as WsClosed;
    expect(closed.code, 4002);
    expect(closed.reason, 'bye');
    expect(() => channel.sendText('x'), throwsStateError);
  });

  test('abandon ends the stream at once', () async {
    final WsChannel channel = await webWsConnector()(url());
    await _next(server);
    final Future<List<WsEvent>> events = channel.events.toList();
    channel.abandon();
    expect(((await events).single as WsClosed).code, isNull);
  });

  test('a refused upgrade fails the connect without detail (B-3.5a)', () async {
    await expectLater(
      webWsConnector()(url('/refuse')),
      throwsA(
        isA<WsConnectException>().having(
          (WsConnectException e) => e.kind,
          'kind',
          WsConnectFailure.other,
        ),
      ),
    );
  });

  test(
    'a non-ws scheme fails with badScheme before any socket (U-C20)',
    () async {
      for (final String scheme in <String>['http', 'https']) {
        await expectLater(
          webWsConnector()(Uri.parse('$scheme://127.0.0.1:$port/.ws')),
          throwsA(
            isA<WsConnectException>().having(
              (WsConnectException e) => e.kind,
              'kind',
              WsConnectFailure.badScheme,
            ),
          ),
        );
      }
    },
  );

  test(
    'the browser connector sends no headers and is the platform connector',
    () async {
      expect(platformSendsHeaders, isFalse);
      expect(wsConnectorSendsHeaders, isFalse);
      final WsChannel channel = await platformWsConnector(maxMessageBytes: 10)(
        url(),
      );
      await _next(server);
      expect(channel, isA<WebWsChannel>());
      await channel.close();
    },
  );

  test('nothing is written to localStorage or sessionStorage (T27)', () {
    expect(web.window.localStorage.length, 0);
    expect(web.window.sessionStorage.length, 0);
  });
}
