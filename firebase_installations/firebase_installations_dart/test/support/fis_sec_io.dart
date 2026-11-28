// VM helpers of the Installations security tests (group fis_sec): temporary directories, the file of a
// store key, and a loopback HttpServer.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

/// A new temporary directory, deleted after the test.
Directory fisSecTempDir() {
  final Directory dir = Directory.systemTemp.createTempSync('fis_sec_');
  addTearDown(() async {
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  });
  return dir;
}

/// The file `FileKeyValueStore` keeps [key] in (5.2.1: lowercase hex SHA-256 of the UTF-8 key, `.json`).
File fisSecStoreFile(Directory dir, String key) => File(
  '${dir.path}${Platform.pathSeparator}${sha256.convert(utf8.encode(key))}.json',
);

/// A loopback server answering every request with [handler]; it records the request paths.
final class FisSecServer {
  FisSecServer._(this._server, this.handler) {
    _server.listen((HttpRequest request) async {
      paths.add(request.uri.toString());
      await request.drain<void>();
      try {
        await handler(request);
      } on Object {
        // The client hung up (it stopped reading at its cap); nothing left to answer.
      }
    });
  }

  /// Starts a server on 127.0.0.1, closed after the test.
  static Future<FisSecServer> start(
    Future<void> Function(HttpRequest request) handler,
  ) async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final FisSecServer result = FisSecServer._(server, handler);
    addTearDown(() => server.close(force: true));
    return result;
  }

  final HttpServer _server;

  /// Answers each request.
  Future<void> Function(HttpRequest request) handler;

  /// The path and query of every request received.
  final List<String> paths = <String>[];

  /// The origin to pass as `serverOrigin`.
  Uri get origin => Uri.parse('http://127.0.0.1:${_server.port}');
}
