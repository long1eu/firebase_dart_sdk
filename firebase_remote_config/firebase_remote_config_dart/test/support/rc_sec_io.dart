// A loopback HttpServer for the VM-only security tests: real IOClient behaviour (redirects, gzip
// decoding) without the network.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'rc_sec_harness.dart';

/// Answers one request on the loopback server.
typedef RcSecServerHandler =
    Future<void> Function(HttpRequest request, Uint8List body);

/// A loopback server that plays Installations, fetch and realtime.
final class RcSecServer {
  RcSecServer._(this._server);

  final HttpServer _server;

  /// The paths requested, in order.
  final List<String> paths = <String>[];

  /// Answers fetch requests.
  RcSecServerHandler? onFetch;

  /// Answers realtime requests.
  RcSecServerHandler? onRealtime;

  /// Answers every other path that is not Installations.
  RcSecServerHandler? onOther;

  /// Starts a server on 127.0.0.1 with a free port.
  static Future<RcSecServer> start() async {
    final RcSecServer server = RcSecServer._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    server._server.listen(server._handle);
    return server;
  }

  /// The origin of the server, `http://127.0.0.1:<port>`.
  Uri get origin => Uri(scheme: 'http', host: '127.0.0.1', port: _server.port);

  Future<void> _handle(HttpRequest request) async {
    final Uint8List body = Uint8List.fromList(
      await request.fold<List<int>>(
        <int>[],
        (List<int> all, List<int> chunk) => all..addAll(chunk),
      ),
    );
    paths.add(request.uri.path);
    final List<String> segments = request.uri.pathSegments;
    final String last = segments.isEmpty ? '' : segments.last;
    try {
      if (last == 'firebase:fetch' && onFetch != null) {
        await onFetch!(request, body);
      } else if (last == 'firebase:streamFetchInvalidations' &&
          onRealtime != null) {
        await onRealtime!(request, body);
      } else if (segments.contains('installations')) {
        await _installations(request, body);
      } else if (onOther != null) {
        await onOther!(request, body);
      } else {
        request.response.statusCode = 404;
        await request.response.close();
      }
    } on Object {
      // The client went away (an abort); nothing to answer.
    }
  }

  Future<void> _installations(HttpRequest request, Uint8List body) async {
    final Map<String, Object?> answer;
    if (request.uri.pathSegments.last == 'authTokens:generate') {
      answer = <String, Object?>{
        'token': authTokenSentinel,
        'expiresIn': '604800s',
      };
    } else {
      final Object? fid =
          (jsonDecode(utf8.decode(body)) as Map<String, Object?>)['fid'];
      answer = <String, Object?>{
        'name': 'projects/$rcSecProjectId/installations/$fid',
        'fid': fid,
        'refreshToken': refreshTokenSentinel,
        'authToken': <String, Object?>{
          'token': authTokenSentinel,
          'expiresIn': '604800s',
        },
      };
    }
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(answer));
    await request.response.close();
  }

  /// Stops the server and drops open connections.
  Future<void> close() => _server.close(force: true);
}

/// Sends [status] with a gzip-encoded body of [source] (`Content-Encoding: gzip`), and completes
/// when the body ended or the client went away. Returns true when the client went away first.
Future<bool> sendGzip(
  HttpRequest request,
  int status,
  Stream<List<int>> source,
) async {
  final HttpResponse response = request.response
    ..statusCode = status
    ..headers.set(HttpHeaders.contentEncodingHeader, 'gzip')
    ..headers.contentType = ContentType.json;
  try {
    await response.addStream(source.transform(gzip.encoder));
    await response.close();
    return false;
  } on Object {
    return true;
  }
}

/// An endless stream of [chunk], one per event-loop turn.
Stream<List<int>> endlessChunks(List<int> chunk, {List<int>? prefix}) async* {
  if (prefix != null) {
    yield prefix;
  }
  while (true) {
    await Future<void>.delayed(Duration.zero);
    yield chunk;
  }
}
