// The VM HTTP client of the web transport tests (test/util/io_web_http_client.dart) keeps the WebHttpRequest
// contract: abort ends a response body that is still streaming.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/web_http_client.dart';
import 'package:test/test.dart';

import '../../../../../util/io_web_http_client.dart';

void main() {
  late ServerSocket server;
  final List<Socket> connections = <Socket>[];

  setUp(() async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((Socket socket) {
      connections.add(socket);
      socket.listen((_) {
        // The headers and a first piece of the body, then nothing: the connection stays open.
        socket.add(
          latin1.encode(
            'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n'
            'Content-Type: text/plain\r\n\r\n5\r\nhello\r\n',
          ),
        );
      });
    });
  });

  tearDown(() async {
    for (final Socket socket in connections) {
      socket.destroy();
    }
    connections.clear();
    await server.close();
  });

  test('abort ends a body that is still streaming', () async {
    final IoWebHttpClient client = IoWebHttpClient();
    final WebHttpRequest request = client.send(
      'GET',
      Uri.parse('http://127.0.0.1:${server.port}/'),
    );
    final WebHttpResponse response = await request.response;
    final List<String> pieces = <String>[];
    final Completer<void> ended = Completer<void>();
    response.body.listen(pieces.add, onDone: ended.complete);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(pieces, <String>['hello']);
    expect(ended.isCompleted, isFalse);

    request.abort();
    await ended.future.timeout(const Duration(seconds: 2));
    client.close();
  });

  test('abort before the body is read ends it at once', () async {
    final IoWebHttpClient client = IoWebHttpClient();
    final WebHttpRequest request = client.send(
      'GET',
      Uri.parse('http://127.0.0.1:${server.port}/'),
    );
    final WebHttpResponse response = await request.response;
    request.abort();
    expect(
      await response.body.toList().timeout(const Duration(seconds: 2)),
      isEmpty,
    );
    client.close();
  });
}
