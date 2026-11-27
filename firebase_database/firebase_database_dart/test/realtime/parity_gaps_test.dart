// Parity row plat.nodeSocket (rtdb/from_boss/reports/round2/parity-refresh.md): the proxy half.
// The headers half is pinned by ws_channel_io_test.dart. FirebaseDatabase has no proxy parameter,
// so the proxy is tested where it is built: the dart:io connector with a caller's HttpClient.
//
// VM only: it needs dart:io (HttpClient, a loopback HttpServer as the proxy). No network: the
// target host is under .invalid and the proxy is on loopback.
@TestOn('vm')
library;

import 'dart:io';

import 'package:firebase_database_dart/src/realtime/transport/ws_channel.dart';
import 'package:firebase_database_dart/src/realtime/transport/ws_channel_io.dart';
import 'package:test/test.dart';

void main() {
  test(
    'a shared HttpClient with a proxy sends the upgrade to the proxy',
    () async {
      final HttpServer proxy = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => proxy.close(force: true));
      final List<String> seen = <String>[];
      proxy.listen((HttpRequest request) {
        seen.add(
          '${request.headers.host}:${request.headers.port} '
          '${request.headers.value(HttpHeaders.upgradeHeader)}',
        );
        request.response.statusCode = HttpStatus.badGateway;
        request.response.close();
      });
      final HttpClient client = HttpClient()
        ..findProxy = ((Uri _) => 'PROXY 127.0.0.1:${proxy.port}');
      addTearDown(() => client.close(force: true));
      final WsConnector connect = ioWsConnector(
        httpClient: client,
        maxMessageBytes: 1000,
      );

      await expectLater(
        connect(Uri.parse('ws://db.proxy-target.invalid:9000/.ws?v=5&ns=n')),
        throwsA(
          isA<WsConnectException>()
              .having(
                (WsConnectException e) => e.kind,
                'kind',
                WsConnectFailure.upgradeRejected,
              )
              .having(
                (WsConnectException e) => e.httpStatus,
                'httpStatus',
                HttpStatus.badGateway,
              ),
        ),
      );
      expect(seen, <String>['db.proxy-target.invalid:9000 websocket']);
    },
  );
}
