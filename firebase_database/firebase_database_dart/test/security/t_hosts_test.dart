// Owner T. The transport rows of the threat model's `hosts_test.dart` (T4, T5), in a file of their
// own because owner U writes the host rows. Loopback servers only.
@TestOn('vm')
library;

import 'dart:io';

import 'package:firebase_database_dart/src/realtime/transport/ws_channel.dart';
import 'package:firebase_database_dart/src/realtime/transport/ws_channel_io.dart';
import 'package:test/test.dart';

void main() {
  final WsConnector connect = ioWsConnector(maxMessageBytes: 1 << 20);

  for (final int status in <int>[301, 302, 303, 307, 308]) {
    test(
      'upgrade $status is a failure: the second server sees no request (T4)',
      () async {
        final List<HttpHeaders> secondSaw = <HttpHeaders>[];
        final HttpServer second = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(() => second.close(force: true));
        second.listen((HttpRequest request) async {
          secondSaw.add(request.headers);
          await WebSocketTransformer.upgrade(request);
        });
        final HttpServer first = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(() => first.close(force: true));
        first.listen((HttpRequest request) {
          request.response
            ..statusCode = status
            ..headers.set(
              HttpHeaders.locationHeader,
              'http://127.0.0.1:${second.port}/.ws',
            )
            ..close();
        });

        await expectLater(
          connect(
            Uri.parse('ws://127.0.0.1:${first.port}/.ws'),
            headers: <String, String>{'X-Firebase-AppCheck': 'marker-ac'},
          ),
          throwsA(
            isA<WsConnectException>()
                .having(
                  (WsConnectException e) => e.kind,
                  'kind',
                  WsConnectFailure.upgradeRejected,
                )
                .having(
                  (WsConnectException e) => e.httpStatus,
                  'status',
                  status,
                )
                .having(
                  (WsConnectException e) => '$e',
                  'text',
                  isNot(contains('marker-ac')),
                ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(secondSaw, isEmpty);
      },
    );
  }

  test(
    'the upgrade request offers no extension, even if a caller asks for one (T5)',
    () async {
      final List<HttpHeaders> seen = <HttpHeaders>[];
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));
      server.listen((HttpRequest request) async {
        seen.add(request.headers);
        final WebSocket socket = await WebSocketTransformer.upgrade(
          request,
          compression: CompressionOptions.compressionDefault,
        );
        await socket.close();
      });
      for (final Map<String, String> headers in <Map<String, String>>[
        <String, String>{},
        <String, String>{'Sec-WebSocket-Extensions': 'permessage-deflate'},
      ]) {
        final WsChannel channel = await connect(
          Uri.parse('ws://127.0.0.1:${server.port}/.ws'),
          headers: headers,
        );
        await channel.events.drain<void>();
      }
      expect(seen, hasLength(2));
      for (final HttpHeaders headers in seen) {
        expect(headers.value('Sec-WebSocket-Extensions'), isNull);
        expect(headers.value(HttpHeaders.authorizationHeader), isNull);
      }
    },
  );

  test('caller headers cannot replace the upgrade handshake headers', () async {
    final List<HttpHeaders> seen = <HttpHeaders>[];
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() => server.close(force: true));
    server.listen((HttpRequest request) async {
      seen.add(request.headers);
      final WebSocket socket = await WebSocketTransformer.upgrade(request);
      await socket.close();
    });
    final WsChannel channel = await connect(
      Uri.parse('ws://127.0.0.1:${server.port}/.ws'),
      headers: <String, String>{
        'Sec-WebSocket-Key': 'AAAAAAAAAAAAAAAAAAAAAA==',
        'Sec-WebSocket-Version': '8',
        'Upgrade': 'h2c',
      },
    );
    await channel.events.drain<void>();
    expect(
      seen.single.value('Sec-WebSocket-Key'),
      isNot('AAAAAAAAAAAAAAAAAAAAAA=='),
    );
    expect(seen.single.value('Sec-WebSocket-Version'), '13');
  });
}
